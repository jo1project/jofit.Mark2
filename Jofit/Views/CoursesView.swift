import SwiftUI

struct CoursesView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var courseStore: CourseStore
    @EnvironmentObject private var reservationStore: ReservationStore

    @State private var timeFilter: TimeFilter = .all
    @State private var hiddenWeekdays: Set<String> = []
    @State private var selectedWeeks: Set<Int> = [0]
    @State private var showFilters = false

    enum TimeFilter: String, CaseIterable, Identifiable {
        case all = "全部顯示"
        case night = "夜間（20:00 後）"
        case day = "非夜間（20:00 前）"
        var id: String { rawValue }
    }

    private var weekRanges: [(index: Int, label: String)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return (0..<CourseStore.weeksAhead).map { week in
            let start = calendar.date(byAdding: .day, value: week * 7, to: today) ?? today
            let end = calendar.date(byAdding: .day, value: week * 7 + 6, to: today) ?? today
            return (week, "\(formatter.string(from: start))–\(formatter.string(from: end))")
        }
    }

    private var filteredCourses: [Course] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return courseStore.courses.filter { course in
            let dayOffset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: course.date)).day ?? 0
            let week = dayOffset / 7
            guard selectedWeeks.contains(week) else { return false }
            guard !hiddenWeekdays.contains(course.weekdayLabel) else { return false }
            switch timeFilter {
            case .all: return true
            case .night: return (Int(course.time) ?? 0) >= 2000
            case .day: return (Int(course.time) ?? 0) < 2000
            }
        }
    }

    private var groupedByDate: [(date: Date, courses: [Course])] {
        let groups = Dictionary(grouping: filteredCourses) { Calendar.current.startOfDay(for: $0.date) }
        return groups.keys.sorted().map { date in
            (date, groups[date]!.sorted { $0.time < $1.time })
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
                if !settings.isBackendConfigured {
                    Section {
                        Text("請先到「設定」分頁填寫後端網址與授權金鑰，才能建立預約")
                            .foregroundStyle(.secondary)
                    }
                } else if let error = reservationStore.lastSyncError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
                ForEach(groupedByDate, id: \.date) { group in
                    Section(sectionTitle(for: group.date)) {
                        ForEach(group.courses) { course in
                            courseRow(course)
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
                FilterView(
                    timeFilter: $timeFilter,
                    hiddenWeekdays: $hiddenWeekdays,
                    selectedWeeks: $selectedWeeks,
                    weekRanges: weekRanges
                )
                .presentationDetents([.medium, .large])
            }
            .overlay {
                if filteredCourses.isEmpty {
                    ContentUnavailableView("沒有符合條件的課程", systemImage: "calendar.badge.exclamationmark")
                }
            }
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "M/d（EEEE）"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private func courseRow(_ course: Course) -> some View {
        let reservation = reservationStore.reservation(for: course.id)
        Button {
            guard reservation == nil else { return }
            Task {
                await reservationStore.reserve(course: course, name: settings.name, employeeID: settings.employeeID)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(displayTime(course.time))　\(course.name)")
                        .font(.body)
                    if let reservation {
                        statusText(reservation)
                    } else {
                        Text(previewFireText(for: course))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                statusIcon(reservation)
            }
        }
        .foregroundStyle(.primary)
        .disabled(reservation != nil || !settings.isComplete || !settings.isBackendConfigured)
        .swipeActions {
            if let reservation {
                switch reservation.status {
                case .pending:
                    Button("取消", role: .destructive) {
                        Task { await reservationStore.cancel(reservation) }
                    }
                case .failed:
                    Button("移除", role: .destructive) {
                        Task { await reservationStore.cancel(reservation) }
                    }
                case .submitting, .submitted:
                    EmptyView()
                }
            }
        }
    }

    private func displayTime(_ time: String) -> String {
        guard time.count == 4 else { return time }
        return "\(time.prefix(2)):\(time.suffix(2))"
    }

    /// Just a preview shown before the user taps — the backend computes the authoritative
    /// fire time once the reservation is actually created, using the same 6-day rule.
    private func previewFireDate(for course: Course, now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let classDay = calendar.startOfDay(for: course.date)
        guard let openDay = calendar.date(byAdding: .day, value: -6, to: classDay) else { return now }
        var comps = calendar.dateComponents([.year, .month, .day], from: openDay)
        comps.hour = 8
        comps.minute = 0
        comps.second = 0
        let candidate = calendar.date(from: comps) ?? now
        return max(candidate, now)
    }

    private func previewFireText(for course: Course) -> String {
        let fireDate = previewFireDate(for: course)
        if fireDate <= Date() {
            return "點一下立即送出"
        }
        return "點一下預約，將於 \(fireDate.formatted(date: .abbreviated, time: .shortened)) 自動送出"
    }

    @ViewBuilder
    private func statusText(_ reservation: Reservation) -> some View {
        switch reservation.status {
        case .pending:
            Text("已排程，將於 \(reservation.fireDate.formatted(date: .abbreviated, time: .shortened)) 自動送出")
                .font(.caption)
                .foregroundStyle(.blue)
        case .submitting:
            Text("送出中…")
                .font(.caption)
                .foregroundStyle(.blue)
        case .submitted:
            Text("已送出")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Text(reservation.lastError ?? "送出失敗")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func statusIcon(_ reservation: Reservation?) -> some View {
        switch reservation?.status {
        case .submitted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .pending, .submitting:
            Image(systemName: "clock.fill").foregroundStyle(.blue)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case nil:
            EmptyView()
        }
    }
}
