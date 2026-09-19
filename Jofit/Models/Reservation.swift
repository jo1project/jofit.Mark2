import Foundation

/// A user's intent to book a specific `Course`. The VPS backend owns the actual lifecycle
/// (deciding when to submit and doing it); this is just the client's view of that state,
/// fetched from / created through `BackendClient`.
struct Reservation: Identifiable, Codable {
    let id: String
    let course: Course
    var status: Status
    let fireDate: Date
    var submittedAt: Date?
    var httpStatus: Int?
    var lastError: String?

    /// Cancellable only while still waiting for a future fire time (courses under 6 days out
    /// are sent immediately, so they never wait). A failed one can be cleared to book again.
    /// Submitting/submitted can't be recalled — Google Forms has no undo.
    var canDismiss: Bool {
        (status == .pending && fireDate > Date()) || status == .failed
    }

    enum Status: String, Codable {
        case pending
        case submitting
        case submitted
        case failed
    }
}
