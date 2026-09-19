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

    private var isFilterActive: Bool {
        timeFilter != .all || shownWeekdays.count != Self.weekdayOrder.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Cards carry their own horizontal padding (not the stack) so the pinned
                // weekday headers can paint edge to edge and hide cards scrolling under them.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if !settings.isComplete {
                        banner("請先到「設定」分頁填寫姓名與員工編號", color: Theme.textSecondary)
                    }
                    if let error = reservationStore.lastSyncError {
                        banner(error, color: Theme.danger)
                    }
                    activeFilterRow
                    ForEach(groupedByWeekday, id: \.weekday) { group in
                        Section {
                            VStack(spacing: 12) {
                                ForEach(group.templates) { template in
                                    templateCard(template)
                                        .padding(.horizontal, 16)
                                }
                            }
                            // 20 here + 4 of the next header's top padding = 24pt before the next weekday.
                            .padding(.bottom, 20)
                        } header: {
                            weekdayHeader(group.weekday)
                        }
                    }
                }
            }
            .contentMargins(.bottom, 24, for: .scrollContent)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("課程")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .overlay(alignment: .topTrailing) {
                                if isFilterActive {
                                    Circle()
                                        .fill(Theme.brand)
                                        .frame(width: 9, height: 9)
                                        .overlay(Circle().strokeBorder(Theme.background, lineWidth: 1.5))
                                        .offset(x: 3, y: -3)
                                }
                            }
                    }
                    .accessibilityLabel("篩選")
                    .accessibilityValue(isFilterActive ? "已啟用" : "")
                }
            }
            .refreshable {
                await courseStore.refresh()
            }
            .sheet(isPresented: $showFilters) {
                FilterView(timeFilter: $timeFilter, shownWeekdays: $shownWeekdays)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(28)
            }
            .overlay {
                if filteredCourses.isEmpty {
                    ContentUnavailableView(
                        "沒有符合條件的課程",
                        systemImage: "calendar.badge.exclamationmark",
                        description: isFilterActive ? Text("篩選條件有點嚴格，放寬一點試試看") : nil
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedInstanceIDs.isEmpty {
                    submitBar
                }
            }
            .clearOfTabBar()
            .cancelConfirmation($reservationPendingCancel)
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(color)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
    }

    /// Summary of non-default filters, shown under the title. Hidden when nothing is filtered.
    @ViewBuilder
    private var activeFilterRow: some View {
        if isFilterActive {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if timeFilter != .all {
                        TagPill(text: timeFilter.rawValue)
                    }
                    if shownWeekdays.count != Self.weekdayOrder.count {
                        let days = Self.weekdayOrder.filter { shownWeekdays.contains($0) }.map { String($0.dropFirst()) }
                        TagPill(text: days.isEmpty ? "未選任何星期" : "星期 " + days.joined(separator: "・"))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 12)
        }
    }

    private func weekdayHeader(_ day: String) -> some View {
        Text(day)
            .font(.subheadline.weight(Theme.Weight.title))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 8) // 8pt between the title and its first card
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.background)
    }

    private var submitBar: some View {
        Button {
            submitSelected()
        } label: {
            if isSubmitting {
                ProgressView()
                    .tint(Theme.brand)
                    .frame(maxWidth: .infinity)
            } else {
                Text("送出預約（\(selectedInstanceIDs.count)）")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.primary)
        .disabled(isSubmitting || !settings.isComplete)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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

    private func templateCard(_ group: TemplateGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Time is small, secondary and fixed-width digits; the name is big and heavy.
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(CourseCategory(courseName: group.name).color)
                    .frame(width: 4, height: 24)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(Course.displayTime(group.time))
                        .font(.subheadline.weight(Theme.Weight.label).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Text(group.name)
                        .font(.title3.weight(Theme.Weight.title))
                        .foregroundStyle(Theme.ink)
                }
            }
            // No coach / venue line: `courses.json` has no such fields yet.
            HStack(spacing: 8) {
                ForEach(group.instances) { course in
                    dateChip(course)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    @ViewBuilder
    private func dateChip(_ course: Course) -> some View {
        let reservation = reservationStore.reservation(for: course.id, employeeID: settings.employeeID)
        let isSelected = selectedInstanceIDs.contains(course.id)

        DateChip(text: course.dateText, state: chipState(reservation: reservation, isSelected: isSelected)) {
            switch reservation?.status {
            case nil:
                Haptics.tap()
                if isSelected {
                    selectedInstanceIDs.remove(course.id)
                } else {
                    selectedInstanceIDs.insert(course.id)
                }
            case .pending, .failed:
                if reservation?.canDismiss == true { reservationPendingCancel = reservation }
            case .submitting, .submitted:
                break
            }
        }
    }

    private func chipState(reservation: Reservation?, isSelected: Bool) -> DateChipState {
        switch reservation?.status {
        case .submitted: return .submitted
        case .pending, .submitting: return .scheduled
        case .failed: return .failed
        case nil: return isSelected ? .selected : .idle
        }
    }
}
