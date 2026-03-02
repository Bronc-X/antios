// AIManager.swift
// AI 服务管理器 - 连接 AICanAPI (OpenAI Compatible)

import Foundation

enum AIModel: String {
    // Current benchmark winners (quality + stability)
    case claude35Sonnet = "claude-3-5-sonnet-20241022"
    case claude37Sonnet = "claude-3-7-sonnet-20250219"
    case kimiK25 = "kimi-k2.5"
    case claudeSonnet45 = "claude-sonnet-4-5-20250929"
    case claudeOpus4 = "claude-opus-4-20250514"
    case claudeOpus45 = "claude-opus-4-5-20251101"
    case claudeOpus46 = "claude-opus-4-6"
    case claudeHaiku45 = "claude-haiku-4-5-20251001"
    case qwen3Coder480B = "qwen3-coder-480b-a35b-instruct"
    case qwenMaxLatest = "qwen-max-latest"
    case deepseekV32 = "deepseek-v3.2"
    case gpt41 = "gpt-4.1"
    case gpt5ChatLatest = "gpt-5-chat-latest"

    // Legacy compatibility models
    case deepseekV3Exp = "deepseek-v3.2-exp"
    case deepseekV3Thinking = "deepseek-v3.1-thinking"
    case geminiThinking = "gemini-3-pro-preview-thinking"
    case geminiStandard = "gemini-3-pro-preview"
}

@MainActor
final class AIManager: ObservableObject, AIManaging {
    static let shared = AIManager()
    private static let defaultModelFallbackChain: [String] = [
        AIModel.gpt5ChatLatest.rawValue,
        AIModel.deepseekV32.rawValue,
        AIModel.claudeSonnet45.rawValue
    ]

    private var prioritizedTop3Models: [String] {
        if let raw = runtimeString(for: "OPENAI_MODEL_FALLBACK_CHAIN") {
            var seen: Set<String> = []
            let parsed = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .filter { seen.insert($0).inserted }
            if !parsed.isEmpty {
                return parsed
            }
        }
        return Self.defaultModelFallbackChain
    }

    private var requestTimeout: TimeInterval {
        max(5, runtimeDouble(for: "OPENAI_REQUEST_TIMEOUT_SEC", fallback: 20))
    }

    private var embeddingCacheTTL: TimeInterval {
        max(300, runtimeDouble(for: "OPENAI_EMBEDDING_CACHE_TTL_SEC", fallback: 6 * 3600))
    }

    private var embeddingCacheMaxEntries: Int {
        max(64, runtimeInt(for: "OPENAI_EMBEDDING_CACHE_MAX_ENTRIES", fallback: 512))
    }

    private var embeddingEnabled: Bool {
        runtimeBool(for: "OPENAI_EMBEDDING_ENABLED", fallback: true)
    }

    private var embeddingRequestTimeout: TimeInterval {
        max(2, runtimeDouble(for: "OPENAI_EMBEDDING_TIMEOUT_SEC", fallback: 8))
    }

    private var embeddingNoChannelCooldown: TimeInterval {
        max(30, runtimeDouble(for: "OPENAI_EMBEDDING_NO_CHANNEL_COOLDOWN_SEC", fallback: 600))
    }

    private var embeddingCache: [String: (vector: [Double], timestamp: Date)] = [:]
    private var embeddingInFlight: [String: Task<[Double], Error>] = [:]
    private var embeddingCircuitUntil: Date?
    private var embeddingCircuitReason: String?
    private var didLogConfig = false
    
    private var apiKey: String {
        guard let key = runtimeString(for: "OPENAI_API_KEY") else {
            fatalError("Missing OPENAI_API_KEY in Info.plist. Please configure Secrets.xcconfig.")
        }
        return key
    }

    private var embeddingAPIKey: String {
        runtimeString(for: "OPENAI_EMBEDDING_API_KEY") ?? apiKey
    }
    
    private var baseURL: String {
        guard let url = runtimeString(for: "OPENAI_API_BASE") else {
            fatalError("Missing OPENAI_API_BASE in Info.plist. Please configure Secrets.xcconfig.")
        }
        return normalizeAPIBaseURL(url)
    }

    private var embeddingBaseURL: String? {
        guard let url = runtimeString(for: "OPENAI_EMBEDDING_API_BASE") else {
            return nil
        }
        return normalizeAPIBaseURL(url)
    }

    private var embeddingURL: String {
        if let url = runtimeString(for: "OPENAI_EMBEDDING_API_URL") {
            let cleaned = url.replacingOccurrences(of: "\\", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }
        if let embeddingBaseURL {
            return "\(embeddingBaseURL)/embeddings"
        }
        return "\(baseURL)/embeddings"
    }

    private var embeddingModel: String {
        if let model = runtimeString(for: "OPENAI_EMBEDDING_MODEL"),
           !model.isEmpty {
            return model
        }
        return "text-embedding-3-small"
    }

    private var defaultModel: String {
        if let model = runtimeString(for: "OPENAI_MODEL"),
           !model.isEmpty {
            return model
        }
        return AIModel.gpt5ChatLatest.rawValue
    }
    
    private init() {}

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

    private func runtimeBool(for key: String, fallback: Bool) -> Bool {
        guard let raw = runtimeString(for: key)?.lowercased() else {
            return fallback
        }
        switch raw {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return fallback
        }
    }

    private func normalizeAPIBaseURL(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "\\", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = cleaned
            .replacingOccurrences(of: "/chat/completions", with: "")
            .replacingOccurrences(of: "/embeddings", with: "")
        return normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
    }

    private struct AIHTTPError: Error {
        let statusCode: Int
        let payload: String
    }

    private func dataWithAbsoluteTimeout(
        for request: URLRequest,
        timeout: TimeInterval
    ) async throws -> (Data, URLResponse) {
        let clamped = max(1, timeout)
        let timeoutNanos = UInt64(clamped * 1_000_000_000)
        return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                try await NetworkSession.shared.data(for: request)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanos)
                throw URLError(.timedOut)
            }
            guard let result = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return result
        }
    }

    // Protocol conformance
    func chatCompletion(messages: [ChatMessage], model: AIModel) async throws -> String {
        return try await chatCompletion(
            messages: messages,
            systemPrompt: nil,
            model: model,
            temperature: 0.7
        )
    }

    func chatCompletion(
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        model: AIModel? = nil,
        temperature: Double = 0.7,
        timeout: TimeInterval? = nil
    ) async throws -> String {
        let resolvedTimeout = max(5, timeout ?? requestTimeout)
        let resolvedModel = model?.rawValue ?? defaultModel
        let candidateModels = buildModelFallbackChain(primary: resolvedModel)

        if !didLogConfig {
            print("✅ [AI] chat.completions base=\(baseURL) modelChain=\(candidateModels.joined(separator: " -> ")) timeout=\(Int(resolvedTimeout))s")
            didLogConfig = true
        } else {
            print("✅ [AI] chat.completions modelChain=\(candidateModels.joined(separator: " -> ")) timeout=\(Int(resolvedTimeout))s")
        }

        var lastError: Error?
        for (index, candidateModel) in candidateModels.enumerated() {
            do {
                return try await requestChatCompletion(
                    messages: messages,
                    systemPrompt: systemPrompt,
                    model: candidateModel,
                    temperature: temperature,
                    timeout: resolvedTimeout
                )
            } catch {
                lastError = error
                let canFallback = shouldFallback(after: error)
                if index < candidateModels.count - 1, canFallback {
                    print("⚠️ [AI] model=\(candidateModel) failed, fallback to next model.")
                    continue
                }
                throw error
            }
        }

        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }

    private func buildModelFallbackChain(primary: String) -> [String] {
        let normalizedPrimary = primary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedPrimary.isEmpty && !prioritizedTop3Models.contains(normalizedPrimary) {
            print("ℹ️ [AI] requested model=\(normalizedPrimary) is outside fixed Top3; using fixed chain.")
        }
        return prioritizedTop3Models
    }

    private func shouldFallback(after error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .badServerResponse:
                return true
            default:
                break
            }
        }

        if let httpError = error as? AIHTTPError {
            if [429, 500, 502, 503, 504].contains(httpError.statusCode) {
                return true
            }
            let payloadLower = httpError.payload.lowercased()
            if payloadLower.contains("model_not_found")
                || payloadLower.contains("no distributor")
                || payloadLower.contains("无可用渠道")
                || payloadLower.contains("未提供令牌") {
                return true
            }
        }

        return false
    }

    private func shouldOpenEmbeddingCircuit(statusCode: Int, payload: String) -> Bool {
        guard (400...599).contains(statusCode) else { return false }
        let payloadLower = payload.lowercased()
        return payloadLower.contains("no distributor")
            || payloadLower.contains("无可用渠道")
            || payloadLower.contains("model_not_found")
    }

    private func openEmbeddingCircuit(reason: String) {
        let until = Date().addingTimeInterval(embeddingNoChannelCooldown)
        embeddingCircuitUntil = until
        embeddingCircuitReason = reason
        let seconds = max(1, Int(until.timeIntervalSinceNow))
        print("[AI][Embedding] circuit opened for \(seconds)s: \(reason.prefix(160))")
    }

    private func requestChatCompletion(
        messages: [ChatMessage],
        systemPrompt: String?,
        model: String,
        temperature: Double,
        timeout: TimeInterval
    ) async throws -> String {
        let url = URL(string: "\(baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        
        // Convert internal ChatMessage to API format
        var apiMessages: [[String: String]] = []
        if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
            apiMessages.append(["role": "system", "content": systemPrompt])
        }
        apiMessages.append(contentsOf: messages.map { msg in
            ["role": msg.role == .user ? "user" : "assistant",
             "content": msg.content]
        })
        
        let body: [String: Any] = [
            "model": model,
            "messages": apiMessages,
            "temperature": temperature
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await dataWithAbsoluteTimeout(
            for: request,
            timeout: timeout + 1
        )
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let payload = String(data: data, encoding: .utf8) ?? "unknown error"
            if let errorStr = String(data: data, encoding: .utf8) {
                print("AI API Error: \(errorStr)")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw AIHTTPError(statusCode: status, payload: payload)
        }
        
        let result = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        return result.choices.first?.message.content ?? "思考中遇到了一些问题..."
    }

    func createEmbedding(for text: String) async throws -> [Double] {
        guard embeddingEnabled else {
            throw AIHTTPError(statusCode: 503, payload: "embedding disabled by OPENAI_EMBEDDING_ENABLED")
        }
        if let until = embeddingCircuitUntil, until > Date() {
            let seconds = max(1, Int(until.timeIntervalSinceNow))
            let reason = embeddingCircuitReason ?? "embedding circuit open"
            throw AIHTTPError(statusCode: 503, payload: "embedding circuit open (\(seconds)s left): \(reason)")
        }
        if embeddingCircuitUntil != nil {
            embeddingCircuitUntil = nil
            embeddingCircuitReason = nil
        }

        let cacheKey = embeddingCacheKey(for: text)
        if let cached = embeddingCache[cacheKey],
           Date().timeIntervalSince(cached.timestamp) < embeddingCacheTTL {
            return cached.vector
        }

        if let inFlight = embeddingInFlight[cacheKey] {
            return try await inFlight.value
        }

        let task = Task<[Double], Error> { [self] in
            let url = URL(string: embeddingURL)!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(embeddingAPIKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = embeddingRequestTimeout

            let body: [String: Any] = [
                "model": embeddingModel,
                "input": String(text.prefix(8000))
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await dataWithAbsoluteTimeout(
                for: request,
                timeout: embeddingRequestTimeout + 1
            )
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let payload = String(data: data, encoding: .utf8) ?? "unknown error"
                if shouldOpenEmbeddingCircuit(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1, payload: payload) {
                    openEmbeddingCircuit(reason: payload)
                }
                print("Embedding API Error: \(payload)")
                throw AIHTTPError(
                    statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1,
                    payload: payload
                )
            }

            if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataArray = parsed["data"] as? [[String: Any]],
               let first = dataArray.first,
               let embedding = first["embedding"] as? [Double] {
                return embedding
            }

            throw URLError(.cannotDecodeRawData)
        }

        embeddingInFlight[cacheKey] = task
        defer {
            embeddingInFlight.removeValue(forKey: cacheKey)
        }

        let embedding = try await task.value
        embeddingCache[cacheKey] = (embedding, Date())
        pruneEmbeddingCacheIfNeeded()
        return embedding
    }

    private func pruneEmbeddingCacheIfNeeded() {
        if embeddingCache.count <= embeddingCacheMaxEntries {
            return
        }
        let sortedByAge = embeddingCache.sorted { $0.value.timestamp < $1.value.timestamp }
        let removeCount = max(0, embeddingCache.count - embeddingCacheMaxEntries)
        guard removeCount > 0 else { return }
        for (key, _) in sortedByAge.prefix(removeCount) {
            embeddingCache.removeValue(forKey: key)
        }
    }

    private func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    private func embeddingCacheKey(for text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.count <= 200 {
            return normalized
        }
        let prefix = normalized.prefix(120)
        let suffix = normalized.suffix(60)
        let hashHex = String(fnv1a64(normalized), radix: 16)
        return "\(prefix)|\(suffix)|\(hashHex)"
    }
}

// MARK: - API Models
struct OpenAIChatResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: APIMessage
    }
    
    struct APIMessage: Codable {
        let content: String
    }
}
