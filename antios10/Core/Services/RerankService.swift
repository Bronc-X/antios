import Foundation

enum RerankService {
    private actor RerankStateStore {
        struct CacheEntry {
            let indices: [Int]
            let insertedAt: Date
            let expiresAt: Date
        }

        private var cache: [String: CacheEntry] = [:]
        private var inFlight: [String: Task<[Int]?, Never>] = [:]

        func cachedIndices(for key: String, now: Date = Date()) -> [Int]? {
            guard let entry = cache[key] else { return nil }
            guard entry.expiresAt > now else {
                cache.removeValue(forKey: key)
                return nil
            }
            return entry.indices
        }

        func inFlightTask(for key: String) -> Task<[Int]?, Never>? {
            inFlight[key]
        }

        func setInFlight(_ task: Task<[Int]?, Never>, for key: String) {
            inFlight[key] = task
        }

        func clearInFlight(for key: String) {
            inFlight.removeValue(forKey: key)
        }

        func setCache(_ indices: [Int], for key: String, ttl: TimeInterval, maxEntries: Int) {
            cache[key] = CacheEntry(
                indices: indices,
                insertedAt: Date(),
                expiresAt: Date().addingTimeInterval(ttl)
            )
            if cache.count > maxEntries {
                let sorted = cache.sorted { lhs, rhs in
                    lhs.value.insertedAt < rhs.value.insertedAt
                }
                let removeCount = cache.count - maxEntries
                for (cacheKey, _) in sorted.prefix(removeCount) {
                    cache.removeValue(forKey: cacheKey)
                }
            }
        }
    }

    private struct CohereConfig {
        static var apiKey: String? {
            guard let key = runtimeString(for: "COHERE_API_KEY") else { return nil }
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        static var baseURL: String {
            if let url = runtimeString(for: "COHERE_API_BASE"),
               !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return url.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return "https://api.cohere.ai"
        }

        static var model: String {
            if let model = runtimeString(for: "COHERE_RERANK_MODEL"),
               !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return model
            }
            return "rerank-multilingual-v3.0"
        }

        static var enabled: Bool {
            runtimeBool(for: "COHERE_RERANK_ENABLED", fallback: true)
        }

        static var timeoutSeconds: TimeInterval {
            runtimeDouble(for: "COHERE_RERANK_TIMEOUT_SEC", fallback: 4.0, min: 1.0, max: 20.0)
        }

        static var minDocuments: Int {
            runtimeInt(for: "COHERE_RERANK_MIN_DOCUMENTS", fallback: 4, min: 2, max: 20)
        }

        static var cacheTTL: TimeInterval {
            runtimeDouble(for: "COHERE_RERANK_CACHE_TTL_SEC", fallback: 300.0, min: 30.0, max: 3600.0)
        }

        static var cacheMaxEntries: Int {
            runtimeInt(for: "COHERE_RERANK_CACHE_MAX_ENTRIES", fallback: 256, min: 32, max: 4096)
        }
    }

    struct RerankResult: Codable {
        let results: [RerankItem]
    }

    struct RerankItem: Codable {
        let index: Int
        let relevance_score: Double
    }

    private static let stateStore = RerankStateStore()

    static func rerank(query: String, documents: [String], topN: Int = 8) async -> [Int]? {
        let startedAt = Date()
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard CohereConfig.enabled else {
            await recordRerankSummary(path: "disabled", startedAt: startedAt, success: false)
            return nil
        }
        guard let apiKey = CohereConfig.apiKey,
              !normalizedQuery.isEmpty,
              !documents.isEmpty else {
            await recordRerankSummary(path: "invalid", startedAt: startedAt, success: false)
            return nil
        }

        let resolvedTopN = min(max(1, topN), documents.count)
        if documents.count < CohereConfig.minDocuments {
            await recordRerankSummary(path: "small_docs", startedAt: startedAt, success: false)
            return nil
        }

        let key = rerankCacheKey(
            query: normalizedQuery,
            documents: documents,
            topN: resolvedTopN
        )
        if let cached = await stateStore.cachedIndices(for: key) {
            await MaxTelemetry.recordAck(metric: "max_rerank_cache_hit", ack: true)
            await recordRerankSummary(path: "cache", startedAt: startedAt, success: !cached.isEmpty)
            return cached
        }
        await MaxTelemetry.recordAck(metric: "max_rerank_cache_hit", ack: false)

        if let inFlight = await stateStore.inFlightTask(for: key) {
            let result = await inFlight.value
            await recordRerankSummary(path: "inflight", startedAt: startedAt, success: isNonEmpty(result))
            return result
        }

        let networkStartedAt = Date()
        let task = Task<[Int]?, Never> {
            await executeRerank(
                apiKey: apiKey,
                query: normalizedQuery,
                documents: documents,
                topN: resolvedTopN
            )
        }
        await stateStore.setInFlight(task, for: key)
        let result = await task.value
        await stateStore.clearInFlight(for: key)
        await MaxTelemetry.recordLatency(
            metric: "max_rerank_network_ms",
            milliseconds: Date().timeIntervalSince(networkStartedAt) * 1000
        )

        if let result, !result.isEmpty {
            await stateStore.setCache(
                result,
                for: key,
                ttl: CohereConfig.cacheTTL,
                maxEntries: CohereConfig.cacheMaxEntries
            )
        }
        await recordRerankSummary(path: "network", startedAt: startedAt, success: isNonEmpty(result))
        return result
    }

    private static func executeRerank(
        apiKey: String,
        query: String,
        documents: [String],
        topN: Int
    ) async -> [Int]? {
        guard let url = URL(string: "\(CohereConfig.baseURL)/v1/rerank") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = CohereConfig.timeoutSeconds

        let body: [String: Any] = [
            "model": CohereConfig.model,
            "query": query,
            "documents": documents,
            "top_n": min(topN, documents.count),
            "return_documents": false
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        request.httpBody = payload

        do {
            let (data, response) = try await NetworkSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(RerankResult.self, from: data)
            return result.results.map { $0.index }
        } catch {
            return nil
        }
    }

    private static func rerankCacheKey(query: String, documents: [String], topN: Int) -> String {
        var accumulator = query.lowercased() + "|n=\(topN)|count=\(documents.count)"
        for (index, document) in documents.enumerated() {
            let normalized = document.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let docHash = fnv1a64(normalized)
            accumulator.append("|\(index):\(docHash)")
        }
        return String(fnv1a64(accumulator), radix: 16)
    }

    private static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 14695981039346656037
        let prime: UInt64 = 1099511628211
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }

    private static func isNonEmpty(_ indices: [Int]?) -> Bool {
        guard let indices else { return false }
        return !indices.isEmpty
    }

    private static func recordRerankSummary(path: String, startedAt: Date, success: Bool) async {
        await MaxTelemetry.recordAck(metric: "max_rerank_success", ack: success)
        await MaxTelemetry.recordLatency(
            metric: "max_rerank_total_ms_\(path)",
            milliseconds: Date().timeIntervalSince(startedAt) * 1000
        )
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
        guard let raw = runtimeString(for: key), let value = Int(raw) else {
            return fallback
        }
        return Swift.max(minimum, Swift.min(maximum, value))
    }

    private static func runtimeDouble(for key: String, fallback: Double, min minimum: Double, max maximum: Double) -> Double {
        guard let raw = runtimeString(for: key), let value = Double(raw) else {
            return fallback
        }
        return Swift.max(minimum, Swift.min(maximum, value))
    }

    private static func runtimeBool(for key: String, fallback: Bool) -> Bool {
        guard let raw = runtimeString(for: key)?.lowercased() else {
            return fallback
        }
        if ["1", "true", "yes", "on"].contains(raw) { return true }
        if ["0", "false", "no", "off"].contains(raw) { return false }
        return fallback
    }
}
