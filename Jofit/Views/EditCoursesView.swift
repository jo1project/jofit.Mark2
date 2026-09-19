import SwiftUI

/// Admin-only tab (see `UserSettings.isAdmin`): edit the weekly course list everyone shares.
/// Edits stay in `draft` until saved; saving needs the admin PIN, which the backend verifies.
struct EditCoursesView: View {
    @EnvironmentObject private var courseStore: CourseStore
    @EnvironmentObject private var reservationStore: ReservationStore

    @State private var draft: [CourseTemplate] = []
    /// What the backend/cache had when `draft` was last synced; `draft != baseline` means unsaved edits.
    @State private var baseline: [CourseTemplate] = []
    @State private var editing: CourseTemplate?
    @State private var showPinPrompt = false
    @State private var pin = ""
    @State private var isSaving = false
    @State private var resultMessage: String?

    private var isDirty: Bool { draft != baseline }

    /// Pending reservations keep the course name/time they were created with, so editing or
    /// deleting a template does not change what they will submit.
    private var affectedPendingCount: Int {
        let draftByID = Dictionary(draft.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let changedIDs = Set(baseline.filter { draftByID[$0.id] != $0 }.map(\.id))
        return reservationStore.reservations
            .filter { $0.status == .pending && changedIDs.contains($0.course.templateID) }
            .count
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(CoursesView.weekdayOrder, id: \.self) { day in
                    let items = draft.filter { $0.weekday == day }.sorted { ($0.time, $0.id) < ($1.time, $1.id) }
                    if !items.isEmpty {
                        Section(day) {
                            ForEach(items) { template in
                                Button { editing = template } label: { row(template) }
                                    .buttonStyle(.plain)
                            }
                            .onDelete { offsets in
                                let ids = Set(offsets.map { items[$0].id })
                                draft.removeAll { ids.contains($0.id) }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("編輯課程")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if isDirty { Button("還原") { draft = baseline } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = CourseTemplate(id: UUID().uuidString.lowercased(), weekday: "週一", time: "1900", name: "")
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("新增課程")
                }
            }
            .overlay {
                if draft.isEmpty {
                    ContentUnavailableView("目前沒有課程", systemImage: "calendar.badge.plus", description: Text("點右上角的「＋」新增。"))
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isDirty { saveBar }
            }
            .clearOfTabBar()
            .sheet(item: $editing) { template in
                CourseEditSheet(template: template) { saved in
                    if let index = draft.firstIndex(where: { $0.id == saved.id }) {
                        draft[index] = saved
                    } else {
                        draft.append(saved)
                    }
                }
                .presentationDetents([.medium])
            }
            .alert("輸入管理密碼", isPresented: $showPinPrompt) {
                SecureField("密碼", text: $pin)
                    .keyboardType(.numberPad)
                Button("取消", role: .cancel) { pin = "" }
                Button("儲存") { save() }
            } message: {
                let count = affectedPendingCount
                Text(count > 0
                     ? "有 \(count) 筆排程中的預約屬於這次改動的課程，它們不會跟著更新，仍會用原本的名稱和時間送出。\n\n儲存後所有人的課表都會更新。"
                     : "儲存後所有人的課表都會更新。")
            }
            .alert(
                "編輯課程",
                isPresented: Binding(get: { resultMessage != nil }, set: { if !$0 { resultMessage = nil } })
            ) {
                Button("好") {}
            } message: {
                Text(resultMessage ?? "")
            }
        }
        .onAppear(perform: syncFromStore)
        .onReceive(courseStore.$courses) { _ in syncFromStore() }
    }

    private func row(_ template: CourseTemplate) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Course.displayTime(template.time))
                .font(.subheadline.weight(Theme.Weight.label).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Text(template.name)
                .font(.body.weight(Theme.Weight.strong))
                .foregroundStyle(Theme.ink)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var saveBar: some View {
        Button {
            pin = ""
            showPinPrompt = true
        } label: {
            if isSaving {
                ProgressView().tint(Theme.brand).frame(maxWidth: .infinity)
            } else {
                Text("儲存變更").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.primary)
        .disabled(isSaving || draft.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Picks up the store's list on first show and after refreshes, but never over unsaved edits.
    private func syncFromStore() {
        guard draft == baseline else { return }
        baseline = courseStore.templates
        draft = baseline
    }

    private func save() {
        let entered = pin
        pin = ""
        // A blank PIN would just count as a wrong attempt toward the backend's lockout.
        guard !entered.isEmpty else { resultMessage = "請輸入管理密碼"; return }
        let toSave = draft
        isSaving = true
        Task {
            do {
                try await courseStore.save(toSave, pin: entered)
                baseline = toSave
                resultMessage = "已儲存。其他人的 App 會在下次開啟或下拉更新時看到新課表。"
            } catch {
                // Edits stay in the draft so a mistyped PIN can just be retried.
                resultMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// Add/edit one weekly slot. The time is a native picker; `time` is stored as "HHmm".
private struct CourseEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var template: CourseTemplate
    @State private var time: Date
    let onSave: (CourseTemplate) -> Void

    init(template: CourseTemplate, onSave: @escaping (CourseTemplate) -> Void) {
        _template = State(initialValue: template)
        _time = State(initialValue: Self.date(from: template.time))
        self.onSave = onSave
    }

    private var canSave: Bool {
        !template.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("課程名稱", text: $template.name)
                Picker("星期", selection: $template.weekday) {
                    ForEach(CoursesView.weekdayOrder, id: \.self) { Text($0).tag($0) }
                }
                DatePicker("時間", selection: $time, displayedComponents: .hourAndMinute)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("課程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        var saved = template
                        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                        saved.time = Self.hhmm(from: time)
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private static func date(from hhmm: String) -> Date {
        let hour = Int(hhmm.prefix(2)) ?? 0
        let minute = Int(hhmm.suffix(2)) ?? 0
        return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    private static func hhmm(from date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}
