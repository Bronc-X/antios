import Foundation

enum MaxRAGDepth {
    case lite
    case full
}

struct MaxRAGContext {
    let memoryBlock: String?
    let playbookBlock: String?
}

enum MaxRAGService {
    static func buildContext(
        userId: String,
        query: String,
        language: String,
        depth: MaxRAGDepth = .full
    ) async -> MaxRAGContext {
        let cleanedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedQuery.isEmpty else {
            return MaxRAGContext(memoryBlock: nil, playbookBlock: nil)
        }

        switch depth {
        case .lite:
            return await buildLiteContext(userId: userId, language: language)
        case .full:
            return await buildFullContext(userId: userId, query: cleanedQuery, language: language)
        }
    }

    private static func buildLiteContext(userId: String, language: String) async -> MaxRAGContext {
        let startedAt = Date()
        async let memoriesTask = MaxMemoryService.retrieveRecentMemories(
            userId: userId,
            limit: liteMemoryLimit
        )
        async let wearableSummaryTask = timedWearableSummary()

        let memories = await memoriesTask
        let wearableSummary = await wearableSummaryTask

        let memoryBlock = formatMemories(memories)
        let playbookBlock = formatKnowledge(
            [],
            language: language,
            wearableSummary: wearableSummary
        )
        let elapsed = Date().timeIntervalSince(startedAt)
        await MaxTelemetry.recordEmpty(metric: "max_rag_memory_empty_lite", isEmpty: memories.isEmpty)
        await MaxTelemetry.recordEmpty(metric: "max_rag_knowledge_empty_lite", isEmpty: true)
        await MaxTelemetry.recordEmpty(
            metric: "max_rag_context_empty_lite",
            isEmpty: memoryBlock == nil && playbookBlock == nil
        )
        await MaxTelemetry.recordLatency(
            metric: "max_rag_build_ms_lite",
            milliseconds: elapsed * 1000
        )
        print("[MaxRAG] depth=lite elapsed=\(String(format: "%.2f", elapsed))s memories=\(memories.count) wearable=\(wearableSummary == nil ? "n" : "y")")
        return MaxRAGContext(memoryBlock: memoryBlock, playbookBlock: playbookBlock)
    }

    private static func buildFullContext(userId: String, query: String, language: String) async -> MaxRAGContext {
        let startedAt = Date()
        async let wearableSummaryTask = timedWearableSummary()
        let embedding = await timedEmbedding(query)
        async let semanticMemoriesTask = MaxMemoryService.retrieveMemories(
            userId: userId,
            query: query,
            embedding: embedding,
            limit: fullMemoryLimit,
            shouldGenerateEmbeddingWhenMissing: false
        )
        async let recentMemoriesTask = MaxMemoryService.retrieveRecentMemories(
            userId: userId,
            limit: max(3, fullMemoryLimit / 2)
        )
        async let knowledgeTask: [KnowledgeBaseChunk] = {
            guard let embedding, !embedding.isEmpty else { return [] }
            return await KnowledgeBaseService.matchKnowledge(
                query: query,
                embedding: embedding,
                limit: fullKnowledgeLimit
            )
        }()

        let semanticMemories = await semanticMemoriesTask
        let recentMemories = await recentMemoriesTask
        let memories = mergeMemories(
            primary: semanticMemories,
            secondary: recentMemories,
            limit: fullMemoryLimit
        )
        var knowledge = await knowledgeTask
        let wearableSummary = await wearableSummaryTask

        if rerankEnabled, knowledge.count >= rerankMinDocuments {
            if let reranked = await RerankService.rerank(
                query: query,
                documents: knowledge.map { $0.content },
                topN: rerankTopN
            ) {
                knowledge = reranked.compactMap { index in
                    guard knowledge.indices.contains(index) else { return nil }
                    return knowledge[index]
                }
            }
        }

        let memoryBlock = formatMemories(memories)
        let playbookBlock = formatKnowledge(
            knowledge,
            language: language,
            wearableSummary: wearableSummary
        )
        let elapsed = Date().timeIntervalSince(startedAt)
        await MaxTelemetry.recordEmpty(metric: "max_rag_memory_empty_full", isEmpty: memories.isEmpty)
        await MaxTelemetry.recordEmpty(metric: "max_rag_knowledge_empty_full", isEmpty: knowledge.isEmpty)
        await MaxTelemetry.recordEmpty(
            metric: "max_rag_context_empty_full",
            isEmpty: memoryBlock == nil && playbookBlock == nil
        )
        await MaxTelemetry.recordLatency(
            metric: "max_rag_build_ms_full",
            milliseconds: elapsed * 1000
        )
        print("[MaxRAG] depth=full elapsed=\(String(format: "%.2f", elapsed))s embedding=\(embedding == nil ? "n" : "y") memories=\(memories.count) knowledge=\(knowledge.count) wearable=\(wearableSummary == nil ? "n" : "y")")
        return MaxRAGContext(memoryBlock: memoryBlock, playbookBlock: playbookBlock)
    }

    private static func mergeMemories(
        primary: [MaxMemoryRecord],
        secondary: [MaxMemoryRecord],
        limit: Int
    ) -> [MaxMemoryRecord] {
        guard limit > 0 else { return [] }
        var merged: [MaxMemoryRecord] = []
        merged.reserveCapacity(limit)
        var seen = Set<String>()

        for record in primary + secondary {
            let contentKey = record.content_text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !contentKey.isEmpty else { continue }
            if seen.insert(contentKey).inserted {
                merged.append(record)
            }
            if merged.count >= limit {
                break
            }
        }
        return merged
    }

    private static func formatMemories(_ records: [MaxMemoryRecord]) -> String? {
        guard !records.isEmpty else { return nil }

        let formatterWithFraction = ISO8601DateFormatter()
        formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let now = Date()

        let scored = records.map { record -> (MaxMemoryRecord, Double) in
            let similarity = record.similarity ?? 0.5
            let recency: Double
            if let date = formatterWithFraction.date(from: record.created_at) ?? formatter.date(from: record.created_at) {
                let days = max(0, now.timeIntervalSince(date) / 86400.0)
                recency = max(0.2, 1.0 - (days / 30.0))
            } else {
                recency = 0.5
            }
            let score = similarity * 0.7 + recency * 0.3
            return (record, score)
        }

        let top = scored.sorted { $0.1 > $1.1 }.prefix(memoryBlockTopN).map { $0.0 }
        let lines = top.map { record in
            let roleTag = record.role == "assistant" ? "assistant" : "user"
            return "• [\(roleTag)] \(record.content_text)"
        }
        return lines.joined(separator: "\n")
    }

    private static func formatKnowledge(
        _ chunks: [KnowledgeBaseChunk],
        language: String,
        wearableSummary: String?
    ) -> String? {
        guard !chunks.isEmpty || wearableSummary != nil else { return nil }
        let top = chunks.prefix(knowledgeBlockTopN)
        var lines = top.map { chunk -> String in
            let content = (language == "en" ? (chunk.contentEn ?? chunk.content) : chunk.content)
            let category = chunk.category ?? "general"
            return "• [\(category)] \(content)"
        }
        if let wearableSummary, !wearableSummary.isEmpty {
            lines.append("• [wearable] \(wearableSummary)")
        }
        return lines.joined(separator: "\n")
    }

    private static func timedEmbedding(_ query: String) async -> [Double]? {
        do {
            return try await withThrowingTimeout(seconds: ragEmbeddingTimeoutSeconds) {
                try await AIManager.shared.createEmbedding(for: query)
            }
        } catch {
            return nil
        }
    }

    private static func timedWearableSummary() async -> String? {
        let timeout = max(0.5, wearableSummaryTimeoutSeconds)
        let timeoutNanos = UInt64(timeout * 1_000_000_000)
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await SupabaseManager.shared.buildWearableRAGSummary()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanos)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    private static func withThrowingTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        let timeout = max(0.8, seconds)
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

    private static func runtimeString(for key: String) -> String? {
        if let env = ProcessInfo.processInfo.environment[key] {
            let trimmed = env.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }

        if let raw = Bundle.main.infoDictionary?[key] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, !trimmed.hasPrefix("$(") { return trimmed }
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

    private static var liteMemoryLimit: Int {
        runtimeInt(for: "MAX_RAG_LITE_MEMORY_LIMIT", fallback: 4, min: 2, max: 12)
    }

    private static var fullMemoryLimit: Int {
        runtimeInt(for: "MAX_RAG_FULL_MEMORY_LIMIT", fallback: 8, min: 3, max: 20)
    }

    private static var fullKnowledgeLimit: Int {
        runtimeInt(for: "MAX_RAG_FULL_KNOWLEDGE_LIMIT", fallback: 10, min: 4, max: 24)
    }

    private static var memoryBlockTopN: Int {
        runtimeInt(for: "MAX_RAG_MEMORY_BLOCK_TOPN", fallback: 6, min: 2, max: 12)
    }

    private static var knowledgeBlockTopN: Int {
        runtimeInt(for: "MAX_RAG_KNOWLEDGE_BLOCK_TOPN", fallback: 6, min: 2, max: 12)
    }

    private static var ragEmbeddingTimeoutSeconds: TimeInterval {
        runtimeDouble(for: "MAX_RAG_EMBED_TIMEOUT_SEC", fallback: 3.6, min: 1.0, max: 12.0)
    }

    private static var wearableSummaryTimeoutSeconds: TimeInterval {
        runtimeDouble(for: "MAX_RAG_WEARABLE_TIMEOUT_SEC", fallback: 1.6, min: 0.5, max: 8.0)
    }

    private static var rerankEnabled: Bool {
        runtimeBool(for: "MAX_RAG_RERANK_ENABLED", fallback: true)
    }

    private static var rerankTopN: Int {
        runtimeInt(for: "MAX_RAG_RERANK_TOPN", fallback: 8, min: 2, max: 16)
    }

    private static var rerankMinDocuments: Int {
        runtimeInt(for: "MAX_RAG_RERANK_MIN_DOCS", fallback: 4, min: 2, max: 12)
    }
}
