import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var reservationStore: ReservationStore
    @State private var expandedMonths: Set<String> = []
    @State private var hasSetInitialExpansion = false

    private var groupedByMonth: [(key: String, reservations: [Reservation])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: reservationStore.reservations) {
            calendar.dateComponents([.year, .month], from: $0.course.date)
        }
        let sortedKeys = groups.keys.sorted {
            ($0.year ?? 0, $0.month ?? 0) < ($1.year ?? 0, $1.month ?? 0)
        }
        return sortedKeys.map { comps in
            let label = "\(comps.year ?? 0) 年 \(comps.month ?? 0) 月"
            let items = groups[comps]!.sorted { $0.course.date < $1.course.date }
            return (label, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedByMonth, id: \.key) { group in
                    DisclosureGroup(isExpanded: bindingForMonth(group.key)) {
                        ForEach(group.reservations) { reservation in
                            reservationRow(reservation)
                        }
                    } label: {
                        Text(group.key).font(.headline)
                    }
                }
            }
            .navigationTitle("預約紀錄")
            .overlay {
                if reservationStore.reservations.isEmpty {
                    ContentUnavailableView("尚無預約紀錄", systemImage: "tray")
                }
            }
            .onAppear {
                guard !hasSetInitialExpansion, let currentKey = groupedByMonth.first(where: { group in
                    group.reservations.contains { $0.status == .pending } || isCurrentMonth(group.key)
                })?.key ?? groupedByMonth.last?.key else { return }
                expandedMonths.insert(currentKey)
                hasSetInitialExpansion = true
            }
        }
    }

    private func isCurrentMonth(_ key: String) -> Bool {
        let now = Date()
        let comps = Calendar.current.dateComponents([.year, .month], from: now)
        return key == "\(comps.year ?? 0) 年 \(comps.month ?? 0) 月"
    }

    private func bindingForMonth(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expandedMonths.contains(key) },
            set: { isExpanded in
                if isExpanded {
                    expandedMonths.insert(key)
                } else {
                    expandedMonths.remove(key)
                }
            }
        )
    }

    @ViewBuilder
    private func reservationRow(_ reservation: Reservation) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color(for: reservation.status))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(reservation.course.submissionText)
                Text(caption(for: reservation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func color(for status: Reservation.Status) -> Color {
        switch status {
        case .submitted: return .green
        case .pending: return .blue
        case .failed: return .red
        }
    }

    private func caption(for reservation: Reservation) -> String {
        switch reservation.status {
        case .submitted:
            return "已送出 · \(reservation.submittedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")"
        case .pending:
            return "排程中 · 將於 \(reservation.fireDate.formatted(date: .abbreviated, time: .shortened)) 送出"
        case .failed:
            return "送出失敗 · \(reservation.lastError ?? "")"
        }
    }
}
