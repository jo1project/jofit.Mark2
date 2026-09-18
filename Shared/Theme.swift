import SwiftUI
import UIKit

/// Single source of truth for the app's look, compiled into BOTH the app and the widget
/// (that's why it lives in `Shared/`). Every color has a light and a dark value; views must
/// reference these tokens instead of hard-coding hex values or system colors.
/// App-only pieces (course categories, button style, nav-bar appearance) are in
/// `Jofit/ThemeApp.swift`.
///
/// Gold (`brand`) is low-contrast on cream: use it for fills and borders only. Anything
/// gold-ish that has to be *read* (text, glyphs on the cream background) uses `accent`.
///
/// Three surface layers, lightest to darkest in light mode: card > background > chip.
enum Theme {
    // MARK: UIKit twins (nav bar / tint appearance can't take SwiftUI Colors)

    enum UI {
        static let accent = UIColor.dynamic(light: 0x6F5300, dark: 0xE8B820)
        static let ink = UIColor.dynamic(light: 0x1A0A08, dark: 0xFBF1DA)
    }

    // MARK: Colors — (light, dark)

    /// Screen background: deeper cream / deep brown-black.
    static let background = Color(uiColor: .dynamic(light: 0xF5E9CB, dark: 0x170D0A))
    /// Card surface: near-white cream / lifted brown.
    static let card = Color(uiColor: .dynamic(light: 0xFFFDF7, dark: 0x2C1D18))
    /// Chip surface: one step darker than the card in light mode, one step lighter in dark.
    static let chipIdle = Color(uiColor: .dynamic(light: 0xE8D8AC, dark: 0x42302A))
    /// Brand gold. Fills and borders only — never text on a light background.
    static let brand = Color(uiColor: .dynamic(light: 0xE8B820, dark: 0xE8B820))
    /// Brand-family color that IS safe for text/glyphs (AA on background and card):
    /// deep ochre in light mode, the gold itself in dark mode. Used as the global tint.
    static let accent = Color(uiColor: UI.accent)
    /// Primary text: brown-black / cream.
    static let ink = Color(uiColor: UI.ink)
    /// Secondary text, AA on background / card / chip in both modes.
    static let textSecondary = Color(uiColor: .dynamic(light: 0x66513F, dark: 0xCDBBA8))
    /// Deep brown for "done" check marks on light chips.
    static let checkBrown = Color(uiColor: .dynamic(light: 0x5C3A26, dark: 0xD8B898))
    /// Inactive tab items: grey-brown.
    static let tabUnselected = Color(uiColor: .dynamic(light: 0x6B5A4E, dark: 0xBBA995))
    /// Fill of the primary button — the only place solid dark is used.
    static let inkFill = Color(uiColor: .dynamic(light: 0x1A0A08, dark: 0x3A2620))
    /// Foreground on `inkFill`.
    static let onInk = Color(uiColor: .dynamic(light: 0xFFFFFF, dark: 0xFFFFFF))
    /// Foreground on `brand` (dark in both modes).
    static let onBrand = Color(uiColor: .dynamic(light: 0x1A0A08, dark: 0x1A0A08))
    /// Errors / failed state: brick red.
    static let danger = Color(uiColor: .dynamic(light: 0xA63D2F, dark: 0xE07A65))
    static let hairline = ink.opacity(0.12)

    // MARK: Shape & weight

    enum Radius {
        static let card: CGFloat = 22
        static let chip: CGFloat = 16
    }

    enum Weight {
        /// Big titles, section titles, course names.
        static let title = Font.Weight.heavy
        static let strong = Font.Weight.bold
        static let label = Font.Weight.semibold
    }
}

// MARK: - Color plumbing

extension UIColor {
    static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
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
