package com.jofit.autobooking.widget

import android.content.Context
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.glance.color.ColorProvider
import com.jofit.autobooking.R
import com.jofit.autobooking.data.Prefs
import com.jofit.autobooking.data.ReservationStore
import com.jofit.autobooking.ui.AppTheme
import com.jofit.autobooking.ui.Duo
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale
import kotlin.math.max
import kotlin.math.roundToInt

private fun Duo.provider() = ColorProvider(day = Color(0xFF000000 or light), night = Color(0xFF000000 or dark))

/**
 * Home-screen widget: today's date plus this user's submitted course(s) for today, or
 * "今天休息". It reads the reservations cache directly (same process as the app).
 */
class JofitWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val today = LocalDate.now()
        val courses = ReservationStore.myCoursesOn(context, today)
        val name = courses.takeIf { it.isNotEmpty() }?.joinToString("、") { it.name }
        val palette = AppTheme.from(Prefs.of(context).getString(Prefs.THEME, null)).palette

        provideContent {
            val density = LocalContext.current.resources.displayMetrics.density
            val heightPx = LocalSize.current.height.value * density * 0.58f
            // Pixel art: snap to a whole number of device pixels per art pixel (art is 54 px tall).
            val scaledHeight = 54 * max(1, (heightPx / 54).roundToInt()) / density
            val (art, aspect) = if (name == null) R.drawable.sleeping_panda_px to 72f / 54 else R.drawable.exercise_panda_px to 59f / 54

            Box(GlanceModifier.fillMaxSize().background(palette.background.provider()), contentAlignment = Alignment.Center) {
                Image(ImageProvider(art), null, GlanceModifier.size(scaledHeight.dp * aspect, scaledHeight.dp))
                Column(GlanceModifier.fillMaxSize().padding(10.dp)) {
                    Text(
                        today.format(DateTimeFormatter.ofPattern("M/d（EEEE）", Locale.TRADITIONAL_CHINESE)),
                        style = TextStyle(color = palette.textSecondary.provider(), fontSize = 11.sp),
                    )
                    Spacer(GlanceModifier.defaultWeight())
                    Text(
                        name ?: "今天休息", maxLines = 1,
                        style = TextStyle(color = palette.ink.provider(), fontSize = 12.sp, fontWeight = FontWeight.Bold),
                    )
                }
            }
        }
    }
}

class JofitWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget = JofitWidget()
}
