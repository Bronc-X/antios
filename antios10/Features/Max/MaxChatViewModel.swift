// MaxChatViewModel.swift
// Max 对话视图模型 - 支持消息持久化、多对话管理、P1/P2 功能

import SwiftUI
import Foundation
import Network

#if DEBUG
private struct DebugMaxBatchState {
    let prompts: [String]
    let source: String
    var currentIndex: Int = 0
    var currentPrompt: String?
    var currentStartedAt: Date?
}
#endif

// MARK: - 模型模式枚举
enum ModelMode: String, CaseIterable {
    case fast = "fast"
    case think = "think"
    
    var displayName: String {
        switch self {
        case .fast: return "快速"
        case .think: return "深思"
        }
    }
    
    var icon: String {
        switch self {
        case .fast: return "hare"
        case .think: return "brain"
        }
    }
}

struct MaxAgentBodySummary: Equatable {
    let headline: String
    let detail: String
    let prompt: String
    let hasSignals: Bool
}

struct MaxAgentPlanSummary: Equatable {
    let headline: String
    let detail: String
    let prompt: String
    let hasActivePlan: Bool
    let ctaTitle: String
}

struct MaxAgentInquirySummary: Equatable {
    let headline: String
    let detail: String
    let prompt: String
    let question: InquiryQuestion?
    let primaryTitle: String
    let evidenceTitle: String?
    let evidenceURL: String?

    var hasPendingInquiry: Bool {
        question != nil
    }
}

struct MaxAgentProactiveSummary: Equatable {
    let headline: String
    let detail: String
    let microAction: String
    let followUpQuestion: String
    let prompt: String
    let continuePrompt: String
    let hasBrief: Bool
    let primaryTitle: String
    let secondaryTitle: String?
}

struct MaxAgentEvidenceSummary: Equatable {
    let headline: String
    let detail: String
    let sourceTitle: String?
    let sourceURL: String?
    let confidenceText: String?
    let prompt: String
    let hasEvidence: Bool
    let primaryTitle: String
}

struct MaxAgentActionReviewSummary: Equatable {
    let actionLabel: String
    let hasAction: Bool
    let completedTitle: String
    let tooHardTitle: String
    let skippedTitle: String
}

struct MaxAgentSurfaceModel: Equatable {
    let body: MaxAgentBodySummary
    let inquiry: MaxAgentInquirySummary
    let plan: MaxAgentPlanSummary
    let proactive: MaxAgentProactiveSummary
    let evidence: MaxAgentEvidenceSummary
    let actionReview: MaxAgentActionReviewSummary

    static func placeholder(language: AppLanguage) -> Self {
        MaxAgentSurfaceModel(
            body: MaxAgentBodySummary(
                headline: L10n.text("等待身体信号同步", "Waiting for body signals", language: language),
                detail: L10n.text("先连接 Apple Health，或者先记录一次现在的状态，Max 会按你的身体感觉继续。", "Connect Apple Health or note your current state once first. Max will continue from how your body feels.", language: language),
                prompt: L10n.text("我还没有同步 Apple Health。先根据我今天的体感，带我快速记录一下状态，然后给我一个恢复动作。", "I have not synced Apple Health yet. Start by quickly capturing how I feel today, then give me one recovery action.", language: language),
                hasSignals: false
            ),
            inquiry: MaxAgentInquirySummary(
                headline: L10n.text("问题会跟着你的状态来", "Questions follow your state", language: language),
                detail: L10n.text("当信息还不够时，Max 会先问你一个最关键的问题。", "When there is not enough information, Max asks one key question first.", language: language),
                prompt: L10n.text("请基于我当前的身体状态，先问我一个最高价值的问题，再据此决定下一步动作。", "Based on my current body state, ask me the highest-value question first, then decide the next action.", language: language),
                question: nil,
                primaryTitle: L10n.text("生成一个聚焦问题", "Generate one focused question", language: language),
                evidenceTitle: nil,
                evidenceURL: nil
            ),
            plan: MaxAgentPlanSummary(
                headline: L10n.text("把计划放回对话里", "Keep the plan in chat", language: language),
                detail: L10n.text("计划执行和复盘可以直接在 Max 里完成，不需要切到独立页面。", "Plan execution and review can happen directly in Max without switching to a separate screen.", language: language),
                prompt: L10n.text("基于我当前的身体状态，给我一个今天 10 分钟内能完成的微计划，并拆成 3 步。", "Based on my current body state, give me a micro-plan I can finish within 10 minutes today and break it into 3 steps.", language: language),
                hasActivePlan: false,
                ctaTitle: L10n.text("让 Max 给今天动作", "Ask Max for today's action", language: language)
            ),
            proactive: MaxAgentProactiveSummary(
                headline: L10n.text("今日建议待整理", "Today's guidance is waiting", language: language),
                detail: L10n.text("Max 会把你的状态、最近变化和相关内容整理成一条今天最有用的建议。", "Max will turn your state, recent changes, and relevant content into one useful suggestion for today.", language: language),
                microAction: L10n.text("先刷新，或让 Max 判断今天最该先做什么。", "Refresh first, or let Max decide what to do first today.", language: language),
                followUpQuestion: L10n.text("完成后，再让 Max 继续追问。", "After completing it, let Max continue the follow-up.", language: language),
                prompt: L10n.text("请基于我今天的身体状态、最近变化和相关内容，给我一条今天最适合的建议：先说结论，再说原因，给一个微动作，最后留一个跟进问题。", "Use my body state, recent changes, and relevant context to give me the most useful guidance for today: conclusion first, then reason, one micro-action, and one follow-up question.", language: language),
                continuePrompt: L10n.text("请基于我今天的身体状态、最近变化和相关内容，给我一条今天最适合的建议：先说结论，再说原因，给一个微动作，最后留一个跟进问题。", "Use my body state, recent changes, and relevant context to give me the most useful guidance for today: conclusion first, then reason, one micro-action, and one follow-up question.", language: language),
                hasBrief: false,
                primaryTitle: L10n.text("整理今天建议", "Generate today's guidance", language: language),
                secondaryTitle: nil
            ),
            evidence: MaxAgentEvidenceSummary(
                headline: L10n.text("原因说明待展开", "Reasoning is waiting", language: language),
                detail: L10n.text("今天的建议会附带原因和参考内容，展开后再让 Max 说得更清楚。", "Today's guidance comes with a reason and reference context, then Max can explain it more clearly.", language: language),
                sourceTitle: nil,
                sourceURL: nil,
                confidenceText: nil,
                prompt: L10n.text("请结合我当前身体状态，把今天建议背后的原因和参考内容讲清楚，并给我一个最小动作。", "Using my current body state, explain the reason and references behind today's guidance, then give me one smallest next action.", language: language),
                hasEvidence: false,
                primaryTitle: L10n.text("看看为什么", "Why this", language: language)
            ),
            actionReview: MaxAgentActionReviewSummary(
                actionLabel: L10n.text("完成一个动作后，再回来标记结果。", "Complete one action first, then return to mark the result.", language: language),
                hasAction: false,
                completedTitle: L10n.text("已完成", "Done", language: language),
                tooHardTitle: L10n.text("太难了", "Too hard", language: language),
                skippedTitle: L10n.text("先跳过", "Skip", language: language)
            )
        )
    }
}

@MainActor
class MaxChatViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var messages: [ChatMessage] = []
    @Published var conversations: [Conversation] = []
    @Published var currentConversationId: String? = nil
    @Published var inputText = ""
    @Published var isTyping = false
    @Published var isLoading = false
    @Published var error: String? = nil
    
    // 🆕 P1 功能
    @Published private(set) var modelMode: ModelMode = .think
    @Published var starterQuestions: [String] = []
    @Published var agentSurface = MaxAgentSurfaceModel.placeholder(language: L10n.currentLanguage())
    @Published var pendingExecutionRequest: MaxAgentExecutionRequest?
    
    // 🆕 P2 功能 - 离线状态
    @Published var isOffline = false
    private var networkMonitor: NWPathMonitor?
    
    // 🆕 停止生成 - 任务引用
    private var currentGenerationTask: Task<Void, Never>? = nil
    private var generationId: Int = 0
    
    // 🆕 个性化上下文缓存
    private var cachedUserContext: String? = nil
    private var cachedUserContextAt: Date? = nil
    private var localConversationBackfillInFlight: Set<String> = []
    private var localConversationMessages: [String: [ChatMessage]] = [:]
    #if DEBUG
    private var debugBatchState: DebugMaxBatchState?
    #endif

    private enum MaxChatTimeoutError: LocalizedError {
        case cloudTimeout
        case conversationUnavailable

        var errorDescription: String? {
            let isEn = AppLanguage.fromStored(UserDefaults.standard.string(forKey: "app_language")) == .en
            switch self {
            case .cloudTimeout:
                return isEn ? "Cloud response timed out" : "云端响应超时"
            case .conversationUnavailable:
                return isEn ? "Conversation is temporarily unavailable. Try again shortly." : "会话暂不可用，请稍后重试"
            }
        }
    }
    
    // MARK: - Init
    
    init() {
        setupNetworkMonitor()
        Task {
            await loadConversations()
            await loadStarterQuestions()
            await refreshAgentSurface()
        }
    }
    
    deinit {
        networkMonitor?.cancel()
    }

    private let maxSystemPrompt = """
    你是 Max，一个高效、直接、简洁的反焦虑跟进助手。
    - 中文回答，避免冗长铺垫
    - 输出结构化科学抚慰（理解/机制/证据/动作/跟进）
    - 不要编造数据；不确定就说不确定
    """

    private var userContextCacheTTL: TimeInterval {
        max(60, runtimeDouble(for: "MAX_USER_CONTEXT_CACHE_TTL_SEC", fallback: 300))
    }

    private var conversationCreateTimeout: TimeInterval {
        max(1, runtimeDouble(for: "MAX_CHAT_CONVERSATION_CREATE_TIMEOUT_SEC", fallback: 3))
    }

    private var messagePersistMaxRetries: Int {
        max(1, runtimeInt(for: "MAX_CHAT_MESSAGE_PERSIST_MAX_RETRIES", fallback: 3))
    }

    private var messagePersistRetryBaseDelayNanos: UInt64 {
        let millis = max(50, runtimeInt(for: "MAX_CHAT_MESSAGE_RETRY_BASE_DELAY_MS", fallback: 350))
        return UInt64(millis) * 1_000_000
    }

    private var cloudResponseTimeoutFastSeconds: UInt64 {
        UInt64(cloudTimeoutSeconds(mode: .fast))
    }

    private var cloudResponseTimeoutThinkSeconds: UInt64 {
        UInt64(cloudTimeoutSeconds(mode: .think))
    }

    private func cloudTimeoutSeconds(mode: ModelMode) -> Int {
        let remoteKey = (mode == .think) ? "MAX_CHAT_REMOTE_TIMEOUT_THINK_SEC" : "MAX_CHAT_REMOTE_TIMEOUT_FAST_SEC"
        let localKey = (mode == .think) ? "MAX_CHAT_LOCAL_TIMEOUT_THINK_SEC" : "MAX_CHAT_LOCAL_TIMEOUT_FAST_SEC"
        let cloudKey = (mode == .think) ? "MAX_CHAT_CLOUD_TIMEOUT_THINK_SEC" : "MAX_CHAT_CLOUD_TIMEOUT_FAST_SEC"

        let remote = max(mode == .think ? 6 : 4, runtimeInt(for: remoteKey, fallback: mode == .think ? 14 : 9))
        let local = max(mode == .think ? 8 : 6, runtimeInt(for: localKey, fallback: mode == .think ? 18 : 12))
        let hardPadding = max(1, Int(ceil(runtimeDouble(for: "SUPABASE_NETWORK_HARD_TIMEOUT_PADDING_SEC", fallback: 1.2))))
        let guardBand = mode == .think ? 8 : 6

        // Budget must cover remote attempt + local fallback path to avoid false timeout downgrade.
        let derivedFloor = remote + local + hardPadding + guardBand
        let configured = runtimeInt(for: cloudKey, fallback: derivedFloor)
        return max(derivedFloor, configured)
    }

    private func runtimeString(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let raw = Bundle.main.infoDictionary?[key] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }

        if let number = Bundle.main.infoDictionary?[key] as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private func runtimeInt(for key: String, fallback: Int) -> Int {
        guard let raw = runtimeString(for: key), let value = Int(raw) else {
            return fallback
        }
        return value
    }

    private func runtimeDouble(for key: String, fallback: Double) -> Double {
        guard let raw = runtimeString(for: key), let value = Double(raw) else {
            return fallback
        }
        return value
    }

    private var currentLanguage: AppLanguage {
        AppLanguage.fromStored(UserDefaults.standard.string(forKey: "app_language"))
    }

    private func t(_ zh: String, _ en: String) -> String {
        L10n.text(zh, en, language: currentLanguage)
    }

    func refreshAgentSurface(forceProactiveBrief: Bool = false) async {
        let language = currentLanguage
        guard SupabaseManager.shared.currentUser != nil else {
            agentSurface = .placeholder(language: language)
            return
        }

        async let dashboardTask: DashboardData? = try? await SupabaseManager.shared.getDashboardData()
        async let activePlanTask = loadActivePlanSummary()
        async let inquiryTask: InquiryPendingResponse? = try? await SupabaseManager.shared.getPendingInquiry(language: language.apiCode)
        async let proactiveBriefTask: ProactiveCareBrief? = try? await SupabaseManager.shared.generateProactiveCareBrief(
            language: language.apiCode,
            forceRefresh: forceProactiveBrief
        )

        let dashboard = await dashboardTask
        let activePlan = await activePlanTask
        let pendingInquiry = await inquiryTask?.inquiry
        let proactiveBrief = await proactiveBriefTask
        agentSurface = buildAgentSurface(
            dashboard: dashboard,
            pendingInquiry: pendingInquiry,
            activePlan: activePlan,
            proactiveBrief: proactiveBrief,
            language: language
        )
    }

    func sendPreparedPrompt(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if isTyping {
            inputText = trimmed
            error = t("Max 仍在回复，建议已放入输入框。", "Max is still responding. The suggested prompt was added to the input.")
            return
        }

        inputText = trimmed
        sendMessage()
    }

    #if DEBUG
    func startDebugBatch(prompts: [String], source: String) {
        let normalizedPrompts = prompts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalizedPrompts.isEmpty else { return }

        debugBatchState = DebugMaxBatchState(prompts: normalizedPrompts, source: source)
        print("[MaxDebugBatch] start count=\(normalizedPrompts.count) source=\(source)")
        startNextDebugBatchPromptIfNeeded()
    }

    private func startNextDebugBatchPromptIfNeeded() {
        guard var state = debugBatchState else { return }
        guard !isTyping else { return }

        if state.currentIndex >= state.prompts.count {
            print("[MaxDebugBatch] complete count=\(state.prompts.count) source=\(state.source)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                exit(0)
            }
            debugBatchState = nil
            return
        }

        let prompt = state.prompts[state.currentIndex]
        state.currentPrompt = prompt
        state.currentStartedAt = Date()
        debugBatchState = state
        print("[MaxDebugBatch] round=\(state.currentIndex + 1)/\(state.prompts.count) prompt=\(prompt)")
        sendPreparedPrompt(prompt)
    }

    private func completeDebugBatchRound(reply: String, fallbackReason: String?) {
        guard var state = debugBatchState,
              let prompt = state.currentPrompt,
              let startedAt = state.currentStartedAt else { return }

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        let sanitizedReply = reply
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        let reason = fallbackReason?.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") ?? ""
        print("[MaxDebugBatch] result round=\(state.currentIndex + 1) elapsed_ms=\(elapsedMs) fallback_reason=\(reason) prompt=\(prompt) reply=\(sanitizedReply)")

        state.currentIndex += 1
        state.currentPrompt = nil
        state.currentStartedAt = nil
        debugBatchState = state

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.startNextDebugBatchPromptIfNeeded()
        }
    }
    #endif

    func handleInputSubmission() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let action = MaxAgentActionRouter.resolveUserInput(
            trimmed,
            language: currentLanguage,
            agentSurface: agentSurface
        ) {
            inputText = ""
            performResolvedAction(action, sourceText: trimmed)
            return
        }

        sendMessage()
    }

    func handleAskMaxNotification(userInfo: [AnyHashable: Any]) {
        if let action = MaxAgentActionRouter.resolveNotificationAction(
            userInfo: userInfo,
            language: currentLanguage,
            agentSurface: agentSurface
        ) {
            performResolvedAction(action, sourceText: userInfo["question"] as? String)
            return
        }

        if let question = userInfo["question"] as? String,
           !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            inputText = question
            sendMessage()
        }
    }

    func explainLatestBodySignals() {
        sendPreparedPrompt(agentSurface.body.prompt)
    }

    func continueFromCheckIn(_ result: DailyCalibrationResult) {
        Task {
            await refreshAgentSurface(forceProactiveBrief: true)
        }
        sendPreparedPrompt(buildCheckInFollowUpPrompt(result))
    }

    func continueFromPlanReview(planName: String, completedItems: [String], remainingCount: Int) {
        Task {
            await refreshAgentSurface()
        }
        sendPreparedPrompt(
            buildPlanReviewFollowUpPrompt(
                planName: planName,
                completedItems: completedItems,
                remainingCount: remainingCount
            )
        )
    }

    func continueFromInquiry(question: InquiryQuestion, selectedOption: InquiryOption) {
        Task {
            await refreshAgentSurface(forceProactiveBrief: true)
        }
        sendPreparedPrompt(buildInquiryFollowUpPrompt(question: question, selectedOption: selectedOption))
    }

    func openProactiveBriefInChat() {
        sendPreparedPrompt(agentSurface.proactive.prompt)
    }

    func openEvidenceDetail() {
        pendingExecutionRequest = .evidence
    }

    func openInquiryThread() {
        pendingExecutionRequest = .inquiry
    }

    func explainAgentEvidence() {
        sendPreparedPrompt(agentSurface.evidence.prompt)
    }

    func requestFocusedInquiry() {
        sendPreparedPrompt(agentSurface.inquiry.prompt)
    }

    func continueFromProactiveBrief() {
        let proactive = agentSurface.proactive
        guard proactive.hasBrief else {
            sendPreparedPrompt(proactive.prompt)
            return
        }

        Task {
            await SupabaseManager.shared.captureUserSignal(
                domain: "max",
                action: "proactive_follow_up_requested",
                summary: proactive.microAction,
                metadata: [
                    "source": "max_agent_surface",
                    "follow_up_question": proactive.followUpQuestion,
                    "has_brief": true
                ]
            )
            await refreshAgentSurface()
        }
        sendPreparedPrompt(proactive.continuePrompt)
    }

    func consumePendingExecutionRequest() {
        pendingExecutionRequest = nil
    }

    func handleInlineAction(_ action: MaxInlineAction) {
        switch action.kind {
        case .checkIn:
            pendingExecutionRequest = .checkIn
        case .planReview:
            pendingExecutionRequest = .planReview
        case .breathing:
            pendingExecutionRequest = .breathing(minutes: max(1, min(30, action.minutes ?? 5)))
        case .inquiry:
            pendingExecutionRequest = .inquiry
        case .evidence:
            pendingExecutionRequest = .evidence
        case .sendPrompt:
            let prompt = action.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? action.title
            sendPreparedPrompt(prompt)
        case .reviewCompleted:
            submitActionReview(.completed, sourceText: action.prompt)
        case .reviewTooHard:
            submitActionReview(.tooHard, sourceText: action.prompt)
        case .reviewSkipped:
            submitActionReview(.skipped, sourceText: action.prompt)
        }
    }

    private func performResolvedAction(_ action: MaxAgentResolvedAction, sourceText: String?) {
        switch action {
        case .execute(let request):
            appendExecutionMessages(for: request, sourceText: sourceText)
            pendingExecutionRequest = request
        case .sendPrompt(let prompt):
            sendPreparedPrompt(prompt)
        case .review(let outcome):
            submitActionReview(outcome, sourceText: sourceText)
        }
    }

    func submitActionReview(_ outcome: MaxActionReviewOutcome, sourceText: String? = nil) {
        let action = agentSurface.actionReview.actionLabel
        guard agentSurface.actionReview.hasAction else { return }

        Task {
            await SupabaseManager.shared.captureUserSignal(
                domain: "agent_action_review",
                action: outcome.rawValue,
                summary: action,
                metadata: [
                    "source": "max_agent_surface",
                    "outcome": outcome.rawValue
                ]
            )
            await refreshAgentSurface(forceProactiveBrief: outcome == .completed)
        }

        let prompt = buildActionReviewFollowUpPrompt(action: action, outcome: outcome, sourceText: sourceText)
        sendPreparedPrompt(prompt)
    }

    private func appendExecutionMessages(for request: MaxAgentExecutionRequest, sourceText: String?) {
        let trimmedSource = sourceText?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedSource, !trimmedSource.isEmpty {
            messages.append(ChatMessage(role: .user, content: trimmedSource))
        }

        let assistantText: String
        switch request {
        case .checkIn:
            assistantText = t(
                "已切到每日状态记录。我会先收 5 个最必要的信息，再根据你的状态继续。",
                "Switched to the daily state note. I will collect the 5 most useful signals first, then continue from your current state."
            )
        case .planReview:
            assistantText = t(
                "已切到计划复盘。先勾选你已经完成的项，我再决定下一步最小动作。",
                "Switched to plan review. Check off what you already completed, then I will decide the next smallest step."
            )
        case .breathing(let minutes):
            assistantText = currentLanguage == .en
                ? "Starting a \(minutes)-minute breathing reset. When you finish, come back and tell me how your body sensation changed."
                : "已开始 \(minutes) 分钟呼吸重置。结束后回来告诉我，你的体感变化了多少。"
        case .inquiry:
            assistantText = t(
                "先回答这个最关键的问题，再继续决定下一步动作。",
                "Answer this key question first, then we can decide the next action."
            )
        case .evidence:
            assistantText = t(
                "先看看原因和参考内容，再让 Max 把建议讲清楚。",
                "Review the reason and references first, then let Max explain the guidance clearly."
            )
        }

        messages.append(ChatMessage(role: .assistant, content: assistantText))

        if let currentConversationId, currentConversationId.hasPrefix("local-") {
            localConversationMessages[currentConversationId] = messages
        }
    }

    private var currentLoopStage: A10LoopStage {
        if !agentSurface.body.hasSignals {
            return .calibration
        }
        if agentSurface.inquiry.hasPendingInquiry {
            return .inquiry
        }
        if agentSurface.proactive.hasBrief || agentSurface.plan.hasActivePlan {
            return .action
        }
        if agentSurface.evidence.hasEvidence {
            return .evidence
        }
        return .action
    }

    private func decorateAssistantResponseIfNeeded(_ response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return response }
        guard parseMaxInlineActionCard(from: trimmed) == nil else { return trimmed }
        guard parsePlanOptions(from: trimmed) == nil else { return trimmed }
        guard let card = buildContextualInlineActionCard(for: trimmed) else { return trimmed }
        return appendMaxInlineActionCard(card, to: trimmed)
    }

    private func buildContextualInlineActionCard(for response: String) -> MaxInlineActionCard? {
        let normalized = response.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        if agentSurface.actionReview.hasAction,
           containsAny(normalized, patterns: [
               "执行后", "做完", "完成后", "复盘", "review", "after the action", "after you do it"
           ]) {
            return MaxInlineActionCard(
                title: t("直接标记这一步结果", "Mark this step right here"),
                detail: agentSurface.actionReview.actionLabel,
                actions: [
                    MaxInlineAction(title: agentSurface.actionReview.completedTitle, kind: .reviewCompleted),
                    MaxInlineAction(title: agentSurface.actionReview.tooHardTitle, kind: .reviewTooHard),
                    MaxInlineAction(title: agentSurface.actionReview.skippedTitle, kind: .reviewSkipped)
                ]
            )
        }

        switch currentLoopStage {
        case .calibration:
            return MaxInlineActionCard(
                title: t("先把身体信号补齐", "Start with body-state capture"),
                detail: t("不用离开对话，先记录一下状态，或者做一个短呼吸。", "Stay in chat and either log your state or do a short breathing reset."),
                actions: [
                    MaxInlineAction(title: t("记录状态", "Log my state"), kind: .checkIn),
                    MaxInlineAction(title: t("做 3 分钟呼吸", "Do 3-minute breathing"), kind: .breathing, minutes: 3)
                ]
            )
        case .inquiry:
            return MaxInlineActionCard(
                title: t("继续这个问题", "Continue this question"),
                detail: t("先补充一个最关键的信息，再决定下一步。", "Add one key detail before deciding the next step."),
                actions: [
                    MaxInlineAction(
                        title: agentSurface.inquiry.primaryTitle,
                        detail: agentSurface.inquiry.detail,
                        kind: .inquiry
                    ),
                    MaxInlineAction(
                        title: t("看看原因和参考内容", "See reasons and references"),
                        detail: agentSurface.inquiry.evidenceTitle ?? agentSurface.evidence.sourceTitle,
                        kind: .evidence
                    )
                ]
            )
        case .action:
            if agentSurface.actionReview.hasAction {
                return MaxInlineActionCard(
                    title: t("直接标记这一步结果", "Mark this step right here"),
                    detail: agentSurface.actionReview.actionLabel,
                    actions: [
                        MaxInlineAction(title: agentSurface.actionReview.completedTitle, kind: .reviewCompleted),
                        MaxInlineAction(title: agentSurface.actionReview.tooHardTitle, kind: .reviewTooHard),
                        MaxInlineAction(title: agentSurface.actionReview.skippedTitle, kind: .reviewSkipped)
                    ]
                )
            }

            return MaxInlineActionCard(
                title: t("把下一步收进对话里", "Keep the next step inside chat"),
                detail: agentSurface.plan.detail,
                actions: [
                    MaxInlineAction(title: agentSurface.plan.ctaTitle, kind: .planReview),
                    MaxInlineAction(
                        title: t("让 Max 继续跟进", "Ask Max to continue"),
                        detail: agentSurface.proactive.hasBrief ? agentSurface.proactive.followUpQuestion : nil,
                        kind: .sendPrompt,
                        prompt: agentSurface.proactive.hasBrief ? agentSurface.proactive.continuePrompt : agentSurface.plan.prompt
                    )
                ]
            )
        case .evidence:
            return MaxInlineActionCard(
                title: t("继续展开解释", "Keep expanding the explanation"),
                detail: agentSurface.evidence.sourceTitle ?? agentSurface.evidence.detail,
                actions: [
                    MaxInlineAction(title: agentSurface.evidence.primaryTitle, kind: .evidence),
                    MaxInlineAction(title: t("做 3 分钟呼吸", "Do 3-minute breathing"), kind: .breathing, minutes: 3)
                ]
            )
        }
    }

    private func containsAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.localizedCaseInsensitiveContains($0) }
    }

    private struct MaxAgentPlanSurfaceRow: Codable {
        let id: String
        let name: String?
        let title: String?
        let progress: Int?
        let status: String?
    }

    private func loadActivePlanSummary() async -> MaxAgentPlanSurfaceRow? {
        guard let user = SupabaseManager.shared.currentUser else { return nil }
        let endpoint = "user_plans?user_id=eq.\(user.id)&select=id,name,title,progress,status&status=eq.active&order=updated_at.desc&limit=1"
        let rows: [MaxAgentPlanSurfaceRow] = (try? await SupabaseManager.shared.request(endpoint)) ?? []
        return rows.first
    }

    private func buildAgentSurface(
        dashboard: DashboardData?,
        pendingInquiry: InquiryQuestion?,
        activePlan: MaxAgentPlanSurfaceRow?,
        proactiveBrief: ProactiveCareBrief?,
        language: AppLanguage
    ) -> MaxAgentSurfaceModel {
        let localize: (String, String) -> String = { zh, en in
            L10n.text(zh, en, language: language)
        }

        let hrv = dashboard?.hardwareData?.hrv?.value
        let restingHeartRate = dashboard?.hardwareData?.resting_heart_rate?.value
        let sleepScore = dashboard?.hardwareData?.sleep_score?.value
        let steps = dashboard?.hardwareData?.steps?.value

        var bodyMetrics: [String] = []
        if let hrv { bodyMetrics.append("HRV \(Int(hrv.rounded()))") }
        if let sleepScore { bodyMetrics.append(localize("睡眠 \(Int(sleepScore.rounded()))", "Sleep \(Int(sleepScore.rounded()))")) }
        if let restingHeartRate { bodyMetrics.append(localize("静息心率 \(Int(restingHeartRate.rounded()))", "Resting HR \(Int(restingHeartRate.rounded()))")) }
        if let steps { bodyMetrics.append(localize("步数 \(Int(steps.rounded()))", "Steps \(Int(steps.rounded()))")) }

        let hasBodySignals = !bodyMetrics.isEmpty
        let bodyHeadline: String
        let bodyDetail: String

        if let hrv, let sleepScore, hrv <= 36, sleepScore <= 70 {
            bodyHeadline = localize("恢复偏低，先减负", "Recovery looks low, reduce load first")
            bodyDetail = bodyMetrics.joined(separator: " · ")
        } else if let restingHeartRate, restingHeartRate >= 78 {
            bodyHeadline = localize("生理唤醒偏高", "Physiological arousal is elevated")
            bodyDetail = bodyMetrics.joined(separator: " · ")
        } else if let steps, steps <= 4000 {
            bodyHeadline = localize("活动量偏低，适合轻恢复", "Activity is low, favor light recovery")
            bodyDetail = bodyMetrics.joined(separator: " · ")
        } else if hasBodySignals {
            bodyHeadline = localize("身体信号已同步", "Body signals are synced")
            bodyDetail = bodyMetrics.joined(separator: " · ")
        } else if let dashboard {
            var fallbackParts: [String] = []
            if dashboard.averageSleepHours > 0 {
                fallbackParts.append(localize("近7天平均睡眠 \(String(format: "%.1f", dashboard.averageSleepHours))h", "7-day average sleep \(String(format: "%.1f", dashboard.averageSleepHours))h"))
            }
            if dashboard.averageStress > 0 {
                fallbackParts.append(localize("平均压力 \(String(format: "%.1f", dashboard.averageStress))", "Average stress \(String(format: "%.1f", dashboard.averageStress))"))
            }
            bodyHeadline = fallbackParts.isEmpty
                ? localize("先记录一下现在的状态", "Start with a quick state note")
                : localize("先用最近状态做一次判断", "Use recent state for a first-pass judgment")
            bodyDetail = fallbackParts.isEmpty
                ? localize("还没有拿到 Apple Health 数据，先记录一下现在的状态，Max 会继续问你最关键的问题。", "Apple Health data is not available yet. Note your current state first, and Max will continue with the most useful question.")
                : fallbackParts.joined(separator: " · ")
        } else {
            bodyHeadline = localize("等待身体信号同步", "Waiting for body signals")
            bodyDetail = localize("连接 Apple Health，或者先记录一次现在的状态，Max 会按你的身体感觉继续。", "Connect Apple Health or note your current state once first. Max will continue from how your body feels.")
        }

        let bodyPrompt: String
        if hasBodySignals {
            bodyPrompt = language == .en
                ? "Use my latest body signals first: \(bodyMetrics.joined(separator: ", ")). Explain what this suggests about my current recovery state, then give me one low-friction action and one follow-up question."
                : "先基于我最新的身体信号判断：\(bodyMetrics.joined(separator: "，"))。请解释这说明了我当前什么样的恢复状态，再给我一个低阻力动作和一个跟进问题。"
        } else if let dashboard, dashboard.averageSleepHours > 0 || dashboard.averageStress > 0 {
            bodyPrompt = language == .en
                ? "I do not have wearable signals yet. Based on my recent averages, sleep \(String(format: "%.1f", dashboard.averageSleepHours))h and stress \(String(format: "%.1f", dashboard.averageStress)), tell me what body-state issue to handle first and give me one action."
                : "我还没有同步穿戴设备。先基于最近状态判断：平均睡眠 \(String(format: "%.1f", dashboard.averageSleepHours))h，平均压力 \(String(format: "%.1f", dashboard.averageStress))。请告诉我当前最该先处理的身体状态问题，并给我一个动作。"
        } else {
            bodyPrompt = localize("我还没有同步身体数据。请先带我快速记录一下现在的状态，再给我今天的恢复动作。", "I have not synced body data yet. Start by quickly capturing my current state, then give me today's recovery action.")
        }

        let inquiryHeadline: String
        let inquiryDetail: String
        let inquiryPrompt: String
        let inquiryPrimaryTitle: String
        let inquiryEvidenceTitle: String?
        let inquiryEvidenceURL: String?

        if let pendingInquiry {
            inquiryHeadline = localize("先回答这个问题", "Answer this question first")
            inquiryDetail = pendingInquiry.questionText
            inquiryPrompt = language == .en
                ? "Ask me one focused follow-up question based on my current body state so you can refine the next action."
                : "请基于我当前的身体状态，先问我一个聚焦的跟进问题，用来细化下一步动作。"
            inquiryPrimaryTitle = localize("回答这条问题", "Answer this question")
            inquiryEvidenceTitle = pendingInquiry.feedContent?.title
            inquiryEvidenceURL = pendingInquiry.feedContent?.url
        } else {
            inquiryHeadline = localize("暂时没有待回答问题", "No question waiting")
            inquiryDetail = localize("当信息已经够用时，Max 会少问；需要更多了解时，再补一个关键问题。", "When there is enough information, Max asks less. It adds another key question only when needed.")
            inquiryPrompt = language == .en
                ? "Ask me one focused follow-up question based on my current body state so you can refine the next action."
                : "请基于我当前的身体状态，先问我一个聚焦的跟进问题，用来细化下一步动作。"
            inquiryPrimaryTitle = localize("生成一个聚焦问题", "Generate one focused question")
            inquiryEvidenceTitle = nil
            inquiryEvidenceURL = nil
        }

        let planTitle = activePlan?.name ?? activePlan?.title
        let planProgress = max(0, min(100, activePlan?.progress ?? 0))
        let hasActivePlan = (activePlan?.status ?? "active") == "active" && !(planTitle?.isEmpty ?? true)

        let planHeadline: String
        let planDetail: String
        let planPrompt: String
        let planCTA: String

        if hasActivePlan, let planTitle {
            planHeadline = localize("继续推进当前计划", "Continue the current plan")
            planDetail = language == .en
                ? "\(planTitle) · Progress \(planProgress)%"
                : "\(planTitle) · 进度 \(planProgress)%"
            planPrompt = language == .en
                ? "I just reviewed my plan \"\(planTitle)\" and the current progress is \(planProgress)%. Based on my latest body state, give me the next smallest step and one review question."
                : "我刚复盘了计划「\(planTitle)」，当前进度 \(planProgress)% 。请结合我最新的身体状态，给我下一步最小动作和一个复盘问题。"
            planCTA = localize("更新计划进度", "Update plan progress")
        } else {
            planHeadline = localize("把计划推进收回对话里", "Move plan follow-up into chat")
            planDetail = localize("没有进行中的计划时，直接让 Max 生成今天的微计划。", "If there is no active plan, let Max generate today's micro-plan directly.")
            planPrompt = localize("基于我最新的身体状态和焦虑负担，给我一个今天 10 分钟内能完成的微计划，并拆成 3 步。", "Based on my latest body state and anxiety load, give me a micro-plan I can finish within 10 minutes today and break it into 3 steps.")
            planCTA = localize("让 Max 给今天动作", "Ask Max for today's action")
        }

        let proactiveHeadline: String
        let proactiveDetail: String
        let proactiveAction: String
        let proactiveFollowUp: String
        let proactivePrompt: String
        let proactiveContinuePrompt: String
        let proactiveHasBrief: Bool
        let proactivePrimaryTitle: String
        let proactiveSecondaryTitle: String?

        if let brief = proactiveBrief {
            proactiveHeadline = brief.title
            proactiveDetail = brief.mechanism
            proactiveAction = brief.microAction
            proactiveFollowUp = brief.followUpQuestion
            proactivePrompt = language == .en
                ? "Expand today's guidance for me. Title: \(brief.title). Reason: \(brief.mechanism). Micro-action: \(brief.microAction). Follow-up question: \(brief.followUpQuestion). Explain why this fits my current body state and keep the next step concrete."
                : "请展开我今天的建议。标题：\(brief.title)。原因：\(brief.mechanism)。微动作：\(brief.microAction)。跟进问题：\(brief.followUpQuestion)。请解释这和我当前身体状态的关系，并把下一步说具体。"
            proactiveContinuePrompt = language == .en
                ? "I saw today's guidance. I completed: \(brief.microAction). Please continue with: \(brief.followUpQuestion)"
                : "我看到今天的建议了。我已执行：\(brief.microAction)。请继续跟进：\(brief.followUpQuestion)"
            proactiveHasBrief = true
            proactivePrimaryTitle = localize("我已执行，继续跟进", "I did it, continue")
            proactiveSecondaryTitle = localize("展开建议", "Expand guidance")
        } else {
            proactiveHeadline = localize("今日建议待整理", "Today's guidance is waiting")
            proactiveDetail = localize("Max 会把你的状态、最近变化和相关内容整理成一条今天最有用的建议。", "Max will turn your state, recent changes, and relevant context into one useful suggestion for today.")
            proactiveAction = localize("先刷新，或让 Max 判断今天最该先做什么。", "Refresh first, or let Max decide what to do first today.")
            proactiveFollowUp = localize("完成后，再让 Max 继续追问。", "After completing it, let Max continue the follow-up.")
            proactivePrompt = localize("请基于我今天的身体状态、最近变化和相关内容，给我一条今天最适合的建议：先说结论，再说原因，给一个微动作，最后留一个跟进问题。", "Use my body state, recent changes, and relevant context to give me the most useful guidance for today: conclusion first, then reason, one micro-action, and one follow-up question.")
            proactiveContinuePrompt = proactivePrompt
            proactiveHasBrief = false
            proactivePrimaryTitle = localize("整理今天建议", "Generate today's guidance")
            proactiveSecondaryTitle = nil
        }

        let evidenceHeadline: String
        let evidenceDetail: String
        let evidenceSourceTitle: String?
        let evidenceSourceURL: String?
        let evidenceConfidenceText: String?
        let evidencePrompt: String
        let evidenceHasEvidence: Bool
        let evidencePrimaryTitle: String

        if let brief = proactiveBrief,
           let sourceTitle = brief.evidenceTitle,
           !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            evidenceHeadline = localize("把原因讲到能马上去做", "Turn reasons into action")
            evidenceDetail = brief.mechanism
            evidenceSourceTitle = sourceTitle
            evidenceSourceURL = brief.evidenceURL
            if let confidence = brief.confidence {
                evidenceConfidenceText = "\(Int((min(max(confidence, 0), 1) * 100).rounded()))%"
            } else {
                evidenceConfidenceText = nil
            }
            evidencePrompt = language == .en
                ? "Explain my current state using mechanism, body signals, evidence, one action, and one follow-up question. Use this evidence source: \(sourceTitle)."
                : "请用原因、身体状态、参考内容、一个动作和一个跟进问题来解释我当前的状态。参考内容：\(sourceTitle)。"
            evidenceHasEvidence = true
            evidencePrimaryTitle = localize("展开原因说明", "Expand reasoning")
        } else {
            evidenceHeadline = localize("原因说明待展开", "Reasoning is waiting")
            evidenceDetail = localize("当今天的参考内容还不够时，先让 Max 根据你的身体状态给出稳妥解释。", "When today's reference context is not ready, let Max start with a grounded explanation from your body state.")
            evidenceSourceTitle = nil
            evidenceSourceURL = nil
            evidenceConfidenceText = nil
            evidencePrompt = language == .en
                ? "Explain my current state using mechanism, body signals, evidence, one action, and one follow-up question."
                : "请用原因、身体状态、参考内容、一个动作和一个跟进问题来解释我当前的状态。"
            evidenceHasEvidence = false
            evidencePrimaryTitle = localize("让 Max 说清原因", "Ask Max why")
        }

        let reviewAction = proactiveHasBrief ? proactiveAction : ""
        let actionReview = MaxAgentActionReviewSummary(
            actionLabel: reviewAction.isEmpty ? localize("完成一个动作后，再回来标记结果。", "Complete one action first, then return to mark the result.") : reviewAction,
            hasAction: !reviewAction.isEmpty,
            completedTitle: localize("已完成", "Done"),
            tooHardTitle: localize("太难了", "Too hard"),
            skippedTitle: localize("先跳过", "Skip")
        )

        return MaxAgentSurfaceModel(
            body: MaxAgentBodySummary(
                headline: bodyHeadline,
                detail: bodyDetail,
                prompt: bodyPrompt,
                hasSignals: hasBodySignals
            ),
            inquiry: MaxAgentInquirySummary(
                headline: inquiryHeadline,
                detail: inquiryDetail,
                prompt: inquiryPrompt,
                question: pendingInquiry,
                primaryTitle: inquiryPrimaryTitle,
                evidenceTitle: inquiryEvidenceTitle,
                evidenceURL: inquiryEvidenceURL
            ),
            plan: MaxAgentPlanSummary(
                headline: planHeadline,
                detail: planDetail,
                prompt: planPrompt,
                hasActivePlan: hasActivePlan,
                ctaTitle: planCTA
            ),
            proactive: MaxAgentProactiveSummary(
                headline: proactiveHeadline,
                detail: proactiveDetail,
                microAction: proactiveAction,
                followUpQuestion: proactiveFollowUp,
                prompt: proactivePrompt,
                continuePrompt: proactiveContinuePrompt,
                hasBrief: proactiveHasBrief,
                primaryTitle: proactivePrimaryTitle,
                secondaryTitle: proactiveSecondaryTitle
            ),
            evidence: MaxAgentEvidenceSummary(
                headline: evidenceHeadline,
                detail: evidenceDetail,
                sourceTitle: evidenceSourceTitle,
                sourceURL: evidenceSourceURL,
                confidenceText: evidenceConfidenceText,
                prompt: evidencePrompt,
                hasEvidence: evidenceHasEvidence,
                primaryTitle: evidencePrimaryTitle
            ),
            actionReview: actionReview
        )
    }

    private func buildCheckInFollowUpPrompt(_ result: DailyCalibrationResult) -> String {
        if currentLanguage == .en {
            return "I just recorded my current state in chat. Daily index \(result.dailyIndex), GAD2 \(result.gad2Score), stress \(result.stressScore), sleep duration score \(result.sleepDurationScore), sleep quality \(result.sleepQualityScore). Based on this and my latest body signals, tell me what to handle first and give me one next action."
        }
        return "我刚在对话里记录了一次当前状态。dailyIndex \(result.dailyIndex)，GAD2 \(result.gad2Score)，压力 \(result.stressScore)，睡眠时长得分 \(result.sleepDurationScore)，睡眠质量得分 \(result.sleepQualityScore)。请结合我最新的身体信号，告诉我现在最该先处理什么，并给我一个下一步动作。"
    }

    private func buildPlanReviewFollowUpPrompt(
        planName: String,
        completedItems: [String],
        remainingCount: Int
    ) -> String {
        let completedSummary = completedItems.prefix(3).joined(separator: currentLanguage == .en ? "; " : "；")
        if currentLanguage == .en {
            let completedText = completedSummary.isEmpty ? "none yet" : completedSummary
            return "I just updated the plan \"\(planName)\" in chat. Completed: \(completedText). Remaining item count: \(remainingCount). Based on my current body state, decide the next smallest step and ask me one review question."
        }
        let completedText = completedSummary.isEmpty ? "暂时还没有完成项" : completedSummary
        return "我刚在对话里更新了计划「\(planName)」。已完成：\(completedText)。剩余项数量：\(remainingCount)。请结合我当前身体状态，决定下一步最小动作，并问我一个复盘问题。"
    }

    private func buildInquiryFollowUpPrompt(question: InquiryQuestion, selectedOption: InquiryOption) -> String {
        if currentLanguage == .en {
            return "I just answered your inquiry. Question: \(question.questionText). My answer: \(selectedOption.value). Based on my latest body state, update your judgment, give me one next action, and ask one follow-up question."
        }
        return "我刚回答了你的问题。问题：\(question.questionText)。我的回答：\(selectedOption.value)。请结合我最新的身体状态，更新判断，给我一个下一步动作，并继续问我一个跟进问题。"
    }

    private func buildActionReviewFollowUpPrompt(
        action: String,
        outcome: MaxActionReviewOutcome,
        sourceText: String?
    ) -> String {
        if let sourceText, !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sourceText
        }

        switch outcome {
        case .completed:
            if currentLanguage == .en {
                return "I completed this action: \(action). Based on my current body sensation, decide the next smallest step and ask me one tracking question."
            }
            return "我完成了这个动作：\(action)。请根据我现在的体感，决定下一步最小动作，并问我一个量化跟进问题。"
        case .tooHard:
            if currentLanguage == .en {
                return "This action felt too hard: \(action). Reduce the load, tell me why it mismatched my body state, and give me an easier replacement."
            }
            return "这个动作对我来说太难了：\(action)。请降低负担，告诉我为什么它和我当前身体状态不匹配，并给我一个更容易完成的替代动作。"
        case .skipped:
            if currentLanguage == .en {
                return "I skipped this action for now: \(action). Keep the goal the same, but give me a lower-friction option and one time to retry it."
            }
            return "我先跳过了这个动作：\(action)。请保持目标不变，但给我一个阻力更低的替代选项，并告诉我什么时候重试更合适。"
        }
    }
    
    // MARK: - 🆕 P2 网络状态监听
    
    private func setupNetworkMonitor() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOffline = (path.status != .satisfied)
                if self?.isOffline == true {
                    print("⚠️ 网络已断开")
                } else {
                    print("✅ 网络已连接")
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global(qos: .background))
    }
    
    // MARK: - 🆕 Starter Questions
    
    /// 加载个性化起始问题
    func loadStarterQuestions() async {
        let language = AppLanguage.fromStored(UserDefaults.standard.string(forKey: "app_language"))
        let questions = await MaxPlanQuestionGenerator.generateStarterQuestions(language: language)
        if questions.isEmpty {
            if language == .en {
                starterQuestions = [
                    "Help me identify today's top anxiety trigger to handle first",
                    "Based on my recent sleep and stress, give me one low-friction action",
                    "Help me understand why my tension keeps coming back",
                    "I completed one action already, what is the next step?"
                ]
            } else {
                starterQuestions = [
                    "帮我判断今天最需要先处理的焦虑触发点",
                    "基于我最近睡眠和压力，先给我一个低阻力动作",
                    "请告诉我最近总是紧张反复，最可能的原因是什么",
                    "我已经完成一个动作了，下一步该怎么跟进？"
                ]
            }
        } else {
            starterQuestions = questions
        }
        print("✅ 加载了 \(starterQuestions.count) 个起始问题")
    }
    
    // MARK: - 🆕 停止生成
    
    func stopGeneration() {
        generationId += 1  // 使当前任务失效
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        isTyping = false
        
        // 更新最后一条 AI 消息
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant && $0.content.isEmpty }) {
            messages[lastIndex].content = t("（已取消）", "(Cancelled)")
        }
        print("⏹️ 已停止生成")
    }
    
    // MARK: - 对话管理
    
    /// 加载对话列表
    func loadConversations() async {
        isLoading = true
        do {
            conversations = try await SupabaseManager.shared.getConversations()
            print("✅ 加载了 \(conversations.count) 个对话")
        } catch {
            conversations = []
            self.error = t("加载对话失败", "Failed to load conversations") + ": \(error.localizedDescription)"
            print("❌ 加载对话列表失败: \(error)")
        }
        isLoading = false
    }
    
    /// 切换到指定对话
    func switchConversation(_ conversationId: String) async {
        currentConversationId = conversationId
        isLoading = true

        if conversationId.hasPrefix("local-") {
            messages = localConversationMessages[conversationId] ?? []
            isLoading = false
            print("✅ 加载本地会话消息: \(messages.count) 条")
            return
        }
        
        do {
            let history = try await SupabaseManager.shared.getChatHistory(conversationId: conversationId)
            messages = history.map { $0.toLocal() }
            print("✅ 加载了 \(messages.count) 条历史消息")
        } catch {
            print("❌ 加载对话历史失败: \(error)")
            messages = []
            self.error = t("加载对话失败", "Failed to load conversation") + ": \(error.localizedDescription)"
        }
        
        isLoading = false
    }
    
    /// 创建新对话并切换
    func startNewConversation() {
        // 取消正在进行的生成
        stopGeneration()
        
        Task {
            do {
                let conversation = try await SupabaseManager.shared.createConversation()
                conversations.insert(conversation, at: 0)
                currentConversationId = conversation.id
                messages = []
                print("✅ 创建新对话: \(conversation.id)")

                // 重新加载 Starter Questions
                await loadStarterQuestions()
            } catch {
                let localConversationId = "local-\(UUID().uuidString)"
                let now = ISO8601DateFormatter().string(from: Date())
                let localConversation = Conversation(
                    id: localConversationId,
                    user_id: SupabaseManager.shared.currentUser?.id ?? "local-user",
                    title: t("新对话", "New chat"),
                    last_message_at: now,
                    message_count: nil,
                    created_at: now
                )
                conversations.insert(localConversation, at: 0)
                currentConversationId = localConversationId
                messages = []
                localConversationMessages[localConversationId] = []
                self.error = t(
                    "云端会话不可用，已切换本地会话",
                    "Cloud conversation is unavailable. Switched to local conversation."
                )
                print("[MaxChat] ⚠️ 创建远端会话失败，切换本地会话：\(error.localizedDescription)")
                await loadStarterQuestions()
            }
        }
    }
    
    /// 删除对话
    func deleteConversation(_ conversationId: String) async -> Bool {
        if conversationId.hasPrefix("local-") {
            localConversationMessages.removeValue(forKey: conversationId)
            conversations.removeAll { $0.id == conversationId }
            if currentConversationId == conversationId {
                currentConversationId = nil
                messages = []
            }
            print("✅ 删除本地对话: \(conversationId)")
            return true
        }

        do {
            try await SupabaseManager.shared.deleteConversation(conversationId: conversationId)
            conversations.removeAll { $0.id == conversationId }
            
            if currentConversationId == conversationId {
                currentConversationId = nil
                messages = []
            }
            
            print("✅ 删除对话: \(conversationId)")
            return true
        } catch {
            print("❌ 删除对话失败: \(error)")
            self.error = t("删除失败", "Delete failed")
            return false
        }
    }
    
    // MARK: - 消息发送（🆕 支持停止生成和模型模式）
    
    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isTyping else { return }

        // 记录当前生成 ID
        let currentGenId = generationId + 1
        generationId = currentGenId

        // 乐观更新 UI
        let tempUserMessage = ChatMessage(role: .user, content: text)
        messages.append(tempUserMessage)
        if let currentConversationId, currentConversationId.hasPrefix("local-") {
            localConversationMessages[currentConversationId] = messages
        }
        inputText = ""
        isTyping = true

        // 使用可取消任务
        currentGenerationTask = Task {
            do {
                guard generationId == currentGenId else { return }

                if isOffline {
                    isTyping = false
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: decorateAssistantResponseIfNeeded(
                            buildLocalScientificSoothingResponse(
                                for: text,
                                fallbackReason: t("网络离线", "offline network")
                            )
                        )
                    ))
                    self.error = t(
                        "网络离线，已切换本地抚慰模式",
                        "Network is offline. Switched to local soothing mode."
                    )
                    return
                }

                // 1. 如果没有对话，先创建一个（短超时，失败则本地兜底）
                var conversationId = currentConversationId
                let conversationTitle = deriveTitle(from: text)
                var shouldPersistRemotely = true
                var shouldBackfillLocalConversation = false
                if conversationId == nil {
                    do {
                        let conversation = try await runWithTimeout(seconds: conversationCreateTimeout) {
                            try await SupabaseManager.shared.createConversation(title: conversationTitle)
                        }
                        conversations.insert(conversation, at: 0)
                        currentConversationId = conversation.id
                        conversationId = conversation.id
                    } catch {
                        shouldPersistRemotely = false
                        let localConversationId = "local-\(UUID().uuidString)"
                        let now = ISO8601DateFormatter().string(from: Date())
                        let localConversation = Conversation(
                            id: localConversationId,
                            user_id: SupabaseManager.shared.currentUser?.id ?? "local-user",
                            title: conversationTitle,
                            last_message_at: now,
                            message_count: nil,
                            created_at: now
                        )
                        conversations.insert(localConversation, at: 0)
                        currentConversationId = localConversationId
                        conversationId = localConversationId
                        localConversationMessages[localConversationId] = messages
                        print("[MaxChat] ⚠️ 远端会话创建失败，切换本地会话：\(error.localizedDescription)")
                    }
                }
                guard let convId = conversationId else {
                    throw MaxChatTimeoutError.conversationUnavailable
                }
                if convId.hasPrefix("local-") {
                    shouldPersistRemotely = false
                    shouldBackfillLocalConversation = true
                    localConversationMessages[convId] = messages
                }

                guard generationId == currentGenId else { return }

                // 2. 异步保存用户消息（不阻塞主回复）
                if shouldPersistRemotely {
                    let userMessageId = tempUserMessage.id
                    let userContent = text
                    Task { [weak self] in
                        guard let self else { return }
                        if let remoteId = await self.persistMessageWithRetry(
                            conversationId: convId,
                            role: "user",
                            content: userContent
                        ) {
                            if let index = self.messages.firstIndex(where: { $0.id == userMessageId }) {
                                self.messages[index].remoteId = remoteId
                            }
                        } else {
                            print("[MaxChat] ⚠️ 用户消息写入失败（已重试）：\(convId)")
                        }
                    }
                }

                guard generationId == currentGenId else { return }

                // 3. 通过 SupabaseManager 统一调用 Max（含记忆/问询/科学上下文）
                let requestMessages = messages.compactMap { message -> ChatRequestMessage? in
                    let content = contentForMaxInference(from: message.content)
                    guard !content.isEmpty else { return nil }
                    return ChatRequestMessage(
                        role: message.role == .user ? "user" : "assistant",
                        content: content
                    )
                }
                let responseText = try await requestMaxResponseWithTimeout(messages: requestMessages)
                let decoratedResponseText = decorateAssistantResponseIfNeeded(responseText)

                guard generationId == currentGenId else { return }

                // 4. 先展示 AI 回复，再异步持久化
                isTyping = false
                let localAssistantMessage = ChatMessage(
                    role: .assistant,
                    content: decoratedResponseText
                )
                messages.append(localAssistantMessage)
                if convId.hasPrefix("local-") {
                    localConversationMessages[convId] = messages
                }

                if shouldPersistRemotely {
                    let assistantMessageId = localAssistantMessage.id
                    let assistantContent = decoratedResponseText
                    Task { [weak self] in
                        guard let self else { return }
                        if let remoteId = await self.persistMessageWithRetry(
                            conversationId: convId,
                            role: "assistant",
                            content: assistantContent
                        ) {
                            if let index = self.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                                self.messages[index].remoteId = remoteId
                            }
                        } else {
                            print("[MaxChat] ⚠️ AI 回复写入失败（已重试）：\(convId)")
                        }
                    }
                }

                if shouldBackfillLocalConversation {
                    let snapshotIds = messages.map(\.id)
                    Task { [weak self] in
                        await self?.backfillLocalConversationIfNeeded(
                            localConversationId: convId,
                            preferredTitle: conversationTitle,
                            messageIDs: snapshotIds
                        )
                    }
                }
                #if DEBUG
                completeDebugBatchRound(reply: decoratedResponseText, fallbackReason: nil)
                #endif
            } catch {
                guard generationId == currentGenId else { return }

                isTyping = false
                let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let fallback = decorateAssistantResponseIfNeeded(
                    buildLocalScientificSoothingResponse(
                        for: text,
                        fallbackReason: localModeReasonSummary(from: description)
                    )
                )
                messages.append(ChatMessage(role: .assistant, content: fallback))
                if let currentConversationId, currentConversationId.hasPrefix("local-") {
                    localConversationMessages[currentConversationId] = messages
                }

                if error is MaxChatTimeoutError {
                    self.error = t(
                        "云端响应超时，已切换本地抚慰模式（可稍后重试）",
                        "Cloud response timed out. Switched to local soothing mode (retry later)."
                    )
                } else if isQuotaLikeFailure(description) {
                    self.error = t(
                        "在线服务暂时繁忙，已切换到本地安抚模式",
                        "Online service is busy. Switched to local soothing mode."
                    )
                } else if isLikelyNetworkError(error) {
                    self.error = t(
                        "网络连接异常，已切换本地抚慰模式",
                        "Network connection issue. Switched to local soothing mode."
                    )
                } else {
                    self.error = t(
                        "云端暂不可用，已切换本地抚慰模式",
                        "Cloud is temporarily unavailable. Switched to local soothing mode."
                    )
                }
                #if DEBUG
                completeDebugBatchRound(reply: fallback, fallbackReason: description)
                #endif
                print("❌ MaxChat Error: \(error)")
            }
        }
    }

    private func backfillLocalConversationIfNeeded(
        localConversationId: String,
        preferredTitle: String,
        messageIDs: [UUID]
    ) async {
        guard localConversationId.hasPrefix("local-") else { return }
        guard !localConversationBackfillInFlight.contains(localConversationId) else { return }
        localConversationBackfillInFlight.insert(localConversationId)
        defer {
            localConversationBackfillInFlight.remove(localConversationId)
        }

        guard let sourceMessages = localConversationMessages[localConversationId] else { return }
        let snapshotIdSet = Set(messageIDs)
        let unsyncedMessages = sourceMessages.filter { message in
            snapshotIdSet.contains(message.id)
            && message.remoteId == nil
            && !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !unsyncedMessages.isEmpty else { return }

        do {
            let remoteConversation = try await runWithTimeout(seconds: conversationCreateTimeout) {
                try await SupabaseManager.shared.createConversation(title: preferredTitle)
            }

            let remoteIdsByLocalId = try await backfillMessagesToRemote(
                remoteConversationId: remoteConversation.id,
                unsyncedMessages: unsyncedMessages
            )

            if let index = conversations.firstIndex(where: { $0.id == localConversationId }) {
                conversations[index] = remoteConversation
            } else {
                conversations.insert(remoteConversation, at: 0)
            }
            if currentConversationId == localConversationId {
                currentConversationId = remoteConversation.id
            }

            localConversationMessages.removeValue(forKey: localConversationId)

            for index in messages.indices {
                if let remoteId = remoteIdsByLocalId[messages[index].id] {
                    messages[index].remoteId = remoteId
                }
            }

            print("[MaxChat] ✅ 本地会话回填成功: \(localConversationId) -> \(remoteConversation.id), messages=\(remoteIdsByLocalId.count)")
        } catch {
            print("[MaxChat] ⚠️ 本地会话回填失败: \(error.localizedDescription)")
        }
    }

    private func persistMessageWithRetry(
        conversationId: String,
        role: String,
        content: String
    ) async -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for attempt in 1...messagePersistMaxRetries {
            do {
                let saved = try await SupabaseManager.shared.appendMessage(
                    conversationId: conversationId,
                    role: role,
                    content: trimmed
                )
                return saved.id
            } catch {
                if attempt >= messagePersistMaxRetries {
                    print("[MaxChat] persist failed role=\(role) attempt=\(attempt) error=\(error.localizedDescription)")
                    return nil
                }
                let delay = messagePersistRetryBaseDelayNanos * UInt64(attempt)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
        return nil
    }

    private func backfillMessagesToRemote(
        remoteConversationId: String,
        unsyncedMessages: [ChatMessage]
    ) async throws -> [UUID: String] {
        let batchPayload: [(role: String, content: String)] = unsyncedMessages.map { message in
            (role: message.role == .user ? "user" : "assistant", content: message.content)
        }

        if let batchSaved = try? await SupabaseManager.shared.appendMessagesBatch(
            conversationId: remoteConversationId,
            messages: batchPayload
        ), batchSaved.count == unsyncedMessages.count {
            var idsByLocalId: [UUID: String] = [:]
            for (local, remote) in zip(unsyncedMessages, batchSaved) {
                idsByLocalId[local.id] = remote.id
            }
            return idsByLocalId
        }

        var idsByLocalId: [UUID: String] = [:]
        for message in unsyncedMessages {
            let role = message.role == .user ? "user" : "assistant"
            let saved = try await SupabaseManager.shared.appendMessage(
                conversationId: remoteConversationId,
                role: role,
                content: message.content
            )
            idsByLocalId[message.id] = saved.id
        }
        return idsByLocalId
    }

    private func requestMaxResponseWithTimeout(messages: [ChatRequestMessage]) async throws -> String {
        let timeoutSeconds = modelMode == .think ? cloudResponseTimeoutThinkSeconds : cloudResponseTimeoutFastSeconds
        let selectedMode = modelMode == .think ? "think" : "fast"

        return try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await SupabaseManager.shared.chatWithMax(
                    messages: messages,
                    mode: selectedMode
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw MaxChatTimeoutError.cloudTimeout
            }

            guard let first = try await group.next() else {
                throw MaxChatTimeoutError.cloudTimeout
            }
            group.cancelAll()
            return first
        }
    }

    private func runWithTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let clamped = max(1, seconds)
        let timeoutNanos = UInt64(clamped * 1_000_000_000)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw URLError(.timedOut)
            }
            guard let first = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return first
        }
    }

    private func isLikelyNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case URLError.Code.secureConnectionFailed.rawValue,
             URLError.Code.networkConnectionLost.rawValue,
             URLError.Code.notConnectedToInternet.rawValue,
             URLError.Code.cannotConnectToHost.rawValue,
             URLError.Code.cannotFindHost.rawValue,
             URLError.Code.timedOut.rawValue,
             URLError.Code.dnsLookupFailed.rawValue:
            return true
        default:
            return false
        }
    }

    private func isQuotaLikeFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("insufficient_user_quota")
            || normalized.contains("quota")
            || normalized.contains("credit")
            || normalized.contains("balance")
            || message.contains("额度不足")
            || message.contains("余额不足")
    }

    private func isAuthLikeFailure(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return message.contains("无效的令牌")
            || message.contains("未提供令牌")
            || normalized.contains("auth error")
            || normalized.contains("unauthorized")
            || normalized.contains("invalid_api_key")
            || normalized.contains("authentication failed")
            || message.contains("401")
    }

    private func localModeReasonSummary(from fallbackReason: String) -> String {
        let normalized = fallbackReason
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !normalized.isEmpty else {
            return t("在线服务暂不可用", "Online service is temporarily unavailable")
        }

        let lowercased = normalized.lowercased()
        if isQuotaLikeFailure(normalized) {
            return t("在线服务暂时繁忙，已改用本地模式", "Online service is busy, using local mode")
        }

        if isAuthLikeFailure(normalized) {
            return t("云端鉴权失败，已改用本地模式", "Cloud authentication failed, using local mode")
        }

        if normalized.contains("超时") || lowercased.contains("timeout") {
            return t("云端响应超时，已改用本地模式", "Cloud timed out, using local mode")
        }

        if normalized.contains("离线")
            || normalized.contains("网络")
            || lowercased.contains("offline")
            || lowercased.contains("network") {
            return t("网络连接异常，已改用本地模式", "Network issue detected, using local mode")
        }

        return t("云端暂不可用，已改用本地模式", "Cloud is unavailable, using local mode")
    }

    private func buildLocalScientificSoothingResponse(for userInput: String, fallbackReason: String) -> String {
        let input = userInput.lowercased()
        let isEn = currentLanguage == .en
        let mechanism: String
        let action: String
        let conclusion: String
        let followUp: String

        if input.contains("睡") || input.contains("失眠") {
            mechanism = isEn
                ? "Short sleep amplifies threat sensitivity, so ordinary stress can feel more dangerous."
                : "睡眠不足会放大大脑的威胁探测，让同样压力更容易被感知为危险。"
            action = isEn
                ? "Set a fixed bedtime tonight, reduce screen stimulation 60 minutes before bed, and do 3 minutes of slow breathing."
                : "今晚固定入睡时间，睡前 60 分钟降低屏幕刺激，并做 3 分钟慢呼吸。"
            conclusion = isEn
                ? "You are not underperforming; your system is overloaded and needs stabilization first."
                : "你并不是做得不够，而是当前神经系统负荷偏高，先稳住更关键。"
            followUp = isEn
                ? "Tomorrow morning, how restored do you feel on a 0-10 scale?"
                : "明早你的恢复感是几分（0-10）？"
        } else if input.contains("心慌") || input.contains("紧张") || input.contains("焦") {
            mechanism = isEn
                ? "This looks like high arousal. Lowering physiological activation first is more effective than cognitive processing first."
                : "你现在更像处在高唤醒状态，先把生理唤醒降下来，再做认知整理会更有效。"
            action = isEn
                ? "Do 2 rounds of inhale-4s/exhale-6s, then walk for 5-8 minutes."
                : "先做 2 轮吸4秒-呼6秒呼吸，再走动 5-8 分钟。"
            conclusion = isEn
                ? "The priority now is to regain body-level control before solving everything."
                : "当前优先级是先恢复身体层面的可控感，再处理问题本身。"
            followUp = isEn
                ? "After the action, how much did your tension drop (0-10)?"
                : "动作后你的紧张度下降了几分（0-10）？"
        } else {
            mechanism = isEn
                ? "Anxiety often comes from high arousal plus uncertainty; small actions quickly rebuild controllability."
                : "焦虑通常来自高唤醒与不确定感叠加，小步行动能快速重建可控感。"
            action = isEn
                ? "Choose one action you can finish within 10 minutes, then rate your body sensation (0-10)."
                : "选一个 10 分钟内能完成的小动作，完成后打一个体感分（0-10）。"
            conclusion = isEn
                ? "Stability before intensity is the right sequence for your state."
                : "对你当前状态来说，先稳住再加码是正确顺序。"
            followUp = isEn
                ? "What is one measurable change after this action?"
                : "执行后你能观察到哪一个可量化变化？"
        }

        let styleSelector = abs(userInput.hashValue) % 2
        if isEn {
            if styleSelector == 0 {
                return """
\(conclusion)

\(mechanism)

Start here: \(action)
When you finish, tell me: \(followUp)

(Local mode: \(fallbackReason))
"""
            }
            return """
\(conclusion) \(mechanism)

For today, do this: \(action)
Then reply with: \(followUp)

(Local mode reason: \(fallbackReason))
"""
        }

        if styleSelector == 0 {
            return """
\(conclusion)

\(mechanism)

先做这一步：\(action)
做完后告诉我：\(followUp)

（当前为本地模式：\(fallbackReason)）
"""
        }
        return """
\(conclusion) \(mechanism)

今天先做：\(action)
然后回复我：\(followUp)

（当前为本地模式：\(fallbackReason)）
"""
    }
    
    func savePlan(_ plan: PlanOption) {
        Task {
            do {
                try await SupabaseManager.shared.savePlan(plan)
                await refreshAgentSurface()
                print("✅ 计划保存成功: \(plan.displayTitle)")
            } catch {
                print("❌ 保存计划失败: \(error)")
            }
        }
    }
    
    // MARK: - 辅助方法
    
    /// 从消息内容生成对话标题
    private func deriveTitle(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 20 {
            return trimmed
        }
        return String(trimmed.prefix(20)) + "..."
    }
    
    // MARK: - 个性化上下文
    
    private func buildSystemPrompt(userContext: String?) -> String {
        var prompt = maxSystemPrompt
        if let userContext, !userContext.isEmpty {
            prompt += "\n\n以下是用户已录入信息，仅用于定制回答（不要编造或虚构）：\n\(userContext)"
        } else {
            prompt += "\n\n如果缺少用户数据，请直接说明缺少，不要编造。"
        }
        return prompt
    }
    
    private func loadUserContextSummary(forceRefresh: Bool = false) async -> String? {
        if !forceRefresh,
           let cached = cachedUserContext,
           let cachedAt = cachedUserContextAt,
           Date().timeIntervalSince(cachedAt) < userContextCacheTTL {
            return cached
        }
        
        let profile = try? await SupabaseManager.shared.getProfileSettings()
        let dashboard = try? await SupabaseManager.shared.getDashboardData()
        
        var lines: [String] = []
        
        if let name = profile?.full_name, !name.isEmpty {
            lines.append("姓名: \(name)")
        }
        if let language = profile?.preferred_language, !language.isEmpty {
            lines.append("偏好语言: \(language)")
        }
        if let goal = profile?.primary_goal, !goal.isEmpty {
            lines.append("主要目标: \(goal)")
        }
        if let focus = profile?.current_focus, !focus.isEmpty {
            lines.append("当前关注: \(focus)")
        }
        if let personality = profile?.ai_personality, !personality.isEmpty {
            lines.append("沟通风格偏好: \(personality)")
        }
        if let persona = profile?.ai_persona_context, !persona.isEmpty {
            lines.append("人设补充: \(persona)")
        }
        if let settings = profile?.ai_settings {
            var settingParts: [String] = []
            if let honesty = settings.honesty_level { settingParts.append("坦诚度=\(honesty)") }
            if let humor = settings.humor_level { settingParts.append("幽默度=\(humor)") }
            if let mode = settings.mode, !mode.isEmpty { settingParts.append("模式=\(mode)") }
            if !settingParts.isEmpty {
                lines.append("AI偏好设置: \(settingParts.joined(separator: ", "))")
            }
        }
        if let scores = profile?.inferred_scale_scores, !scores.isEmpty {
            let gad7 = scores["gad7"]
            let phq9 = scores["phq9"]
            let isi = scores["isi"]
            let pss10 = scores["pss10"]
            var parts: [String] = []
            if let gad7 { parts.append("GAD7=\(gad7)") }
            if let phq9 { parts.append("PHQ9=\(phq9)") }
            if let isi { parts.append("ISI=\(isi)") }
            if let pss10 { parts.append("PSS10=\(pss10)") }
            if !parts.isEmpty {
                lines.append("量表分数: \(parts.joined(separator: ", "))")
            }
        }
        
        if let dashboard {
            let logs = dashboard.weeklyLogs
            if !logs.isEmpty {
                let avgSleep = average(logs.map { $0.sleep_duration_minutes }).map { String(format: "%.1f", $0 / 60.0) }
                let avgStress = average(logs.map { $0.stress_level }).map { String(format: "%.1f", $0) }
                let avgEnergy = average(logs.map { $0.energy_level }).map { String(format: "%.1f", $0) }
                let avgAnxiety = average(logs.map { $0.anxiety_level }).map { String(format: "%.1f", $0) }
                let avgExercise = average(logs.map { $0.exercise_duration_minutes }).map { String(format: "%.0f", $0) }
                let avgMindfulness = average(logs.map { $0.mindfulness_minutes }).map { String(format: "%.0f", $0) }
                var summaryParts: [String] = []
                if let avgSleep { summaryParts.append("平均睡眠=\(avgSleep)小时") }
                if let avgStress { summaryParts.append("平均压力=\(avgStress)") }
                if let avgAnxiety { summaryParts.append("平均焦虑=\(avgAnxiety)") }
                if let avgEnergy { summaryParts.append("平均精力=\(avgEnergy)") }
                if let avgExercise { summaryParts.append("平均运动=\(avgExercise)分钟") }
                if let avgMindfulness { summaryParts.append("平均冥想=\(avgMindfulness)分钟") }
                if !summaryParts.isEmpty {
                    lines.append("最近7天: \(summaryParts.joined(separator: ", "))")
                }
            }
            
            if let unified = dashboard.profile {
                if let name = unified.full_name, !name.isEmpty {
                    lines.append("画像姓名: \(name)")
                }
                if let demographics = unified.demographics {
                    var demoParts: [String] = []
                    if let age = demographics.age { demoParts.append("年龄=\(age)") }
                    if let gender = demographics.gender, !gender.isEmpty { demoParts.append("性别=\(gender)") }
                    if let bmi = demographics.bmi { demoParts.append("BMI=\(String(format: "%.1f", bmi))") }
                    if !demoParts.isEmpty {
                        lines.append("人口统计: \(demoParts.joined(separator: ", "))")
                    }
                }
                if let goals = unified.health_goals, !goals.isEmpty {
                    let goalTexts = goals.map { $0.goal_text }.filter { !$0.isEmpty }
                    if !goalTexts.isEmpty {
                        lines.append("反焦虑目标: \(goalTexts.joined(separator: "、"))")
                    }
                }
                if let concerns = unified.health_concerns, !concerns.isEmpty {
                    lines.append("焦虑关注点: \(concerns.joined(separator: "、"))")
                }
                if let lifestyle = unified.lifestyle_factors {
                    var lifestyleParts: [String] = []
                    if let exercise = lifestyle.exercise_frequency, !exercise.isEmpty { lifestyleParts.append("运动频率=\(exercise)") }
                    if let sleepPattern = lifestyle.sleep_pattern, !sleepPattern.isEmpty { lifestyleParts.append("睡眠习惯=\(sleepPattern)") }
                    if let sleepHours = lifestyle.sleep_hours { lifestyleParts.append("睡眠时长=\(String(format: "%.1f", sleepHours))小时") }
                    if let stress = lifestyle.stress_level, !stress.isEmpty { lifestyleParts.append("压力水平=\(stress)") }
                    if let diet = lifestyle.diet_preference, !diet.isEmpty { lifestyleParts.append("饮食偏好=\(diet)") }
                    if !lifestyleParts.isEmpty {
                        lines.append("生活方式: \(lifestyleParts.joined(separator: ", "))")
                    }
                }
                if let trend = unified.recent_mood_trend, !trend.isEmpty {
                    lines.append("最近情绪趋势: \(trend)")
                }
                if let traits = unified.ai_inferred_traits, !traits.isEmpty {
                    let traitPairs = traits.map { "\($0.key)=\($0.value)" }.sorted()
                    lines.append("AI推断特质: \(traitPairs.joined(separator: ", "))")
                }
            }
            
            if let hardware = dashboard.hardwareData {
                var hardwareParts: [String] = []
                if let hrv = hardware.hrv?.value { hardwareParts.append("HRV=\(String(format: "%.0f", hrv))") }
                if let rhr = hardware.resting_heart_rate?.value { hardwareParts.append("静息心率=\(String(format: "%.0f", rhr))") }
                if let sleepScore = hardware.sleep_score?.value { hardwareParts.append("睡眠评分=\(String(format: "%.0f", sleepScore))") }
                if let spo2 = hardware.spo2?.value { hardwareParts.append("血氧=\(String(format: "%.0f", spo2))") }
                if let steps = hardware.steps?.value { hardwareParts.append("步数=\(String(format: "%.0f", steps))") }
                if !hardwareParts.isEmpty {
                    lines.append("穿戴设备: \(hardwareParts.joined(separator: ", "))")
                }
            }
        }
        
        let context = lines.joined(separator: "\n")
        if !context.isEmpty {
            cachedUserContext = context
            cachedUserContextAt = Date()
            return context
        }
        
        return nil
    }
    
    private func average(_ values: [Int?]) -> Double? {
        let nums = values.compactMap { $0 }
        guard !nums.isEmpty else { return nil }
        return Double(nums.reduce(0, +)) / Double(nums.count)
    }

}
