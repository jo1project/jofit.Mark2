package com.jofit.autobooking.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * Single source of truth for the app's look — the Android twin of `Shared/Theme.swift`; keep
 * the palettes' hex values identical. Every color has a light and a dark value; screens must
 * read [Theme.c] instead of hard-coding hex values or Material colors. The user picks an
 * [AppTheme] in Settings and dark mode follows the system.
 *
 * Three surface layers, lightest to darkest in light mode: card > background > chip.
 */
class Duo(val light: Long, val dark: Long) {
    fun pick(isDark: Boolean) = Color(0xFF000000 or if (isDark) dark else light)
}

private fun d(light: Long, dark: Long) = Duo(light, dark)

class Palette(
    val background: Duo, val card: Duo, val chipIdle: Duo,
    /** Fills and borders (selected chips, tab capsule). */
    val brand: Duo,
    /** Brand-family color that IS safe for text/glyphs (AA on background and card). */
    val accent: Duo,
    val ink: Duo, val textSecondary: Duo, val checkBrown: Duo, val tabUnselected: Duo,
    /** Fill of the primary button, its label, and whether it gets a `brand` outline. */
    val primaryFill: Duo, val primaryText: Duo, val primaryOutlined: Boolean,
    val onBrand: Duo, val onInk: Duo, val danger: Duo,
    // Course-category bars.
    val strength: Duo, val cardio: Duo, val dance: Duo, val conditioning: Duo, val other: Duo,
    // Shape & weight.
    val cardRadius: Dp, val chipRadius: Dp,
    val title: FontWeight, val strong: FontWeight, val label: FontWeight,
)

enum class AppTheme(val title: String, val palette: Palette) {
    /** Cream + gold + brown-black. Gold is low-contrast on cream, hence the separate `accent`. */
    Classic(
        "經典",
        Palette(
            background = d(0xF5E9CB, 0x170D0A), card = d(0xFFFDF7, 0x2C1D18), chipIdle = d(0xE8D8AC, 0x42302A),
            brand = d(0xE8B820, 0xE8B820), accent = d(0x6F5300, 0xE8B820),
            ink = d(0x1A0A08, 0xFBF1DA), textSecondary = d(0x66513F, 0xCDBBA8),
            checkBrown = d(0x5C3A26, 0xD8B898), tabUnselected = d(0x6B5A4E, 0xBBA995),
            primaryFill = d(0x1A0A08, 0x3A2620), primaryText = d(0xE8B820, 0xE8B820), primaryOutlined = true,
            onBrand = d(0x1A0A08, 0x1A0A08), onInk = d(0xFFFFFF, 0xFFFFFF), danger = d(0xA63D2F, 0xE07A65),
            strength = d(0x8B5E3C, 0xC9976B), cardio = d(0x627629, 0xA9BB6B), dance = d(0xB04A35, 0xE28C77),
            conditioning = d(0x5B7083, 0x93AABD), other = d(0x7D6E5E, 0x9C8B7C),
            cardRadius = 22.dp, chipRadius = 16.dp,
            title = FontWeight.ExtraBold, strong = FontWeight.Bold, label = FontWeight.SemiBold,
        ),
    ),

    /** Clean system-style look: greys, white cards, blue, tighter corners, lighter weights. */
    Apple(
        "Apple 風格",
        Palette(
            background = d(0xF2F2F7, 0x000000), card = d(0xFFFFFF, 0x1C1C1E), chipIdle = d(0xE5E5EA, 0x2C2C2E),
            brand = d(0x0071E3, 0x0071E3), accent = d(0x0066CC, 0x2997FF),
            ink = d(0x1D1D1F, 0xF5F5F7), textSecondary = d(0x636366, 0xAEAEB2),
            checkBrown = d(0x48484A, 0xD1D1D6), tabUnselected = d(0x6E6E73, 0x98989D),
            primaryFill = d(0x0071E3, 0x0071E3), primaryText = d(0xFFFFFF, 0xFFFFFF), primaryOutlined = false,
            onBrand = d(0xFFFFFF, 0xFFFFFF), onInk = d(0xFFFFFF, 0xFFFFFF), danger = d(0xC9342B, 0xFF5A52),
            strength = d(0x8E6A47, 0xC49A6C), cardio = d(0x1E7A34, 0x30D158), dance = d(0xC9342B, 0xFF6961),
            conditioning = d(0x5856D6, 0x9E9CFF), other = d(0x6E6E73, 0x98989D),
            cardRadius = 16.dp, chipRadius = 12.dp,
            title = FontWeight.Bold, strong = FontWeight.SemiBold, label = FontWeight.SemiBold,
        ),
    );

    companion object {
        fun from(name: String?): AppTheme = entries.firstOrNull { it.name == name } ?: Classic
    }
}

/** A [Palette] resolved for one light/dark mode. */
@Immutable
class Tokens(val p: Palette, val isDark: Boolean) {
    val background = p.background.pick(isDark)
    val card = p.card.pick(isDark)
    val chipIdle = p.chipIdle.pick(isDark)
    val brand = p.brand.pick(isDark)
    val accent = p.accent.pick(isDark)
    val ink = p.ink.pick(isDark)
    val textSecondary = p.textSecondary.pick(isDark)
    val checkBrown = p.checkBrown.pick(isDark)
    val tabUnselected = p.tabUnselected.pick(isDark)
    val primaryFill = p.primaryFill.pick(isDark)
    val primaryText = p.primaryText.pick(isDark)
    val onBrand = p.onBrand.pick(isDark)
    val onInk = p.onInk.pick(isDark)
    val danger = p.danger.pick(isDark)
    val hairline = ink.copy(alpha = 0.12f)
    val cardRadius = p.cardRadius
    val chipRadius = p.chipRadius
    val title = p.title
    val strong = p.strong
    val label = p.label
}

private val LocalTokens = staticCompositionLocalOf<Tokens> { error("JofitTheme missing") }

object Theme {
    val c: Tokens
        @Composable @ReadOnlyComposable get() = LocalTokens.current
}

@Composable
fun JofitTheme(theme: AppTheme, content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val t = remember(theme, dark) { Tokens(theme.palette, dark) }
    // Material components (dialogs, sheets, text fields) read this; our own screens read `Theme.c`.
    val scheme = (if (dark) darkColorScheme() else lightColorScheme()).copy(
        primary = t.accent, onPrimary = t.background,
        background = t.background, onBackground = t.ink,
        surface = t.card, onSurface = t.ink, surfaceTint = Color.Transparent,
        surfaceVariant = t.chipIdle, onSurfaceVariant = t.textSecondary,
        surfaceContainerHigh = t.card, surfaceContainerHighest = t.chipIdle,
        outline = t.textSecondary.copy(alpha = 0.6f), outlineVariant = t.hairline,
        error = t.danger,
    )
    CompositionLocalProvider(LocalTokens provides t) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}

// MARK: Course categories

/**
 * Color of the small bar beside each class name. Classification is by keywords in the class
 * name; edit [keywords] to re-map. Unmatched names get the neutral color.
 */
enum class CourseCategory {
    Dance, Strength, Cardio, Conditioning, Other;

    fun color(t: Tokens): Color = when (this) {
        Strength -> t.p.strength
        Cardio -> t.p.cardio
        Dance -> t.p.dance
        Conditioning -> t.p.conditioning
        Other -> t.p.other
    }.pick(t.isDark)

    companion object {
        private val keywords = listOf(
            Dance to listOf("Zumba"),
            Strength to listOf("TRX", "核心毀滅者", "肌力循環", "啞鈴"),
            Cardio to listOf("拳擊", "踢拳", "飛輪"),
            Conditioning to listOf("VIPR"),
        )

        fun of(courseName: String): CourseCategory =
            keywords.firstOrNull { (_, words) -> words.any { courseName.contains(it, ignoreCase = true) } }?.first ?: Other
    }
}
