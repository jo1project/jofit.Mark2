import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var courseStore: CourseStore
    @EnvironmentObject private var reservationStore: ReservationStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: AppTab = .courses

    private enum AppTab: CaseIterable {
        case courses, history, settings

        var title: String {
            switch self {
            case .courses: return "課程"
            case .history: return "紀錄"
            case .settings: return "設定"
            }
        }

        var icon: String {
            switch self {
            case .courses: return "calendar"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        // A custom floating bar instead of TabView: the system tab bar can't be given a gold
        // selection capsule reliably across iOS versions. All three screens stay alive in the
        // ZStack (just hidden) so unsent selections and filters survive tab switches, and the
        // bar is a real bottom safe-area inset so scroll content ends above it.
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { item in
                page(item)
                    .opacity(tab == item ? 1 : 0)
                    .allowsHitTesting(tab == item)
                    .accessibilityHidden(tab != item)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .tint(Theme.accent)
        .task {
            await courseStore.refresh()
            await reservationStore.refresh()
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
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { item in
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
    }
}
