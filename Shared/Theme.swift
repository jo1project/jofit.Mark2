import SwiftUI
import UIKit

/// Single source of truth for the app's look, compiled into BOTH the app and the widget
/// (that's why it lives in `Shared/`). Every color has a light and a dark value; views must
/// reference these tokens instead of hard-coding hex values or system colors.
/// App-only pieces (course categories, button style, nav-bar appearance) are in
/// `Jofit/ThemeApp.swift`.
///
/// The user picks an `AppTheme` in Settings; `Theme.xxx` resolves against it every time it is
/// read, so views never mention the theme. The chosen theme lives in the shared App Group
/// defaults so the widget sees it too. Switching rebuilds the pages (`.id(theme)` in
/// `ContentView`) so already-built views re-read their tokens.
///
/// Three surface layers, lightest to darkest in light mode: card > background > chip.
enum Theme {
    typealias Pair = (light: UInt32, dark: UInt32)

    struct Palette {
        var background, card, chipIdle: Pair
        /// Fills and borders (selected chips, tab capsule).
        var brand: Pair
        /// Brand-family color that IS safe for text/glyphs (AA on background and card).
        var accent: Pair
        var ink, textSecondary, checkBrown, tabUnselected: Pair
        /// Fill of the primary button, its label, and whether it gets a `brand` outline.
        var primaryFill, primaryText: Pair
        var primaryOutlined: Bool
        var onInk, onBrand, danger: Pair
        // Course-category bars.
        var strength, cardio, dance, conditioning, other: Pair
        // Shape & weight.
        var cardRadius, chipRadius: CGFloat
        var title, strong, label: Font.Weight
        var navLargeTitle: UIFont.Weight
    }

    static var palette: Palette { AppTheme.current.palette }

    // MARK: UIKit twins (nav bar / tint appearance can't take SwiftUI Colors)

    enum UI {
        static var accent: UIColor { .dynamic(palette.accent) }
        static var ink: UIColor { .dynamic(palette.ink) }
    }

    // MARK: Colors — (light, dark)

    /// Screen background.
    static var background: Color { color(palette.background) }
    /// Card surface.
    static var card: Color { color(palette.card) }
    /// Chip surface: one step darker than the card in light mode, one step lighter in dark.
    static var chipIdle: Color { color(palette.chipIdle) }
    /// Brand fill. Fills and borders only — never text on a light background.
    static var brand: Color { color(palette.brand) }
    /// Text-safe brand color. Used as the global tint.
    static var accent: Color { Color(uiColor: UI.accent) }
    /// Primary text.
    static var ink: Color { Color(uiColor: UI.ink) }
    /// Secondary text, AA on background / card / chip in both modes.
    static var textSecondary: Color { color(palette.textSecondary) }
    /// "Done" check marks on chips.
    static var checkBrown: Color { color(palette.checkBrown) }
    /// Inactive tab items.
    static var tabUnselected: Color { color(palette.tabUnselected) }
    /// Foreground on `danger` fills.
    static var onInk: Color { color(palette.onInk) }
    /// Foreground on `brand`.
    static var onBrand: Color { color(palette.onBrand) }
    /// Errors / failed state.
    static var danger: Color { color(palette.danger) }
    static var hairline: Color { ink.opacity(0.12) }

    private static func color(_ pair: Pair) -> Color { Color(uiColor: .dynamic(pair)) }

    // MARK: Shape & weight

    enum Radius {
        static var card: CGFloat { palette.cardRadius }
        static var chip: CGFloat { palette.chipRadius }
    }

    enum Weight {
        /// Big titles, section titles, course names.
        static var title: Font.Weight { palette.title }
        static var strong: Font.Weight { palette.strong }
        static var label: Font.Weight { palette.label }
    }
}

// MARK: - Themes

enum AppTheme: String, CaseIterable, Identifiable {
    case classic, apple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "經典"
        case .apple: return "Apple 風格"
        }
    }

    private static let key = "settings.theme"
    private static var defaults: UserDefaults { UserDefaults(suiteName: WidgetData.appGroupID) ?? .standard }

    /// Persisted in the App Group so the widget process reads the same value.
    static var current: AppTheme {
        get { defaults.string(forKey: key).flatMap(AppTheme.init(rawValue:)) ?? .classic }
        set { defaults.set(newValue.rawValue, forKey: key) }
    }

    var palette: Theme.Palette {
        switch self {
        case .classic: return .classic
        case .apple: return .apple
        }
    }
}

extension Theme.Palette {
    /// Cream + gold + brown-black. Gold is low-contrast on cream, hence the separate `accent`.
    static let classic = Theme.Palette(
        background: (0xF5E9CB, 0x170D0A), card: (0xFFFDF7, 0x2C1D18), chipIdle: (0xE8D8AC, 0x42302A),
        brand: (0xE8B820, 0xE8B820), accent: (0x6F5300, 0xE8B820),
        ink: (0x1A0A08, 0xFBF1DA), textSecondary: (0x66513F, 0xCDBBA8),
        checkBrown: (0x5C3A26, 0xD8B898), tabUnselected: (0x6B5A4E, 0xBBA995),
        primaryFill: (0x1A0A08, 0x3A2620), primaryText: (0xE8B820, 0xE8B820), primaryOutlined: true,
        onInk: (0xFFFFFF, 0xFFFFFF), onBrand: (0x1A0A08, 0x1A0A08), danger: (0xA63D2F, 0xE07A65),
        strength: (0x8B5E3C, 0xC9976B), cardio: (0x627629, 0xA9BB6B), dance: (0xB04A35, 0xE28C77),
        conditioning: (0x5B7083, 0x93AABD), other: (0x7D6E5E, 0x9C8B7C),
        cardRadius: 22, chipRadius: 16,
        title: .heavy, strong: .bold, label: .semibold, navLargeTitle: .heavy
    )

    /// iOS-native look: system greys, white cards, Apple blue, tighter corners, lighter weights.
    static let apple = Theme.Palette(
        background: (0xF2F2F7, 0x000000), card: (0xFFFFFF, 0x1C1C1E), chipIdle: (0xE5E5EA, 0x2C2C2E),
        brand: (0x0071E3, 0x0071E3), accent: (0x0066CC, 0x2997FF),
        ink: (0x1D1D1F, 0xF5F5F7), textSecondary: (0x636366, 0xAEAEB2),
        checkBrown: (0x48484A, 0xD1D1D6), tabUnselected: (0x6E6E73, 0x98989D),
        primaryFill: (0x0071E3, 0x0071E3), primaryText: (0xFFFFFF, 0xFFFFFF), primaryOutlined: false,
        onInk: (0xFFFFFF, 0xFFFFFF), onBrand: (0xFFFFFF, 0xFFFFFF), danger: (0xC9342B, 0xFF5A52),
        strength: (0x8E6A47, 0xC49A6C), cardio: (0x1E7A34, 0x30D158), dance: (0xC9342B, 0xFF6961),
        conditioning: (0x5856D6, 0x9E9CFF), other: (0x6E6E73, 0x98989D),
        cardRadius: 16, chipRadius: 12,
        title: .bold, strong: .semibold, label: .semibold, navLargeTitle: .bold
    )
}

// MARK: - Color plumbing

extension UIColor {
    static func dynamic(_ pair: Theme.Pair) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: pair.dark) : UIColor(hex: pair.light) }
    }

    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
