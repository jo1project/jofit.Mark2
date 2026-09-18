import Foundation

/// A recurring weekly class slot, e.g. "every Monday at 18:35, Zumba" — `courses.json` stores
/// these rather than one-off dates, because the gym's timetable repeats every week. `CourseStore`
/// resolves each template into a concrete `Course` for the one date that currently falls inside
/// the form's 7-day booking window.
struct CourseTemplate: Codable {
    let id: String
    let weekday: String
    let time: String
    let name: String

    private static let weekdayNumbers: [String: Int] = [
        "週日": 1, "週一": 2, "週二": 3, "週三": 4, "週四": 5, "週五": 6, "週六": 7,
    ]

    /// Every weekday appears exactly once in any 7 consecutive days, so "the next date matching
    /// this weekday, counting today" always lands inside the form's today...today+6 booking
    /// window — that's the one instance worth showing.
    func resolvedCourse(from today: Date = Date(), calendar: Calendar = .current) -> Course? {
        guard let targetWeekday = Self.weekdayNumbers[weekday] else { return nil }
        let todayWeekday = calendar.component(.weekday, from: today)
        let offset = (targetWeekday - todayWeekday + 7) % 7
        guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
        let comps = calendar.dateComponents([.month, .day], from: date)
        guard let month = comps.month, let day = comps.day else { return nil }
        return Course(id: "\(id)_\(month)-\(day)", month: month, day: day, weekday: weekday, time: time, name: name)
    }
}

/// Used only before the first successful fetch of `courses.json` (e.g. first launch offline).
enum CourseTemplates {
    static let fallback: [CourseTemplate] = [
        CourseTemplate(id: "mon-1835-1", weekday: "週一", time: "1835", name: "Zumba"),
        CourseTemplate(id: "mon-1920-1", weekday: "週一", time: "1920", name: "基礎啞鈴"),
        CourseTemplate(id: "mon-2035-1", weekday: "週一", time: "2035", name: "TRX"),
    ]
}
