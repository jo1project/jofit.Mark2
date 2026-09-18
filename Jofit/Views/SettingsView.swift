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
                    TextField("後端網址", text: $settings.backendURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("授權金鑰", text: $settings.backendToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("後端連線")
                } footer: {
                    Text("預約的排程與送出都是由這個後端伺服器負責，跟手機有沒有開、App 有沒有被關掉無關。授權金鑰只會存在手機裡，不會出現在程式碼中。")
                }

                Section {
                    Text("姓名與員工編號會在建立預約時傳給後端，由後端代為送出 Google 表單。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
    }
}
