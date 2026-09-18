import SwiftUI

struct CoursesView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var courseStore: CourseStore
    @EnvironmentObject private var reservationStore: ReservationStore

    @State private var timeFilter: TimeFilter = .all
    @State private var shownWeekdays: Set<String> = Set(CoursesView.weekdayOrder)
    @State private var showFilters = false
    @State private var selectedInstanceIDs: Set<String> = []
    @State private var isSubmitting = false
    @State private var reservationPendingCancel: Reservation?

    static let weekdayOrder = ["週一", "週二", "週三", "週四", "週五", "週六", "週日"]

    enum TimeFilter: String, CaseIterable, Identifiable {
        case all = "全部顯示"
        case night = "夜間（20:00 後）"
        case day = "非夜間（20:00 前）"
        var id: String { rawValue }
    }

    private struct TemplateGroup: Identifiable {
        let templateID: String
        let name: String
        let time: String
        let weekdayLabel: String
        let instances: [Course] // sorted by date, one per upcoming week
        var id: String { templateID }
    }

    private var filteredCourses: [Course] {
        courseStore.courses.filter { course in
            guard shownWeekdays.contains(course.weekdayLabel) else { return false }
            switch timeFilter {
            case .all: return true
            case .night: return (Int(course.time) ?? 0) >= 2000
            case .day: return (Int(course.time) ?? 0) < 2000
            }
        }
    }

    private var groupedByWeekday: [(weekday: String, templates: [TemplateGroup])] {
        let templateGroups = Dictionary(grouping: filteredCourses, by: \.templateID).map { key, courses -> TemplateGroup in
            let sorted = courses.sorted { $0.date < $1.date }
            let first = sorted[0]
            return TemplateGroup(templateID: key, name: first.name, time: first.time, weekdayLabel: first.weekdayLabel, instances: sorted)
        }
        let byWeekday = Dictionary(grouping: templateGroups, by: \.weekdayLabel)
        return Self.weekdayOrder.compactMap { day in
            guard let templates = byWeekday[day], !templates.isEmpty else { return nil }
            // Three classrooms means multiple classes can share the same weekday+time — sort by
            // (time, templateID) rather than time alone, so ties break on something stable and
            // unique instead of Dictionary's iteration order, which isn't guaranteed consistent
            // across re-renders and was making tied rows visibly swap places on every tap.
            return (day, templates.sorted { ($0.time, $0.templateID) < ($1.time, $1.templateID) })
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !settings.isComplete {
                    Section {
                        Text("請先到「設定」分頁填寫姓名與員工編號")
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = reservationStore.lastSyncError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                ForEach(groupedByWeekday, id: \.weekday) { group in
                    Section(group.weekday) {
                        ForEach(group.templates) { template in
                            templateRow(template)
                        }
                    }
                }
            }
            .navigationTitle("課程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Label("篩選", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .refreshable {
                await courseStore.refresh()
            }
            .sheet(isPresented: $showFilters) {
                FilterView(timeFilter: $timeFilter, shownWeekdays: $shownWeekdays)
                    .presentationDetents([.medium, .large])
            }
            .overlay {
                if filteredCourses.isEmpty {
                    ContentUnavailableView("沒有符合條件的課程", systemImage: "calendar.badge.exclamationmark")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedInstanceIDs.isEmpty {
                    submitBar
                }
            }
            .confirmationDialog(
                "這堂課要取消預約嗎？",
                isPresented: Binding(
                    get: { reservationPendingCancel != nil },
                    set: { if !$0 { reservationPendingCancel = nil } }
                ),
                presenting: reservationPendingCancel
            ) { reservation in
                Button(reservation.status == .failed ? "移除" : "取消預約", role: .destructive) {
                    Task { await reservationStore.cancel(reservation) }
                }
            } message: { reservation in
                Text(reservation.course.submissionText)
            }
        }
    }

    private var submitBar: some View {
        Button {
            submitSelected()
        } label: {
            if isSubmitting {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("送出預約（\(selectedInstanceIDs.count)）")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSubmitting || !settings.isComplete)
        .padding()
        .background(.bar)
    }

    private func submitSelected() {
        let ids = selectedInstanceIDs
        let coursesToSubmit = courseStore.courses.filter { ids.contains($0.id) }
        isSubmitting = true
        Task {
            for course in coursesToSubmit {
                await reservationStore.reserve(course: course, name: settings.name, employeeID: settings.employeeID)
                selectedInstanceIDs.remove(course.id)
            }
            isSubmitting = false
        }
    }

    @ViewBuilder
    private func templateRow(_ group: TemplateGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(displayTime(group.time))　\(group.name)")
                .font(.body)
            HStack(spacing: 10) {
                ForEach(group.instances) { course in
                    weekOption(course)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func weekOption(_ course: Course) -> some View {
        let reservation = reservationStore.reservation(for: course.id)
        let isSelected = selectedInstanceIDs.contains(course.id)

        Button {
            switch reservation?.status {
            case nil:
                if isSelected {
                    selectedInstanceIDs.remove(course.id)
                } else {
                    selectedInstanceIDs.insert(course.id)
                }
            case .pending, .failed:
                reservationPendingCancel = reservation
            case .submitting, .submitted:
                break
            }
        } label: {
            VStack(spacing: 4) {
                statusOrCheckIcon(reservation: reservation, isSelected: isSelected)
                Text(course.dateText)
                    .font(.caption2)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(optionBackground(reservation: reservation, isSelected: isSelected))
            )
        }
        .buttonStyle(.plain)
        .disabled(reservation?.status == .submitting || reservation?.status == .submitted)
    }

    @ViewBuilder
    private func statusOrCheckIcon(reservation: Reservation?, isSelected: Bool) -> some View {
        switch reservation?.status {
        case .submitted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .pending, .submitting:
            Image(systemName: "clock.fill").foregroundStyle(.blue)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case nil:
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
    }

    private func optionBackground(reservation: Reservation?, isSelected: Bool) -> Color {
        if reservation != nil {
            return Color(.secondarySystemBackground)
        }
        return isSelected ? Color.accentColor.opacity(0.15) : Color(.secondarySystemBackground)
    }

    private func displayTime(_ time: String) -> String {
        guard time.count == 4 else { return time }
        return "\(time.prefix(2)):\(time.suffix(2))"
    }
}
