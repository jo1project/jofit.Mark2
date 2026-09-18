import Foundation

/// A user's intent to book a specific `Course`, tracked from the moment they pick it through
/// to the actual form submission (which may happen immediately or days later).
struct Reservation: Identifiable, Codable {
    let id: UUID
    let course: Course
    let createdAt: Date
    let fireDate: Date
    var status: Status
    var submittedAt: Date?
    var httpStatus: Int?
    var lastError: String?

    enum Status: String, Codable {
        case pending
        case submitted
        case failed
    }

    /// The form only accepts bookings up to 6 days ahead of the class date, so registration
    /// opens at 08:00 on (class date − 6 days). If that moment has already passed — the class
    /// is less than 6 days out when the user reserves it — the reservation should fire right away.
    static func computeFireDate(for course: Course, now: Date = Date(), calendar: Calendar = .current) -> Date {
        let classDay = calendar.startOfDay(for: course.date)
        guard let openDay = calendar.date(byAdding: .day, value: -6, to: classDay) else { return now }
        var comps = calendar.dateComponents([.year, .month, .day], from: openDay)
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        let candidate = calendar.date(from: comps) ?? now
        return max(candidate, now)
    }
}
