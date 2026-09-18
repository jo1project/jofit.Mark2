import Foundation

struct Course: Identifiable, Hashable {
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

/// Update this list whenever the gym publishes a new week's schedule, then push to `main`
/// so the GitHub Actions workflow builds a fresh TestFlight release.
enum Courses {
    static let all: [Course] = [
        Course(id: "2026-01-16-1120-muaythai", month: 1, day: 16, weekday: "週六", time: "1120", name: "燃脂泰拳"),
        Course(id: "2026-01-17-0900-pilates", month: 1, day: 17, weekday: "週日", time: "0900", name: "皮拉提斯"),
        Course(id: "2026-01-18-1900-boxing", month: 1, day: 18, weekday: "週一", time: "1900", name: "拳擊有氧"),
    ]
}
