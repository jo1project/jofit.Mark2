import SwiftUI

struct QuickSubmitView: View {
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var store: SubmissionStore
    @State private var selectedCourse: Course?
    @State private var isSubmitting = false
    @State private var resultMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !settings.isComplete {
                    Section {
                        NavigationLink("請先到「設定」填寫姓名與員工編號") {
                            SettingsView()
                        }
                    }
                }
                Section("選擇課程") {
                    ForEach(Courses.all) { course in
                        Button {
                            selectedCourse = course
                        } label: {
                            HStack {
                                Text(course.submissionText)
                                Spacer()
                                if selectedCourse?.id == course.id {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                if let resultMessage {
                    Section {
                        Text(resultMessage)
                    }
                }
            }
            .navigationTitle("快速報名")
            .safeAreaInset(edge: .bottom) {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("送出報名")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCourse == nil || !settings.isComplete || isSubmitting)
                .padding()
            }
        }
    }

    private func submit() {
        guard let course = selectedCourse else { return }
        isSubmitting = true
        resultMessage = nil
        Task {
            let record = await store.submit(course: course, name: settings.name, employeeID: settings.employeeID, mode: .quick)
            isSubmitting = false
            resultMessage = record.success
                ? "已送出：\(record.courseText)"
                : "送出失敗，請重試（狀態碼 \(record.httpStatus.map(String.init) ?? "無回應")）"
        }
    }
}
