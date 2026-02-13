// MaxChatViewModel.swift
// Max 对话视图模型 - 支持消息持久化、多对话管理、P1/P2 功能

import SwiftUI
import Foundation
import Network

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
    @Published var modelMode: ModelMode = .fast
    @Published var starterQuestions: [String] = []
    
    // 🆕 P2 功能 - 离线状态
    @Published var isOffline = false
    private var networkMonitor: NWPathMonitor?
    
    // 🆕 停止生成 - 任务引用
    private var currentGenerationTask: Task<Void, Never>? = nil
    private var generationId: Int = 0
    
    // 🆕 个性化上下文缓存
    private var cachedUserContext: String? = nil
    private var cachedUserContextAt: Date? = nil

    private enum MaxChatTimeoutError: LocalizedError {
        case cloudTimeout

        var errorDescription: String? {
            "云端响应超时"
        }
    }
    
    // MARK: - Init
    
    init() {
        setupNetworkMonitor()
        Task {
            await loadConversations()
            await loadStarterQuestions()
        }
    }
    
    deinit {
        networkMonitor?.cancel()
    }

    private let maxSystemPrompt = """
    你是 Max，一个高效、直接、简洁的反焦虑闭环助手。
    - 中文回答，避免冗长铺垫
    - 输出结构化科学抚慰（理解/机制/证据/动作/跟进）
    - 不要编造数据；不确定就说不确定
    """
    
    private let userContextCacheTTL: TimeInterval = 300
    private let remotePersistenceTimeout: TimeInterval = 2.5
    
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
            starterQuestions = [
                "帮我判断今天最需要先处理的焦虑触发点",
                "基于我最近睡眠和压力，先给我一个低阻力动作",
                "请用证据解释我最近紧张反复的原因",
                "我已经完成一个动作了，下一步该怎么跟进？"
            ]
        } else {
            starterQuestions = questions
        }
        print("✅ 加载了 \(starterQuestions.count) 个起始问题")
    }
    
    // MARK: - 🆕 模型模式切换
    
    func toggleModelMode() {
        modelMode = modelMode == .fast ? .think : .fast
        print("🔄 切换模型模式: \(modelMode.displayName)")
    }
    
    // MARK: - 🆕 停止生成
    
    func stopGeneration() {
        generationId += 1  // 使当前任务失效
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        isTyping = false
        
        // 更新最后一条 AI 消息
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant && $0.content.isEmpty }) {
            messages[lastIndex].content = "（已取消）"
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
            self.error = "加载对话失败: \(error.localizedDescription)"
            print("❌ 加载对话列表失败: \(error)")
        }
        isLoading = false
    }
    
    /// 切换到指定对话
    func switchConversation(_ conversationId: String) async {
        currentConversationId = conversationId
        isLoading = true
        
        do {
            let history = try await SupabaseManager.shared.getChatHistory(conversationId: conversationId)
            messages = history.map { $0.toLocal() }
            print("✅ 加载了 \(messages.count) 条历史消息")
        } catch {
            print("❌ 加载对话历史失败: \(error)")
            messages = []
            self.error = "加载对话失败: \(error.localizedDescription)"
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
                print("❌ 创建对话失败: \(error)")
                self.error = "创建对话失败: \(error.localizedDescription)"
            }
        }
    }
    
    /// 删除对话
    func deleteConversation(_ conversationId: String) async -> Bool {
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
            self.error = "删除失败"
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
                        content: buildLocalScientificSoothingResponse(for: text, fallbackReason: "网络离线")
                    ))
                    self.error = "网络离线，已切换本地抚慰模式"
                    return
                }

                // 1. 如果没有对话，先创建一个（短超时，失败则本地兜底）
                var conversationId = currentConversationId
                let conversationTitle = deriveTitle(from: text)
                var shouldPersistRemotely = true
                if conversationId == nil {
                    do {
                        let conversation = try await runWithTimeout(seconds: remotePersistenceTimeout) {
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
                        print("[MaxChat] ⚠️ 远端会话创建失败，切换本地会话：\(error.localizedDescription)")
                    }
                }
                guard let convId = conversationId else {
                    throw SupabaseError.requestFailed
                }
                if convId.hasPrefix("local-") {
                    shouldPersistRemotely = false
                }

                guard generationId == currentGenId else { return }

                // 2. 异步保存用户消息（不阻塞主回复）
                if shouldPersistRemotely {
                    let userMessageId = tempUserMessage.id
                    let userContent = text
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            let savedUserMsg = try await self.runWithTimeout(seconds: self.remotePersistenceTimeout) {
                                try await SupabaseManager.shared.appendMessage(
                                    conversationId: convId,
                                    role: "user",
                                    content: userContent
                                )
                            }
                            if let index = self.messages.firstIndex(where: { $0.id == userMessageId }) {
                                self.messages[index].remoteId = savedUserMsg.id
                            }
                        } catch {
                            print("[MaxChat] ⚠️ 用户消息写入失败，继续请求回复：\(error.localizedDescription)")
                        }
                    }
                }

                guard generationId == currentGenId else { return }

                // 3. 通过 SupabaseManager 统一调用 Max（含记忆/问询/科学上下文）
                let requestMessages = messages.map { message in
                    ChatRequestMessage(
                        role: message.role == .user ? "user" : "assistant",
                        content: message.content
                    )
                }
                let responseText = try await requestMaxResponseWithTimeout(messages: requestMessages)

                guard generationId == currentGenId else { return }

                // 4. 先展示 AI 回复，再异步持久化
                isTyping = false
                let localAssistantMessage = ChatMessage(
                    role: .assistant,
                    content: responseText
                )
                messages.append(localAssistantMessage)

                if shouldPersistRemotely {
                    let assistantMessageId = localAssistantMessage.id
                    let assistantContent = responseText
                    Task { [weak self] in
                        guard let self else { return }
                        do {
                            let savedAssistantMsg = try await self.runWithTimeout(seconds: self.remotePersistenceTimeout) {
                                try await SupabaseManager.shared.appendMessage(
                                    conversationId: convId,
                                    role: "assistant",
                                    content: assistantContent
                                )
                            }
                            if let index = self.messages.firstIndex(where: { $0.id == assistantMessageId }) {
                                self.messages[index].remoteId = savedAssistantMsg.id
                            }
                        } catch {
                            print("[MaxChat] ⚠️ AI 回复写入失败，仅本地展示：\(error.localizedDescription)")
                        }
                    }
                }
            } catch {
                guard generationId == currentGenId else { return }

                isTyping = false
                let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let fallback = buildLocalScientificSoothingResponse(for: text, fallbackReason: description)
                messages.append(ChatMessage(role: .assistant, content: fallback))

                if error is MaxChatTimeoutError {
                    self.error = "云端响应超时，已切换本地抚慰模式（可稍后重试）"
                } else if isLikelyNetworkError(error) {
                    self.error = "网络连接异常，已切换本地抚慰模式"
                } else {
                    self.error = "已使用本地模式回复，云端原因：\(description)"
                }
                print("❌ MaxChat Error: \(error)")
            }
        }
    }

    private func requestMaxResponseWithTimeout(messages: [ChatRequestMessage]) async throws -> String {
        let timeoutSeconds: UInt64 = modelMode == .think ? 18 : 12
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

    private func buildLocalScientificSoothingResponse(for userInput: String, fallbackReason: String) -> String {
        let input = userInput.lowercased()
        let mechanism: String
        let action: String

        if input.contains("睡") || input.contains("失眠") {
            mechanism = "睡眠不足会放大大脑的威胁探测，让同样压力更容易被感知为危险。"
            action = "今晚固定入睡时间，睡前 60 分钟降低屏幕刺激，并做 3 分钟慢呼吸。"
        } else if input.contains("心慌") || input.contains("紧张") || input.contains("焦") {
            mechanism = "你现在更像处在高唤醒状态，先把生理唤醒降下来，再做认知整理会更有效。"
            action = "先做 2 轮吸4秒-呼6秒呼吸，再走动 5-8 分钟。"
        } else {
            mechanism = "焦虑通常来自高唤醒与不确定感叠加，小步行动能快速重建可控感。"
            action = "选一个 10 分钟内能完成的小动作，完成后打一个体感分（0-10）。"
        }

        return """
理解结论：你并不是做得不够，而是当前神经系统负荷偏高，先稳住是正确顺序。
机制解释：\(mechanism)
证据来源：行为激活与呼吸调节的通用心理生理证据；当前处于本地模式（\(fallbackReason)）。
可执行动作：\(action)
跟进问题：做完后你的紧张程度从几分降到几分（0-10）？
"""
    }
    
    func savePlan(_ plan: PlanOption) {
        Task {
            do {
                try await SupabaseManager.shared.savePlan(plan)
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
