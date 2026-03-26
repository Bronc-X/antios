import WidgetKit
import SwiftUI
import Intents
import Foundation

private enum WidgetSharedConfig {
    static let suiteName = "group.com.youngtony.antios10"
}

struct WidgetSnapshot {
    let anxietyScore: Int?
    let hrv: Double
    let restingHeartRate: Double
    let sleepHours: Double
    let steps: Int
    let proactiveTitle: String?
    let proactiveAction: String?
    let followUpQuestion: String?
    let lastUpdate: Date?

    static func load() -> Self {
        guard let defaults = UserDefaults(suiteName: WidgetSharedConfig.suiteName) else {
            return .empty
        }

        let anxietyScore: Int? = defaults.object(forKey: "widget_anxietyScore") as? Int
        let hrv = defaults.double(forKey: "widget_hrv")
        let restingHeartRate = defaults.double(forKey: "widget_restingHeartRate")
        let sleepHours = defaults.double(forKey: "widget_sleepHours")
        let steps = defaults.integer(forKey: "widget_steps")
        let proactiveTitle = defaults.string(forKey: "widget_proactive_title")
        let proactiveAction = defaults.string(forKey: "widget_proactive_action")
        let followUpQuestion = defaults.string(forKey: "widget_proactive_follow_up")
        let lastUpdate = defaults.object(forKey: "widget_lastUpdate") as? Date

        return WidgetSnapshot(
            anxietyScore: anxietyScore,
            hrv: hrv,
            restingHeartRate: restingHeartRate,
            sleepHours: sleepHours,
            steps: steps,
            proactiveTitle: proactiveTitle,
            proactiveAction: proactiveAction,
            followUpQuestion: followUpQuestion,
            lastUpdate: lastUpdate
        )
    }

    static let empty = WidgetSnapshot(
        anxietyScore: nil,
        hrv: 0,
        restingHeartRate: 0,
        sleepHours: 0,
        steps: 0,
        proactiveTitle: nil,
        proactiveAction: nil,
        followUpQuestion: nil,
        lastUpdate: nil
    )

    var stateTitle: String {
        if let anxietyScore {
            return "今日稳定度 \(anxietyScore)"
        }
        return "等待同步"
    }

    var stateDetail: String {
        if let proactiveAction, !proactiveAction.isEmpty {
            return proactiveAction
        }
        if let proactiveTitle, !proactiveTitle.isEmpty {
            return proactiveTitle
        }
        return "打开 AntiAnxiety 同步 Dashboard 与 Max 建议。"
    }
}

struct Provider: IntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            configuration: ConfigurationIntent(),
            snapshot: .empty
        )
    }

    func getSnapshot(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(
            date: Date(),
            configuration: configuration,
            snapshot: WidgetSnapshot.load()
        )
        completion(entry)
    }

    func getTimeline(for configuration: ConfigurationIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        let entry = SimpleEntry(
            date: Date(),
            configuration: configuration,
            snapshot: WidgetSnapshot.load()
        )
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        let timeline = Timeline(entries: [entry], policy: .after(refreshDate))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationIntent
    let snapshot: WidgetSnapshot
}

struct antios10WidgetEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.snapshot.stateTitle)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(entry.snapshot.stateDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 10) {
                metric(label: "HRV", value: entry.snapshot.hrv > 0 ? "\(Int(entry.snapshot.hrv))" : "--")
                metric(label: "睡眠", value: entry.snapshot.sleepHours > 0 ? String(format: "%.1fh", entry.snapshot.sleepHours) : "--")
                metric(label: "步数", value: entry.snapshot.steps > 0 ? "\(entry.snapshot.steps)" : "--")
            }

            if let followUpQuestion = entry.snapshot.followUpQuestion, !followUpQuestion.isEmpty {
                Text(followUpQuestion)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func metric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }
}

struct antios10Widget: Widget {
    let kind: String = "antios10Widget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: Provider()) { entry in
            antios10WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AntiAnxiety 状态卡")
        .description("显示今日稳定度、恢复动作和关键身体信号。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
