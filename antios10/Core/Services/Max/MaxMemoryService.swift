import Foundation

enum MaxMemoryKind: String, Codable, CaseIterable {
    case sensorDerived = "sensor_derived"
    case behaviorSignal = "behavior_signal"
    case chatTurn = "chat_turn"
    case assistantStrategy = "assistant_strategy"
    case proactiveBrief = "proactive_brief"
    case generic = "generic"

    static let metadataKey = "memory_kind"

    var storagePrefix: String {
        switch self {
        case .sensorDerived:
            return "[body_memory] "
        case .behaviorSignal:
            return "[behavior_memory] "
        case .chatTurn:
            return "[chat_memory] "
        case .assistantStrategy:
            return "[assistant_strategy] "
        case .proactiveBrief:
            return "[proactive_brief] "
        case .generic:
            return ""
        }
    }

    var forcesAssistantEmbedding: Bool {
        switch self {
        case .assistantStrategy, .proactiveBrief:
            return true
        default:
            return false
        }
    }

    func decorate(_ content: String) -> String {
        guard !storagePrefix.isEmpty else { return content }
        if content.hasPrefix(storagePrefix) {
            return content
        }
        return storagePrefix + content
    }

    func strip(from content: String) -> String {
        guard !storagePrefix.isEmpty, content.hasPrefix(storagePrefix) else {
            return content
        }
        return String(content.dropFirst(storagePrefix.count))
    }

    func ragTag(for role: String) -> String {
        switch self {
        case .sensorDerived:
            return "body"
        case .behaviorSignal:
            return "signal"
        case .assistantStrategy, .proactiveBrief:
            return "assistant"
        case .chatTurn, .generic:
            return role == "assistant" ? "assistant" : "user"
        }
    }

    static func detect(from content: String) -> MaxMemoryKind {
        for kind in Self.allCases where !kind.storagePrefix.isEmpty {
            if content.hasPrefix(kind.storagePrefix) {
                return kind
            }
        }
        return .generic
    }
}

struct MaxMemoryRecord: Codable {
    let content_text: String
    let role: String
    let created_at: String
    let similarity: Double?

    var kind: MaxMemoryKind {
        MaxMemoryKind.detect(from: content_text)
    }

    var renderedContent: String {
        kind.strip(from: content_text)
    }
}

enum MaxMemoryService {
    private struct MemoryPayload: Codable {
        let user_id: String
        let content_text: String
        let role: String
        let embedding: [Double]?
        let metadata: [String: AnyCodable]?
    }

    private struct RPCPayload: Encodable {
        let query_embedding: [Double]
        let match_threshold: Double
        let match_count: Int
        let p_user_id: String
    }

    private struct ConversationMemoryRow: Decodable {
        let content: String
        let role: String
        let created_at: String?
    }

    private struct PendingMemoryItem: Codable {
        let id: String
        let payload: MemoryPayload
        let enqueuedAtEpochSec: TimeInterval
    }

    private actor PendingMemoryQueue {
        private let storeURL: URL
        private var loaded = false
        private var items: [PendingMemoryItem] = []
        private var isFlushing = false

        init(storeURL: URL) {
            self.storeURL = storeURL
        }

        func append(_ payloads: [MemoryPayload], maxItems: Int) -> Int {
            guard !payloads.isEmpty else { return count() }
            loadIfNeeded()
            let now = Date().timeIntervalSince1970
            for payload in payloads {
                items.append(PendingMemoryItem(
                    id: UUID().uuidString,
                    payload: payload,
                    enqueuedAtEpochSec: now
                ))
            }
            if items.count > maxItems {
                items.removeFirst(items.count - maxItems)
            }
            persist()
            return items.count
        }

        func peek(limit: Int) -> [PendingMemoryItem] {
            loadIfNeeded()
            let resolvedLimit = max(1, limit)
            guard !items.isEmpty else { return [] }
            return Array(items.prefix(resolvedLimit))
        }

        func remove(ids: Set<String>) -> Int {
            guard !ids.isEmpty else { return count() }
            loadIfNeeded()
            items.removeAll { ids.contains($0.id) }
            persist()
            return items.count
        }

        func count() -> Int {
            loadIfNeeded()
            return items.count
        }

        func beginFlush() -> Bool {
            loadIfNeeded()
            if isFlushing {
                return false
            }
            isFlushing = true
            return true
        }

        func endFlush() {
            isFlushing = false
        }

        private func loadIfNeeded() {
            guard !loaded else { return }
            loaded = true
            guard let data = try? Data(contentsOf: storeURL), !data.isEmpty else {
                items = []
                return
            }
            if let decoded = try? JSONDecoder().decode([PendingMemoryItem].self, from: data) {
                items = decoded
            } else {
                items = []
            }
        }

        private func persist() {
            let directory = storeURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                let data = try JSONEncoder().encode(items)
                try data.write(to: storeURL, options: [.atomic])
            } catch {
                print("[MaxMemory] pending queue persist failed: \(error)")
            }
        }
    }

    private static let pendingQueue = PendingMemoryQueue(storeURL: pendingQueueStorageURL)

    @discardableResult
    static func storeCategorizedMemory(
        userId: String,
        content: String,
        role: String,
        kind: MaxMemoryKind,
        metadata: [String: Any]? = nil
    ) async -> Bool {
        var mergedMetadata = metadata ?? [:]
        mergedMetadata[MaxMemoryKind.metadataKey] = kind.rawValue
        return await storeMemory(
            userId: userId,
            content: content,
            role: role,
            metadata: mergedMetadata
        )
    }

    @discardableResult
    static func storeSensorDerivedMemory(
        userId: String,
        content: String,
        metadata: [String: Any]? = nil
    ) async -> Bool {
        await storeCategorizedMemory(
            userId: userId,
            content: content,
            role: "user",
            kind: .sensorDerived,
            metadata: metadata
        )
    }

    static func retrieveMemories(
        userId: String,
        query: String,
        embedding: [Double]? = nil,
        limit: Int = 8,
        shouldGenerateEmbeddingWhenMissing: Bool = true
    ) async -> [MaxMemoryRecord] {
        schedulePendingFlush()
        guard !query.isEmpty else { return [] }
        let startedAt = Date()
        let resolvedLimit = max(1, limit)
        let resolvedEmbedding: [Double]
        if let embedding {
            resolvedEmbedding = embedding
        } else if shouldGenerateEmbeddingWhenMissing {
            resolvedEmbedding = await createEmbeddingForRetrieval(query)
        } else {
            resolvedEmbedding = []
        }
        if resolvedEmbedding.isEmpty {
            await MaxTelemetry.recordAck(metric: "max_memory_vector_ready_ack", ack: false)
            guard allowLexicalFallback else {
                return await finalizeRetrieval(records: [], startedAt: startedAt)
            }
            let fallback = await lexicalFallbackMemories(
                userId: userId,
                query: query,
                limit: resolvedLimit
            )
            return await finalizeRetrieval(records: fallback, startedAt: startedAt)
        }
        await MaxTelemetry.recordAck(metric: "max_memory_vector_ready_ack", ack: true)
        let payload = RPCPayload(
            query_embedding: resolvedEmbedding,
            match_threshold: memoryMatchThreshold,
            match_count: resolvedLimit,
            p_user_id: userId
        )
        var semanticRecords: [MaxMemoryRecord] = (try? await SupabaseManager.shared.request("rpc/match_ai_memories", method: "POST", body: payload)) ?? []
        if semanticRecords.count < max(2, resolvedLimit / 2),
           memoryRelaxedMatchThreshold < memoryMatchThreshold {
            let relaxedPayload = RPCPayload(
                query_embedding: resolvedEmbedding,
                match_threshold: memoryRelaxedMatchThreshold,
                match_count: resolvedLimit,
                p_user_id: userId
            )
            let relaxedRecords: [MaxMemoryRecord] = (try? await SupabaseManager.shared.request("rpc/match_ai_memories", method: "POST", body: relaxedPayload)) ?? []
            semanticRecords = mergeMemories(
                primary: semanticRecords,
                secondary: relaxedRecords,
                limit: resolvedLimit
            )
        }
        if semanticRecords.count >= resolvedLimit {
            return await finalizeRetrieval(
                records: Array(semanticRecords.prefix(resolvedLimit)),
                startedAt: startedAt
            )
        }
        guard allowLexicalFallback else {
            return await finalizeRetrieval(
                records: Array(semanticRecords.prefix(resolvedLimit)),
                startedAt: startedAt
            )
        }

        let lexicalRecords = await lexicalFallbackMemories(
            userId: userId,
            query: query,
            limit: resolvedLimit
        )
        let merged = mergeMemories(
            primary: semanticRecords,
            secondary: lexicalRecords,
            limit: resolvedLimit
        )
        return await finalizeRetrieval(records: merged, startedAt: startedAt)
    }

    static func retrieveRecentMemories(userId: String, limit: Int = 6) async -> [MaxMemoryRecord] {
        schedulePendingFlush()
        return (try? await retrieveRecentMemoriesFromStore(userId: userId, limit: limit)) ?? []
    }

    static func triggerPendingFlush() {
        schedulePendingFlush()
    }

    @discardableResult
    static func storeMemory(userId: String, content: String, role: String, metadata: [String: Any]? = nil) async -> Bool {
        let startedAt = Date()
        guard let payload = await buildPayload(
            userId: userId,
            content: content,
            role: role,
            metadata: metadata
        ) else {
            return false
        }
        let stored = await insertMemoryWithRetry(payload)
        let buffered = (!stored) ? await enqueuePendingPayloads([payload]) : false
        let accepted = stored || buffered
        await MaxTelemetry.recordAck(metric: "max_memory_write_ack_\(role)", ack: stored)
        if !stored {
            await MaxTelemetry.recordAck(metric: "max_memory_write_buffered_\(role)", ack: buffered)
        }
        await MaxTelemetry.recordLatency(
            metric: "max_memory_write_ms_\(role)",
            milliseconds: Date().timeIntervalSince(startedAt) * 1000
        )
        if accepted {
            schedulePendingFlush()
        }
        return accepted
    }

    @discardableResult
    static func storeConversationTurn(
        userId: String,
        userContent: String?,
        assistantReply: String?,
        metadata: [String: Any]? = nil
    ) async -> (userStored: Bool, assistantStored: Bool) {
        let startedAt = Date()
        async let userPayloadTask = buildPayload(
            userId: userId,
            content: userContent ?? "",
            role: "user",
            metadata: metadata
        )
        async let assistantPayloadTask = buildPayload(
            userId: userId,
            content: assistantReply ?? "",
            role: "assistant",
            metadata: metadata
        )

        let userPayload = await userPayloadTask
        let assistantPayload = await assistantPayloadTask
        var payloads: [MemoryPayload] = []
        if let userPayload {
            payloads.append(userPayload)
        }
        if let assistantPayload {
            payloads.append(assistantPayload)
        }
        guard !payloads.isEmpty else {
            return (false, false)
        }

        if payloads.count > 1, await insertMemoriesBatchWithRetry(payloads) {
            if userPayload != nil {
                await MaxTelemetry.recordAck(metric: "max_memory_write_ack_user", ack: true)
            }
            if assistantPayload != nil {
                await MaxTelemetry.recordAck(metric: "max_memory_write_ack_assistant", ack: true)
            }
            await MaxTelemetry.recordLatency(
                metric: "max_memory_write_ms_turn",
                milliseconds: Date().timeIntervalSince(startedAt) * 1000
            )
            schedulePendingFlush()
            return (userPayload != nil, assistantPayload != nil)
        }

        var userStored = false
        var assistantStored = false
        var userBuffered = false
        var assistantBuffered = false
        if let userPayload {
            userStored = await insertMemoryWithRetry(userPayload)
            if !userStored {
                userBuffered = await enqueuePendingPayloads([userPayload])
            }
        }
        if let assistantPayload {
            assistantStored = await insertMemoryWithRetry(assistantPayload)
            if !assistantStored {
                assistantBuffered = await enqueuePendingPayloads([assistantPayload])
            }
        }
        if userPayload != nil {
            await MaxTelemetry.recordAck(metric: "max_memory_write_ack_user", ack: userStored)
            if !userStored {
                await MaxTelemetry.recordAck(metric: "max_memory_write_buffered_user", ack: userBuffered)
            }
        }
        if assistantPayload != nil {
            await MaxTelemetry.recordAck(metric: "max_memory_write_ack_assistant", ack: assistantStored)
            if !assistantStored {
                await MaxTelemetry.recordAck(metric: "max_memory_write_buffered_assistant", ack: assistantBuffered)
            }
        }
        await MaxTelemetry.recordLatency(
            metric: "max_memory_write_ms_turn",
            milliseconds: Date().timeIntervalSince(startedAt) * 1000
        )
        let userAccepted = userPayload != nil ? (userStored || userBuffered) : false
        let assistantAccepted = assistantPayload != nil ? (assistantStored || assistantBuffered) : false
        if userAccepted || assistantAccepted {
            schedulePendingFlush()
        }
        return (userAccepted, assistantAccepted)
    }

    private static func retrieveRecentMemoriesFromStore(userId: String, limit: Int) async throws -> [MaxMemoryRecord] {
        let resolvedLimit = max(1, limit)
        let endpoint = "ai_memory?user_id=eq.\(userId)&select=content_text,role,created_at&order=created_at.desc&limit=\(resolvedLimit)"
        let memoryRows: [MaxMemoryRecord] = (try? await SupabaseManager.shared.request(endpoint)) ?? []
        if memoryRows.count >= resolvedLimit {
            return Array(memoryRows.prefix(resolvedLimit))
        }

        if let conversationRows = try? await retrieveConversationFallbackRows(
            userId: userId,
            limit: max(conversationFallbackLimit, resolvedLimit)
        ) {
            return mergeMemories(
                primary: memoryRows,
                secondary: conversationRows,
                limit: resolvedLimit
            )
        }

        return Array(memoryRows.prefix(resolvedLimit))
    }

    private static func shouldStoreMemory(content: String, role: String) -> Bool {
        let lowered = content.lowercased()
        if containsSensitivePattern(lowered) { return false }

        if role == "user" {
            if isLowSignalUserMessage(lowered) { return false }
            let signalTokens = [
                "喜欢", "偏好", "更喜欢", "不喜欢", "讨厌", "有用", "有效", "对我有效", "不适合",
                "触发", "加重", "缓解", "让我", "对我", "我更", "焦虑", "紧张", "心慌", "失眠", "睡不好", "压力", "崩溃",
                "害怕", "烦躁", "胸闷", "低落", "抑郁", "没动力", "累",
                "prefer", "works for me", "doesn't work", "trigger", "worse", "better", "anxiety", "panic", "stress",
                "sleep", "can't sleep", "insomnia", "heart racing", "overwhelmed", "helpful", "not helpful"
            ]
            if signalTokens.contains(where: { lowered.contains($0) }) {
                return true
            }
            // Keep medium-length reflective user statements to avoid losing useful memory.
            if containsCJK(lowered) {
                return lowered.count >= minUserCharsCJK
            }
            return lowered.count >= minUserCharsLatin
        }

        if role == "assistant" {
            let strategyTokens = [
                "建议", "方案", "策略", "步骤", "行动", "计划", "练习", "干预",
                "recommend", "plan", "step", "practice", "intervention", "action"
            ]
            return strategyTokens.contains { lowered.contains($0) }
        }

        return false
    }

    private static func mergeMemories(
        primary: [MaxMemoryRecord],
        secondary: [MaxMemoryRecord],
        limit: Int
    ) -> [MaxMemoryRecord] {
        var merged: [MaxMemoryRecord] = []
        var seen: Set<String> = []

        func appendIfNeeded(_ record: MaxMemoryRecord) {
            let key = "\(record.role)|\(record.renderedContent)|\(record.created_at)"
            if seen.contains(key) {
                return
            }
            seen.insert(key)
            merged.append(record)
        }

        primary.forEach(appendIfNeeded)
        secondary.forEach(appendIfNeeded)
        return Array(merged.prefix(max(1, limit)))
    }

    private static func retrieveConversationFallbackRows(
        userId: String,
        limit: Int
    ) async throws -> [MaxMemoryRecord] {
        let endpoint = "chat_conversations?user_id=eq.\(userId)&select=content,role,created_at&order=created_at.desc&limit=\(max(1, limit))"
        let rows: [ConversationMemoryRow] = (try? await SupabaseManager.shared.request(endpoint)) ?? []
        let fallbackDate = ISO8601DateFormatter().string(from: Date())
        return rows.compactMap { row in
            let content = row.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            return MaxMemoryRecord(
                content_text: String(content.prefix(maxMemoryChars)),
                role: row.role,
                created_at: row.created_at ?? fallbackDate,
                similarity: nil
            )
        }
    }

    private static func finalizeRetrieval(
        records: [MaxMemoryRecord],
        startedAt: Date
    ) async -> [MaxMemoryRecord] {
        await MaxTelemetry.recordEmpty(metric: "max_memory_retrieve_empty", isEmpty: records.isEmpty)
        await MaxTelemetry.recordLatency(
            metric: "max_memory_retrieve_ms",
            milliseconds: Date().timeIntervalSince(startedAt) * 1000
        )
        return records
    }

    private static func lexicalFallbackMemories(
        userId: String,
        query: String,
        limit: Int
    ) async -> [MaxMemoryRecord] {
        let candidateLimit = max(limit * 4, conversationFallbackLimit)
        guard let candidates = try? await retrieveRecentMemoriesFromStore(userId: userId, limit: candidateLimit),
              !candidates.isEmpty else {
            return []
        }

        let querySignals = lexicalSignals(from: query)
        guard !querySignals.isEmpty else {
            return Array(candidates.prefix(limit))
        }

        let scored = candidates.compactMap { record -> (MaxMemoryRecord, Double)? in
            let haystack = record.renderedContent.lowercased()
            var overlap = 0
            for signal in querySignals {
                if haystack.contains(signal) {
                    overlap += 1
                }
            }
            if overlap == 0 {
                return nil
            }

            let semanticProxy = Double(overlap) / Double(querySignals.count)
            let roleBoost = record.role == "user" ? 0.08 : 0
            let recency = recencyScore(createdAt: record.created_at)
            let score = semanticProxy * 0.74 + recency * 0.18 + roleBoost
            return (MaxMemoryRecord(
                content_text: record.content_text,
                role: record.role,
                created_at: record.created_at,
                similarity: score
            ), score)
        }

        if scored.isEmpty {
            return Array(candidates.prefix(limit))
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(max(1, limit))
            .map { $0.0 }
    }

    private static func recencyScore(createdAt: String) -> Double {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: createdAt) ?? fallbackFormatter.date(from: createdAt)
        guard let date else { return 0.55 }
        let ageDays = max(0, Date().timeIntervalSince(date) / 86_400)
        return max(0.2, 1.0 - (ageDays / 30.0))
    }

    private static func lexicalSignals(from text: String) -> [String] {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var signals: [String] = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted.union(.whitespacesAndNewlines))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 2 }

        if containsCJK(normalized) {
            let scalars = normalized.unicodeScalars.filter(isCJKScalar)
            if scalars.count >= 2 {
                let chars = Array(String(String.UnicodeScalarView(scalars)))
                for index in 0..<(chars.count - 1) {
                    signals.append(String(chars[index...index + 1]))
                    if signals.count >= 28 {
                        break
                    }
                }
            }
        }

        var unique: [String] = []
        var seen: Set<String> = []
        for signal in signals {
            if seen.insert(signal).inserted {
                unique.append(signal)
            }
            if unique.count >= 32 {
                break
            }
        }
        return unique
    }

    private static func buildPayload(
        userId: String,
        content: String,
        role: String,
        metadata: [String: Any]?
    ) async -> MemoryPayload? {
        let sanitized = sanitizeMemoryContent(content)
        guard let sanitized, shouldStoreMemory(content: sanitized, role: role) else { return nil }

        let resolvedKind = resolveMemoryKind(metadata: metadata)
        let metadataEncoded = mergedMetadata(
            metadata: metadata,
            kind: resolvedKind
        )?.mapValues { AnyCodable($0) }
        let shouldEmbed = role == "user" || embedAssistantMessages || resolvedKind.forcesAssistantEmbedding
        let embedding = shouldEmbed ? await createEmbeddingForStorage(sanitized) : nil
        let storedContent = resolvedKind.decorate(sanitized)
        return MemoryPayload(
            user_id: userId,
            content_text: storedContent,
            role: role,
            embedding: embedding?.isEmpty == false ? embedding : nil,
            metadata: metadataEncoded
        )
    }

    private static func resolveMemoryKind(metadata: [String: Any]?) -> MaxMemoryKind {
        guard let raw = metadata?[MaxMemoryKind.metadataKey] as? String,
              let kind = MaxMemoryKind(rawValue: raw) else {
            return .generic
        }
        return kind
    }

    private static func mergedMetadata(
        metadata: [String: Any]?,
        kind: MaxMemoryKind
    ) -> [String: Any]? {
        var merged = metadata ?? [:]
        if merged[MaxMemoryKind.metadataKey] == nil {
            merged[MaxMemoryKind.metadataKey] = kind.rawValue
        }
        return merged.isEmpty ? nil : merged
    }

    private static func createEmbeddingForRetrieval(_ text: String) async -> [Double] {
        do {
            let embedding = try await withTimeout(seconds: retrievalEmbeddingTimeoutSeconds) {
                try await AIManager.shared.createEmbedding(for: text)
            }
            return embedding
        } catch {
            return []
        }
    }

    private static func createEmbeddingForStorage(_ text: String) async -> [Double]? {
        do {
            let embedding = try await withTimeout(seconds: storageEmbeddingTimeoutSeconds) {
                try await AIManager.shared.createEmbedding(for: text)
            }
            return embedding.isEmpty ? nil : embedding
        } catch {
            return nil
        }
    }

    private static func insertMemoriesBatchWithRetry(_ payloads: [MemoryPayload]) async -> Bool {
        guard !payloads.isEmpty else { return false }
        var lastError: Error?
        for attempt in 1...memoryStoreRetryAttempts {
            do {
                try await SupabaseManager.shared.requestVoid(
                    "ai_memory",
                    method: "POST",
                    body: payloads,
                    prefer: "return=minimal"
                )
                return true
            } catch {
                lastError = error
                let retryable = await SupabaseManager.shared.isRetryableRequestError(error)
                if !retryable,
                   await SupabaseManager.shared.isPermissionDeniedRequestError(error) {
                    await MaxTelemetry.recordAck(metric: "max_memory_write_permission_ack", ack: false)
                }
                if retryable, attempt < memoryStoreRetryAttempts {
                    await sleepForRetryAttempt(attempt)
                    continue
                }
                break
            }
        }

        let fallbackPayloads = payloads.map { payload in
            MemoryPayload(
                user_id: payload.user_id,
                content_text: payload.content_text,
                role: payload.role,
                embedding: nil,
                metadata: payload.metadata
            )
        }
        do {
            try await SupabaseManager.shared.requestVoid(
                "ai_memory",
                method: "POST",
                body: fallbackPayloads,
                prefer: "return=minimal"
            )
            return true
        } catch {
            if payloads.contains(where: { $0.metadata != nil }) {
                let legacyPayloads = payloads.map { payload in
                    MemoryPayload(
                        user_id: payload.user_id,
                        content_text: payload.content_text,
                        role: payload.role,
                        embedding: nil,
                        metadata: nil
                    )
                }
                do {
                    try await SupabaseManager.shared.requestVoid(
                        "ai_memory",
                        method: "POST",
                        body: legacyPayloads,
                        prefer: "return=minimal"
                    )
                    return true
                } catch {
                    if await SupabaseManager.shared.isPermissionDeniedRequestError(error) {
                        await MaxTelemetry.recordAck(metric: "max_memory_write_permission_ack", ack: false)
                    }
                    if let lastError {
                        print("[MaxMemory] batch store failed (legacy): primary=\(lastError), fallback=\(error)")
                    } else {
                        print("[MaxMemory] batch store failed (legacy): \(error)")
                    }
                    return false
                }
            }
            if await SupabaseManager.shared.isPermissionDeniedRequestError(error) {
                await MaxTelemetry.recordAck(metric: "max_memory_write_permission_ack", ack: false)
            }
            if let lastError {
                print("[MaxMemory] batch store failed: primary=\(lastError), fallback=\(error)")
            } else {
                print("[MaxMemory] batch store failed: \(error)")
            }
            return false
        }
    }

    private static func insertMemoryWithRetry(_ payload: MemoryPayload) async -> Bool {
        var lastError: Error?
        for attempt in 1...memoryStoreRetryAttempts {
            do {
                try await SupabaseManager.shared.requestVoid(
                    "ai_memory",
                    method: "POST",
                    body: payload,
                    prefer: "return=minimal"
                )
                return true
            } catch {
                lastError = error
                let retryable = await SupabaseManager.shared.isRetryableRequestError(error)
                if !retryable,
                   await SupabaseManager.shared.isPermissionDeniedRequestError(error) {
                    await MaxTelemetry.recordAck(metric: "max_memory_write_permission_ack", ack: false)
                }
                if retryable, attempt < memoryStoreRetryAttempts {
                    await sleepForRetryAttempt(attempt)
                    continue
                }
                break
            }
        }

        if payload.embedding != nil {
            let fallbackPayload = MemoryPayload(
                user_id: payload.user_id,
                content_text: payload.content_text,
                role: payload.role,
                embedding: nil,
                metadata: payload.metadata
            )
            do {
                try await SupabaseManager.shared.requestVoid(
                    "ai_memory",
                    method: "POST",
                    body: fallbackPayload,
                    prefer: "return=minimal"
                )
                return true
            } catch {
                if payload.metadata != nil {
                    let legacyPayload = MemoryPayload(
                        user_id: payload.user_id,
                        content_text: payload.content_text,
                        role: payload.role,
                        embedding: nil,
                        metadata: nil
                    )
                    do {
                        try await SupabaseManager.shared.requestVoid(
                            "ai_memory",
                            method: "POST",
                            body: legacyPayload,
                            prefer: "return=minimal"
                        )
                        return true
                    } catch {
                        if await SupabaseManager.shared.isPermissionDeniedRequestError(error) {
                            await MaxTelemetry.recordAck(metric: "max_memory_write_permission_ack", ack: false)
                        }
                        if let lastError {
                            print("[MaxMemory] store failed (legacy): primary=\(lastError), fallback=\(error)")
                        } else {
                            print("[MaxMemory] store failed (legacy): \(error)")
                        }
                        return false
                    }
                }
                if await SupabaseManager.shared.isPermissionDeniedRequestError(error) {
                    await MaxTelemetry.recordAck(metric: "max_memory_write_permission_ack", ack: false)
                }
                if let lastError {
                    print("[MaxMemory] store failed (fallback): primary=\(lastError), fallback=\(error)")
                } else {
                    print("[MaxMemory] store failed (fallback): \(error)")
                }
            }
        } else if let lastError {
            print("[MaxMemory] store failed: \(lastError)")
        }

        return false
    }

    @discardableResult
    private static func enqueuePendingPayloads(_ payloads: [MemoryPayload]) async -> Bool {
        guard !payloads.isEmpty else { return false }
        let queueCount = await pendingQueue.append(payloads, maxItems: pendingQueueLimit)
        await MaxTelemetry.recordAck(metric: "max_memory_pending_enqueue_ack", ack: true)
        await MaxTelemetry.recordEmpty(metric: "max_memory_pending_queue_empty", isEmpty: queueCount == 0)
        return true
    }

    private static func schedulePendingFlush() {
        Task(priority: .utility) {
            await flushPendingPayloads()
        }
    }

    private static func flushPendingPayloads() async {
        guard await pendingQueue.beginFlush() else { return }

        let startedAt = Date()
        var processed = 0
        var batches = 0

        while batches < pendingFlushMaxBatches {
            let batch = await pendingQueue.peek(limit: pendingFlushBatchSize)
            guard !batch.isEmpty else { break }
            batches += 1
            let payloads = batch.map(\.payload)
            let stored: Bool
            if payloads.count > 1 {
                stored = await insertMemoriesBatchWithRetry(payloads)
            } else if let payload = payloads.first {
                stored = await insertMemoryWithRetry(payload)
            } else {
                stored = false
            }
            if !stored {
                await MaxTelemetry.recordAck(metric: "max_memory_pending_flush_ack", ack: false)
                break
            }

            let ids = Set(batch.map(\.id))
            _ = await pendingQueue.remove(ids: ids)
            processed += batch.count
            await MaxTelemetry.recordAck(metric: "max_memory_pending_flush_ack", ack: true)
        }

        let remaining = await pendingQueue.count()
        await pendingQueue.endFlush()
        await MaxTelemetry.recordEmpty(metric: "max_memory_pending_queue_empty", isEmpty: remaining == 0)
        await MaxTelemetry.recordLatency(
            metric: "max_memory_pending_flush_ms",
            milliseconds: Date().timeIntervalSince(startedAt) * 1000
        )
        if processed > 0 || remaining > 0 {
            print("[MaxMemory] pending flush processed=\(processed) remaining=\(remaining)")
        }
    }

    private static func sleepForRetryAttempt(_ attempt: Int) async {
        let base = Double(memoryStoreRetryBaseDelayMs)
        let multiplier = pow(1.8, Double(max(0, attempt - 1)))
        let jitter = Double.random(in: 0.85...1.2)
        let delayMs = min(2_000.0, max(base, base * multiplier * jitter))
        let nanos = UInt64(delayMs * 1_000_000)
        try? await Task.sleep(nanoseconds: nanos)
    }

    private static func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let timeout = max(0.6, seconds)
        let timeoutNanos = UInt64(timeout * 1_000_000_000)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
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

    private static func sanitizeMemoryContent(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maxMemoryChars))
    }

    private static func containsSensitivePattern(_ text: String) -> Bool {
        let patterns = [
            "[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}",
            "\\b\\d{7,}\\b"
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text)) != nil {
                return true
            }
        }
        return false
    }

    private static func isLowSignalUserMessage(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return true }

        let shortClinicalSignals = [
            "焦虑", "心慌", "失眠", "胸闷", "崩溃", "恐慌", "害怕", "panic", "anxious", "insomnia"
        ]
        if cleaned.count <= 3,
           shortClinicalSignals.contains(where: { cleaned.contains($0) }) {
            return false
        }

        let lowSignal = Set([
            "ok", "okay", "thanks", "thank you", "got it", "yes", "no",
            "好的", "好", "谢谢", "收到", "嗯", "哦", "知道了"
        ])
        if lowSignal.contains(cleaned) { return true }

        if cleaned.count <= 1 {
            return true
        }
        return false
    }

    private static func isCJKScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private static func containsCJK(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if isCJKScalar(scalar) {
                return true
            }
        }
        return false
    }

    // Read runtime dictionaries once to avoid concurrent Objective-C bridging crashes.
    private static let runtimeEnvironmentSnapshot: [String: String] = ProcessInfo.processInfo.environment
    private static let runtimeInfoSnapshot: [String: Any] = Bundle.main.infoDictionary ?? [:]

    private static func runtimeString(for key: String) -> String? {
        if let env = runtimeEnvironmentSnapshot[key] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let raw = runtimeInfoSnapshot[key] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }

        if let number = runtimeInfoSnapshot[key] as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func runtimeInt(
        for key: String,
        fallback: Int,
        min minimum: Int,
        max maximum: Int
    ) -> Int {
        guard let raw = runtimeString(for: key), let value = Int(raw) else {
            return fallback
        }
        let capped = Swift.min(maximum, value)
        return Swift.max(minimum, capped)
    }

    private static func runtimeDouble(
        for key: String,
        fallback: Double,
        min minimum: Double,
        max maximum: Double
    ) -> Double {
        guard let raw = runtimeString(for: key), let value = Double(raw) else {
            return fallback
        }
        let capped = Swift.min(maximum, value)
        return Swift.max(minimum, capped)
    }

    private static func runtimeBool(for key: String, fallback: Bool) -> Bool {
        guard let raw = runtimeString(for: key)?.lowercased() else { return fallback }
        if ["1", "true", "yes", "on"].contains(raw) { return true }
        if ["0", "false", "no", "off"].contains(raw) { return false }
        return fallback
    }

    private static var maxMemoryChars: Int {
        runtimeInt(for: "MAX_MEMORY_MAX_CHARS", fallback: 600, min: 200, max: 2_000)
    }

    private static var minUserCharsCJK: Int {
        runtimeInt(for: "MAX_MEMORY_MIN_USER_CHARS_CJK", fallback: 2, min: 1, max: 12)
    }

    private static var minUserCharsLatin: Int {
        runtimeInt(for: "MAX_MEMORY_MIN_USER_CHARS_LATIN", fallback: 6, min: 2, max: 24)
    }

    private static var conversationFallbackLimit: Int {
        runtimeInt(for: "MAX_MEMORY_CONVERSATION_FALLBACK_LIMIT", fallback: 36, min: 8, max: 180)
    }

    private static var memoryStoreRetryAttempts: Int {
        runtimeInt(for: "MAX_MEMORY_STORE_RETRY_ATTEMPTS", fallback: 3, min: 1, max: 6)
    }

    private static var memoryStoreRetryBaseDelayMs: Int {
        runtimeInt(for: "MAX_MEMORY_STORE_RETRY_BASE_DELAY_MS", fallback: 250, min: 80, max: 1_200)
    }

    private static var retrievalEmbeddingTimeoutSeconds: TimeInterval {
        runtimeDouble(for: "MAX_MEMORY_RETRIEVAL_EMBED_TIMEOUT_SEC", fallback: 3.6, min: 1.0, max: 12.0)
    }

    private static var storageEmbeddingTimeoutSeconds: TimeInterval {
        runtimeDouble(for: "MAX_MEMORY_STORAGE_EMBED_TIMEOUT_SEC", fallback: 1.8, min: 0.8, max: 10.0)
    }

    private static var embedAssistantMessages: Bool {
        runtimeBool(for: "MAX_MEMORY_EMBED_ASSISTANT", fallback: false)
    }

    private static var memoryMatchThreshold: Double {
        runtimeDouble(for: "MAX_MEMORY_MATCH_THRESHOLD", fallback: 0.7, min: 0.3, max: 0.9)
    }

    private static var memoryRelaxedMatchThreshold: Double {
        runtimeDouble(for: "MAX_MEMORY_RELAXED_MATCH_THRESHOLD", fallback: 0.52, min: 0.2, max: 0.9)
    }

    private static var pendingQueueLimit: Int {
        runtimeInt(for: "MAX_MEMORY_PENDING_QUEUE_LIMIT", fallback: 800, min: 100, max: 8_000)
    }

    private static var pendingFlushBatchSize: Int {
        runtimeInt(for: "MAX_MEMORY_PENDING_FLUSH_BATCH_SIZE", fallback: 10, min: 1, max: 80)
    }

    private static var pendingFlushMaxBatches: Int {
        runtimeInt(for: "MAX_MEMORY_PENDING_FLUSH_MAX_BATCHES", fallback: 10, min: 1, max: 200)
    }

    private static var allowLexicalFallback: Bool {
        runtimeBool(for: "MAX_MEMORY_ALLOW_LEXICAL_FALLBACK", fallback: false)
    }

    private static var pendingQueueStorageURL: URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = baseURL.appendingPathComponent("max-memory", isDirectory: true)
        return directory.appendingPathComponent("pending-memory-queue.json", isDirectory: false)
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = ()
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable unsupported")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is Void:
            try container.encodeNil()
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case let arrayVal as [Any]:
            try container.encode(arrayVal.map { AnyCodable($0) })
        case let dictVal as [String: Any]:
            let wrapped = dictVal.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "AnyCodable unsupported"))
        }
    }
}

enum MaxTelemetry {
    private struct BinaryStat {
        var total: Int = 0
        var positive: Int = 0

        mutating func add(_ value: Bool) {
            total += 1
            if value {
                positive += 1
            }
        }

        var rate: Double {
            guard total > 0 else { return 0 }
            return Double(positive) / Double(total)
        }
    }

    private actor Store {
        private var ackStats: [String: BinaryStat] = [:]
        private var emptyStats: [String: BinaryStat] = [:]
        private var latencyStats: [String: [Double]] = [:]
        private var eventsSinceFlush: Int = 0
        private var lastFlushAt: Date = Date()

        func recordAck(metric: String, ack: Bool) {
            var stat = ackStats[metric] ?? BinaryStat()
            stat.add(ack)
            ackStats[metric] = stat
            eventsSinceFlush += 1
        }

        func recordEmpty(metric: String, isEmpty: Bool) {
            var stat = emptyStats[metric] ?? BinaryStat()
            stat.add(isEmpty)
            emptyStats[metric] = stat
            eventsSinceFlush += 1
        }

        func recordLatency(metric: String, milliseconds: Double, sampleLimit: Int) {
            let safeValue = max(0, milliseconds)
            var samples = latencyStats[metric] ?? []
            samples.append(safeValue)
            if samples.count > sampleLimit {
                samples.removeFirst(samples.count - sampleLimit)
            }
            latencyStats[metric] = samples
            eventsSinceFlush += 1
        }

        func maybeFlush(force: Bool, minEvents: Int, minIntervalSec: TimeInterval) -> String? {
            let now = Date()
            let reachedEventGate = eventsSinceFlush >= minEvents
            let reachedTimeGate = now.timeIntervalSince(lastFlushAt) >= minIntervalSec
            if !force, !reachedEventGate, !reachedTimeGate {
                return nil
            }

            let ackSummary = ackStats.keys.sorted().compactMap { key -> String? in
                guard let stat = ackStats[key], stat.total > 0 else { return nil }
                let pct = Int((stat.rate * 100).rounded())
                return "\(key)=\(pct)%(\(stat.positive)/\(stat.total))"
            }

            let emptySummary = emptyStats.keys.sorted().compactMap { key -> String? in
                guard let stat = emptyStats[key], stat.total > 0 else { return nil }
                let pct = Int((stat.rate * 100).rounded())
                return "\(key)=\(pct)%(\(stat.positive)/\(stat.total))"
            }

            let latencySummary = latencyStats.keys.sorted().compactMap { key -> String? in
                guard let samples = latencyStats[key], !samples.isEmpty else { return nil }
                let p50 = percentile(samples, p: 0.50)
                let p95 = percentile(samples, p: 0.95)
                let avg = samples.reduce(0, +) / Double(samples.count)
                return "\(key) p50=\(Int(p50.rounded()))ms p95=\(Int(p95.rounded()))ms avg=\(Int(avg.rounded()))ms n=\(samples.count)"
            }

            let ackBlock: String? = ackSummary.isEmpty ? nil : "ack{ " + ackSummary.joined(separator: " | ") + " }"
            let emptyBlock: String? = emptySummary.isEmpty ? nil : "empty{ " + emptySummary.joined(separator: " | ") + " }"
            let latencyBlock: String? = latencySummary.isEmpty ? nil : "latency{ " + latencySummary.joined(separator: " | ") + " }"

            var blocks: [String] = []
            if let ackBlock {
                blocks.append(ackBlock)
            }
            if let emptyBlock {
                blocks.append(emptyBlock)
            }
            if let latencyBlock {
                blocks.append(latencyBlock)
            }
            let summary = blocks.joined(separator: " ")

            eventsSinceFlush = 0
            lastFlushAt = now
            return summary.isEmpty ? nil : summary
        }

        private func percentile(_ samples: [Double], p: Double) -> Double {
            let sorted = samples.sorted()
            guard !sorted.isEmpty else { return 0 }
            let clamped = min(1, max(0, p))
            let index = Int((Double(sorted.count - 1) * clamped).rounded())
            return sorted[max(0, min(sorted.count - 1, index))]
        }
    }

    private static let store = Store()

    static func recordAck(metric: String, ack: Bool) async {
        guard enabled else { return }
        await store.recordAck(metric: metric, ack: ack)
        await flushIfNeeded()
    }

    static func recordEmpty(metric: String, isEmpty: Bool) async {
        guard enabled else { return }
        await store.recordEmpty(metric: metric, isEmpty: isEmpty)
        await flushIfNeeded()
    }

    static func recordLatency(metric: String, milliseconds: Double) async {
        guard enabled else { return }
        await store.recordLatency(
            metric: metric,
            milliseconds: milliseconds,
            sampleLimit: latencySampleLimit
        )
        await flushIfNeeded()
    }

    static func flushIfNeeded(force: Bool = false) async {
        guard enabled else { return }
        if let summary = await store.maybeFlush(
            force: force,
            minEvents: flushMinEvents,
            minIntervalSec: flushMinIntervalSec
        ) {
            print("[MaxTelemetry] \(summary)")
        }
    }

    private static var enabled: Bool {
        runtimeBool(for: "MAX_TELEMETRY_ENABLED", fallback: true)
    }

    private static var flushMinEvents: Int {
        runtimeInt(for: "MAX_TELEMETRY_FLUSH_MIN_EVENTS", fallback: 25, min: 5, max: 500)
    }

    private static var flushMinIntervalSec: TimeInterval {
        runtimeDouble(for: "MAX_TELEMETRY_FLUSH_INTERVAL_SEC", fallback: 45, min: 5, max: 300)
    }

    private static var latencySampleLimit: Int {
        runtimeInt(for: "MAX_TELEMETRY_LATENCY_SAMPLE_LIMIT", fallback: 300, min: 30, max: 5000)
    }

    private static func runtimeString(for key: String) -> String? {
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

    private static func runtimeInt(for key: String, fallback: Int, min minimum: Int, max maximum: Int) -> Int {
        guard let raw = runtimeString(for: key), let value = Int(raw) else { return fallback }
        return Swift.max(minimum, Swift.min(maximum, value))
    }

    private static func runtimeDouble(for key: String, fallback: Double, min minimum: Double, max maximum: Double) -> Double {
        guard let raw = runtimeString(for: key), let value = Double(raw) else { return fallback }
        return Swift.max(minimum, Swift.min(maximum, value))
    }

    private static func runtimeBool(for key: String, fallback: Bool) -> Bool {
        guard let raw = runtimeString(for: key)?.lowercased() else { return fallback }
        if ["1", "true", "yes", "on"].contains(raw) { return true }
        if ["0", "false", "no", "off"].contains(raw) { return false }
        return fallback
    }
}
