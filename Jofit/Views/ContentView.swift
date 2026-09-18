import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            QuickSubmitView()
                .tabItem { Label("快速報名", systemImage: "bolt.fill") }
            ScheduleView()
                .tabItem { Label("排程搶課", systemImage: "timer") }
            HistoryView()
                .tabItem { Label("紀錄", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
