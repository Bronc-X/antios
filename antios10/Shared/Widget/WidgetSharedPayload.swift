import Foundation
import WidgetKit

struct WidgetSharedPayloadV1: Codable, Equatable {
    let stateTitle: String
    let stateDetail: String
    let anxietyScore: Int?
    let hrv: Double?
    let restingHeartRate: Double?
    let sleepHours: Double?
    let steps: Int?
    let proactiveTitle: String?
    let proactiveAction: String?
    let followUpQuestion: String?
    let lastUpdate: Date
}

enum WidgetSharedStore {
    static let payloadKey = "widget_payload_v1"
    static let anxietyScoreKey = "widget_anxietyScore"
    static let hrvKey = "widget_hrv"
    static let restingHeartRateKey = "widget_restingHeartRate"
    static let sleepDurationKey = "widget_sleepDuration"
    static let sleepHoursKey = "widget_sleepHours"
    static let stepsKey = "widget_steps"
    static let proactiveTitleKey = "widget_proactive_title"
    static let proactiveActionKey = "widget_proactive_action"
    static let proactiveFollowUpKey = "widget_proactive_follow_up"
    static let lastUpdateKey = "widget_lastUpdate"

    static func write(
        payload: WidgetSharedPayloadV1,
        defaults: UserDefaults,
        reloadTimelines: Bool = true
    ) {
        if let score = payload.anxietyScore {
            defaults.set(score, forKey: anxietyScoreKey)
        } else {
            defaults.removeObject(forKey: anxietyScoreKey)
        }

        defaults.set(payload.hrv ?? 0, forKey: hrvKey)
        defaults.set(payload.restingHeartRate ?? 0, forKey: restingHeartRateKey)

        let sleepHours = payload.sleepHours ?? 0
        defaults.set(sleepHours, forKey: sleepDurationKey)
        defaults.set(sleepHours, forKey: sleepHoursKey)

        defaults.set(payload.steps ?? 0, forKey: stepsKey)

        setOrRemove(nonEmpty(payload.proactiveTitle), key: proactiveTitleKey, defaults: defaults)
        setOrRemove(nonEmpty(payload.proactiveAction), key: proactiveActionKey, defaults: defaults)
        setOrRemove(nonEmpty(payload.followUpQuestion), key: proactiveFollowUpKey, defaults: defaults)
        defaults.set(payload.lastUpdate, forKey: lastUpdateKey)

        if let payloadData = try? JSONEncoder().encode(payload) {
            defaults.set(payloadData, forKey: payloadKey)
        } else {
            defaults.removeObject(forKey: payloadKey)
        }

        if reloadTimelines {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static func readPayload(from defaults: UserDefaults) -> WidgetSharedPayloadV1? {
        guard let payloadData = defaults.data(forKey: payloadKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSharedPayloadV1.self, from: payloadData)
    }

    private static func setOrRemove(_ value: String?, key: String, defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
