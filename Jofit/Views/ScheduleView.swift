import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var store: SubmissionStore
    @EnvironmentObject private var scheduler: ScheduleManager
    @EnvironmentObject private var courseStore: CourseStore
    @State private var selectedCourse: Course?
    @State private var fireDate: Date = Date().addingTimeInterval(60)

    var body: some View {
        NavigationStack {
            Form {
                Section("選擇課程") {
                    if courseStore.courses.isEmpty {
                        ProgressView("課表載入中…")
                    } else {
                        Picker("課程", selection: $selectedCourse) {
                            ForEach(courseStore.courses) { course in
                                Text(course.submissionText).tag(Optional(course))
                            }
                        }
                    }
                }
                Section("開放搶課時間") {
                    DatePicker("時間", selection: $fireDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                }

                if let job = scheduler.pendingJob {
                    Section("倒數") {
                        Text(job.course.submissionText)
                        Text(scheduler.countdownText)
                            .font(.system(.largeTitle, design: .monospaced))
                        Button("取消排程", role: .destructive) {
                            scheduler.cancel()
                        }
                    }
                } else {
                    Section {
                        Button("開始排程") {
                            guard let course = selectedCourse else { return }
                            scheduler.schedule(course: course, fireDate: fireDate)
                        }
                        .disabled(!settings.isComplete || selectedCourse == nil)
                    }
                }

                if let last = scheduler.lastResult {
                    Section("上次結果") {
                        Text(last.success
                             ? "✅ 已送出：\(last.courseText)"
                             : "❌ 失敗（狀態碼 \(last.httpStatus.map(String.init) ?? "無回應")）")
                    }
                }

                Section {
                    Text("提醒：iOS 為了省電會暫停背景中的 App，精準倒數只有在 App 開著（前景）時才可靠。系統會在開放時間前 2 分鐘發通知提醒你，請提前回到 App 等待倒數結束再離開。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .refreshable {
                await courseStore.refresh()
            }
            .navigationTitle("排程搶課")
            .onAppear {
                if selectedCourse == nil {
                    selectedCourse = courseStore.courses.first
                }
                scheduler.setFireHandler { course in
                    Task {
                        let record = await store.submit(course: course, name: settings.name, employeeID: settings.employeeID, mode: .scheduled)
                        scheduler.lastResult = record
                        scheduler.pendingJob = nil
                    }
                }
            }
            .onChange(of: courseStore.courses) { _, newCourses in
                if selectedCourse == nil {
                    selectedCourse = newCourses.first
                }
            }
        }
    }
}
