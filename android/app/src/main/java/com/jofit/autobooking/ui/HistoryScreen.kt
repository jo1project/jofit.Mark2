package com.jofit.autobooking.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jofit.autobooking.data.ReservationStore
import com.jofit.autobooking.data.UserSettings
import com.jofit.autobooking.model.Reservation
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

private class FireGroup(val fireDate: Instant, val items: List<Reservation>)

private val dateTimeFormat = DateTimeFormatter.ofPattern("M月d日 HH:mm")
private val timeFormat = DateTimeFormatter.ofPattern("HH:mm")

/**
 * "紀錄" shows only the current user's reservations (matched by employee ID); the admin-only
 * "伺服器" tab is the same screen with [showAll], listing everyone's. [isActive] is whether this
 * tab is the one on screen — every tab stays composed, so the server tab uses it to ask for the PIN.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HistoryScreen(settings: UserSettings, store: ReservationStore, showAll: Boolean = false, isActive: Boolean = true) {
    val t = Theme.c
    val scope = rememberCoroutineScope()

    var expandedMonths by remember { mutableStateOf(emptySet<String>()) }
    var hasSetInitialExpansion by remember { mutableStateOf(false) }
    var pendingCancel by remember { mutableStateOf<Reservation?>(null) }
    var isRefreshing by remember { mutableStateOf(false) }

    // Admin bulk cancel (see UserSettings.isAdmin): pick pending rows, confirm with the PIN.
    var isSelecting by remember { mutableStateOf(false) }
    var selectedIDs by remember { mutableStateOf(emptySet<String>()) }
    var showPinPrompt by remember { mutableStateOf(false) }
    var isCancelling by remember { mutableStateOf(false) }
    var resultMessage by remember { mutableStateOf<String?>(null) }

    // Admin "伺服器" tab: the backend only returns everyone's reservations for a valid PIN.
    var showUnlockPrompt by remember { mutableStateOf(false) }

    // id as a tiebreaker: two reservations can share the same day (different classrooms).
    fun byCourse(items: List<Reservation>) = items.sortedWith(compareBy({ it.course.date }, { it.course.time }, { it.id }))

    val visible = if (showAll) {
        if (store.isAdminUnlocked) store.reservations else emptyList()
    } else {
        store.reservations.filter { it.isBooked(settings.employeeID) }
    }
    val scheduled = visible.filter { it.status == Reservation.Status.Pending || it.status == Reservation.Status.Submitting }
    // Only pending ones can be bulk-cancelled; a submitting one is mid-POST and a submitted one can't be un-submitted.
    val pending = visible.filter { it.status == Reservation.Status.Pending }
    val selectedTargets = pending.filter { it.id in selectedIDs }
    val failed = visible.filter { it.status == Reservation.Status.Failed }
    val submitted = visible.filter { it.status == Reservation.Status.Submitted }

    // Reservations that fire in the same minute are shown as one batch.
    val scheduledGroups = scheduled.groupBy { it.fireDate.epochSecond / 60 }.values
        .map { items -> byCourse(items).let { FireGroup(it[0].fireDate, it) } }
        .sortedBy { it.fireDate }
    val submittedByMonth = submitted.groupBy { YearMonth.from(it.course.date) }.toSortedMap()
        .map { (month, items) -> "${month.year} 年 ${month.monthValue} 月" to byCourse(items) }

    LaunchedEffect(submittedByMonth.map { it.first }) {
        if (hasSetInitialExpansion || submittedByMonth.isEmpty()) return@LaunchedEffect
        val current = YearMonth.now().let { "${it.year} 年 ${it.monthValue} 月" }
        expandedMonths = expandedMonths + (submittedByMonth.firstOrNull { it.first == current } ?: submittedByMonth.last()).first
        hasSetInitialExpansion = true
    }
    LaunchedEffect(isActive) {
        if (showAll && isActive && !store.isAdminUnlocked) showUnlockPrompt = true
    }

    // "今天 08:00" / "明天 08:00" / "9月19日 07:05"
    fun friendly(instant: Instant): String {
        val zoned = instant.atZone(ZoneId.systemDefault())
        return when (zoned.toLocalDate()) {
            LocalDate.now() -> "今天 " + timeFormat.format(zoned)
            LocalDate.now().plusDays(1) -> "明天 " + timeFormat.format(zoned)
            else -> dateTimeFormat.format(zoned)
        }
    }

    @Composable
    fun ReservationRow(reservation: Reservation) {
        val course = reservation.course
        val selectable = isSelecting && reservation.status == Reservation.Status.Pending
        val isPicked = reservation.id in selectedIDs
        Row(
            Modifier.fillMaxWidth()
                .clickable(enabled = selectable) { selectedIDs = if (isPicked) selectedIDs - reservation.id else selectedIDs + reservation.id }
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (selectable) {
                Icon(
                    if (isPicked) Icons.Filled.CheckCircle else Icons.Outlined.Circle, null, Modifier.size(24.dp),
                    tint = if (isPicked) t.accent else t.textSecondary,
                )
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(course.name, color = t.ink, fontSize = 16.sp, fontWeight = t.strong)
                Text("${course.dateText} ${course.weekdayLabel} ${course.timeText}", color = t.textSecondary, fontSize = 14.sp, style = Tabular)
                if (showAll) {
                    val who = listOfNotNull(reservation.reporterName, reservation.employeeID).filter { it.isNotEmpty() }
                    if (who.isNotEmpty()) Text(who.joinToString("・"), color = t.textSecondary, fontSize = 12.sp)
                }
                // The pill already says the status; this adds only what it can't (when / why).
                // Scheduled rows need none — their batch header carries the send time.
                val note = when (reservation.status) {
                    Reservation.Status.Submitted -> reservation.submittedAt?.let { "${friendly(it)} 送出" }
                    Reservation.Status.Failed -> reservation.lastError ?: "送出失敗"
                    else -> null
                }
                if (note != null) {
                    Text(note, color = if (reservation.status == Reservation.Status.Failed) t.danger else t.textSecondary, fontSize = 12.sp)
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                StatusPill(reservation.status)
                if (reservation.canDismiss && !isSelecting) {
                    Text(
                        if (reservation.status == Reservation.Status.Failed) "移除" else "取消",
                        Modifier.clickable { pendingCancel = reservation }.padding(vertical = 4.dp),
                        color = t.danger, fontSize = 12.sp, fontWeight = t.strong,
                    )
                }
            }
        }
    }

    @Composable
    fun Rows(items: List<Reservation>) {
        items.forEachIndexed { index, reservation ->
            if (index > 0) Hairline()
            ReservationRow(reservation)
        }
    }

    @Composable
    fun SectionTitle(text: String, count: Int) {
        Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(text, color = t.ink, fontSize = 20.sp, fontWeight = t.title)
            Text("$count", color = t.textSecondary, fontSize = 14.sp, fontWeight = t.label, style = Tabular, modifier = Modifier.padding(bottom = 2.dp))
        }
    }

    Column(Modifier.fillMaxSize().background(t.background)) {
        PageHeader(if (showAll) "伺服器" else "預約紀錄") {
            if (settings.isAdmin && (isSelecting || pending.isNotEmpty())) {
                TextButton({ isSelecting = !isSelecting; selectedIDs = emptySet() }) {
                    Text(if (isSelecting) "完成" else "選取", color = t.accent, fontWeight = t.strong)
                }
            }
        }

        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                scope.launch {
                    isRefreshing = true
                    try { store.refresh() } finally { isRefreshing = false }
                }
            },
            modifier = Modifier.weight(1f),
        ) {
            Column(
                Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                store.lastSyncError?.let { Text(it, color = t.danger, fontSize = 14.sp) }
                if (scheduledGroups.isNotEmpty()) {
                    SectionTitle("排程中", scheduled.size)
                    scheduledGroups.forEach { group ->
                        val when_ = friendly(group.fireDate)
                        val title = if (group.items.size > 1) "$when_ 一併送出・${group.items.size} 筆" else "$when_ 送出"
                        Column(Modifier.fillMaxWidth().cardBackground().padding(horizontal = 16.dp)) {
                            Row(Modifier.padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Icon(Icons.Outlined.Schedule, null, Modifier.size(18.dp), tint = t.accent)
                                Text(title, color = t.ink, fontSize = 14.sp, fontWeight = t.strong)
                            }
                            Hairline()
                            Rows(group.items)
                        }
                    }
                }
                if (failed.isNotEmpty()) {
                    SectionTitle("送出失敗", failed.size)
                    Column(Modifier.fillMaxWidth().cardBackground().padding(horizontal = 16.dp)) { Rows(failed) }
                }
                if (submitted.isNotEmpty()) {
                    SectionTitle("已送出", submitted.size)
                    submittedByMonth.forEach { (key, items) ->
                        val isExpanded = key in expandedMonths
                        Column(Modifier.fillMaxWidth().cardBackground().padding(horizontal = 16.dp)) {
                            Row(
                                Modifier.fillMaxWidth()
                                    .clickable { expandedMonths = if (isExpanded) expandedMonths - key else expandedMonths + key }
                                    .semantics { contentDescription = key + if (isExpanded) "，已展開" else "，已收合" }
                                    .padding(vertical = 14.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(key, Modifier.weight(1f), color = t.ink, fontSize = 16.sp, fontWeight = t.title)
                                Text("${items.size} 筆", color = t.textSecondary, fontSize = 14.sp)
                                Icon(Icons.Filled.ChevronRight, null, Modifier.size(20.dp).rotate(if (isExpanded) 90f else 0f), tint = t.textSecondary)
                            }
                            AnimatedVisibility(isExpanded) {
                                Column {
                                    Hairline()
                                    Rows(items)
                                }
                            }
                        }
                    }
                }
            }
            if (visible.isEmpty()) {
                EmptyState(
                    Icons.Outlined.Inbox,
                    if (showAll) "伺服器上沒有預約" else "還沒有預約紀錄",
                    if (showAll) (if (store.isAdminUnlocked) "" else "尚未輸入管理密碼")
                    else "到「課程」挑一堂想上的課吧，剩下的交給我們，你只要準時出現就好。",
                )
            }
        }

        if (isSelecting) {
            val allSelected = pending.isNotEmpty() && selectedTargets.size == pending.size
            Row(
                Modifier.fillMaxWidth().background(t.background).padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(
                    if (allSelected) "取消全選" else "全選",
                    Modifier.clickable { selectedIDs = if (allSelected) emptySet() else pending.map { it.id }.toSet() }.padding(vertical = 8.dp),
                    color = t.accent, fontSize = 16.sp, fontWeight = t.strong,
                )
                PrimaryButton({ showPinPrompt = true }, Modifier.weight(1f), enabled = selectedTargets.isNotEmpty() && !isCancelling) {
                    if (isCancelling) CircularProgressIndicator(Modifier.size(22.dp), color = t.brand, strokeWidth = 2.dp)
                    else ButtonLabel("取消所選（${selectedTargets.size}）")
                }
            }
        }
    }

    CancelDialog(pendingCancel, onDismiss = { pendingCancel = null }) { scope.launch { store.cancel(it) } }

    if (showPinPrompt) {
        val targets = selectedTargets
        PinDialog(
            message = "將取消 ${targets.size} 筆排程中的預約${if (showAll) "（可能包含其他人的）" else ""}，無法復原。",
            confirmLabel = "取消 ${targets.size} 筆預約",
            destructive = true,
            onDismiss = { showPinPrompt = false },
            onConfirm = { pin ->
                showPinPrompt = false
                isCancelling = true
                scope.launch {
                    try {
                        val cancelled = store.cancelPending(targets, pin)
                        selectedIDs = emptySet()
                        isSelecting = false
                        resultMessage = if (cancelled == targets.size) "已取消 $cancelled 筆預約。"
                        else "已取消 $cancelled 筆，另外 ${targets.size - cancelled} 筆已經開始送出或已送出，無法取消。"
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        // Keep the selection so a mistyped PIN can just be retried.
                        resultMessage = e.message
                    } finally {
                        isCancelling = false
                    }
                }
            },
        )
    }

    if (showUnlockPrompt) {
        PinDialog(
            message = "需要管理密碼才能查看所有人的預約。",
            confirmLabel = "查看",
            destructive = false,
            onDismiss = { showUnlockPrompt = false },
            onConfirm = { pin ->
                showUnlockPrompt = false
                scope.launch {
                    try {
                        store.unlockAdmin(pin)
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        store.lastSyncError = e.message
                    }
                }
            },
        )
    }

    MessageDialog("取消結果", resultMessage) { resultMessage = null }
}
