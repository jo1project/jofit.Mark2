import Foundation

/// A concrete, bookable instance of a class — resolved from a `CourseTemplate` by pairing it
/// with the one calendar date (within the form's 7-day booking window) that matches its weekday.
struct Course: Identifiable, Hashable, Codable {
    let id: String
    let month: Int
    let day: Int
    let weekday: String
    let time: String
    let name: String

    var dateText: String {
        String(format: "%d/%02d", month, day)
    }

    /// Must match the format the Jofit admin parses by hand, e.g. "1/16 週六 1120 燃脂泰拳".
    var submissionText: String {
        "\(dateText) \(weekday) \(time) \(name)"
    }
}
