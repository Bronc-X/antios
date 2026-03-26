import WidgetKit
import SwiftUI
import Intents
import Foundation

private enum WidgetSharedConfig {
    static let suiteName = "group.com.youngtony.antios10"
}

private enum WidgetL10n {
    static func text(_ zh: String, _ en: String) -> String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("en") ? en : zh
    }
}

struct WidgetSnapshot {
    let stateTitleOverride: String?
    let stateDetailOverride: String?
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

        if let payload = WidgetSharedStore.readPayload(from: defaults) {
            return WidgetSnapshot(
                stateTitleOverride: payload.stateTitle,
                stateDetailOverride: payload.stateDetail,
                anxietyScore: payload.anxietyScore,
                hrv: payload.hrv ?? 0,
                restingHeartRate: payload.restingHeartRate ?? 0,
                sleepHours: payload.sleepHours ?? 0,
                steps: payload.steps ?? 0,
                proactiveTitle: payload.proactiveTitle,
                proactiveAction: payload.proactiveAction,
                followUpQuestion: payload.followUpQuestion,
                lastUpdate: payload.lastUpdate
            )
        }

        let anxietyScore: Int? = defaults.object(forKey: WidgetSharedStore.anxietyScoreKey) as? Int
        let hrv = defaults.double(forKey: WidgetSharedStore.hrvKey)
        let restingHeartRate = defaults.double(forKey: WidgetSharedStore.restingHeartRateKey)
        let sleepHours = defaults.double(forKey: WidgetSharedStore.sleepHoursKey)
        let steps = defaults.integer(forKey: WidgetSharedStore.stepsKey)
        let proactiveTitle = defaults.string(forKey: WidgetSharedStore.proactiveTitleKey)
        let proactiveAction = defaults.string(forKey: WidgetSharedStore.proactiveActionKey)
        let followUpQuestion = defaults.string(forKey: WidgetSharedStore.proactiveFollowUpKey)
        let lastUpdate = defaults.object(forKey: WidgetSharedStore.lastUpdateKey) as? Date

        return WidgetSnapshot(
            stateTitleOverride: nil,
            stateDetailOverride: nil,
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
        stateTitleOverride: nil,
        stateDetailOverride: nil,
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
        if let stateTitleOverride, !stateTitleOverride.isEmpty {
            return stateTitleOverride
        }
        if let anxietyScore {
            return WidgetL10n.text("今日稳定度 \(anxietyScore)", "Today's stability \(anxietyScore)")
        }
        return WidgetL10n.text("先问身体", "Check with body first")
    }

    var stateDetail: String {
        if let stateDetailOverride, !stateDetailOverride.isEmpty {
            return stateDetailOverride
        }
        if let proactiveAction, !proactiveAction.isEmpty {
            return proactiveAction
        }
        if let proactiveTitle, !proactiveTitle.isEmpty {
            return proactiveTitle
        }
        return WidgetL10n.text(
            "打开 antios，同步今天的身体信号和 Max 建议。",
            "Open antios to sync today's body signals and Max guidance."
        )
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("antios")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.snapshot.stateTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                if let lastUpdate = entry.snapshot.lastUpdate {
                    Text(relativeUpdateText(for: lastUpdate))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(entry.snapshot.stateDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            HStack(spacing: 10) {
                metric(label: "HRV", value: entry.snapshot.hrv > 0 ? "\(Int(entry.snapshot.hrv))" : "--")
                metric(label: WidgetL10n.text("静息心率", "Resting HR"), value: entry.snapshot.restingHeartRate > 0 ? "\(Int(entry.snapshot.restingHeartRate))" : "--")
                metric(label: WidgetL10n.text("睡眠", "Sleep"), value: entry.snapshot.sleepHours > 0 ? String(format: "%.1fh", entry.snapshot.sleepHours) : "--")
                metric(label: WidgetL10n.text("步数", "Steps"), value: entry.snapshot.steps > 0 ? "\(entry.snapshot.steps)" : "--")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

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

    private func relativeUpdateText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct antios10Widget: Widget {
    let kind: String = "antios10Widget"

    var body: some WidgetConfiguration {
        IntentConfiguration(kind: kind, intent: ConfigurationIntent.self, provider: Provider()) { entry in
            antios10WidgetEntryView(entry: entry)
        }
        .configurationDisplayName(WidgetL10n.text("antios 状态卡", "antios status"))
        .description(WidgetL10n.text("显示今日稳定度、恢复动作和关键身体信号。", "Shows today's stability, recovery action, and key body signals."))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
