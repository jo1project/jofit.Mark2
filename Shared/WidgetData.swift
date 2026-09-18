import Foundation

/// A slimmed-down copy of submitted reservations, written by the main app into the shared
/// App Group container so the widget extension (a separate process that can't see the app's
/// own UserDefaults/files) can read it.
struct SharedCourseEntry: Codable {
    let date: Date
    let name: String
    let time: String
}

struct WidgetData: Codable {
    let submittedCourses: [SharedCourseEntry]
    let updatedAt: Date

    static let appGroupID = "group.com.jofit.autobooking"
    private static let storageKey = "widget_data"

    static func load() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(WidgetData.self, from: data) else {
            return WidgetData(submittedCourses: [], updatedAt: .distantPast)
        }
        return decoded
    }

    func save() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func courses(on day: Date, calendar: Calendar = .current) -> [SharedCourseEntry] {
        submittedCourses
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.time < $1.time }
    }
}
