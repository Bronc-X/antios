import Foundation

extension SupabaseManager {
    // MARK: - Max Service

    func chatWithMax(messages: [ChatRequestMessage], mode: String = "fast") async throws -> String {
        let startedAt = Date()
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let chatMode = MaxChatMode(rawValue: mode) ?? .fast
        let sanitizedMessages = messages.compactMap { message -> ChatRequestMessage? in
            let content = contentForMaxInference(from: message.content)
            guard !content.isEmpty else { return nil }
            return ChatRequestMessage(role: message.role, content: content)
        }
        let localMessages = trimMessagesForInference(sanitizedMessages.map { message in
            ChatMessage(
                role: message.role == "user" ? .user : .assistant,
                content: message.content
            )
        })

        let appLanguage = AppLanguage.fromStored(UserDefaults.standard.string(forKey: "app_language")).apiCode
        let language = (appLanguage == "en" || appLanguage == "zh")
            ? appLanguage
            : "zh"
        let lastUserMessage = localMessages.last { $0.role == .user }

        if let lastUserMessage, shouldRefuseNonHealthRequest(lastUserMessage.content) {
            return refusalMessage(language: language)
        }

        let degradedLocalFallback: Bool
        do {
            let remoteText = try await chatWithMaxRemote(
                messages: sanitizedMessages,
                mode: chatMode.rawValue,
                userId: user.id,
                language: language
            )
            let cleanedRemote = stripReasoningContent(remoteText)
            if shouldRejectRemoteResponse(
                cleanedRemote,
                language: language,
                lastUserMessage: lastUserMessage?.content,
                localMessages: localMessages
            ) {
                registerMaxChatRemoteFailure(reason: "quality gate: template/language mismatch")
                throw makeRequestFailure(
                    context: "chatWithMaxRemote quality gate",
                    fallbackReason: language == "en"
                        ? "Cloud output quality gate triggered; switched to adaptive local path."
                        : "云端输出触发质量闸门，已切换自适应本地路径。"
                )
            }
            persistChatMemoriesAsync(userId: user.id, lastUserMessage: lastUserMessage, assistantReply: cleanedRemote)
            let elapsed = Date().timeIntervalSince(startedAt)
            await MaxTelemetry.recordLatency(
                metric: "max_chat_round_ms_\(chatMode.rawValue)_remote",
                milliseconds: elapsed * 1000
            )
            await MaxTelemetry.recordAck(metric: "max_chat_round_success_remote", ack: true)
            print("[MaxPerf] mode=\(chatMode.rawValue) path=remote elapsed=\(String(format: "%.2f", elapsed))s messages=\(localMessages.count)")
            return cleanedRemote
        } catch {
            degradedLocalFallback = shouldUseDegradedLocalFallback(for: error)
            let remoteElapsed = Date().timeIntervalSince(startedAt)
            await MaxTelemetry.recordLatency(
                metric: "max_chat_round_ms_\(chatMode.rawValue)_remote_failed",
                milliseconds: remoteElapsed * 1000
            )
            await MaxTelemetry.recordAck(metric: "max_chat_round_success_remote", ack: false)
            print("[MaxChatRemote] fallback mode=\(degradedLocalFallback ? "degraded" : "standard") reason=\(networkErrorSummary(error))")
        }

        let effectiveMode: MaxChatMode = degradedLocalFallback ? .fast : chatMode
        let conversationState = MaxConversationStateTracker.extractState(from: localMessages)
        let inquirySummary: String? = (!degradedLocalFallback && effectiveMode == .think)
            ? await getInquiryContextSummaryCached(userId: user.id, language: language)
            : nil

        let eagerRAGTask: Task<MaxRAGContext, Never>? = lastUserMessage.map { message in
            Task { [self] in
                await buildRAGContextCached(
                    userId: user.id,
                    query: message.content,
                    language: language,
                    mode: effectiveMode
                )
            }
        }
        async let profileTask = getProfileSettingsCached(userId: user.id)
        let profile = await profileTask

        var ragContext = MaxRAGContext(memoryBlock: nil, playbookBlock: nil)
        var contextBlock: String? = nil

        if let lastUserMessage {
            async let contextTask: String? = degradedLocalFallback ? nil : buildScientificContextBlock(
                query: lastUserMessage.content,
                state: conversationState,
                healthFocus: profile?.current_focus ?? profile?.primary_goal,
                mode: effectiveMode,
                language: language
            )
            if let eagerRAGTask {
                ragContext = await eagerRAGTask.value
            } else {
                ragContext = await buildRAGContextCached(
                    userId: user.id,
                    query: lastUserMessage.content,
                    language: language,
                    mode: effectiveMode
                )
            }
            contextBlock = await contextTask
        } else if let healthFocus = profile?.current_focus ?? profile?.primary_goal {
            let decision = MaxContextOptimizer.optimize(
                state: conversationState,
                healthFocus: healthFocus,
                scientificPapers: [],
                language: language
            )
            contextBlock = MaxContextOptimizer.buildContextBlock(decision: decision, language: language)
        }

        let userContext = await buildUserContextSummaryCached(
            profile: profile,
            userId: user.id,
            mode: chatMode,
            language: language
        )

        var combinedContext: [String] = []
        if let userContext, !userContext.isEmpty {
            combinedContext.append("[USER CONTEXT]\n\(userContext)")
        }
        if let proactiveBrief = getCachedProactiveBrief(userId: user.id, language: language) {
            combinedContext.append(
                """
                [PROACTIVE CARE CONTEXT]
                - title: \(proactiveBrief.title)
                - understanding: \(proactiveBrief.understanding)
                - mechanism: \(proactiveBrief.mechanism)
                - action: \(proactiveBrief.microAction)
                - follow_up: \(proactiveBrief.followUpQuestion)
                """
            )
        }
        if let contextBlock, !contextBlock.isEmpty {
            combinedContext.append(contextBlock)
        }
        let finalContextBlock = combinedContext.isEmpty ? nil : combinedContext.joined(separator: "\n")

        let prompt = MaxPromptBuilder.build(input: MaxPromptInput(
            conversationState: conversationState,
            aiSettings: profile?.ai_settings,
            aiPersonaContext: profile?.ai_persona_context,
            personality: profile?.ai_personality,
            healthFocus: profile?.current_focus ?? profile?.primary_goal,
            inquirySummary: inquirySummary,
            memoryContext: ragContext.memoryBlock,
            playbookContext: ragContext.playbookBlock,
            contextBlock: finalContextBlock,
            language: language
        ))

        let modelChain = maxLocalModelChain(for: effectiveMode)
        let localTimeout: TimeInterval
        if degradedLocalFallback {
            localTimeout = maxChatLocalDegradedTimeout
        } else {
            localTimeout = (effectiveMode == .think) ? maxChatLocalThinkTimeout : maxChatLocalFastTimeout
        }
        do {
            let response = try await AIManager.shared.chatCompletion(
                messages: localMessages,
                systemPrompt: prompt,
                modelChain: modelChain,
                temperature: 0.7,
                timeout: localTimeout
            )
            let cleaned = stripReasoningContent(response)
            persistChatMemoriesAsync(userId: user.id, lastUserMessage: lastUserMessage, assistantReply: cleaned)

            let elapsed = Date().timeIntervalSince(startedAt)
            let path = degradedLocalFallback ? "local-degraded" : "local"
            await MaxTelemetry.recordLatency(
                metric: "max_chat_round_ms_\(effectiveMode.rawValue)_\(path)",
                milliseconds: elapsed * 1000
            )
            await MaxTelemetry.recordAck(metric: "max_chat_round_success_local", ack: true)
            print("[MaxPerf] mode=\(effectiveMode.rawValue) path=\(path) elapsed=\(String(format: "%.2f", elapsed))s messages=\(localMessages.count)")
            return cleaned
        } catch {
            let elapsed = Date().timeIntervalSince(startedAt)
            let path = degradedLocalFallback ? "local-degraded" : "local"
            await MaxTelemetry.recordLatency(
                metric: "max_chat_round_ms_\(effectiveMode.rawValue)_\(path)_failed",
                milliseconds: elapsed * 1000
            )
            await MaxTelemetry.recordAck(metric: "max_chat_round_success_local", ack: false)
            throw error
        }
    }

    private func shouldUseDegradedLocalFallback(for error: Error) -> Bool {
        if isRetriableNetworkError(error) || isHardTLSFailure(error) {
            return true
        }
        if let requestFailure = error as? SupabaseRequestFailure {
            if requestFailure.retryable {
                return true
            }
            if let statusCode = requestFailure.statusCode {
                return statusCode == 408 || statusCode == 409 || statusCode == 425 || statusCode == 429 || statusCode >= 500
            }
        }
        if let supabaseError = error as? SupabaseError {
            switch supabaseError {
            case .appApiCircuitOpen, .appApiRequiresRemote, .requestFailed:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func maxLocalModelChain(for mode: MaxChatMode) -> [AIModel] {
        switch mode {
        case .fast:
            return uniqueMaxLocalModels([
                resolvedMaxLocalModel(
                    runtimeKey: "MAX_CHAT_FAST_PRIMARY_MODEL",
                    fallback: .gpt51ChatLatest
                ),
                resolvedMaxLocalModel(
                    runtimeKey: "MAX_CHAT_FAST_BACKUP_MODEL",
                    fallback: .gpt5ChatLatest
                )
            ])
        case .think:
            return uniqueMaxLocalModels([
                resolvedMaxLocalModel(
                    runtimeKey: "MAX_CHAT_THINK_PRIMARY_MODEL",
                    fallback: .gpt52ChatLatest
                ),
                resolvedMaxLocalModel(
                    runtimeKey: "MAX_CHAT_THINK_BACKUP_MODEL",
                    fallback: .gpt51ChatLatest
                )
            ])
        }
    }

    private func resolvedMaxLocalModel(runtimeKey: String, fallback: AIModel) -> AIModel {
        guard let raw = runtimeString(for: runtimeKey),
              let model = AIModel(rawValue: raw) else {
            return fallback
        }
        return model
    }

    private func uniqueMaxLocalModels(_ models: [AIModel]) -> [AIModel] {
        var seen: Set<String> = []
        return models.filter { seen.insert($0.rawValue).inserted }
    }

    private func persistChatMemoriesAsync(
        userId: String,
        lastUserMessage: ChatMessage?,
        assistantReply: String
    ) {
        if let lastUserMessage {
            let userContent = lastUserMessage.content
            Task(priority: .utility) {
                _ = await MaxMemoryService.storeConversationTurn(
                    userId: userId,
                    userContent: userContent,
                    assistantReply: assistantReply,
                    metadata: [
                        "source": "max_chat",
                        MaxMemoryKind.metadataKey: MaxMemoryKind.chatTurn.rawValue
                    ]
                )
            }
        } else {
            Task(priority: .utility) {
                _ = await MaxMemoryService.storeCategorizedMemory(
                    userId: userId,
                    content: assistantReply,
                    role: "assistant",
                    kind: .chatTurn,
                    metadata: ["source": "max_chat"]
                )
            }
        }
    }

    private struct RemoteMaxChatPayload: Encodable {
        let messages: [ChatRequestMessage]
        let mode: String
        let language: String
        let userId: String
        let source: String

        enum CodingKeys: String, CodingKey {
            case messages
            case mode
            case language
            case userId = "userId"
            case source
        }
    }

    private struct RemoteMaxChatLegacyPayload: Encodable {
        let message: String
        let mode: String
        let language: String
    }

    private func chatWithMaxRemote(
        messages: [ChatRequestMessage],
        mode: String,
        userId: String,
        language: String
    ) async throws -> String {
        if let until = Self.maxChatRemoteCooldownUntil, until > Date() {
            throw SupabaseError.appApiCircuitOpen
        }

        let base = try await resolveMaxAgentBaseURL()
        guard let url = buildAppAPIURL(baseURL: base, path: AppAPIConfig.maxChatPath) else {
            registerMaxChatRemoteFailure(reason: "invalid URL path")
            throw makeRequestFailure(
                context: "chatWithMaxRemote invalid URL",
                fallbackReason: "Max 云端地址无效"
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachSupabaseCookies(to: &request)
        request.timeoutInterval = (mode == MaxChatMode.think.rawValue) ? maxChatRemoteThinkTimeout : maxChatRemoteFastTimeout
        request.httpBody = try JSONEncoder().encode(
            RemoteMaxChatPayload(
                messages: messages,
                mode: mode,
                language: language,
                userId: userId,
                source: "ios"
            )
        )

        do {
            let (data, httpResponse) = try await performAppAPIRequest(request)
            if (200...299).contains(httpResponse.statusCode),
               let text = extractRemoteChatText(from: data) {
                resetMaxChatRemoteFailureState()
                return text
            }

            if httpResponse.statusCode == 404 || httpResponse.statusCode == 405 || httpResponse.statusCode == 422 {
                if let legacyText = try await chatWithMaxRemoteLegacy(
                    baseURL: base,
                    mode: mode,
                    language: language,
                    lastMessage: messages.last?.content ?? ""
                ) {
                    resetMaxChatRemoteFailureState()
                    return legacyText
                }
            }

            registerMaxChatRemoteFailure(reason: "status \(httpResponse.statusCode)")
            throw makeRequestFailure(
                context: "chatWithMaxRemote status failure",
                request: request,
                response: httpResponse,
                data: data
            )
        } catch {
            registerMaxChatRemoteFailure(reason: networkErrorSummary(error))
            throw error
        }
    }

    private func chatWithMaxRemoteLegacy(
        baseURL: URL,
        mode: String,
        language: String,
        lastMessage: String
    ) async throws -> String? {
        guard !lastMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        guard let url = buildAppAPIURL(baseURL: baseURL, path: AppAPIConfig.maxChatPath) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachSupabaseCookies(to: &request)
        request.timeoutInterval = maxChatRemoteLegacyTimeout
        request.httpBody = try JSONEncoder().encode(
            RemoteMaxChatLegacyPayload(
                message: lastMessage,
                mode: mode,
                language: language
            )
        )

        let (data, httpResponse) = try await performAppAPIRequest(request)
        guard (200...299).contains(httpResponse.statusCode) else { return nil }
        return extractRemoteChatText(from: data)
    }

    private func extractRemoteChatText(from data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           !text.hasPrefix("{"),
           !text.hasPrefix("[") {
            return text
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let candidates = ["response", "content", "message", "reply", "text", "answer"]
            for key in candidates {
                if let value = object[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }
        return nil
    }

    private func registerMaxChatRemoteFailure(reason: String) {
        Self.maxChatRemoteFailureCount += 1
        print("[MaxChatRemote] failed: \(reason)")
        if Self.maxChatRemoteFailureCount >= maxChatRemoteFailureThreshold {
            Self.maxChatRemoteCooldownUntil = Date().addingTimeInterval(maxChatRemoteCooldownTTL)
            print("[MaxChatRemote] cooldown \(Int(maxChatRemoteCooldownTTL))s")
        }
    }

    private func resetMaxChatRemoteFailureState() {
        Self.maxChatRemoteFailureCount = 0
        Self.maxChatRemoteCooldownUntil = nil
    }

    private func trimMessagesForInference(_ messages: [ChatMessage], maxCount: Int = 10) -> [ChatMessage] {
        let trimmed = messages.count > maxCount ? Array(messages.suffix(maxCount)) : messages
        return trimmed.map { message in
            let normalizedContent = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = normalizedContent.count > 800 ? String(normalizedContent.prefix(800)) : normalizedContent
            return ChatMessage(role: message.role, content: content)
        }
    }

    private func normalizedContextCacheKey(userId: String, language: String, query: String) -> String {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(normalized.prefix(220))
        return "\(userId)|\(language)|\(prefix)"
    }

    private func getInquiryContextSummaryCached(userId: String, language: String) async -> String? {
        let cacheKey = "\(userId)|\(language)"
        if let cached = Self.inquirySummaryCache[cacheKey], cached.expiresAt > Date() {
            return cached.text
        }

        let summary = try? await getInquiryContextSummary(language: language)
        if let summary, !summary.isEmpty {
            Self.inquirySummaryCache[cacheKey] = TimedTextCache(
                text: summary,
                expiresAt: Date().addingTimeInterval(inquirySummaryCacheTTL)
            )
        }
        return summary
    }

    private func buildRAGContextCached(
        userId: String,
        query: String,
        language: String,
        mode: MaxChatMode
    ) async -> MaxRAGContext {
        let normalizedKey = normalizedContextCacheKey(userId: userId, language: language, query: query)
        let cacheKey = "\(mode.rawValue)|\(normalizedKey)"
        if let cached = Self.ragContextCache[cacheKey], cached.expiresAt > Date() {
            return cached.context
        }

        if let inFlight = Self.ragContextInFlight[cacheKey] {
            return await inFlight.value
        }

        let task = Task<MaxRAGContext, Never> {
            await MaxRAGService.buildContext(
                userId: userId,
                query: query,
                language: language,
                depth: mode.ragDepth
            )
        }
        Self.ragContextInFlight[cacheKey] = task
        defer {
            Self.ragContextInFlight.removeValue(forKey: cacheKey)
        }

        let context = await task.value
        Self.ragContextCache[cacheKey] = TimedRAGCache(
            context: context,
            expiresAt: Date().addingTimeInterval(ragCacheTTL)
        )
        return context
    }

    private func buildScientificContextBlock(
        query: String,
        state: MaxConversationState,
        healthFocus: String?,
        mode: MaxChatMode,
        language: String
    ) async -> String? {
        let cacheKey = "\(mode.rawValue)|\(normalizedContextCacheKey(userId: "global", language: language, query: query))"
        if let cached = Self.scientificBlockCache[cacheKey], cached.expiresAt > Date() {
            return cached.block
        }

        let papers: [ScientificPaperLite]
        if mode == .think {
            let searchResult = await ScientificSearchService.searchScientificTruth(query: query)
            papers = searchResult.papers.map { ScientificPaperLite(title: $0.title, year: $0.year) }
        } else {
            papers = []
        }

        let decision = MaxContextOptimizer.optimize(
            state: state,
            healthFocus: healthFocus,
            scientificPapers: papers,
            language: language
        )
        let block = MaxContextOptimizer.buildContextBlock(decision: decision, language: language)
        Self.scientificBlockCache[cacheKey] = TimedScientificBlockCache(
            block: block,
            expiresAt: Date().addingTimeInterval(scientificBlockCacheTTL)
        )
        return block
    }

    private func buildUserContextSummaryCached(
        profile: ProfileSettings?,
        userId: String,
        mode: MaxChatMode,
        language: String
    ) async -> String? {
        let cacheKey = "\(userId)|\(mode.rawValue)|\(language)"
        if let cached = Self.userContextCache[cacheKey], cached.expiresAt > Date() {
            return cached.text
        }

        let summary: String?
        if mode == .fast {
            summary = buildUserContextSummary(profile: profile, dashboard: nil, language: language)
        } else {
            let dashboard = await getDashboardDataCached(userId: userId)
            summary = buildUserContextSummary(profile: profile, dashboard: dashboard, language: language)
        }

        if let summary, !summary.isEmpty {
            Self.userContextCache[cacheKey] = TimedTextCache(
                text: summary,
                expiresAt: Date().addingTimeInterval(userContextCacheTTL)
            )
        }
        return summary
    }

    private func getProfileSettingsCached(userId: String) async -> ProfileSettings? {
        if let cached = Self.profileCache[userId], cached.expiresAt > Date() {
            return cached.profile
        }

        guard let profile = try? await getProfileSettings() else { return nil }
        Self.profileCache[userId] = TimedProfileCache(
            profile: profile,
            expiresAt: Date().addingTimeInterval(profileCacheTTL)
        )
        return profile
    }

    private func getDashboardDataCached(userId: String) async -> DashboardData? {
        if let cached = Self.dashboardCache[userId], cached.expiresAt > Date() {
            return cached.data
        }
        let dashboard = try? await getDashboardData()
        if let dashboard {
            Self.dashboardCache[userId] = TimedDashboardCache(
                data: dashboard,
                expiresAt: Date().addingTimeInterval(dashboardCacheTTL)
            )
        }
        return dashboard
    }

    private func getCachedProactiveBrief(userId: String, language: String) -> ProactiveCareBrief? {
        let lang = language == "en" ? "en" : "zh"
        let dayKey = recommendationDateString(Date())
        let cacheKey = "\(userId)|\(lang)|\(dayKey)"
        guard let cached = Self.proactiveBriefCache[cacheKey], cached.expiresAt > Date() else {
            return nil
        }
        return cached.brief
    }

    private func shouldRejectRemoteResponse(
        _ text: String,
        language: String,
        lastUserMessage: String?,
        localMessages: [ChatMessage]
    ) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        if language == "en" && cjkCharacterRatio(in: trimmed) > 0.10 {
            return true
        }
        if language == "zh" && cjkCharacterRatio(in: trimmed) < 0.01 && englishWordCount(in: trimmed) > 80 {
            return true
        }

        let looksRigidTemplate = containsRigidFiveSectionTemplate(trimmed)
        guard looksRigidTemplate else { return false }

        let repeated = isNearDuplicateOfLastAssistantMessage(trimmed, localMessages: localMessages)
        let lowPersonalization = lacksUserAnchors(response: trimmed, lastUserMessage: lastUserMessage)
        return repeated || lowPersonalization
    }

    private func containsRigidFiveSectionTemplate(_ text: String) -> Bool {
        let sectionMarkers = [
            "理解结论", "机制解释", "证据来源", "可执行动作", "跟进问题",
            "understanding conclusion", "mechanism explanation", "evidence sources", "executable actions", "follow-up question"
        ]
        let lowered = text.lowercased()
        let matchedSections = sectionMarkers.reduce(0) { partial, marker in
            partial + (lowered.contains(marker.lowercased()) ? 1 : 0)
        }
        let numberedMatches: Int = {
            guard let regex = try? NSRegularExpression(pattern: "(?m)^\\s*[1-5][\\.|\\)]\\s+") else { return 0 }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.numberOfMatches(in: text, options: [], range: range)
        }()
        return matchedSections >= 4 && numberedMatches >= 4
    }

    private func cjkCharacterRatio(in text: String) -> Double {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return 0 }
        let cjkCount = scalars.filter { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }.count
        return Double(cjkCount) / Double(scalars.count)
    }

    private func englishWordCount(in text: String) -> Int {
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }
        return words.filter { $0.count >= 2 }.count
    }

    private func isNearDuplicateOfLastAssistantMessage(
        _ response: String,
        localMessages: [ChatMessage]
    ) -> Bool {
        guard let lastAssistant = localMessages.reversed().first(where: { $0.role == .assistant }) else {
            return false
        }
        let currentTokens = normalizedSimilarityTokens(from: response)
        let previousTokens = normalizedSimilarityTokens(from: lastAssistant.content)
        guard !currentTokens.isEmpty, !previousTokens.isEmpty else { return false }

        let union = currentTokens.union(previousTokens)
        guard !union.isEmpty else { return false }
        let intersection = currentTokens.intersection(previousTokens)
        let jaccard = Double(intersection.count) / Double(union.count)
        return jaccard >= 0.78
    }

    private func normalizedSimilarityTokens(from text: String) -> Set<String> {
        let lowered = text.lowercased()
        let separators = CharacterSet.alphanumerics.inverted.union(.whitespacesAndNewlines)
        let baseTokens = lowered
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }
        var unique: Set<String> = []
        for token in baseTokens {
            unique.insert(token)
            if unique.count >= 120 {
                break
            }
        }
        return unique
    }

    private func lacksUserAnchors(response: String, lastUserMessage: String?) -> Bool {
        guard let lastUserMessage else { return true }
        let userTokens = anchorTokens(from: lastUserMessage)
        guard !userTokens.isEmpty else { return true }
        let loweredResponse = response.lowercased()
        let matched = userTokens.contains { loweredResponse.contains($0.lowercased()) }
        return !matched
    }

    private func anchorTokens(from text: String) -> [String] {
        let stopwords: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "have", "what", "why", "how",
            "good", "ok", "yes", "no", "really", "just", "about", "your", "you", "today"
        ]
        let lowered = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return [] }

        var tokens: [String] = lowered
            .components(separatedBy: CharacterSet.alphanumerics.inverted.union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 && !stopwords.contains($0) }

        let cjkScalars = lowered.unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
                return true
            default:
                return false
            }
        }
        if cjkScalars.count >= 2 {
            let cjkText = String(String.UnicodeScalarView(cjkScalars))
            let chars = Array(cjkText)
            if chars.count >= 2 {
                for index in 0..<(chars.count - 1) {
                    let token = String(chars[index...index + 1])
                    if token.trimmingCharacters(in: .whitespacesAndNewlines).count == 2 {
                        tokens.append(token)
                    }
                    if tokens.count >= 20 {
                        break
                    }
                }
            }
        }

        var unique: [String] = []
        var seen = Set<String>()
        for token in tokens {
            if seen.insert(token).inserted {
                unique.append(token)
            }
            if unique.count >= 16 {
                break
            }
        }
        return unique
    }

    private func shouldRefuseNonHealthRequest(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let politicsTokens = [
            "特朗普", "拜登", "哈里斯", "共和党", "民主党", "选举", "大选", "投票", "竞选",
            "摇摆州", "总统", "议会", "参议院", "众议院", "民调",
            "trump", "biden", "harris", "election", "vote", "campaign", "poll", "swing state"
        ]
        let gamblingTokens = [
            "博彩", "赔率", "下注", "赌", "盘口", "赌场",
            "bet", "odds", "sportsbook", "casino", "wager"
        ]
        let containsPolitics = politicsTokens.contains { lowered.contains($0.lowercased()) }
        let containsGambling = gamblingTokens.contains { lowered.contains($0.lowercased()) }
        return containsPolitics || containsGambling
    }

    private func refusalMessage(language: String) -> String {
        if language == "en" {
            return "I can’t help with election predictions or betting odds. If you want anti-anxiety support, I can help with calibration, evidence, and actions."
        }
        return "我不能提供政治选举预测或博彩赔率等内容。如果你需要反焦虑支持，我可以帮你做校准、机制解释和行动跟进。"
    }

    private func buildMemoryContext(_ records: [MaxMemoryRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let lines = records.prefix(6).map { record -> String in
            if let date = formatter.date(from: record.created_at) {
                let dateString = ISO8601DateFormatter().string(from: date)
                return "[\(dateString)] \(record.role): \(record.content_text)"
            }
            return "[\(record.created_at)] \(record.role): \(record.content_text)"
        }
        return lines.joined(separator: "\n")
    }

    private func stripReasoningContent(_ text: String) -> String {
        var cleaned = text
        if let regex = try? NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>", options: [.caseInsensitive]) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }
        if cleaned.contains("reasoning_content") {
            let lines = cleaned.split(separator: "\n").filter { !$0.contains("reasoning_content") }
            cleaned = lines.joined(separator: "\n")
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildUserContextSummary(
        profile: ProfileSettings?,
        dashboard: DashboardData?,
        language: String
    ) -> String? {
        let isEn = language == "en"
        var lines: [String] = []

        if let profile {
            if let name = profile.full_name, !name.isEmpty {
                lines.append(isEn ? "name: \(name)" : "姓名: \(name)")
            }
            if let preferredLanguage = profile.preferred_language, !preferredLanguage.isEmpty {
                lines.append(isEn ? "preferred language: \(preferredLanguage)" : "偏好语言: \(preferredLanguage)")
            }
            if let goal = profile.primary_goal, !goal.isEmpty {
                lines.append(isEn ? "primary goal: \(goal)" : "主要目标: \(goal)")
            }
            if let focus = profile.current_focus, !focus.isEmpty {
                lines.append(isEn ? "current focus: \(focus)" : "当前关注: \(focus)")
            }
            if let personality = profile.ai_personality, !personality.isEmpty {
                lines.append(isEn ? "communication style: \(personality)" : "沟通风格: \(personality)")
            }
            if let scores = profile.inferred_scale_scores, !scores.isEmpty {
                let gad7 = scores["gad7"].map { "GAD7=\($0)" }
                let phq9 = scores["phq9"].map { "PHQ9=\($0)" }
                let isi = scores["isi"].map { "ISI=\($0)" }
                let pss10 = scores["pss10"].map { "PSS10=\($0)" }
                let parts = [gad7, phq9, isi, pss10].compactMap { $0 }
                if !parts.isEmpty {
                    lines.append(isEn ? "scale scores: \(parts.joined(separator: ", "))" : "量表分数: \(parts.joined(separator: ", "))")
                }
            }
        }

        if let dashboard {
            let logs = dashboard.weeklyLogs
            if !logs.isEmpty {
                let avgSleep = average(logs.map { $0.sleep_duration_minutes }).map { String(format: "%.1f", $0 / 60.0) }
                let avgStress = average(logs.map { $0.stress_level }).map { String(format: "%.1f", $0) }
                let avgEnergy = average(logs.map { $0.energy_level }).map { String(format: "%.1f", $0) }
                let avgAnxiety = average(logs.map { $0.anxiety_level }).map { String(format: "%.1f", $0) }
                var summaryParts: [String] = []
                if let avgSleep { summaryParts.append(isEn ? "avg sleep=\(avgSleep)h" : "平均睡眠=\(avgSleep)小时") }
                if let avgStress { summaryParts.append(isEn ? "avg stress=\(avgStress)" : "平均压力=\(avgStress)") }
                if let avgAnxiety { summaryParts.append(isEn ? "avg anxiety=\(avgAnxiety)" : "平均焦虑=\(avgAnxiety)") }
                if let avgEnergy { summaryParts.append(isEn ? "avg energy=\(avgEnergy)" : "平均精力=\(avgEnergy)") }
                if !summaryParts.isEmpty {
                    lines.append(isEn ? "last 7 days: \(summaryParts.joined(separator: ", "))" : "最近7天: \(summaryParts.joined(separator: ", "))")
                }
            }

            if let hardware = dashboard.hardwareData {
                var hardwareParts: [String] = []
                if let hrv = hardware.hrv?.value { hardwareParts.append("HRV=\(String(format: "%.0f", hrv))") }
                if let rhr = hardware.resting_heart_rate?.value {
                    hardwareParts.append(isEn ? "restingHR=\(String(format: "%.0f", rhr))" : "静息心率=\(String(format: "%.0f", rhr))")
                }
                if let sleepScore = hardware.sleep_score?.value {
                    hardwareParts.append(isEn ? "sleepScore=\(String(format: "%.0f", sleepScore))" : "睡眠评分=\(String(format: "%.0f", sleepScore))")
                }
                if let steps = hardware.steps?.value {
                    hardwareParts.append(isEn ? "steps=\(String(format: "%.0f", steps))" : "步数=\(String(format: "%.0f", steps))")
                }
                if !hardwareParts.isEmpty {
                    lines.append(isEn ? "wearable: \(hardwareParts.joined(separator: ", "))" : "穿戴设备: \(hardwareParts.joined(separator: ", "))")
                }
            }
        }

        let context = lines.joined(separator: "\n")
        return context.isEmpty ? nil : context
    }

    private func average(_ values: [Int?]) -> Double? {
        let nums = values.compactMap { $0 }
        guard !nums.isEmpty else { return nil }
        return Double(nums.reduce(0, +)) / Double(nums.count)
    }
}
