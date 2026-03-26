import Foundation
import SwiftData

enum A10Tab: String, CaseIterable, Identifiable {
    case home
    case max
    case me

    var id: String { rawValue }
}

enum A10LoopStage: String, CaseIterable, Identifiable, Codable {
    case inquiry
    case calibration
    case evidence
    case action

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inquiry: return "bubble.left.and.bubble.right"
        case .calibration: return "waveform.path.ecg"
        case .evidence: return "doc.text.magnifyingglass"
        case .action: return "checklist"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .inquiry:
            return L10n.text("了解", "Check in", language: language)
        case .calibration:
            return L10n.text("记录", "Track", language: language)
        case .evidence:
            return L10n.text("分析", "Explain", language: language)
        case .action:
            return L10n.text("行动", "Action", language: language)
        }
    }

    func summary(language: AppLanguage) -> String {
        switch self {
        case .inquiry:
            return L10n.text("用一句话说出今天最明显的不舒服。", "Describe today's clearest discomfort in one sentence.", language: language)
        case .calibration:
            return L10n.text("记下今天的状态和身体感觉。", "Capture today's state and body feelings.", language: language)
        case .evidence:
            return L10n.text("把原因和建议讲清楚。", "Explain the reason and suggestion clearly.", language: language)
        case .action:
            return L10n.text("执行一个最低阻力动作。", "Complete one lowest-friction action.", language: language)
        }
    }

    var next: A10LoopStage {
        switch self {
        case .inquiry: return .calibration
        case .calibration: return .evidence
        case .evidence: return .action
        case .action: return .action
        }
    }
}

enum A10MaxRole: String, Codable {
    case user
    case assistant
}

enum A10PlanSource: String, Codable {
    case local
    case habit
    case recommendation
}

@Model
final class A10LoopSnapshot {
    var headline: String
    var summary: String
    var nextActionTitle: String
    var nextActionDetail: String
    var evidenceNote: String
    var currentStageRaw: String
    var stressScore: Int
    var updatedAt: Date

    init(
        headline: String,
        summary: String,
        nextActionTitle: String,
        nextActionDetail: String,
        evidenceNote: String,
        currentStageRaw: String,
        stressScore: Int,
        updatedAt: Date = .now
    ) {
        self.headline = headline
        self.summary = summary
        self.nextActionTitle = nextActionTitle
        self.nextActionDetail = nextActionDetail
        self.evidenceNote = evidenceNote
        self.currentStageRaw = currentStageRaw
        self.stressScore = stressScore
        self.updatedAt = updatedAt
    }

    var stage: A10LoopStage {
        get { A10LoopStage(rawValue: currentStageRaw) ?? .inquiry }
        set { currentStageRaw = newValue.rawValue }
    }
}

@Model
final class A10ActionPlan {
    var title: String
    var detail: String
    var effortLabel: String
    var estimatedMinutes: Int
    var isCompleted: Bool
    var remoteID: String?
    var sourceRaw: String
    var sortOrder: Int
    var updatedAt: Date

    init(
        title: String,
        detail: String,
        effortLabel: String,
        estimatedMinutes: Int,
        isCompleted: Bool = false,
        remoteID: String? = nil,
        sourceRaw: String = A10PlanSource.local.rawValue,
        sortOrder: Int = 0,
        updatedAt: Date = .now
    ) {
        self.title = title
        self.detail = detail
        self.effortLabel = effortLabel
        self.estimatedMinutes = estimatedMinutes
        self.isCompleted = isCompleted
        self.remoteID = remoteID
        self.sourceRaw = sourceRaw
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }

    var source: A10PlanSource {
        get { A10PlanSource(rawValue: sourceRaw) ?? .local }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class A10CoachSession {
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \A10CoachMessage.session)
    var messages: [A10CoachMessage] = []

    init(title: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

typealias A10MaxSession = A10CoachSession

@Model
final class A10CoachMessage {
    var roleRaw: String
    var body: String
    var createdAt: Date
    var session: A10CoachSession?

    init(
        roleRaw: String,
        body: String,
        createdAt: Date = .now,
        session: A10CoachSession? = nil
    ) {
        self.roleRaw = roleRaw
        self.body = body
        self.createdAt = createdAt
        self.session = session
    }

    var role: A10MaxRole {
        A10MaxRole(rawValue: roleRaw) ?? .assistant
    }
}

typealias A10MaxMessage = A10CoachMessage

@Model
final class A10PreferenceRecord {
    var languageCode: String
    var healthSyncEnabled: Bool
    var notificationsEnabled: Bool
    var dailyCheckInHour: Int
    var updatedAt: Date

    init(
        languageCode: String,
        healthSyncEnabled: Bool,
        notificationsEnabled: Bool,
        dailyCheckInHour: Int,
        updatedAt: Date = .now
    ) {
        self.languageCode = languageCode
        self.healthSyncEnabled = healthSyncEnabled
        self.notificationsEnabled = notificationsEnabled
        self.dailyCheckInHour = dailyCheckInHour
        self.updatedAt = updatedAt
    }
}

struct A10ShellActivePlanSummary {
    let id: String
    let title: String
    let progress: Int
    let status: String
}

struct A10ShellRemoteContext {
    let dashboard: DashboardData?
    let recommendations: [DailyAIRecommendationItem]
    let scienceArticles: [ScienceArticle]
    let habits: [SupabaseManager.HabitStatus]
    let profile: ProfileSettings?
    let pendingInquiry: InquiryQuestion?
    let proactiveBrief: ProactiveCareBrief?
    let activePlan: A10ShellActivePlanSummary?
    let refreshedAt: Date

    var openHabitsCount: Int {
        habits.filter { !$0.isCompleted }.count
    }

    var completedHabitsCount: Int {
        habits.filter(\.isCompleted).count
    }

    var recommendationCount: Int {
        recommendations.count
    }

    var scienceArticleCount: Int {
        scienceArticles.count
    }

    var focusText: String? {
        A10NonEmpty(profile?.current_focus) ?? A10NonEmpty(profile?.primary_goal)
    }

    var readinessScore: Int? {
        dashboard?.todayLog?.overall_readiness
    }

    var effectiveStressScore: Int? {
        dashboard?.todayLog?.anxiety_level
        ?? dashboard?.todayLog?.stress_level
        ?? dashboard?.todayLog?.body_tension
    }

    var hasActivePlan: Bool {
        guard let activePlan else { return false }
        return activePlan.status.lowercased() == "active"
    }

    var signalCount: Int {
        let hardwareCount = [
            dashboard?.hardwareData?.hrv,
            dashboard?.hardwareData?.resting_heart_rate,
            dashboard?.hardwareData?.sleep_score,
            dashboard?.hardwareData?.spo2,
            dashboard?.hardwareData?.steps,
        ]
        .compactMap { $0 }
        .count

        let todayLogCount = [
            dashboard?.todayLog?.stress_level,
            dashboard?.todayLog?.anxiety_level,
            dashboard?.todayLog?.body_tension,
            dashboard?.todayLog?.mental_clarity,
            dashboard?.todayLog?.overall_readiness,
        ]
        .compactMap { $0 }
        .count

        return hardwareCount + todayLogCount
    }

    var hasSignals: Bool {
        signalCount > 0 || dashboard?.todayLog != nil
    }
}

enum A10RiskLevel: String, Codable, Equatable {
    case green
    case yellow
    case red

    func title(language: AppLanguage) -> String {
        switch self {
        case .green:
            return L10n.text("绿色", "Green", language: language)
        case .yellow:
            return L10n.text("黄色", "Yellow", language: language)
        case .red:
            return L10n.text("红色", "Red", language: language)
        }
    }
}

enum A10IntensityCap: String, Codable, Equatable {
    case increase
    case maintain
    case moderateOnly
    case lowOnly
    case stopOrLowOnly

    func shortLabel(language: AppLanguage) -> String {
        switch self {
        case .increase:
            return L10n.text("可加量", "Can increase", language: language)
        case .maintain:
            return L10n.text("维持计划", "Stay on plan", language: language)
        case .moderateOnly:
            return L10n.text("降到中强度", "Downgrade to moderate", language: language)
        case .lowOnly:
            return L10n.text("低强度", "Low only", language: language)
        case .stopOrLowOnly:
            return L10n.text("先停高强度", "Stop hard effort", language: language)
        }
    }
}

enum A10FollowUpStatus: String, Codable, Equatable {
    case automatic
    case pending
    case passive

    func title(language: AppLanguage) -> String {
        switch self {
        case .automatic:
            return L10n.text("自动跟进", "Automatic", language: language)
        case .pending:
            return L10n.text("待确认", "Needs input", language: language)
        case .passive:
            return L10n.text("已安排", "Scheduled", language: language)
        }
    }
}

struct HealthRuntimeSnapshot: Equatable {
    let hrv: Double?
    let restingHeartRate: Double?
    let sleepScore: Double?
    let steps: Double?
    let overallReadiness: Int?
    let sleepDurationMinutes: Int?
    let exerciseDurationMinutes: Int?
    let anxietyLevel: Int?
    let stressLevel: Int?
    let bodyTension: Int?
    let mentalClarity: Int?

    var hasSignals: Bool {
        [
            hrv != nil,
            restingHeartRate != nil,
            sleepScore != nil,
            steps != nil,
            overallReadiness != nil,
            sleepDurationMinutes != nil,
            exerciseDurationMinutes != nil,
            anxietyLevel != nil,
            stressLevel != nil,
            bodyTension != nil,
            mentalClarity != nil,
        ]
        .contains(true)
    }

    static func from(dashboard: DashboardData?) -> Self {
        let hardware = dashboard?.hardwareData
        let log = dashboard?.todayLog
        return HealthRuntimeSnapshot(
            hrv: hardware?.hrv?.value,
            restingHeartRate: hardware?.resting_heart_rate?.value,
            sleepScore: hardware?.sleep_score?.value,
            steps: hardware?.steps?.value,
            overallReadiness: log?.overall_readiness,
            sleepDurationMinutes: log?.sleep_duration_minutes,
            exerciseDurationMinutes: log?.exercise_duration_minutes,
            anxietyLevel: log?.anxiety_level,
            stressLevel: log?.stress_level,
            bodyTension: log?.body_tension,
            mentalClarity: log?.mental_clarity
        )
    }
}

struct RiskPreventionState: Equatable {
    let readinessScore: Int
    let riskLevel: A10RiskLevel
    let intensityCap: A10IntensityCap
    let redFlags: [String]
    let evidenceLines: [String]
}

struct FollowUpRuntime: Equatable {
    let title: String
    let detail: String
    let status: A10FollowUpStatus
    let actionTitle: String
    let intent: String
    let prompt: String
}

struct FusionReplyRuntime: Equatable {
    let primaryConclusion: String
    let riskLevel: A10RiskLevel
    let readinessScore: Int
    let intensityCap: A10IntensityCap
    let bodySignalSummary: String
    let reasonSummary: String
    let recommendedAction: String
    let blockedActions: [String]
    let followUpTask: String
    let evidenceSummary: [String]
    let primaryActionTitle: String
    let secondaryActionTitle: String
    let explanationActionTitle: String
    let continuePrompt: String
    let overridePrompt: String
    let discomfortPrompt: String
    let explanationPrompt: String
}

struct A10FusionRuntimeBundle: Equatable {
    let health: HealthRuntimeSnapshot
    let risk: RiskPreventionState
    let followUp: FollowUpRuntime
    let fusion: FusionReplyRuntime
}

enum A10RiskRedFlagEngine {
    static func evaluate(snapshot: HealthRuntimeSnapshot, language: AppLanguage) -> [String] {
        var flags: [String] = []

        if let readiness = snapshot.overallReadiness, readiness < 35 {
            flags.append(
                L10n.text(
                    "今天的恢复储备偏低，不适合硬上强度。",
                    "Recovery reserve looks low today, so hard effort is not a good fit.",
                    language: language
                )
            )
        }

        if let sleepMinutes = snapshot.sleepDurationMinutes, sleepMinutes < 270 {
            flags.append(
                L10n.text(
                    "昨晚睡眠明显不足，今天先别把训练强度顶上去。",
                    "Sleep was clearly short last night, so avoid pushing intensity today.",
                    language: language
                )
            )
        }

        if let hrv = snapshot.hrv,
           let restingHeartRate = snapshot.restingHeartRate,
           hrv < 24,
           restingHeartRate > 82 {
            flags.append(
                L10n.text(
                    "HRV 偏低且静息心率偏高，恢复信号偏紧。",
                    "HRV is low while resting heart rate is elevated, which points to tight recovery.",
                    language: language
                )
            )
        }

        if let bodyTension = snapshot.bodyTension,
           let anxietyLevel = snapshot.anxietyLevel,
           max(bodyTension, anxietyLevel) >= 9 {
            flags.append(
                L10n.text(
                    "主观负荷已经很高，今天更适合先稳住身体。",
                    "Subjective load is already high, so today is better for stabilizing first.",
                    language: language
                )
            )
        }

        return flags
    }
}

enum A10ExerciseReadinessEngine {
    static func evaluate(
        snapshot: HealthRuntimeSnapshot,
        redFlags: [String],
        language: AppLanguage
    ) -> RiskPreventionState {
        let sleep = snapshot.sleepScore ?? sleepDurationScore(snapshot.sleepDurationMinutes)
        let hrv = hrvScore(snapshot.hrv)
        let rhr = restingHeartRateScore(snapshot.restingHeartRate)
        let fatigue = fatigueScore(snapshot)
        let recovery = recentRecoveryScore(snapshot)

        let computedReadiness = weightedAverage([
            (sleep, 0.30),
            (hrv, 0.25),
            (rhr, 0.20),
            (fatigue, 0.15),
            (recovery, 0.10)
        ]) ?? 62

        let blended = weightedAverage([
            (computedReadiness, 0.85),
            (snapshot.overallReadiness.map(Double.init), 0.15)
        ]) ?? snapshot.overallReadiness.map(Double.init) ?? computedReadiness

        let readinessScore = max(0, min(100, Int(blended.rounded())))

        let intensityCap: A10IntensityCap
        if !redFlags.isEmpty {
            intensityCap = .stopOrLowOnly
        } else if readinessScore >= 90 {
            intensityCap = .increase
        } else if readinessScore >= 75 {
            intensityCap = .maintain
        } else if readinessScore >= 55 {
            intensityCap = .moderateOnly
        } else {
            intensityCap = .lowOnly
        }

        let riskLevel: A10RiskLevel
        switch intensityCap {
        case .increase, .maintain:
            riskLevel = .green
        case .moderateOnly, .lowOnly:
            riskLevel = .yellow
        case .stopOrLowOnly:
            riskLevel = .red
        }

        return RiskPreventionState(
            readinessScore: readinessScore,
            riskLevel: riskLevel,
            intensityCap: intensityCap,
            redFlags: redFlags,
            evidenceLines: buildEvidenceLines(
                snapshot: snapshot,
                readinessScore: readinessScore,
                redFlags: redFlags,
                language: language
            )
        )
    }

    private static func buildEvidenceLines(
        snapshot: HealthRuntimeSnapshot,
        readinessScore: Int,
        redFlags: [String],
        language: AppLanguage
    ) -> [String] {
        var lines: [String] = []

        if let hrv = snapshot.hrv {
            lines.append("HRV \(Int(hrv.rounded()))")
        }
        if let restingHeartRate = snapshot.restingHeartRate {
            lines.append(L10n.text("静息心率 \(Int(restingHeartRate.rounded()))", "Resting HR \(Int(restingHeartRate.rounded()))", language: language))
        }
        if let sleepScore = snapshot.sleepScore {
            lines.append(L10n.text("睡眠分 \(Int(sleepScore.rounded()))", "Sleep score \(Int(sleepScore.rounded()))", language: language))
        } else if let sleepMinutes = snapshot.sleepDurationMinutes {
            let hours = Double(sleepMinutes) / 60
            lines.append(L10n.text("睡眠 \(String(format: "%.1f", hours))h", "Sleep \(String(format: "%.1f", hours))h", language: language))
        }
        if let steps = snapshot.steps {
            lines.append(L10n.text("步数 \(Int(steps.rounded()))", "Steps \(Int(steps.rounded()))", language: language))
        }
        if let exercise = snapshot.exerciseDurationMinutes, exercise > 0 {
            lines.append(L10n.text("运动 \(exercise) 分钟", "Exercise \(exercise) min", language: language))
        }
        if lines.isEmpty {
            lines.append(
                L10n.text(
                    "系统还在补身体信号，先按当前记录做保守判断。",
                    "Signals are still loading, so the system is staying conservative for now.",
                    language: language
                )
            )
        }
        if !redFlags.isEmpty {
            lines.append(contentsOf: redFlags)
        } else {
            lines.append(L10n.text("当前就绪度 \(readinessScore)/100", "Current readiness \(readinessScore)/100", language: language))
        }
        return Array(lines.prefix(4))
    }

    private static func weightedAverage(_ entries: [(Double?, Double)]) -> Double? {
        let resolved = entries.compactMap { value, weight -> (Double, Double)? in
            guard let value else { return nil }
            return (value, weight)
        }
        guard !resolved.isEmpty else { return nil }

        let totalWeight = resolved.reduce(0) { $0 + $1.1 }
        guard totalWeight > 0 else { return nil }
        return resolved.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
    }

    private static func sleepDurationScore(_ minutes: Int?) -> Double? {
        guard let minutes else { return nil }
        return min(max(Double(minutes) / 480 * 100, 0), 100)
    }

    private static func hrvScore(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max((value - 15) / 45 * 100, 0), 100)
    }

    private static func restingHeartRateScore(_ value: Double?) -> Double? {
        guard let value else { return nil }
        return min(max((90 - value) / 35 * 100, 0), 100)
    }

    private static func fatigueScore(_ snapshot: HealthRuntimeSnapshot) -> Double? {
        let entries: [Double?] = [
            snapshot.anxietyLevel.map { (10 - min(max(Double($0), 0), 10)) * 10 },
            snapshot.stressLevel.map { (10 - min(max(Double($0), 0), 10)) * 10 },
            snapshot.bodyTension.map { (10 - min(max(Double($0), 0), 10)) * 10 },
            snapshot.mentalClarity.map { min(max(Double($0), 0), 10) * 10 }
        ]
        let resolved = entries.compactMap { $0 }
        guard !resolved.isEmpty else { return nil }
        return resolved.reduce(0, +) / Double(resolved.count)
    }

    private static func recentRecoveryScore(_ snapshot: HealthRuntimeSnapshot) -> Double? {
        guard let exerciseMinutes = snapshot.exerciseDurationMinutes else {
            return 72
        }

        let base: Double
        switch exerciseMinutes {
        case 0..<20:
            base = 88
        case 20..<40:
            base = 80
        case 40..<60:
            base = 68
        default:
            base = 56
        }

        if let bodyTension = snapshot.bodyTension, bodyTension >= 7 {
            return max(35, base - 12)
        }
        return base
    }
}

enum A10FollowUpOrchestrator {
    static func build(
        snapshot: HealthRuntimeSnapshot,
        risk: RiskPreventionState,
        language: AppLanguage
    ) -> FollowUpRuntime {
        if let exerciseMinutes = snapshot.exerciseDurationMinutes, exerciseMinutes > 0 {
            return FollowUpRuntime(
                title: L10n.text("运动后自动复盘", "Automatic post-workout review", language: language),
                detail: L10n.text(
                    "系统已经拿到你今天 \(exerciseMinutes) 分钟的运动基础数据。运动后心率和明早恢复会继续作为复盘依据。",
                    "The system already has the base data from today's \(exerciseMinutes)-minute workout. Post-workout heart rate and tomorrow morning recovery will keep feeding the review.",
                    language: language
                ),
                status: .automatic,
                actionTitle: L10n.text("让 Max 继续复盘", "Let Max review it", language: language),
                intent: "workout_follow_up",
                prompt: L10n.text(
                    "系统已经拿到我今天的运动基础数据。请直接开始运动后复盘：先判断恢复是否正常，再告诉我接下来需要关注什么。",
                    "The system already has the base data from today's workout. Start the post-workout review directly: tell me whether recovery looks normal, then what to watch next.",
                    language: language
                )
            )
        }

        if risk.riskLevel == .red {
            return FollowUpRuntime(
                title: L10n.text("先稳住，再看明早恢复", "Stabilize first, then check tomorrow", language: language),
                detail: L10n.text(
                    "今天先不要追求完成训练。明早再看睡眠、HRV 和静息心率，再决定要不要恢复运动。",
                    "Do not chase training completion today. Re-check sleep, HRV, and resting heart rate tomorrow morning before deciding whether to return.",
                    language: language
                ),
                status: .pending,
                actionTitle: L10n.text("让 Max 讲清楚", "Ask Max to explain", language: language),
                intent: "next_day_follow_up",
                prompt: L10n.text(
                    "请按保守原则帮我安排明早的恢复复盘，告诉我先看哪些信号，再决定是否恢复运动。",
                    "Using a conservative approach, set up my recovery review for tomorrow morning and tell me which signals to check before returning to exercise.",
                    language: language
                )
            )
        }

        return FollowUpRuntime(
            title: L10n.text("明早再确认一次身体", "Check again tomorrow morning", language: language),
            detail: L10n.text(
                "明早系统会继续用睡眠、HRV 和静息心率做下一次判断，尽量减少你手动输入。",
                "Tomorrow morning the system will use sleep, HRV, and resting heart rate for the next judgment, with minimal manual input from you.",
                language: language
            ),
            status: .automatic,
            actionTitle: L10n.text("让 Max 做晨间判断", "Let Max do the morning check", language: language),
            intent: "next_day_follow_up",
            prompt: L10n.text(
                "请按明早恢复复盘来判断我是不是适合继续运动，优先看睡眠、HRV、静息心率和昨天的负荷。",
                "Run the next-morning recovery review and tell me whether I am fit to continue exercising, prioritizing sleep, HRV, resting heart rate, and yesterday's load.",
                language: language
            )
        )
    }
}

enum A10FusionReplyEngine {
    static func build(
        snapshot: HealthRuntimeSnapshot,
        risk: RiskPreventionState,
        followUp: FollowUpRuntime,
        proactiveBrief: ProactiveCareBrief?,
        activePlanTitle: String?,
        language: AppLanguage
    ) -> FusionReplyRuntime {
        let blockedActions = blockedActions(for: risk.intensityCap, language: language)
        let recommendedAction = recommendedAction(
            for: risk.intensityCap,
            proactiveBrief: proactiveBrief,
            language: language
        )
        let bodySignalSummary = bodySignalSummary(snapshot: snapshot, language: language)
        let reasonSummary = reasonSummary(risk: risk, language: language)
        let primaryConclusion = primaryConclusion(
            risk: risk,
            activePlanTitle: activePlanTitle,
            language: language
        )

        return FusionReplyRuntime(
            primaryConclusion: primaryConclusion,
            riskLevel: risk.riskLevel,
            readinessScore: risk.readinessScore,
            intensityCap: risk.intensityCap,
            bodySignalSummary: bodySignalSummary,
            reasonSummary: reasonSummary,
            recommendedAction: recommendedAction,
            blockedActions: blockedActions,
            followUpTask: followUp.title,
            evidenceSummary: Array((risk.redFlags + risk.evidenceLines).prefix(3)),
            primaryActionTitle: L10n.text("按建议执行", "Follow guidance", language: language),
            secondaryActionTitle: L10n.text("我还是想跑", "I still want to run", language: language),
            explanationActionTitle: L10n.text("看看为什么", "Why this", language: language),
            continuePrompt: continuePrompt(
                risk: risk,
                recommendedAction: recommendedAction,
                followUp: followUp,
                language: language
            ),
            overridePrompt: overridePrompt(risk: risk, language: language),
            discomfortPrompt: discomfortPrompt(language: language),
            explanationPrompt: explanationPrompt(
                bodySignalSummary: bodySignalSummary,
                risk: risk,
                recommendedAction: recommendedAction,
                language: language
            )
        )
    }

    private static func primaryConclusion(
        risk: RiskPreventionState,
        activePlanTitle: String?,
        language: AppLanguage
    ) -> String {
        switch risk.intensityCap {
        case .increase:
            return L10n.text("今天可以小幅加一点强度。", "You can increase intensity a little today.", language: language)
        case .maintain:
            if let activePlanTitle, !activePlanTitle.isEmpty {
                return language == .en
                    ? "Stay with today's plan: \(activePlanTitle)."
                    : "今天维持原计划：\(activePlanTitle)。"
            }
            return L10n.text("今天维持原计划就够了。", "Holding the original plan is enough today.", language: language)
        case .moderateOnly:
            return L10n.text("今天不建议上高强度，先降到中等强度。", "High intensity is not a good fit today. Downgrade to moderate first.", language: language)
        case .lowOnly:
            return L10n.text("今天更适合低强度或恢复日。", "Today fits low intensity or a recovery day better.", language: language)
        case .stopOrLowOnly:
            return L10n.text("今天先不要做中高强度。", "Avoid moderate-to-hard intensity today.", language: language)
        }
    }

    private static func bodySignalSummary(
        snapshot: HealthRuntimeSnapshot,
        language: AppLanguage
    ) -> String {
        var parts: [String] = []
        if let hrv = snapshot.hrv { parts.append("HRV \(Int(hrv.rounded()))") }
        if let restingHeartRate = snapshot.restingHeartRate {
            parts.append(L10n.text("静息心率 \(Int(restingHeartRate.rounded()))", "Resting HR \(Int(restingHeartRate.rounded()))", language: language))
        }
        if let sleepScore = snapshot.sleepScore {
            parts.append(L10n.text("睡眠分 \(Int(sleepScore.rounded()))", "Sleep score \(Int(sleepScore.rounded()))", language: language))
        } else if let sleepMinutes = snapshot.sleepDurationMinutes {
            let hours = Double(sleepMinutes) / 60
            parts.append(L10n.text("睡眠 \(String(format: "%.1f", hours))h", "Sleep \(String(format: "%.1f", hours))h", language: language))
        }
        if let steps = snapshot.steps {
            parts.append(L10n.text("步数 \(Int(steps.rounded()))", "Steps \(Int(steps.rounded()))", language: language))
        }

        if parts.isEmpty {
            return L10n.text(
                "身体信号还在补齐，当前先按已有记录做保守判断。",
                "Signals are still loading, so the current judgment stays conservative.",
                language: language
            )
        }
        return parts.joined(separator: language == .en ? " · " : "｜")
    }

    private static func reasonSummary(
        risk: RiskPreventionState,
        language: AppLanguage
    ) -> String {
        if let firstRedFlag = risk.redFlags.first {
            return firstRedFlag
        }

        switch risk.intensityCap {
        case .increase:
            return L10n.text("恢复信号比较完整，可以在不冒进的前提下轻微加量。", "Recovery signals are fairly complete, so you can add a little without getting aggressive.", language: language)
        case .maintain:
            return L10n.text("今天的状态能支撑原计划，但没有必要再额外加码。", "Today's state supports the original plan, but there is no need to add extra load.", language: language)
        case .moderateOnly:
            return L10n.text("恢复并不差，但还不到适合冲高强度的程度。", "Recovery is not bad, but not strong enough for hard effort.", language: language)
        case .lowOnly:
            return L10n.text("恢复信号偏弱，今天更适合轻恢复和把身体带回稳定。", "Recovery is soft today, so light recovery and stabilizing the body are a better fit.", language: language)
        case .stopOrLowOnly:
            return L10n.text("风险提示已经高于训练收益，今天先稳住更重要。", "Risk signals are outweighing training upside, so stabilizing first matters more today.", language: language)
        }
    }

    private static func recommendedAction(
        for intensityCap: A10IntensityCap,
        proactiveBrief: ProactiveCareBrief?,
        language: AppLanguage
    ) -> String {
        let fallback: String
        switch intensityCap {
        case .increase:
            fallback = L10n.text("按计划完成今天训练，最多只加一档，不做冲动加量。", "Do today's planned session and add at most one step, without impulsive extra load.", language: language)
        case .maintain:
            fallback = L10n.text("按原计划完成，不额外加码。", "Complete the original plan without adding extra load.", language: language)
        case .moderateOnly:
            fallback = L10n.text("把今天的训练自动降到中等强度，去掉冲刺和间歇。", "Downgrade today's session to moderate intensity and remove sprints or intervals.", language: language)
        case .lowOnly:
            fallback = L10n.text("改成 20 分钟轻松走跑、散步或恢复动作。", "Switch to 20 minutes of easy walk-jog, walking, or recovery work.", language: language)
        case .stopOrLowOnly:
            fallback = L10n.text("暂停中高强度，先做恢复动作，必要时只保留轻松步行。", "Pause moderate-to-hard effort, start with recovery work, and keep only easy walking if needed.", language: language)
        }

        guard let proactiveBrief,
              !proactiveBrief.microAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return proactiveBrief.microAction
    }

    private static func blockedActions(
        for intensityCap: A10IntensityCap,
        language: AppLanguage
    ) -> [String] {
        switch intensityCap {
        case .increase, .maintain:
            return [L10n.text("不要临时冲动加很多量", "Do not impulsively add a lot of extra load", language: language)]
        case .moderateOnly:
            return [
                L10n.text("不要冲刺", "No sprinting", language: language),
                L10n.text("不要间歇加量", "No interval spikes", language: language),
                L10n.text("不要把时长再拉长", "Do not extend duration", language: language)
            ]
        case .lowOnly, .stopOrLowOnly:
            return [
                L10n.text("不要做中高强度", "Avoid moderate-to-hard effort", language: language),
                L10n.text("不要冲刺", "No sprinting", language: language),
                L10n.text("不要硬撑", "Do not force it", language: language)
            ]
        }
    }

    private static func continuePrompt(
        risk: RiskPreventionState,
        recommendedAction: String,
        followUp: FollowUpRuntime,
        language: AppLanguage
    ) -> String {
        let lead = L10n.text(
            "请基于当前身体信号和风险判断，把今天的执行方案说得非常具体：先给结论，再说原因，再列出我现在就做的动作，最后告诉我完成后怎么反馈给你。",
            "Using the current body signals and risk judgment, make today's execution plan concrete: conclusion first, then reason, then what I should do now, and finally how to report back after finishing.",
            language: language
        )
        return "\(lead) \(recommendedAction) \(followUp.detail)"
    }

    private static func overridePrompt(
        risk: RiskPreventionState,
        language: AppLanguage
    ) -> String {
        let lead = L10n.text(
            "我还是想跑。请不要直接鼓励我上强度，而是给我最低风险的降级版本，并明确告诉我出现什么信号必须立刻停。",
            "I still want to run. Do not simply encourage hard effort. Give me the lowest-risk downgraded version and tell me exactly which signals mean I should stop immediately.",
            language: language
        )
        return "\(lead) \(risk.evidenceLines.joined(separator: " "))"
    }

    private static func discomfortPrompt(language: AppLanguage) -> String {
        L10n.text(
            "我现在不舒服。请先别鼓励运动，先问我一个最高价值的问题，再给我最安全的下一步。",
            "I feel unwell right now. Do not encourage exercise first. Ask me one highest-value question, then give me the safest next step.",
            language: language
        )
    }

    private static func explanationPrompt(
        bodySignalSummary: String,
        risk: RiskPreventionState,
        recommendedAction: String,
        language: AppLanguage
    ) -> String {
        let lead = L10n.text(
            "请把这次判断讲清楚：身体信号、风险级别、为什么是这个强度上限、为什么推荐这个动作。",
            "Explain this judgment clearly: body signals, risk level, why this is the intensity cap, and why this action is recommended.",
            language: language
        )
        return "\(lead) \(bodySignalSummary) \(risk.evidenceLines.joined(separator: " ")) \(recommendedAction)"
    }
}

enum A10FusionRuntimeBuilder {
    static func build(
        dashboard: DashboardData?,
        proactiveBrief: ProactiveCareBrief?,
        activePlanTitle: String?,
        language: AppLanguage
    ) -> A10FusionRuntimeBundle {
        let health = HealthRuntimeSnapshot.from(dashboard: dashboard)
        let redFlags = A10RiskRedFlagEngine.evaluate(snapshot: health, language: language)
        let risk = A10ExerciseReadinessEngine.evaluate(
            snapshot: health,
            redFlags: redFlags,
            language: language
        )
        let followUp = A10FollowUpOrchestrator.build(
            snapshot: health,
            risk: risk,
            language: language
        )
        let fusion = A10FusionReplyEngine.build(
            snapshot: health,
            risk: risk,
            followUp: followUp,
            proactiveBrief: proactiveBrief,
            activePlanTitle: activePlanTitle,
            language: language
        )
        return A10FusionRuntimeBundle(health: health, risk: risk, followUp: followUp, fusion: fusion)
    }
}
