import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var courseStore: CourseStore
    @EnvironmentObject private var reservationStore: ReservationStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab = .courses
    /// Measured height of the floating tab bar (initial value is an estimate for the first frame).
    @State private var tabBarHeight: CGFloat = 72

    private enum AppTab: CaseIterable {
        case courses, history, settings, admin

        var title: String {
            switch self {
            case .courses: return "課程"
            case .history: return "紀錄"
            case .settings: return "設定"
            case .admin: return "編輯"
            }
        }

        var icon: String {
            switch self {
            case .courses: return "calendar"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape"
            case .admin: return "square.and.pencil"
            }
        }
    }

    /// The edit tab exists only for the admin (see `UserSettings.isAdmin`).
    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { $0 != .admin || settings.isAdmin }
    }

    var body: some View {
        // A custom floating bar instead of TabView: the system tab bar can't be given a gold
        // selection capsule reliably across iOS versions. All three screens stay alive in the
        // ZStack (just hidden) so unsent selections and filters survive tab switches. The bar
        // floats as an overlay; each screen reserves its height itself via `clearOfTabBar()`,
        // because an outer safe-area inset does not reach inside NavigationStack.
        ZStack {
            ForEach(visibleTabs, id: \.self) { item in
                page(item)
                    .opacity(tab == item ? 1 : 0)
                    .allowsHitTesting(tab == item)
                    .accessibilityHidden(tab != item)
            }
        }
        // Rebuild the pages on theme change so views re-read `Theme` tokens (unsent selections
        // and filters reset; the tab itself is kept).
        .id(settings.theme)
        .environment(\.tabBarInset, tabBarHeight)
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .bottom) { tabBar }
        .onPreferenceChange(TabBarHeightKey.self) { tabBarHeight = $0 }
        .tint(Theme.accent)
        .task {
            await courseStore.refresh()
            await reservationStore.refresh()
        }
        .onChange(of: settings.isAdmin) { _, isAdmin in
            if !isAdmin && tab == .admin { tab = .settings }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await courseStore.refresh()
                await reservationStore.refresh()
            }
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            guard scenePhase == .active else { return }
            Task { await reservationStore.refresh() }
        }
        .fullScreenCover(isPresented: .constant(!settings.hasOnboarded)) {
            OnboardingView()
        }
    }
}

extension ContentView {
    @ViewBuilder
    private func page(_ item: AppTab) -> some View {
        switch item {
        case .courses: CoursesView()
        case .history: HistoryView()
        case .settings: SettingsView()
        case .admin: EditCoursesView()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(visibleTabs, id: \.self) { item in
                let isOn = tab == item
                Button {
                    withAnimation(.snappy(duration: 0.2)) { tab = item }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: item.icon)
                            .font(.system(size: 19, weight: Theme.Weight.label))
                        Text(item.title)
                            .font(.caption2.weight(Theme.Weight.label))
                    }
                    .foregroundStyle(isOn ? Theme.onBrand : Theme.tabUnselected)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(isOn ? Theme.brand : Color.clear))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 24)
        .padding(.bottom, 4)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: TabBarHeightKey.self, value: proxy.size.height)
        })
    }
}

private struct TabBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct TabBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var tabBarInset: CGFloat {
        get { self[TabBarInsetKey.self] }
        set { self[TabBarInsetKey.self] = newValue }
    }
}

private struct TabBarClearance: ViewModifier {
    @Environment(\.tabBarInset) private var inset

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: inset + 8)
        }
    }
}

extension View {
    /// Keeps this screen's content (and any bottom bar attached BEFORE this call) above the
    /// floating tab bar. Apply it last among the bottom `safeAreaInset`s so it is outermost.
    func clearOfTabBar() -> some View {
        modifier(TabBarClearance())
    }
}
