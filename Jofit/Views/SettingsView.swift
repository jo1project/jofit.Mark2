import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("個人資料") {
                    TextField("姓名", text: $settings.name)
                    TextField("員工編號", text: $settings.employeeID)
                        .keyboardType(.numbersAndPunctuation)
                }
                Section {
                    Text("這些資料只會存在你的手機裡，送出報名時會直接帶入 Google 表單。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }
}
