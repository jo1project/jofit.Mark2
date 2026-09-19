import SwiftUI

/// "紀錄" shows only the current user's reservations (matched by employee ID); the admin-only
/// "伺服器" tab is the same screen with `showAll`, listing everyone's.
struct HistoryView: View {
    let showAll: Bool

    // Explicit: the synthesized memberwise init would be private because of the @State below.
    init(showAll: Bool = false) { self.showAll = showAll }

    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var reservationStore: ReservationStore
    @State private var expandedMonths: Set<String> = []
    @State private var hasSetInitialExpansion = false
    @State private var reservationPendingCancel: Reservation?

    // Admin bulk cancel (see `UserSettings.isAdmin`): pick pending rows, confirm with the PIN.
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showPinPrompt = false
    @State private var pin = ""
    @State private var isCancelling = false
    @State private var resultMessage: String?

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

    private var visible: [Reservation] {
        guard !showAll else { return reservationStore.reservations }
        return reservationStore.reservations.filter { $0.isBooked(by: settings.employeeID) }
    }

    private var scheduled: [Reservation] {
        visible.filter { $0.status == .pending || $0.status == .submitting }
    }

    /// Only reservations still waiting can be bulk-cancelled; a submitting one is mid-POST and
    /// can't be recalled, and a submitted one can't be un-submitted.
    private var pending: [Reservation] {
        visible.filter { $0.status == .pending }
    }

    private var selectedTargets: [Reservation] {
        pending.filter { selectedIDs.contains($0.id) }
    }

    private var failed: [Reservation] {
        visible.filter { $0.status == .failed }
    }

    private var submitted: [Reservation] {
        visible.filter { $0.status == .submitted }
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
                // Not Lazy: month cards change height when expanded, and LazyVStack can fail to
                // re-layout after that. The list is small, so eager is fine.
                VStack(alignment: .leading, spacing: 12) {
                    if let error = reservationStore.lastSyncError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(Theme.danger)
                    }
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
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(showAll ? "伺服器" : "預約紀錄")
            .toolbar {
                if settings.isAdmin && (isSelecting || !pending.isEmpty) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isSelecting ? "完成" : "選取") {
                            isSelecting.toggle()
                            selectedIDs = []
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { selectionBar }
            }
            .clearOfTabBar()
            .cancelConfirmation($reservationPendingCancel)
            .alert("輸入管理密碼", isPresented: $showPinPrompt) {
                SecureField("密碼", text: $pin)
                    .keyboardType(.numberPad)
                Button("取消", role: .cancel) { pin = "" }
                Button("取消 \(selectedTargets.count) 筆預約", role: .destructive) { cancelSelected() }
            } message: {
                Text("將取消 \(selectedTargets.count) 筆排程中的預約\(showAll ? "（可能包含其他人的）" : "")，無法復原。")
            }
            .alert(
                "取消結果",
                isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(resultMessage ?? "")
            }
            .refreshable {
                await reservationStore.refresh()
            }
            .overlay {
                if visible.isEmpty {
                    ContentUnavailableView(
                        showAll ? "伺服器上沒有預約" : "還沒有預約紀錄",
                        systemImage: "tray",
                        description: Text(showAll ? "" : "到「課程」挑一堂想上的課吧，剩下的交給我們，你只要準時出現就好。")
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

    // MARK: Bulk cancel

    private var selectionBar: some View {
        let allSelected = !pending.isEmpty && selectedTargets.count == pending.count
        return HStack(spacing: 16) {
            Button(allSelected ? "取消全選" : "全選") {
                selectedIDs = allSelected ? [] : Set(pending.map(\.id))
            }
            .font(.body.weight(Theme.Weight.strong))
            .foregroundStyle(Theme.accent)
            Button {
                pin = ""
                showPinPrompt = true
            } label: {
                if isCancelling {
                    ProgressView().tint(Theme.brand).frame(maxWidth: .infinity)
                } else {
                    Text("取消所選（\(selectedTargets.count)）").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.primary)
            .disabled(selectedTargets.isEmpty || isCancelling)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func cancelSelected() {
        let entered = pin
        pin = ""
        // A blank PIN would just count as a wrong attempt toward the backend's lockout.
        guard !entered.isEmpty else { resultMessage = "請輸入管理密碼"; return }
        let targets = selectedTargets
        isCancelling = true
        Task {
            do {
                let cancelled = try await reservationStore.cancelPending(targets, pin: entered)
                selectedIDs = []
                isSelecting = false
                resultMessage = cancelled == targets.count
                    ? "已取消 \(cancelled) 筆預約。"
                    : "已取消 \(cancelled) 筆，另外 \(targets.count - cancelled) 筆已經開始送出或已送出，無法取消。"
            } catch {
                // Keep the selection so a mistyped PIN can just be retried.
                resultMessage = error.localizedDescription
            }
            isCancelling = false
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
        let selectable = isSelecting && reservation.status == .pending
        return HStack(spacing: 12) {
            if selectable {
                Image(systemName: selectedIDs.contains(reservation.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIDs.contains(reservation.id) ? Theme.accent : Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(course.name)
                    .font(.body.weight(Theme.Weight.strong))
                    .foregroundStyle(Theme.ink)
                Text("\(course.dateText) \(course.weekdayLabel) \(course.timeText)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                if showAll, let who = who(booked: reservation) {
                    Text(who)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let note = note(for: reservation) {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(reservation.status == .failed ? Theme.danger : Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(status: reservation.status)
                if reservation.canDismiss && !isSelecting {
                    Button(reservation.status == .failed ? "移除" : "取消") {
                        reservationPendingCancel = reservation
                    }
                    .font(.caption.weight(Theme.Weight.strong))
                    .foregroundStyle(Theme.danger)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            guard selectable else { return }
            if !selectedIDs.insert(reservation.id).inserted { selectedIDs.remove(reservation.id) }
        }
    }

    // MARK: Formatting

    private func who(booked reservation: Reservation) -> String? {
        let parts = [reservation.reporterName, reservation.employeeID]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "・")
    }

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
