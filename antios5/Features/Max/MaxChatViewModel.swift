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
    private var localConversationBackfillInFlight: Set<String> = []
    private var localConversationMessages: [String: [ChatMessage]] = [:]

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
            if !LaunchOverrides.boolFlag("UI_TEST_BYPASS_GATEKEEPING") {
                await loadConversations()
            } else {
                conversations = []
                error = nil
            }
            await loadStarterQuestions()
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
                    "Explain with evidence why my tension keeps recurring",
                    "I completed one action already, what is the next step?"
                ]
            } else {
                starterQuestions = [
                    "帮我判断今天最需要先处理的焦虑触发点",
                    "基于我最近睡眠和压力，先给我一个低阻力动作",
                    "请用证据解释我最近紧张反复的原因",
                    "我已经完成一个动作了，下一步该怎么跟进？"
                ]
            }
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
                        content: buildLocalScientificSoothingResponse(
                            for: text,
                            fallbackReason: t("网络离线", "offline network")
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
                if convId.hasPrefix("local-") {
                    localConversationMessages[convId] = messages
                }

                if shouldPersistRemotely {
                    let assistantMessageId = localAssistantMessage.id
                    let assistantContent = responseText
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
            } catch {
                guard generationId == currentGenId else { return }

                isTyping = false
                let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                let fallback = buildLocalScientificSoothingResponse(for: text, fallbackReason: description)
                messages.append(ChatMessage(role: .assistant, content: fallback))
                if let currentConversationId, currentConversationId.hasPrefix("local-") {
                    localConversationMessages[currentConversationId] = messages
                }

                if error is MaxChatTimeoutError {
                    self.error = t(
                        "云端响应超时，已切换本地抚慰模式（可稍后重试）",
                        "Cloud response timed out. Switched to local soothing mode (retry later)."
                    )
                } else if isLikelyNetworkError(error) {
                    self.error = t(
                        "网络连接异常，已切换本地抚慰模式",
                        "Network connection issue. Switched to local soothing mode."
                    )
                } else {
                    self.error = t(
                        "已使用本地模式回复，云端原因：\(description)",
                        "Responded in local mode. Cloud reason: \(description)"
                    )
                }
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
Conclusion: \(conclusion)
Why this helps: \(mechanism)
Evidence note: general psychophysiology evidence on behavioral activation and breath regulation; local mode due to \(fallbackReason).
Next step: \(action)
Follow-up: \(followUp)
"""
            }
            return """
\(conclusion)
\(mechanism)
Action for today: \(action)
Check-in question: \(followUp)
(Local mode reason: \(fallbackReason))
"""
        }

        if styleSelector == 0 {
            return """
理解结论：\(conclusion)
机制解释：\(mechanism)
证据说明：基于行为激活与呼吸调节的通用心理生理证据；当前处于本地模式（\(fallbackReason)）。
今日动作：\(action)
跟进问题：\(followUp)
"""
        }
        return """
\(conclusion)
\(mechanism)
先执行这一步：\(action)
执行后复盘：\(followUp)
（当前为本地模式：\(fallbackReason)）
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
