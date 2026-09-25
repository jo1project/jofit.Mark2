package com.jofit.autobooking.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimeInput
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jofit.autobooking.data.CourseStore
import com.jofit.autobooking.data.ReservationStore
import com.jofit.autobooking.model.Course
import com.jofit.autobooking.model.CourseTemplate
import com.jofit.autobooking.model.Reservation
import com.jofit.autobooking.model.WEEKDAYS
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

/**
 * Admin-only tab (see UserSettings.isAdmin): edit the weekly course list everyone shares.
 * Edits stay in `draft` until saved; saving needs the admin PIN, which the backend verifies.
 */
@Composable
fun EditCoursesScreen(courseStore: CourseStore, reservationStore: ReservationStore) {
    val t = Theme.c
    val scope = rememberCoroutineScope()

    var draft by remember { mutableStateOf(emptyList<CourseTemplate>()) }
    // What the backend/cache had when `draft` was last synced; `draft != baseline` means unsaved edits.
    var baseline by remember { mutableStateOf(emptyList<CourseTemplate>()) }
    var editing by remember { mutableStateOf<CourseTemplate?>(null) }
    var showPinPrompt by remember { mutableStateOf(false) }
    var isSaving by remember { mutableStateOf(false) }
    var resultMessage by remember { mutableStateOf<String?>(null) }

    val isDirty = draft != baseline

    // Picks up the store's list on first show and after refreshes, but never over unsaved edits.
    LaunchedEffect(courseStore.templates) {
        if (draft == baseline) {
            baseline = courseStore.templates
            draft = baseline
        }
    }

    // Pending reservations keep the course name/time they were created with, so editing or
    // deleting a template does not change what they will submit.
    val affectedPendingCount = run {
        val draftByID = draft.associateBy { it.id }
        val changedIDs = baseline.filter { draftByID[it.id] != it }.map { it.id }.toSet()
        reservationStore.reservations.count { it.status == Reservation.Status.Pending && it.course.templateID in changedIDs }
    }

    Column(Modifier.fillMaxSize().background(t.background)) {
        PageHeader("編輯課程") {
            if (isDirty) TextButton({ draft = baseline }) { Text("還原", color = t.accent, fontWeight = t.strong) }
            IconButton({ editing = CourseTemplate(UUID.randomUUID().toString().lowercase(), "週一", "1900", "") }) {
                Icon(Icons.Filled.Add, "新增課程", tint = t.accent)
            }
        }

        Box(Modifier.weight(1f)) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                WEEKDAYS.forEach { day ->
                    val items = draft.filter { it.weekday == day }.sortedWith(compareBy({ it.time }, { it.id }))
                    if (items.isNotEmpty()) {
                        item(key = "section-$day") {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                SectionLabel(day)
                                Column(Modifier.fillMaxWidth().cardBackground().padding(start = 16.dp)) {
                                    items.forEachIndexed { index, template ->
                                        if (index > 0) Hairline()
                                        Row(
                                            Modifier.fillMaxWidth().clickable { editing = template },
                                            verticalAlignment = Alignment.CenterVertically,
                                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                                        ) {
                                            Text(Course.displayTime(template.time), color = t.textSecondary, fontSize = 14.sp, fontWeight = t.label, style = Tabular)
                                            Text(template.name, Modifier.weight(1f).padding(vertical = 14.dp), color = t.ink, fontSize = 16.sp, fontWeight = t.strong)
                                            IconButton({ draft = draft.filter { it.id != template.id } }) {
                                                Icon(Icons.Outlined.Delete, "刪除 ${template.name}", tint = t.danger)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (draft.isEmpty()) EmptyState(Icons.Outlined.CalendarMonth, "目前沒有課程", "點右上角的「＋」新增。")
        }

        if (isDirty) {
            Box(Modifier.fillMaxWidth().background(t.background).padding(horizontal = 16.dp, vertical = 8.dp)) {
                PrimaryButton({ showPinPrompt = true }, Modifier.fillMaxWidth(), enabled = !isSaving && draft.isNotEmpty()) {
                    if (isSaving) CircularProgressIndicator(Modifier.size(22.dp), color = t.brand, strokeWidth = 2.dp)
                    else ButtonLabel("儲存變更")
                }
            }
        }
    }

    editing?.let { template ->
        CourseEditSheet(template, onDismiss = { editing = null }) { saved ->
            draft = if (draft.any { it.id == saved.id }) draft.map { if (it.id == saved.id) saved else it } else draft + saved
        }
    }

    if (showPinPrompt) {
        PinDialog(
            message = (if (affectedPendingCount > 0) "有 $affectedPendingCount 筆排程中的預約屬於這次改動的課程，它們不會跟著更新，仍會用原本的名稱和時間送出。\n\n" else "") +
                "儲存後所有人的課表都會更新。",
            confirmLabel = "儲存",
            destructive = false,
            onDismiss = { showPinPrompt = false },
            onConfirm = { pin ->
                showPinPrompt = false
                val toSave = draft
                isSaving = true
                scope.launch {
                    try {
                        courseStore.save(toSave, pin)
                        baseline = toSave
                        resultMessage = "已儲存。其他人的 App 會在下次開啟或下拉更新時看到新課表。"
                    } catch (e: CancellationException) {
                        throw e
                    } catch (e: Exception) {
                        // Edits stay in the draft so a mistyped PIN can just be retried.
                        resultMessage = e.message
                    } finally {
                        isSaving = false
                    }
                }
            },
        )
    }
    MessageDialog("編輯課程", resultMessage) { resultMessage = null }
}

/** Add/edit one weekly slot. `time` is stored as "HHmm". */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CourseEditSheet(template: CourseTemplate, onDismiss: () -> Unit, onSave: (CourseTemplate) -> Unit) {
    val t = Theme.c
    var name by remember { mutableStateOf(template.name) }
    var weekday by remember { mutableStateOf(template.weekday) }
    val time = rememberTimePickerState(
        initialHour = template.time.take(2).toIntOrNull() ?: 0,
        initialMinute = template.time.takeLast(2).toIntOrNull() ?: 0,
        is24Hour = true,
    )
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = t.background,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
    ) {
        Column(
            Modifier.navigationBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("課程", color = t.ink, fontSize = 17.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold)
            OutlinedTextField(name, { name = it }, Modifier.fillMaxWidth(), label = { Text("課程名稱") }, singleLine = true)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                WEEKDAYS.forEach { day -> WeekdayChip(day, day == weekday, Modifier.weight(1f)) { weekday = day } }
            }
            TimeInput(time)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                TextButton(onDismiss, Modifier.weight(1f)) { Text("取消") }
                PrimaryButton(
                    onClick = {
                        onSave(template.copy(name = name.trim(), weekday = weekday, time = "%02d%02d".format(time.hour, time.minute)))
                        onDismiss()
                    },
                    modifier = Modifier.weight(1f),
                    enabled = name.isNotBlank(),
                ) { ButtonLabel("完成") }
            }
        }
    }
}
