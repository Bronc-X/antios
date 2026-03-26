import Foundation

enum MaxAgentExecutionRequest: Equatable, Identifiable {
    case checkIn
    case planReview
    case breathing(minutes: Int)
    case inquiry
    case evidence

    var id: String {
        switch self {
        case .checkIn:
            return "check_in"
        case .planReview:
            return "plan_review"
        case .breathing(let minutes):
            return "breathing_\(minutes)"
        case .inquiry:
            return "inquiry"
        case .evidence:
            return "evidence"
        }
    }
}

enum MaxActionReviewOutcome: String, Equatable {
    case completed
    case tooHard
    case skipped
}

enum MaxAgentResolvedAction: Equatable {
    case execute(MaxAgentExecutionRequest)
    case sendPrompt(String)
    case review(MaxActionReviewOutcome)
}

enum MaxAgentActionRouter {
    static func resolveNotificationAction(
        userInfo: [AnyHashable: Any],
        language: AppLanguage,
        agentSurface: MaxAgentSurfaceModel
    ) -> MaxAgentResolvedAction? {
        if let intent = (userInfo["intent"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let action = resolveIntent(intent, userInfo: userInfo, language: language, agentSurface: agentSurface) {
            return action
        }

        if let question = (userInfo["question"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !question.isEmpty {
            return resolveUserInput(question, language: language, agentSurface: agentSurface) ?? .sendPrompt(question)
        }

        return nil
    }

    static func resolveUserInput(
        _ text: String,
        language: AppLanguage,
        agentSurface: MaxAgentSurfaceModel
    ) -> MaxAgentResolvedAction? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if matchesAny(normalized, patterns: [
            "开始校准", "做校准", "每日校准", "check-in", "check in", "checkin", "daily check"
        ]) {
            return .execute(.checkIn)
        }

        if matchesAny(normalized, patterns: [
            "复盘计划", "更新计划", "计划进度", "review plan", "update plan", "plan progress"
        ]) {
            return .execute(.planReview)
        }

        if matchesAny(normalized, patterns: [
            "主动关怀", "今日关怀", "care brief", "proactive care", "proactive brief"
        ]) {
            return .sendPrompt(agentSurface.proactive.prompt)
        }

        if matchesAny(normalized, patterns: [
            "先问身体", "适合跑吗", "今天能跑吗", "要跑步", "跑步前", "run today", "ready to run", "exercise precheck"
        ]) {
            return .sendPrompt(agentSurface.proactive.prompt)
        }

        if agentSurface.actionReview.hasAction,
           matchesAny(normalized, patterns: [
            "做完了", "完成了", "已完成", "done", "completed", "i did it", "finished"
           ]) {
            return .review(.completed)
        }

        if agentSurface.actionReview.hasAction,
           matchesAny(normalized, patterns: [
            "太难了", "太难", "做不到", "too hard", "can't do", "cannot do"
           ]) {
            return .review(.tooHard)
        }

        if agentSurface.actionReview.hasAction,
           matchesAny(normalized, patterns: [
            "先跳过", "跳过", "稍后", "skip", "later", "not now"
           ]) {
            return .review(.skipped)
        }

        if matchesAny(normalized, patterns: [
            "呼吸", "breathing", "breathe", "breathwork"
        ]) {
            return .execute(.breathing(minutes: parseDurationMinutes(from: normalized) ?? 5))
        }

        if matchesAny(normalized, patterns: [
            "身体信号", "hrv", "睡眠", "静息心率", "body signal", "recovery state", "sensor"
        ]) {
            return .sendPrompt(agentSurface.body.prompt)
        }

        if matchesAny(normalized, patterns: [
            "为什么", "证据", "机制", "why", "evidence", "mechanism"
        ]) {
            return .execute(.evidence)
        }

        if matchesAny(normalized, patterns: [
            "追问", "问我一个问题", "继续问", "inquiry", "follow-up question", "ask me one question"
        ]) {
            return .execute(.inquiry)
        }

        return nil
    }

    private static func resolveIntent(
        _ intent: String,
        userInfo: [AnyHashable: Any],
        language: AppLanguage,
        agentSurface: MaxAgentSurfaceModel
    ) -> MaxAgentResolvedAction? {
        switch intent {
        case "check_in", "checkin", "daily_check":
            return .execute(.checkIn)
        case "plan_review", "plan_commit":
            return .execute(.planReview)
        case "proactive_brief", "care_brief":
            return .sendPrompt(agentSurface.proactive.prompt)
        case "exercise_precheck", "risk_prevention", "fusion_reply":
            return .sendPrompt(agentSurface.proactive.prompt)
        case "workout_follow_up", "next_day_follow_up":
            return .sendPrompt(agentSurface.proactive.continuePrompt)
        case "sensor_follow_up", "body_signal":
            return .sendPrompt(agentSurface.body.prompt)
        case "evidence_explain":
            return .execute(.evidence)
        case "inquiry":
            return .execute(.inquiry)
        case "breathing", "breathwork":
            let duration = (userInfo["duration"] as? Int).flatMap { max(1, $0) } ?? 5
            return .execute(.breathing(minutes: duration))
        default:
            return nil
        }
    }

    private static func matchesAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private static func parseDurationMinutes(from text: String) -> Int? {
        let pattern = #"(\d{1,2})\s*(分钟|分鐘|min|mins|minute|minutes)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let numberRange = Range(match.range(at: 1), in: text),
              let minutes = Int(text[numberRange]) else {
            return nil
        }
        return max(1, min(30, minutes))
    }
}
