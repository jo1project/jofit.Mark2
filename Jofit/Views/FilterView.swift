import SwiftUI

struct FilterView: View {
    @Binding var timeFilter: CoursesView.TimeFilter
    @Binding var hiddenWeekdays: Set<String>
    @Binding var selectedWeeks: Set<Int>
    let weekRanges: [(index: Int, label: String)]

    @Environment(\.dismiss) private var dismiss

    private let weekdays = ["週一", "週二", "週三", "週四", "週五", "週六", "週日"]

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
                    ForEach(weekdays, id: \.self) { day in
                        Toggle(day, isOn: Binding(
                            get: { hiddenWeekdays.contains(day) },
                            set: { isHidden in
                                if isHidden {
                                    hiddenWeekdays.insert(day)
                                } else {
                                    hiddenWeekdays.remove(day)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("不顯示的星期")
                } footer: {
                    Text("打開開關代表隱藏該星期幾的課程")
                }

                Section {
                    ForEach(weekRanges, id: \.index) { week in
                        Toggle("第 \(week.index + 1) 週（\(week.label)）", isOn: Binding(
                            get: { selectedWeeks.contains(week.index) },
                            set: { isOn in
                                if isOn {
                                    selectedWeeks.insert(week.index)
                                } else {
                                    selectedWeeks.remove(week.index)
                                }
                            }
                        ))
                    }
                } header: {
                    Text("顯示週數")
                } footer: {
                    Text("最多可以看未來 4 週的課程；選了之後才會自動在開放時間送出")
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
