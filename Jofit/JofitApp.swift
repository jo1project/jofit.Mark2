import SwiftUI

@main
struct JofitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: UserSettings
    @StateObject private var courseStore = CourseStore()
    @StateObject private var reservationStore: ReservationStore

    init() {
        let settings = UserSettings()
        _settings = StateObject(wrappedValue: settings)
        _reservationStore = StateObject(wrappedValue: ReservationStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(courseStore)
                .environmentObject(reservationStore)
                .onAppear {
                    appDelegate.onDeviceToken = { token in
                        Task { await reservationStore.registerDeviceToken(token) }
                    }
                }
        }
    }
}
