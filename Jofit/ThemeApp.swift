import SwiftUI
import UIKit

/// App-only theme pieces. The palette itself lives in `Shared/Theme.swift` so the widget
/// can use it too.

extension Theme {
    /// Call once at launch: large-title font, nav bar background, and UIKit-drawn tints
    /// (confirmation dialogs, etc.) so nothing falls back to system blue.
    static func applyAppearance() {
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithTransparentBackground()
        scrollEdge.largeTitleTextAttributes = [
            .font: UIFont.systemFont(ofSize: 34, weight: palette.navLargeTitle),
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

/// Color of the small bar beside each class name. Classification is by keywords in the class
/// name; edit `keywords` to re-map, `color` to re-color. Unmatched names get the neutral color
/// (and, in DEBUG builds, are printed once so you can add a keyword for them).
enum CourseCategory {
    case dance, strength, cardio, conditioning, other

    private static let keywords: [(category: CourseCategory, words: [String])] = [
        (.dance, ["Zumba"]),
        (.strength, ["TRX", "核心毀滅者", "肌力循環", "啞鈴"]),
        (.cardio, ["拳擊", "踢拳", "飛輪"]),
        (.conditioning, ["VIPR"]),
    ]

    #if DEBUG
    private static var loggedUnmatched = Set<String>()
    #endif

    init(courseName: String) {
        let hit = Self.keywords.first { entry in
            entry.words.contains { courseName.range(of: $0, options: .caseInsensitive) != nil }
        }
        #if DEBUG
        if hit == nil, Self.loggedUnmatched.insert(courseName).inserted {
            print("[CourseCategory] unmatched course name: \(courseName)")
        }
        #endif
        self = hit?.category ?? .other
    }

    /// Four clearly different hues plus a neutral, each ≥ 4.5:1 against the card in both modes
    /// (the actual values are per theme, in `Theme.Palette`).
    var color: Color {
        let p = Theme.palette
        let pair: Theme.Pair
        switch self {
        case .strength: pair = p.strength
        case .cardio: pair = p.cardio
        case .dance: pair = p.dance
        case .conditioning: pair = p.conditioning
        case .other: pair = p.other
        }
        return Color(uiColor: .dynamic(pair))
    }
}

// MARK: - Reusable styles

/// The main action on any screen (filter "完成", submit bar, onboarding, future "確認預約").
/// Classic: dark capsule, gold border, gold label. Apple: solid blue capsule, white label.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let p = Theme.palette
        return configuration.label
            .font(.headline)
            .foregroundStyle(Color(uiColor: .dynamic(p.primaryText)))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color(uiColor: .dynamic(p.primaryFill))))
            .overlay(Capsule().strokeBorder(Theme.brand, lineWidth: p.primaryOutlined ? 1.5 : 0))
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
