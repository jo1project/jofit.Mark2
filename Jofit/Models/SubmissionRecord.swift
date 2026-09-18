import Foundation

struct SubmissionRecord: Identifiable, Codable {
    let id: UUID
    let courseText: String
    let submittedAt: Date
    let success: Bool
    let httpStatus: Int?
    let mode: Mode

    enum Mode: String, Codable {
        case quick
        case scheduled
    }
}
