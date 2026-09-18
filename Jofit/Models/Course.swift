import Foundation

/// A concrete, bookable instance of a class on a specific calendar date — resolved from a
/// `CourseTemplate` (a weekly-recurring slot) for one particular week.
struct Course: Identifiable, Hashable, Codable {
    let id: String
    /// The `CourseTemplate.id` this instance was resolved from — lets the UI group every
    /// week's occurrence of "Monday 18:35 Zumba" back together.
    let templateID: String
    let date: Date
    let time: String
    let name: String

    private static let weekdayLabels: [Int: String] = [
        1: "週日", 2: "週一", 3: "週二", 4: "週三", 5: "週四", 6: "週五", 7: "週六",
    ]

    var weekdayLabel: String {
        Self.weekdayLabels[Calendar.current.component(.weekday, from: date)] ?? ""
    }

    var dateText: String {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        return String(format: "%d/%02d", comps.month ?? 0, comps.day ?? 0)
    }

    /// Display-only "1920" -> "19:20". `submissionText` keeps the raw form the admin parses.
    static func displayTime(_ raw: String) -> String {
        guard raw.count == 4 else { return raw }
        return "\(raw.prefix(2)):\(raw.suffix(2))"
    }

    var timeText: String { Self.displayTime(time) }

    /// Must match the format the Jofit admin parses by hand, e.g. "1/16 週六 1120 燃脂泰拳".
    var submissionText: String {
        "\(dateText) \(weekdayLabel) \(time) \(name)"
    }
}
