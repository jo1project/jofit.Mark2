package com.jofit.autobooking.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jofit.autobooking.model.WEEKDAYS

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FilterSheet(
    timeFilter: TimeFilter,
    onTimeFilter: (TimeFilter) -> Unit,
    shownWeekdays: Set<String>,
    onShownWeekdays: (Set<String>) -> Unit,
    onDismiss: () -> Unit,
) {
    val t = Theme.c
    val haptic = LocalHapticFeedback.current
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = t.background,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp),
    ) {
        Column(Modifier.navigationBarsPadding().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
            Text("篩選", Modifier.fillMaxWidth(), color = t.ink, fontSize = 17.sp, fontWeight = FontWeight.Bold, textAlign = androidx.compose.ui.text.style.TextAlign.Center)

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionLabel("時段")
                Column(Modifier.fillMaxWidth().cardBackground().padding(horizontal = 16.dp)) {
                    TimeFilter.entries.forEachIndexed { index, filter ->
                        if (index > 0) Hairline()
                        ChoiceRow(filter.label, timeFilter == filter) {
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onTimeFilter(filter)
                        }
                    }
                }
            }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                SectionLabel("顯示星期")
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    WEEKDAYS.forEach { day ->
                        WeekdayChip(day, day in shownWeekdays, Modifier.weight(1f)) {
                            haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            onShownWeekdays(if (day in shownWeekdays) shownWeekdays - day else shownWeekdays + day)
                        }
                    }
                }
                Text("未選取的星期會隱藏課程", color = t.textSecondary, fontSize = 13.sp)
            }

            PrimaryButton(onDismiss, Modifier.fillMaxWidth()) { ButtonLabel("完成") }
        }
    }
}
