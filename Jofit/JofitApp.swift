import SwiftUI

@main
struct JofitApp: App {
    @StateObject private var settings = UserSettings()
    @StateObject private var store = SubmissionStore()
    @StateObject private var scheduler = ScheduleManager()
    @StateObject private var courseStore = CourseStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(scheduler)
                .environmentObject(courseStore)
        }
    }
}
