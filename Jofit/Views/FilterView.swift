import SwiftUI

struct FilterView: View {
    @Binding var timeFilter: CoursesView.TimeFilter
    @Binding var shownWeekdays: Set<String>

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("時段")
                        VStack(spacing: 0) {
                            ForEach(Array(CoursesView.TimeFilter.allCases.enumerated()), id: \.element) { index, filter in
                                if index > 0 { Hairline() }
                                timeRow(filter)
                            }
                        }
                        .padding(.horizontal, 16)
                        .cardBackground()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionTitle("顯示星期")
                        HStack(spacing: 6) {
                            ForEach(CoursesView.weekdayOrder, id: \.self) { day in
                                WeekdayChip(label: day, isOn: shownWeekdays.contains(day)) {
                                    Haptics.tap()
                                    if shownWeekdays.contains(day) {
                                        shownWeekdays.remove(day)
                                    } else {
                                        shownWeekdays.insert(day)
                                    }
                                }
                            }
                        }
                        Text("未選取的星期會隱藏課程")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(16)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("篩選")
            .navigationBarTitleDisplayMode(.inline)
            // Bottom bar instead of a toolbar item: a capsule inside the toolbar would get a
            // second system capsule drawn around it.
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("完成").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(Theme.Weight.title))
            .foregroundStyle(Theme.textSecondary)
    }

    private func timeRow(_ filter: CoursesView.TimeFilter) -> some View {
        let isOn = timeFilter == filter
        return Button {
            Haptics.tap()
            timeFilter = filter
        } label: {
            HStack {
                Text(filter.rawValue)
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Spacer()
                CheckDot(isOn: isOn)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
