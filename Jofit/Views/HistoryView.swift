import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var reservationStore: ReservationStore
    @State private var expandedMonths: Set<String> = []
    @State private var hasSetInitialExpansion = false

    private struct FireGroup: Identifiable {
        let fireDate: Date
        let items: [Reservation]
        var id: Date { fireDate }
    }

    private static let dateTimeFormatter = makeFormatter("M月d日 HH:mm")
    private static let timeFormatter = makeFormatter("HH:mm")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateFormat = format
        return formatter
    }

    // MARK: Data

    private func byCourse(_ items: [Reservation]) -> [Reservation] {
        // id as a tiebreaker: two reservations can share the same day (different classrooms).
        items.sorted { ($0.course.date, $0.course.time, $0.id) < ($1.course.date, $1.course.time, $1.id) }
    }

    private var scheduled: [Reservation] {
        reservationStore.reservations.filter { $0.status == .pending || $0.status == .submitting }
    }

    private var failed: [Reservation] {
        reservationStore.reservations.filter { $0.status == .failed }
    }

    private var submitted: [Reservation] {
        reservationStore.reservations.filter { $0.status == .submitted }
    }

    /// Reservations that fire in the same minute are shown as one batch.
    private var scheduledGroups: [FireGroup] {
        let byMinute = Dictionary(grouping: scheduled) { Int($0.fireDate.timeIntervalSince1970 / 60) }
        return byMinute.values
            .map { items -> FireGroup in
                let ordered = byCourse(items)
                return FireGroup(fireDate: ordered[0].fireDate, items: ordered)
            }
            .sorted { $0.fireDate < $1.fireDate }
    }

    private var submittedByMonth: [(key: String, reservations: [Reservation])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: submitted) {
            calendar.dateComponents([.year, .month], from: $0.course.date)
        }
        let sortedKeys = groups.keys.sorted {
            ($0.year ?? 0, $0.month ?? 0) < ($1.year ?? 0, $1.month ?? 0)
        }
        return sortedKeys.map { comps in
            ("\(comps.year ?? 0) 年 \(comps.month ?? 0) 月", byCourse(groups[comps]!))
        }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !scheduledGroups.isEmpty {
                        sectionTitle("排程中", count: scheduled.count)
                        ForEach(scheduledGroups) { group in
                            batchCard(group)
                        }
                    }
                    if !failed.isEmpty {
                        sectionTitle("送出失敗", count: failed.count)
                        VStack(spacing: 0) { rows(failed) }
                            .padding(.horizontal, 16)
                            .cardBackground()
                    }
                    if !submitted.isEmpty {
                        sectionTitle("已送出", count: submitted.count)
                        ForEach(submittedByMonth, id: \.key) { month in
                            monthCard(month.key, month.reservations)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .clearOfTabBar()
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("預約紀錄")
            .refreshable {
                await reservationStore.refresh()
            }
            .overlay {
                if reservationStore.reservations.isEmpty {
                    ContentUnavailableView(
                        "還沒有預約紀錄",
                        systemImage: "tray",
                        description: Text("到「課程」挑一堂想上的課吧，剩下的交給我們，你只要準時出現就好。")
                    )
                }
            }
            .onAppear {
                guard !hasSetInitialExpansion,
                      let key = submittedByMonth.first(where: { isCurrentMonth($0.key) })?.key ?? submittedByMonth.last?.key
                else { return }
                expandedMonths.insert(key)
                hasSetInitialExpansion = true
            }
        }
    }

    // MARK: Pieces

    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(text)
                .font(.title3.weight(Theme.Weight.title))
                .foregroundStyle(Theme.ink)
            Text("\(count)")
                .font(.subheadline.weight(Theme.Weight.label).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 8)
    }

    private func batchCard(_ group: FireGroup) -> some View {
        let when = friendly(group.fireDate)
        let title = group.items.count > 1 ? "\(when) 一併送出・\(group.items.count) 筆" : "\(when) 送出"
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.subheadline.weight(Theme.Weight.strong))
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.subheadline.weight(Theme.Weight.strong))
                    .foregroundStyle(Theme.ink)
            }
            .padding(.vertical, 12)
            Hairline()
            rows(group.items)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func monthCard(_ key: String, _ items: [Reservation]) -> some View {
        let isExpanded = expandedMonths.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) {
                    if isExpanded {
                        expandedMonths.remove(key)
                    } else {
                        expandedMonths.insert(key)
                    }
                }
            } label: {
                HStack {
                    Text(key)
                        .font(.headline.weight(Theme.Weight.title))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(items.count) 筆")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(Theme.Weight.strong))
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "已展開" : "已收合")

            if isExpanded {
                Hairline()
                rows(items)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private func rows(_ items: [Reservation]) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, reservation in
            if index > 0 { Hairline() }
            reservationRow(reservation)
        }
    }

    private func reservationRow(_ reservation: Reservation) -> some View {
        let course = reservation.course
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.body.weight(Theme.Weight.strong))
                    .foregroundStyle(Theme.ink)
                Text("\(course.dateText) \(course.weekdayLabel) \(course.timeText)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                if let note = note(for: reservation) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(reservation.status == .failed ? Theme.danger : Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            StatusPill(status: reservation.status)
        }
        .padding(.vertical, 12)
    }

    // MARK: Formatting

    /// The pill already says the status; this adds only what it can't (when / why).
    /// Scheduled rows need none — their batch header carries the send time.
    private func note(for reservation: Reservation) -> String? {
        switch reservation.status {
        case .submitted:
            return reservation.submittedAt.map { "\(friendly($0)) 送出" }
        case .failed:
            return reservation.lastError ?? "送出失敗"
        case .pending, .submitting:
            return nil
        }
    }

    /// "今天 08:00" / "明天 08:00" / "9月19日 07:05"
    private func friendly(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天 " + Self.timeFormatter.string(from: date) }
        if calendar.isDateInTomorrow(date) { return "明天 " + Self.timeFormatter.string(from: date) }
        return Self.dateTimeFormatter.string(from: date)
    }

    private func isCurrentMonth(_ key: String) -> Bool {
        let comps = Calendar.current.dateComponents([.year, .month], from: Date())
        return key == "\(comps.year ?? 0) 年 \(comps.month ?? 0) 月"
    }
}
