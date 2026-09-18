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
        .task {
            await courseStore.refresh()
            await checkDueReservations()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await courseStore.refresh()
                await checkDueReservations()
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard scenePhase == .active else { return }
            Task { await checkDueReservations() }
        }
        .fullScreenCover(isPresented: .constant(!settings.hasOnboarded)) {
            OnboardingView()
        }
    }

    private func checkDueReservations() async {
        await reservationStore.processDue(name: settings.name, employeeID: settings.employeeID)
    }
}
