import SwiftUI

@main
struct JofitApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = UserSettings()
    @StateObject private var courseStore = CourseStore()
    @StateObject private var reservationStore = ReservationStore()

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
