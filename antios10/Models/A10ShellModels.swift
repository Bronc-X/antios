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
