package com.jofit.autobooking.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jofit.autobooking.model.Reservation

/** Warm-white rounded card with a hairline border. */
@Composable
fun Modifier.cardBackground(): Modifier {
    val t = Theme.c
    val shape = RoundedCornerShape(t.cardRadius)
    return this.clip(shape).background(t.card).border(1.dp, t.hairline, shape)
}

@Composable
fun Hairline() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Theme.c.hairline))
}

/** Fixed-width digits so times and dates line up. */
val Tabular = TextStyle(fontFeatureSettings = "tnum")

/** Screen title row: large title on the left, optional action on the right. */
@Composable
fun PageHeader(title: String, trailing: @Composable RowScope.() -> Unit = {}) {
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().padding(start = 20.dp, end = 12.dp, top = 8.dp, bottom = 8.dp)
            .height(48.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, Modifier.weight(1f), color = Theme.c.ink, fontSize = 30.sp, fontWeight = Theme.c.title)
        trailing()
    }
}

/** The main action on any screen. Classic: dark capsule, gold border, gold label. Apple: solid blue capsule. */
@Composable
fun PrimaryButton(onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, content: @Composable () -> Unit) {
    val t = Theme.c
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.height(48.dp),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = t.primaryFill, contentColor = t.primaryText,
            disabledContainerColor = t.primaryFill.copy(alpha = 0.4f), disabledContentColor = t.primaryText.copy(alpha = 0.4f),
        ),
        border = if (t.p.primaryOutlined) BorderStroke(1.5.dp, t.brand.copy(alpha = if (enabled) 1f else 0.4f)) else null,
        contentPadding = PaddingValues(horizontal = 24.dp),
    ) { content() }
}

@Composable
fun ButtonLabel(text: String) = Text(text, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)

/**
 * Visual state of one bookable date (one week's occurrence of a class).
 * idle: hollow circle on chip · selected: gold + check · scheduled: gold + clock ·
 * submitted: chip color + brown check, greyed date · failed: red warning.
 */
enum class DateChipState(val icon: ImageVector, val spokenName: String) {
    Idle(Icons.Outlined.Circle, "未選取"),
    Selected(Icons.Filled.Check, "已選取"),
    Scheduled(Icons.Outlined.Schedule, "排程中"),
    Submitted(Icons.Filled.Check, "已送出"),
    Failed(Icons.Filled.Warning, "送出失敗"),
}

@Composable
fun DateChip(text: String, state: DateChipState, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val t = Theme.c
    val shape = RoundedCornerShape(t.chipRadius)
    val iconColor = when (state) {
        DateChipState.Idle -> t.textSecondary
        DateChipState.Selected, DateChipState.Scheduled -> t.onBrand
        DateChipState.Submitted -> t.checkBrown
        DateChipState.Failed -> t.danger
    }
    val textColor = when (state) {
        DateChipState.Selected, DateChipState.Scheduled -> t.onBrand
        DateChipState.Submitted -> t.textSecondary
        else -> t.ink
    }
    val fill = when (state) {
        DateChipState.Idle, DateChipState.Submitted -> t.chipIdle
        DateChipState.Selected, DateChipState.Scheduled -> t.brand
        DateChipState.Failed -> t.danger.copy(alpha = 0.12f)
    }
    val border = when (state) {
        DateChipState.Idle, DateChipState.Submitted -> t.hairline
        DateChipState.Selected, DateChipState.Scheduled -> Color.Transparent
        DateChipState.Failed -> t.danger
    }
    Column(
        modifier.clip(shape).background(fill).border(1.dp, border, shape).clickable(onClick = onClick)
            .semantics { contentDescription = "$text，${state.spokenName}" }
            .padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(state.icon, null, Modifier.size(18.dp), tint = iconColor)
        Text(text, color = textColor, fontSize = 12.sp, fontWeight = t.label, style = Tabular)
    }
}

/** Round single-character weekday toggle (一…日). Same palette as [DateChip]. */
@Composable
fun WeekdayChip(label: String, isOn: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val t = Theme.c
    Box(modifier, contentAlignment = Alignment.Center) {
        Box(
            Modifier.size(44.dp).aspectRatio(1f).clip(CircleShape).background(if (isOn) t.brand else t.chipIdle)
                .border(1.dp, if (isOn) Color.Transparent else t.hairline, CircleShape)
                .clickable(onClick = onClick)
                .semantics { contentDescription = label + if (isOn) "，已選取" else "" },
            contentAlignment = Alignment.Center,
        ) {
            Text(label.drop(1), color = if (isOn) t.onBrand else t.textSecondary, fontSize = 15.sp, fontWeight = t.strong)
        }
    }
}

/** Filled gold circle with a dark check when on, empty ring when off. */
@Composable
fun CheckDot(isOn: Boolean) {
    val t = Theme.c
    Box(
        Modifier.size(24.dp).clip(CircleShape)
            .then(if (isOn) Modifier.background(t.brand) else Modifier.border(1.5.dp, t.textSecondary.copy(alpha = 0.5f), CircleShape)),
        contentAlignment = Alignment.Center,
    ) {
        if (isOn) Icon(Icons.Filled.Check, null, Modifier.size(14.dp), tint = t.onBrand)
    }
}

/** Reservation status as a colored capsule label. */
@Composable
fun StatusPill(status: Reservation.Status) {
    val t = Theme.c
    val (title, fill, fg) = when (status) {
        Reservation.Status.Pending -> Triple("排程中", t.brand, t.onBrand)
        Reservation.Status.Submitting -> Triple("送出中", t.brand, t.onBrand)
        Reservation.Status.Submitted -> Triple("已送出", t.chipIdle, t.checkBrown)
        Reservation.Status.Failed -> Triple("失敗", t.danger, t.onInk)
    }
    Text(
        title, color = fg, fontSize = 12.sp, fontWeight = t.strong,
        modifier = Modifier.clip(CircleShape).background(fill)
            .border(1.dp, if (status == Reservation.Status.Submitted) t.hairline else Color.Transparent, CircleShape)
            .padding(horizontal = 10.dp, vertical = 4.dp),
    )
}

/** Small read-only capsule, e.g. the active-filter summary row. */
@Composable
fun TagPill(text: String) {
    val t = Theme.c
    Text(
        text, color = t.ink, fontSize = 12.sp, fontWeight = t.label,
        modifier = Modifier.clip(CircleShape).background(t.chipIdle).border(1.5.dp, t.brand, CircleShape)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

@Composable
fun EmptyState(icon: ImageVector, title: String, description: String) {
    val t = Theme.c
    Column(
        Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(icon, null, Modifier.size(44.dp), tint = t.textSecondary)
        Text(title, Modifier.padding(top = 12.dp), color = t.ink, fontSize = 20.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
        if (description.isNotEmpty()) {
            Text(description, Modifier.padding(top = 6.dp), color = t.textSecondary, fontSize = 14.sp, textAlign = TextAlign.Center)
        }
    }
}

/** Confirm, then cancel (or clear, if failed) [reservation]. Shared by the courses and history screens. */
@Composable
fun CancelDialog(reservation: Reservation?, onDismiss: () -> Unit, onConfirm: (Reservation) -> Unit) {
    if (reservation == null) return
    val t = Theme.c
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("這堂課要取消預約嗎？") },
        text = { Text(reservation.course.submissionText) },
        confirmButton = {
            TextButton({ onConfirm(reservation); onDismiss() }) {
                Text(if (reservation.status == Reservation.Status.Failed) "移除" else "取消預約", color = t.danger)
            }
        },
        dismissButton = { TextButton(onDismiss) { Text("返回") } },
    )
}

/** Asks for the admin PIN. A blank PIN is rejected here: it would just count as a wrong attempt toward the backend's lockout. */
@Composable
fun PinDialog(message: String, confirmLabel: String, destructive: Boolean, onDismiss: () -> Unit, onConfirm: (String) -> Unit) {
    var pin by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("輸入管理密碼") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(message)
                OutlinedTextField(
                    pin, { pin = it }, label = { Text("密碼") }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                )
            }
        },
        confirmButton = {
            TextButton({ onConfirm(pin) }, enabled = pin.isNotEmpty()) {
                Text(confirmLabel, color = if (destructive) Theme.c.danger else Color.Unspecified)
            }
        },
        dismissButton = { TextButton(onDismiss) { Text("取消") } },
    )
}

@Composable
fun MessageDialog(title: String, message: String?, onDismiss: () -> Unit) {
    if (message == null) return
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { Text(message) },
        confirmButton = { TextButton(onDismiss) { Text("好") } },
    )
}

/** Small secondary-colored heading above a group of controls. */
@Composable
fun SectionLabel(text: String) {
    Text(text, color = Theme.c.textSecondary, fontSize = 14.sp, fontWeight = Theme.c.title)
}

/** A tappable card row with a trailing [CheckDot], used for single-choice lists (time filter, theme). */
@Composable
fun ChoiceRow(label: String, isOn: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .semantics { contentDescription = label + if (isOn) "，已選取" else "" }
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f), color = Theme.c.ink, fontSize = 16.sp)
        CheckDot(isOn)
    }
}
