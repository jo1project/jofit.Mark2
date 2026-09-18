import WidgetKit
import SwiftUI

struct JofitEntry: TimelineEntry {
    let date: Date
    let courseName: String?
}

struct JofitTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> JofitEntry {
        JofitEntry(date: Date(), courseName: "燃脂泰拳")
    }

    func getSnapshot(in context: Context, completion: @escaping (JofitEntry) -> Void) {
        completion(entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JofitEntry>) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        let entries: [JofitEntry] = (0..<2).compactMap { dayOffset in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else { return nil }
            return entry(for: day)
        }

        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
    }

    private func entry(for day: Date) -> JofitEntry {
        let data = WidgetData.load()
        let todays = data.courses(on: day)
        let name = todays.isEmpty ? nil : todays.map(\.name).joined(separator: "、")
        return JofitEntry(date: day, courseName: name)
    }
}

struct JofitWidgetView: View {
    var entry: JofitEntry

    var body: some View {
        VStack(spacing: 6) {
            Text(dateText(entry.date))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let courseName = entry.courseName {
                Image("ExerciseDay")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                Text(courseName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Image("RestDay")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 60)
                Text("今天休息")
                    .font(.headline)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "M/d（EEEE）"
        return formatter.string(from: date)
    }
}

struct JofitWidget: Widget {
    let kind = "JofitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JofitTimelineProvider()) { entry in
            JofitWidgetView(entry: entry)
        }
        .configurationDisplayName("Jofit 今日課程")
        .description("顯示今天有沒有已報名的課程。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
