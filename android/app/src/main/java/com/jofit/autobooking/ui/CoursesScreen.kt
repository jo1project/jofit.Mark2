package com.jofit.autobooking.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.EventBusy
import androidx.compose.material.icons.outlined.FilterList
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jofit.autobooking.data.CourseStore
import com.jofit.autobooking.data.ReservationStore
import com.jofit.autobooking.data.UserSettings
import com.jofit.autobooking.model.Course
import com.jofit.autobooking.model.Reservation
import com.jofit.autobooking.model.WEEKDAYS
import kotlinx.coroutines.launch

enum class TimeFilter(val label: String) {
    All("全部顯示"), Night("夜間（20:00 後）"), Day("非夜間（20:00 前）")
}

private class TemplateGroup(
    val templateID: String,
    val name: String,
    val time: String,
    val weekdayLabel: String,
    /** Sorted by date, one per upcoming week. */
    val instances: List<Course>,
)

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun CoursesScreen(settings: UserSettings, courseStore: CourseStore, reservationStore: ReservationStore) {
    val t = Theme.c
    val scope = rememberCoroutineScope()
    val haptic = LocalHapticFeedback.current

    var timeFilter by remember { mutableStateOf(TimeFilter.All) }
    var shownWeekdays by remember { mutableStateOf(WEEKDAYS.toSet()) }
    var showFilters by remember { mutableStateOf(false) }
    var selectedIDs by remember { mutableStateOf(emptySet<String>()) }
    var isSubmitting by remember { mutableStateOf(false) }
    var isRefreshing by remember { mutableStateOf(false) }
    var pendingCancel by remember { mutableStateOf<Reservation?>(null) }

    val filtered = courseStore.courses.filter { course ->
        course.weekdayLabel in shownWeekdays && when (timeFilter) {
            TimeFilter.All -> true
            TimeFilter.Night -> (course.time.toIntOrNull() ?: 0) >= 2000
            TimeFilter.Day -> (course.time.toIntOrNull() ?: 0) < 2000
        }
    }
    val grouped = run {
        val groups = filtered.groupBy { it.templateID }.map { (id, courses) ->
            val sorted = courses.sortedBy { it.date }
            TemplateGroup(id, sorted[0].name, sorted[0].time, sorted[0].weekdayLabel, sorted)
        }
        val byWeekday = groups.groupBy { it.weekdayLabel }
        // Ties (several classrooms share a weekday+time) break on templateID so rows never swap places.
        WEEKDAYS.mapNotNull { day ->
            byWeekday[day]?.let { day to it.sortedWith(compareBy({ g -> g.time }, { g -> g.templateID })) }
        }
    }
    val isFilterActive = timeFilter != TimeFilter.All || shownWeekdays.size != WEEKDAYS.size

    Column(Modifier.fillMaxSize().background(t.background)) {
        PageHeader("課程") {
            IconButton({ showFilters = true }, Modifier.semantics { contentDescription = "篩選" + if (isFilterActive) "，已啟用" else "" }) {
                Box {
                    Icon(Icons.Outlined.FilterList, null, tint = t.accent)
                    if (isFilterActive) {
                        Box(
                            Modifier.align(Alignment.TopEnd).offset(3.dp, (-3).dp).size(9.dp)
                                .background(t.brand, CircleShape).border(1.5.dp, t.background, CircleShape),
                        )
                    }
                }
            }
        }

        PullToRefreshBox(
            isRefreshing = isRefreshing,
            onRefresh = {
                scope.launch {
                    isRefreshing = true
                    try { courseStore.refresh() } finally { isRefreshing = false }
                }
            },
            modifier = Modifier.weight(1f),
        ) {
            // Cards carry their own horizontal padding (not the list) so the pinned weekday
            // headers can paint edge to edge and hide cards scrolling under them.
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
                if (!settings.isComplete) item(key = "incomplete") { Banner("請先到「設定」分頁填寫姓名與員工編號", t.textSecondary) }
                reservationStore.lastSyncError?.let { item(key = "error") { Banner(it, t.danger) } }
                if (isFilterActive) item(key = "filters") {
                    LazyRow(Modifier.padding(bottom = 12.dp), contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (timeFilter != TimeFilter.All) item { TagPill(timeFilter.label) }
                        if (shownWeekdays.size != WEEKDAYS.size) item {
                            val days = WEEKDAYS.filter { it in shownWeekdays }.map { it.drop(1) }
                            TagPill(if (days.isEmpty()) "未選任何星期" else "星期 " + days.joinToString("・"))
                        }
                    }
                }
                grouped.forEach { (day, templates) ->
                    stickyHeader(key = "header-$day") {
                        Text(
                            day, Modifier.fillMaxWidth().background(t.background).padding(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 8.dp),
                            color = t.textSecondary, fontSize = 14.sp, fontWeight = t.title,
                        )
                    }
                    itemsIndexed(templates, key = { _, g -> g.templateID }) { index, group ->
                        // 12 between cards; 20 after the last so the next weekday header has air.
                        Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = if (index == templates.lastIndex) 20.dp else 12.dp)) {
                            TemplateCard(group, settings, reservationStore, selectedIDs,
                                onToggle = { id ->
                                    haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                                    selectedIDs = if (id in selectedIDs) selectedIDs - id else selectedIDs + id
                                },
                                onCancel = { pendingCancel = it })
                        }
                    }
                }
            }
            if (filtered.isEmpty()) {
                EmptyState(Icons.Outlined.EventBusy, "沒有符合條件的課程", if (isFilterActive) "篩選條件有點嚴格，放寬一點試試看" else "")
            }
        }

        if (selectedIDs.isNotEmpty()) {
            Box(Modifier.fillMaxWidth().background(t.background).padding(horizontal = 16.dp, vertical = 8.dp)) {
                PrimaryButton(
                    onClick = {
                        val toSubmit = courseStore.courses.filter { it.id in selectedIDs }
                        isSubmitting = true
                        scope.launch {
                            try {
                                for (course in toSubmit) {
                                    reservationStore.reserve(course, settings.name, settings.employeeID)
                                    selectedIDs = selectedIDs - course.id
                                }
                            } finally {
                                isSubmitting = false
                            }
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !isSubmitting && settings.isComplete,
                ) {
                    if (isSubmitting) CircularProgressIndicator(Modifier.size(22.dp), color = t.brand, strokeWidth = 2.dp)
                    else ButtonLabel("送出預約（${selectedIDs.size}）")
                }
            }
        }
    }

    if (showFilters) {
        FilterSheet(timeFilter, { timeFilter = it }, shownWeekdays, { shownWeekdays = it }, onDismiss = { showFilters = false })
    }
    CancelDialog(pendingCancel, onDismiss = { pendingCancel = null }) { scope.launch { reservationStore.cancel(it) } }
}

@Composable
private fun Banner(text: String, color: androidx.compose.ui.graphics.Color) {
    Text(
        text, Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp).fillMaxWidth().cardBackground().padding(14.dp),
        color = color, fontSize = 14.sp,
    )
}

@Composable
private fun TemplateCard(
    group: TemplateGroup,
    settings: UserSettings,
    reservationStore: ReservationStore,
    selectedIDs: Set<String>,
    onToggle: (String) -> Unit,
    onCancel: (Reservation) -> Unit,
) {
    val t = Theme.c
    Column(Modifier.fillMaxWidth().cardBackground().padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        // Time is small, secondary and fixed-width digits; the name is big and heavy.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(width = 4.dp, height = 24.dp).background(CourseCategory.of(group.name).color(t), RoundedCornerShape(2.dp)))
            Text(Course.displayTime(group.time), color = t.textSecondary, fontSize = 14.sp, fontWeight = t.label, style = Tabular)
            Text(group.name, color = t.ink, fontSize = 20.sp, fontWeight = t.title)
        }
        // No coach / venue line: `courses.json` has no such fields yet.
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            group.instances.forEach { course ->
                val reservation = reservationStore.reservation(course.id, settings.employeeID)
                val isSelected = course.id in selectedIDs
                val state = when (reservation?.status) {
                    Reservation.Status.Submitted -> DateChipState.Submitted
                    Reservation.Status.Pending, Reservation.Status.Submitting -> DateChipState.Scheduled
                    Reservation.Status.Failed -> DateChipState.Failed
                    null -> if (isSelected) DateChipState.Selected else DateChipState.Idle
                }
                DateChip(course.dateText, state, Modifier.weight(1f)) {
                    when (reservation?.status) {
                        null -> onToggle(course.id)
                        Reservation.Status.Pending, Reservation.Status.Failed -> if (reservation.canDismiss) onCancel(reservation)
                        Reservation.Status.Submitting, Reservation.Status.Submitted -> {}
                    }
                }
            }
        }
    }
}
