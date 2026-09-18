import SwiftUI

struct FilterView: View {
    @Binding var timeFilter: CoursesView.TimeFilter
    @Binding var shownWeekdays: Set<String>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("時段") {
                    Picker("時段", selection: $timeFilter) {
                        ForEach(CoursesView.TimeFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    ForEach(CoursesView.weekdayOrder, id: \.self) { day in
                        Toggle(day, isOn: Binding(
                            get: { shownWeekdays.contains(day) },
                            set: { isOn in
                                if isOn {
                                    shownWeekdays.insert(day)
                                } else {
                                    shownWeekdays.remove(day)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("顯示星期")
                } footer: {
                    Text("關掉開關代表隱藏該星期幾的課程")
                }
            }
            .navigationTitle("篩選")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
