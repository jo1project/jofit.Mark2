import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var store: SubmissionStore

    var body: some View {
        NavigationStack {
            List(store.records) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.courseText)
                        .font(.body)
                    HStack {
                        Image(systemName: record.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(record.success ? .green : .red)
                        Text(record.submittedAt.formatted(date: .abbreviated, time: .standard))
                        Spacer()
                        Text(record.mode == .quick ? "快速" : "排程")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("報名紀錄")
            .overlay {
                if store.records.isEmpty {
                    ContentUnavailableView("尚無紀錄", systemImage: "tray")
                }
            }
        }
    }
}
