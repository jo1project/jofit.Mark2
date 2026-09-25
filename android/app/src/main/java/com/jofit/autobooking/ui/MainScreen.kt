package com.jofit.autobooking.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.glance.appwidget.updateAll
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.jofit.autobooking.data.CourseStore
import com.jofit.autobooking.data.ReservationStore
import com.jofit.autobooking.data.UserSettings
import com.jofit.autobooking.widget.JofitWidget
import kotlinx.coroutines.delay

private enum class AppTab(val title: String, val icon: ImageVector) {
    Courses("課程", Icons.Outlined.CalendarMonth),
    History("紀錄", Icons.Outlined.History),
    Server("伺服器", Icons.Outlined.Dns),
    Admin("編輯", Icons.Outlined.Edit),
    Settings("設定", Icons.Outlined.Settings),
}

@Composable
fun MainScreen(settings: UserSettings, courseStore: CourseStore, reservationStore: ReservationStore) {
    val t = Theme.c
    val context = LocalContext.current
    var tab by remember { mutableStateOf(AppTab.Courses) }

    // The edit and server tabs exist only for the admin (see UserSettings.isAdmin).
    val visibleTabs = AppTab.entries.filter { (it != AppTab.Admin && it != AppTab.Server) || settings.isAdmin }
    LaunchedEffect(settings.isAdmin) { if (tab !in visibleTabs) tab = AppTab.Settings }

    // Refresh when the app comes to the foreground, then every 30 s while it stays there.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            courseStore.refresh()
            reservationStore.refresh()
            while (true) {
                delay(30_000)
                reservationStore.refresh()
            }
        }
    }
    // The widget draws with the chosen theme too.
    LaunchedEffect(settings.theme) { JofitWidget().updateAll(context) }

    Box(Modifier.fillMaxSize().background(t.background)) {
        Column(Modifier.fillMaxSize()) {
            // All pages stay composed (just hidden) so unsent selections, filters and unsaved
            // course edits survive tab switches.
            Box(Modifier.weight(1f)) {
                visibleTabs.forEach { item ->
                    val active = tab == item
                    Box(
                        Modifier.fillMaxSize()
                            .then(if (active) Modifier.zIndex(1f) else Modifier.alpha(0f).blockTouches().clearAndSetSemantics {}),
                    ) {
                        when (item) {
                            AppTab.Courses -> CoursesScreen(settings, courseStore, reservationStore)
                            AppTab.History -> HistoryScreen(settings, reservationStore)
                            AppTab.Server -> HistoryScreen(settings, reservationStore, showAll = true, isActive = active)
                            AppTab.Admin -> EditCoursesScreen(courseStore, reservationStore)
                            AppTab.Settings -> SettingsScreen(settings)
                        }
                    }
                }
            }
            TabBar(visibleTabs, tab) { tab = it }
        }
        if (!settings.hasOnboarded) {
            // The empty tap handler stops touches falling through to the pages underneath.
            Box(Modifier.fillMaxSize().zIndex(2f).pointerInput(Unit) { detectTapGestures {} }) { OnboardingScreen(settings) }
        }
    }
}

/** Consumes every touch before the children see it (used on hidden pages). */
private fun Modifier.blockTouches() = pointerInput(Unit) {
    awaitPointerEventScope {
        while (true) awaitPointerEvent(PointerEventPass.Initial).changes.forEach { it.consume() }
    }
}

// A custom floating capsule bar instead of NavigationBar so the selection can be the gold capsule.
@Composable
private fun TabBar(tabs: List<AppTab>, selected: AppTab, onSelect: (AppTab) -> Unit) {
    val t = Theme.c
    Box(Modifier.fillMaxWidth().background(t.background).navigationBarsPadding().padding(horizontal = 24.dp, vertical = 6.dp)) {
        Row(
            Modifier.fillMaxWidth().shadow(12.dp, CircleShape).clip(CircleShape).background(t.card)
                .border(1.dp, t.hairline, CircleShape).padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            tabs.forEach { item ->
                val isOn = item == selected
                val color = if (isOn) t.onBrand else t.tabUnselected
                Column(
                    Modifier.weight(1f).clip(CircleShape).background(if (isOn) t.brand else androidx.compose.ui.graphics.Color.Transparent)
                        .clickable { onSelect(item) }
                        .semantics { contentDescription = item.title; this.selected = isOn }
                        .padding(vertical = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Icon(item.icon, null, Modifier.size(22.dp), tint = color)
                    Text(item.title, color = color, fontSize = 11.sp, fontWeight = t.label)
                }
            }
        }
    }
}
