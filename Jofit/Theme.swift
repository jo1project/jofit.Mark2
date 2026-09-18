import SwiftUI
import UIKit

/// Single source of truth for the app's look. Every color has a light and a dark value;
/// views must reference these tokens instead of hard-coding hex values or system colors.
///
/// Gold (`brand`) is low-contrast on cream: use it for fills and borders only. Anything
/// gold-ish that has to be *read* (text, glyphs on the cream background) uses `accent`.
enum Theme {
    // MARK: UIKit twins (nav bar / tint appearance can't take SwiftUI Colors)

    enum UI {
        static let accent = UIColor.dynamic(light: 0x7A5C00, dark: 0xE8B820)
        static let ink = UIColor.dynamic(light: 0x1A0A08, dark: 0xFBF1DA)
    }

    // MARK: Colors — (light, dark)

    /// Screen background: cream / deep brown-black.
    static let background = Color(uiColor: .dynamic(light: 0xFBF1DA, dark: 0x1A0F0C))
    /// Card surface: warm white / lifted brown.
    static let card = Color(uiColor: .dynamic(light: 0xFFFBF0, dark: 0x2B1C17))
    /// Brand gold. Fills and borders only — never text on a light background.
    static let brand = Color(uiColor: .dynamic(light: 0xE8B820, dark: 0xE8B820))
    /// Brand-family color that IS safe for text/glyphs (AA on background, card and chip):
    /// deep ochre in light mode, the gold itself in dark mode. Used as the global tint.
    static let accent = Color(uiColor: UI.accent)
    /// Primary text: brown-black / cream.
    static let ink = Color(uiColor: UI.ink)
    /// Secondary text, AA on background / card / chip in both modes.
    static let textSecondary = Color(uiColor: .dynamic(light: 0x66513F, dark: 0xCDBBA8))
    /// Dark filled surfaces (submitted chip, primary button).
    static let inkFill = Color(uiColor: .dynamic(light: 0x1A0A08, dark: 0x3A2620))
    /// Foreground on `inkFill`.
    static let onInk = Color(uiColor: .dynamic(light: 0xFFFFFF, dark: 0xFFFFFF))
    /// Foreground on `brand` (dark in both modes).
    static let onBrand = Color(uiColor: .dynamic(light: 0x1A0A08, dark: 0x1A0A08))
    /// Un-selected chip fill.
    static let chipIdle = Color(uiColor: .dynamic(light: 0xF3E6C6, dark: 0x3A2720))
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

    /// Call once at launch: large-title font, nav bar background, and UIKit-drawn tints
    /// (confirmation dialogs, etc.) so nothing falls back to system blue.
    static func applyAppearance() {
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: .heavy),
            .foregroundColor: UI.ink,
        ]
        scrollEdge.titleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: UI.ink,
        ]
        let standard = UINavigationBarAppearance()
        standard.configureWithDefaultBackground()
        standard.largeTitleTextAttributes = scrollEdge.largeTitleTextAttributes
        standard.titleTextAttributes = scrollEdge.titleTextAttributes

        UINavigationBar.appearance().standardAppearance = standard
        UINavigationBar.appearance().scrollEdgeAppearance = scrollEdge
        UIView.appearance().tintColor = UI.accent
    }
}

// MARK: - Course categories

/// Left-stripe color per class type. Classification is by keywords in the class name;
/// edit `keywords` to re-map, `color` to re-color. Unmatched names get the neutral color.
enum CourseCategory {
    case dance, strength, cardio, conditioning, other

    private static let keywords: [(category: CourseCategory, words: [String])] = [
        (.dance, ["Zumba"]),
        (.strength, ["TRX", "核心毀滅者", "肌力循環", "啞鈴"]),
        (.cardio, ["拳擊", "踢拳", "飛輪"]),
        (.conditioning, ["VIPR"]),
    ]

    init(courseName: String) {
        let hit = Self.keywords.first { entry in
            entry.words.contains { courseName.localizedCaseInsensitiveContains($0) }
        }
        self = hit?.category ?? .other
    }

    /// Warm palette only: brick red, wood brown, ochre, olive, neutral taupe.
    var color: Color {
        switch self {
        case .dance: return Color(uiColor: .dynamic(light: 0xB5523B, dark: 0xD9826B))
        case .strength: return Color(uiColor: .dynamic(light: 0x8B5E3C, dark: 0xC08F68))
        case .cardio: return Color(uiColor: .dynamic(light: 0xB9791C, dark: 0xDC9F45))
        case .conditioning: return Color(uiColor: .dynamic(light: 0x6F7A3E, dark: 0xA3AE6C))
        case .other: return Color(uiColor: .dynamic(light: 0xB8A898, dark: 0x7A6A5E))
        }
    }
}

// MARK: - Reusable styles

/// Dark capsule, gold border, gold label. Use for the main action on any screen
/// (filter "完成", submit bar, onboarding, future "確認預約").
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            // Gold text is fine here only because it sits on the dark fill (~10:1).
            .foregroundStyle(Theme.brand)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(Theme.inkFill))
            .overlay(Capsule().strokeBorder(Theme.brand, lineWidth: 1.5))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension View {
    /// Warm-white rounded card with a hairline border.
    func cardBackground() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return self
            .background(Theme.card)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
