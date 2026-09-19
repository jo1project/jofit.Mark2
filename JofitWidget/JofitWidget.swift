import WidgetKit
import SwiftUI
import UIKit

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
        GeometryReader { geo in
            ZStack {
                PixelArt(name: entry.courseName == nil ? "RestDay" : "ExerciseDay", targetHeight: geo.size.height * 0.58)
                VStack {
                    Text(dateText(entry.date))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(entry.courseName ?? "今天休息")
                        .font(.caption.weight(Theme.Weight.title))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(10)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .containerBackground(for: .widget) { Theme.background }
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_TW")
        formatter.dateFormat = "M/d（EEEE）"
        return formatter.string(from: date)
    }
}

/// Pixel art drawn without smoothing. The assets are 1x PNGs at native art resolution, so the
/// scale is snapped to a whole number of device pixels per art pixel (nearest to `targetHeight`).
struct PixelArt: View {
    let name: String
    let targetHeight: CGFloat
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let sourceHeight = UIImage(named: name)?.size.height ?? 0
        let factor = sourceHeight > 0 ? max(1, (targetHeight * displayScale / sourceHeight).rounded()) : 1
        let height = sourceHeight > 0 ? sourceHeight * factor / displayScale : targetHeight
        Image(name)
            .resizable()
            .interpolation(.none)
            .antialiased(false)
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
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
        .contentMarginsDisabled()
    }
}
