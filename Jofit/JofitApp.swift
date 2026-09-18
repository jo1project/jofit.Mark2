import SwiftUI

@main
struct JofitApp: App {
    @StateObject private var settings = UserSettings()
    @StateObject private var courseStore = CourseStore()
    @StateObject private var reservationStore = ReservationStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(courseStore)
                .environmentObject(reservationStore)
        }
    }
}
