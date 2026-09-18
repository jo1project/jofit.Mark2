import Foundation

/// A recurring weekly class slot, e.g. "every Monday at 18:35, Zumba" — `courses.json` stores
/// these rather than one-off dates, because the gym's timetable repeats every week.
/// `CourseStore` expands each template into concrete `Course` instances, one per upcoming week.
struct CourseTemplate: Codable {
    let id: String
    let weekday: String
    let time: String
    let name: String

    private static let weekdayNumbers: [String: Int] = [
        "週日": 1, "週一": 2, "週二": 3, "週三": 4, "週四": 5, "週五": 6, "週六": 7,
    ]

    /// Every weekday appears exactly once in any 7 consecutive days, so "the next date matching
    /// this weekday, counting today" is week 0; adding multiples of 7 gives the following weeks.
    func resolvedCourses(weeksAhead: Int, from today: Date = Date(), calendar: Calendar = .current) -> [Course] {
        guard let targetWeekday = Self.weekdayNumbers[weekday] else { return [] }
        let startOfToday = calendar.startOfDay(for: today)
        let todayWeekday = calendar.component(.weekday, from: startOfToday)
        let firstOffset = (targetWeekday - todayWeekday + 7) % 7

        return (0..<weeksAhead).compactMap { week -> Course? in
            let totalOffset = firstOffset + week * 7
            guard let date = calendar.date(byAdding: .day, value: totalOffset, to: startOfToday) else { return nil }
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let stamp = String(format: "%04d%02d%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
            return Course(id: "\(id)_\(stamp)", date: date, time: time, name: name)
        }
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
