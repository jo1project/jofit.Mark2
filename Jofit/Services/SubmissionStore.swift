import Foundation
import Combine

@MainActor
final class SubmissionStore: ObservableObject {
    @Published private(set) var records: [SubmissionRecord] = []

    private let service = FormSubmissionService()
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("submissions.json")
        load()
    }

    @discardableResult
    func submit(course: Course, name: String, employeeID: String, mode: SubmissionRecord.Mode) async -> SubmissionRecord {
        let record: SubmissionRecord
        do {
            let status = try await service.submit(name: name, employeeID: employeeID, courseText: course.submissionText)
            record = SubmissionRecord(
                id: UUID(),
                courseText: course.submissionText,
                submittedAt: Date(),
                success: (200...299).contains(status),
                httpStatus: status,
                mode: mode
            )
        } catch {
            record = SubmissionRecord(
                id: UUID(),
                courseText: course.submissionText,
                submittedAt: Date(),
                success: false,
                httpStatus: nil,
                mode: mode
            )
        }
        records.insert(record, at: 0)
        save()
        return record
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        records = (try? JSONDecoder().decode([SubmissionRecord].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
