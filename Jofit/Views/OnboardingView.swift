import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("歡迎使用 Jofit 自動報名")
                    .font(.title2.bold())
                Text("第一次使用請先填寫姓名與員工編號，之後每次報名都會自動帶入這份資料。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            VStack(spacing: 12) {
                TextField("姓名", text: $settings.name)
                    .textFieldStyle(.roundedBorder)
                TextField("員工編號", text: $settings.employeeID)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                settings.hasOnboarded = true
            } label: {
                Text("開始使用")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!settings.isComplete)
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .interactiveDismissDisabled()
    }
}
