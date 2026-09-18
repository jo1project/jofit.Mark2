import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var courseStore: CourseStore
    @EnvironmentObject private var reservationStore: ReservationStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            CoursesView()
                .tabItem { Label("課程", systemImage: "calendar") }
            HistoryView()
                .tabItem { Label("紀錄", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
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
