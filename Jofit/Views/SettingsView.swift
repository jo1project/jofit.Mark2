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
                    Text("姓名與員工編號會在建立預約時傳給後端，由後端代為送出 Google 表單。預約的排程與送出都是由後端伺服器負責，跟手機有沒有開、App 有沒有被關掉無關。")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("設定")
        }
    }
}
