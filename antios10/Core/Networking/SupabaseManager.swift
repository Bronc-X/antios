// SupabaseManager.swift
// Supabase 客户端管理器 - 连接现有后端

import Foundation
import Security

enum AppGroupConfig {
    static let sharedSuiteName = "group.com.youngtony.antios10"
}

enum SupabaseCredentialStore {
    private static let service = "com.youngtony.antios10.supabase"
    private static let legacyAccessTokenKey = "supabase_access_token"
    private static let legacyRefreshTokenKey = "supabase_refresh_token"

    enum TokenKind {
        case access
        case refresh

        var account: String {
            switch self {
            case .access:
                return "access_token"
            case .refresh:
                return "refresh_token"
            }
        }

        var legacyDefaultsKey: String {
            switch self {
            case .access:
                return legacyAccessTokenKey
            case .refresh:
                return legacyRefreshTokenKey
            }
        }
    }

    static func token(for kind: TokenKind) -> String? {
        if let stored = readToken(for: kind), !stored.isEmpty {
            removeLegacyToken(for: kind)
            return stored
        }
        guard let legacy = UserDefaults.standard.string(forKey: kind.legacyDefaultsKey), !legacy.isEmpty else {
            return nil
        }
        writeToken(legacy, for: kind)
        removeLegacyToken(for: kind)
        return legacy
    }

    static func store(accessToken: String, refreshToken: String) {
        writeToken(accessToken, for: .access)
        writeToken(refreshToken, for: .refresh)
        removeLegacyToken(for: .access)
        removeLegacyToken(for: .refresh)
    }

    static func clear() {
        deleteToken(for: .access)
        deleteToken(for: .refresh)
        removeLegacyToken(for: .access)
        removeLegacyToken(for: .refresh)
    }

    private static func baseQuery(for kind: TokenKind) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: kind.account
        ]
    }

    private static func readToken(for kind: TokenKind) -> String? {
        var query = baseQuery(for: kind)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    private static func writeToken(_ token: String, for kind: TokenKind) {
        guard let data = token.data(using: .utf8) else { return }

        let query = baseQuery(for: kind)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var createQuery = query
            attributes.forEach { createQuery[$0.key] = $0.value }
            SecItemAdd(createQuery as CFDictionary, nil)
        }
    }

    private static func deleteToken(for kind: TokenKind) {
        let query = baseQuery(for: kind)
        SecItemDelete(query as CFDictionary)
    }

    private static func removeLegacyToken(for kind: TokenKind) {
        UserDefaults.standard.removeObject(forKey: kind.legacyDefaultsKey)
    }
}

private enum DebugNetworkConfig {
    static let allowInsecureTLS: Bool = {
        #if DEBUG
        #if targetEnvironment(simulator)
        if let raw = Bundle.main.infoDictionary?["ALLOW_INSECURE_SSL"] {
            if let value = raw as? Bool { return value }
            if let value = raw as? String {
                return ["1", "true", "yes"].contains(value.lowercased())
            }
        }
        if let env = ProcessInfo.processInfo.environment["ALLOW_INSECURE_SSL"] {
            return ["1", "true", "yes"].contains(env.lowercased())
        }
        // Default to secure transport; opt-in explicitly when debugging custom certs.
        return false
        #else
        return false
        #endif
        #else
        return false
        #endif
    }()
}

enum NetworkSession {
    private static func makeDefaultSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        // Keep session-level limits above per-request budgets to avoid premature global timeout.
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 45
        return URLSession(configuration: config)
    }

    private static func makeDebugInsecureSession(label: String) -> URLSession? {
        #if DEBUG
        #if targetEnvironment(simulator)
        if DebugNetworkConfig.allowInsecureTLS {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = false
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 45
            print("[NetworkSession] Insecure SSL enabled for simulator debug (\(label)).")
            return URLSession(configuration: config, delegate: InsecureSessionDelegate(), delegateQueue: nil)
        }
        #endif
        #endif
        return nil
    }

    static let shared: URLSession = {
        makeDebugInsecureSession(label: "shared") ?? makeDefaultSession()
    }()

    static let appAPI: URLSession = {
        makeDebugInsecureSession(label: "appAPI") ?? makeDefaultSession()
    }()
}

#if DEBUG
#if targetEnvironment(simulator)
private final class InsecureSessionDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
#endif
#endif

// MARK: - 科学期刊数据模型（主要定义位置）

struct ScienceArticleScoreBreakdown: Codable, Equatable {
    let historyAlignment: Int
    let signalAlignment: Int
    let topicAlignment: Int
    let recency: Int
    let authority: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case historyAlignment = "history_alignment"
        case signalAlignment = "signal_alignment"
        case topicAlignment = "topic_alignment"
        case recency
        case authority
        case total
    }
}

/// 科学文章模型
struct ScienceArticle: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let titleZh: String?
    let summary: String?
    let summaryZh: String?
    let sourceType: String?
    let sourceUrl: String?
    let matchPercentage: Int?
    let category: String?
    let isRecommended: Bool?
    let whyRecommended: String?
    let actionableInsight: String?
    let tags: [String]?
    let createdAt: Date?
    let matchReasons: [String]?
    let scoreBreakdown: ScienceArticleScoreBreakdown?

    init(
        id: String,
        title: String,
        titleZh: String?,
        summary: String?,
        summaryZh: String?,
        sourceType: String?,
        sourceUrl: String?,
        matchPercentage: Int?,
        category: String?,
        isRecommended: Bool?,
        whyRecommended: String?,
        actionableInsight: String?,
        tags: [String]?,
        createdAt: Date?,
        matchReasons: [String]? = nil,
        scoreBreakdown: ScienceArticleScoreBreakdown? = nil
    ) {
        self.id = id
        self.title = title
        self.titleZh = titleZh
        self.summary = summary
        self.summaryZh = summaryZh
        self.sourceType = sourceType
        self.sourceUrl = sourceUrl
        self.matchPercentage = matchPercentage
        self.category = category
        self.isRecommended = isRecommended
        self.whyRecommended = whyRecommended
        self.actionableInsight = actionableInsight
        self.tags = tags
        self.createdAt = createdAt
        self.matchReasons = matchReasons
        self.scoreBreakdown = scoreBreakdown
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, summary, tags
        case titleZh = "title_zh"
        case summaryZh = "summary_zh"
        case sourceType = "source_type"
        case sourceUrl = "source_url"
        case matchPercentage = "match_percentage"
        case category
        case isRecommended = "is_recommended"
        case whyRecommended = "why_recommended"
        case actionableInsight = "actionable_insight"
        case createdAt = "created_at"
        case matchReasons = "match_reasons"
        case scoreBreakdown = "score_breakdown"
    }
}

/// Feed API 响应
struct ScienceFeedResponse: Codable {
    let success: Bool?
    let items: [ScienceArticle]?
    let data: [ScienceArticle]?
    let personalization: FeedPersonalization?
    
    var articles: [ScienceArticle] { items ?? data ?? [] }
}

/// 个性化信息
struct FeedPersonalization: Codable {
    let ready: Bool?
    let message: String?
    let fallback: String?
}

/// Feed 反馈输入
struct FeedFeedbackInput: Codable {
    let contentId: String
    let contentUrl: String?
    let contentTitle: String?
    let source: String?
    let feedbackType: String
    
    enum CodingKeys: String, CodingKey {
        case contentId = "content_id"
        case contentUrl = "content_url"
        case contentTitle = "content_title"
        case source
        case feedbackType = "feedback_type"
    }
}

// MARK: - Daily AI Recommendations

struct DailyAIRecommendationItem: Codable, Equatable, Identifiable {
    let title: String
    let summary: String
    let action: String
    let reason: String?

    var id: String { "\(title)-\(action)" }
}

struct DailyAIRecommendationsRow: Codable {
    let id: String
    let recommendation_date: String
    let recommendations: [DailyAIRecommendationItem]
}

// MARK: - Evidence Models
struct EvidenceItem: Codable, Identifiable {
    let id: UUID
    let type: EvidenceType
    let value: String
    let weight: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case value
        case weight
    }

    init(id: UUID = UUID(), type: EvidenceType, value: String, weight: Double? = nil) {
        self.id = id
        self.type = type
        self.value = value
        self.weight = weight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(EvidenceType.self, forKey: .type)) ?? .bio
        value = (try? container.decode(String.self, forKey: .value)) ?? ""
        weight = try? container.decode(Double.self, forKey: .weight)
        id = UUID()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(value, forKey: .value)
        try container.encodeIfPresent(weight, forKey: .weight)
    }
}

enum EvidenceType: String, Codable {
    case bio
    case science
    case action
}

// MARK: - Supabase 配置 (从 Info.plist 读取，由 xcconfig 注入)
enum SupabaseConfig {
    private static func runtimeString(_ key: String) -> String? {
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
        return nil
    }

    static var url: URL? {
        guard let urlString = runtimeString("SUPABASE_URL") else {
            return nil
        }
        let sanitized = urlString
            .replacingOccurrences(of: "\\", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: sanitized),
              let scheme = url.scheme,
              !scheme.isEmpty,
              url.host != nil else {
            return nil
        }
        return url
    }
    
    static var anonKey: String? {
        guard let key = runtimeString("SUPABASE_ANON_KEY") else {
            return nil
        }
        return key
    }

    static var missingKeys: [String] {
        var keys: [String] = []
        if url == nil {
            keys.append("SUPABASE_URL")
        }
        if anonKey == nil {
            keys.append("SUPABASE_ANON_KEY")
        }
        return keys
    }
}

// MARK: - Supabase Manager
@MainActor
final class SupabaseManager: ObservableObject, SupabaseManaging {
    static let shared = SupabaseManager()

    private static var inquirySessionKey: String?
    private static var hasGeneratedInquiryForSession = false
    let clinicalCompletionCachePrefix = "supabase_clinical_complete_"
    
    @Published var currentUser: AuthUser?
    @Published var isAuthenticated = false
    @Published var isSessionRestored = false
    @Published var isClinicalComplete = false {
        didSet {
            guard oldValue != isClinicalComplete else { return }
            persistClinicalCompletionForCurrentUserIfNeeded()
        }
    }

    enum HabitsBackend {
        case v2
        case legacy
    }
    var habitsBackendCache: HabitsBackend?
    var reminderPreferencesColumnAvailable: Bool?
    private var userHealthDataTableAvailable: Bool?
    
    private init() {
        // 初始化时检查会话
        Task {
            await checkSession()
        }
    }

    private var networkRetryAttempts: Int {
        max(1, runtimeInt(for: "SUPABASE_NETWORK_RETRY_ATTEMPTS", fallback: 2))
    }

    private var networkRetryDelayNanos: UInt64 {
        let millis = max(50, runtimeInt(for: "SUPABASE_NETWORK_RETRY_DELAY_MS", fallback: 400))
        return UInt64(millis) * 1_000_000
    }

    private var networkRetryMaxDelayNanos: UInt64 {
        let millis = max(100, runtimeInt(for: "SUPABASE_NETWORK_RETRY_MAX_DELAY_MS", fallback: 2_000))
        return UInt64(millis) * 1_000_000
    }

    private var networkRetryBackoffMultiplier: Double {
        max(1.1, runtimeDouble(for: "SUPABASE_NETWORK_RETRY_BACKOFF_MULTIPLIER", fallback: 2.0))
    }

    private var networkRetryJitterRatio: Double {
        let ratio = runtimeDouble(for: "SUPABASE_NETWORK_RETRY_JITTER_RATIO", fallback: 0.25)
        return min(0.9, max(0.0, ratio))
    }

    private var supabaseAuthTimeout: TimeInterval {
        max(4, runtimeDouble(for: "SUPABASE_AUTH_TIMEOUT_SEC", fallback: 8))
    }

    private var supabaseRestReadTimeout: TimeInterval {
        max(4, runtimeDouble(for: "SUPABASE_REST_TIMEOUT_READ_SEC", fallback: 8))
    }

    private var supabaseRestWriteTimeout: TimeInterval {
        max(4, runtimeDouble(for: "SUPABASE_REST_TIMEOUT_WRITE_SEC", fallback: 9))
    }

    private var supabaseAppAPITimeout: TimeInterval {
        max(4, runtimeDouble(for: "SUPABASE_APP_API_TIMEOUT_SEC", fallback: 8))
    }

    private var supabaseUploadTimeout: TimeInterval {
        max(6, runtimeDouble(for: "SUPABASE_UPLOAD_TIMEOUT_SEC", fallback: 12))
    }

    private var supabaseHardTimeoutPadding: TimeInterval {
        max(0.5, runtimeDouble(for: "SUPABASE_NETWORK_HARD_TIMEOUT_PADDING_SEC", fallback: 1))
    }
    let cachedAuthUserKey = "supabase_cached_auth_user"

    enum MaxChatMode: String {
        case fast
        case think

        var ragDepth: MaxRAGDepth {
            switch self {
            case .fast: return .lite
            case .think: return .full
            }
        }
    }

    struct TimedTextCache {
        let text: String
        let expiresAt: Date
    }

    struct TimedDashboardCache {
        let data: DashboardData
        let expiresAt: Date
    }

    struct TimedRAGCache {
        let context: MaxRAGContext
        let expiresAt: Date
    }

    struct TimedScientificBlockCache {
        let block: String?
        let expiresAt: Date
    }

    struct TimedProfileCache {
        let profile: ProfileSettings
        let expiresAt: Date
    }

    struct TimedWearableSummaryCache {
        let summary: String?
        let expiresAt: Date
    }

    struct TimedProactiveBriefCache {
        let brief: ProactiveCareBrief
        let expiresAt: Date
    }

    static var inquirySummaryCache: [String: TimedTextCache] = [:]
    static var userContextCache: [String: TimedTextCache] = [:]
    static var dashboardCache: [String: TimedDashboardCache] = [:]
    static var ragContextCache: [String: TimedRAGCache] = [:]
    static var ragContextInFlight: [String: Task<MaxRAGContext, Never>] = [:]
    static var scientificBlockCache: [String: TimedScientificBlockCache] = [:]
    static var profileCache: [String: TimedProfileCache] = [:]
    static var wearableSummaryCache: [String: TimedWearableSummaryCache] = [:]
    static var proactiveBriefCache: [String: TimedProactiveBriefCache] = [:]
    static var appAPIHealthCooldownUntil: [String: Date] = [:]
    static var appAPIFailureCount: Int = 0
    static var appAPICircuitUntil: Date?
    static var appAPICircuitReason: String?
    static var maxChatRemoteFailureCount: Int = 0
    static var maxChatRemoteCooldownUntil: Date?
    private static var proactivePrewarmAt: Date?

    var inquirySummaryCacheTTL: TimeInterval { max(30, runtimeDouble(for: "MAX_INQUIRY_CACHE_TTL_SEC", fallback: 90)) }
    var userContextCacheTTL: TimeInterval { max(30, runtimeDouble(for: "MAX_USER_CONTEXT_CACHE_TTL_SEC", fallback: 120)) }
    var dashboardCacheTTL: TimeInterval { max(30, runtimeDouble(for: "MAX_DASHBOARD_CACHE_TTL_SEC", fallback: 90)) }
    var ragCacheTTL: TimeInterval { max(30, runtimeDouble(for: "MAX_RAG_CACHE_TTL_SEC", fallback: 180)) }
    var scientificBlockCacheTTL: TimeInterval { max(30, runtimeDouble(for: "MAX_SCIENCE_BLOCK_CACHE_TTL_SEC", fallback: 180)) }
    var profileCacheTTL: TimeInterval { max(30, runtimeDouble(for: "MAX_PROFILE_CACHE_TTL_SEC", fallback: 300)) }
    var wearableSummaryCacheTTL: TimeInterval { max(30, runtimeDouble(for: "MAX_WEARABLE_CACHE_TTL_SEC", fallback: 180)) }
    var proactiveBriefCacheTTL: TimeInterval { max(120, runtimeDouble(for: "MAX_PROACTIVE_BRIEF_CACHE_TTL_SEC", fallback: 3_600)) }
    var appAPIHealthCooldownTTL: TimeInterval { max(5, runtimeDouble(for: "APP_API_HEALTH_COOLDOWN_SEC", fallback: 120)) }
    var appAPICircuitTTL: TimeInterval { max(5, runtimeDouble(for: "APP_API_CIRCUIT_TTL_SEC", fallback: 90)) }
    var appAPIFailureThreshold: Int { max(1, runtimeInt(for: "APP_API_FAILURE_THRESHOLD", fallback: 2)) }
    var maxChatRemoteFailureThreshold: Int { max(1, runtimeInt(for: "MAX_CHAT_REMOTE_FAILURE_THRESHOLD", fallback: 2)) }
    var maxChatRemoteCooldownTTL: TimeInterval { max(5, runtimeDouble(for: "MAX_CHAT_REMOTE_COOLDOWN_SEC", fallback: 60)) }
    private var proactivePrewarmDebounceTTL: TimeInterval { max(30, runtimeDouble(for: "MAX_PROACTIVE_PREWARM_DEBOUNCE_SEC", fallback: 300)) }
    private var chatSessionStatsDebounceNanos: UInt64 {
        let millis = max(100, runtimeInt(for: "MAX_CHAT_SESSION_STATS_DEBOUNCE_MS", fallback: 800))
        return UInt64(millis) * 1_000_000
    }
    var maxChatLocalFastTimeout: TimeInterval { max(6, runtimeDouble(for: "MAX_CHAT_LOCAL_TIMEOUT_FAST_SEC", fallback: 12)) }
    var maxChatLocalThinkTimeout: TimeInterval { max(8, runtimeDouble(for: "MAX_CHAT_LOCAL_TIMEOUT_THINK_SEC", fallback: 18)) }
    var maxChatLocalDegradedTimeout: TimeInterval { max(4, runtimeDouble(for: "MAX_CHAT_LOCAL_TIMEOUT_DEGRADED_SEC", fallback: 8)) }
    var maxChatRemoteFastTimeout: TimeInterval { max(4, runtimeDouble(for: "MAX_CHAT_REMOTE_TIMEOUT_FAST_SEC", fallback: 9)) }
    var maxChatRemoteThinkTimeout: TimeInterval { max(6, runtimeDouble(for: "MAX_CHAT_REMOTE_TIMEOUT_THINK_SEC", fallback: 14)) }
    var maxChatRemoteLegacyTimeout: TimeInterval { max(4, runtimeDouble(for: "MAX_CHAT_REMOTE_TIMEOUT_LEGACY_SEC", fallback: 9)) }
    var appAPIHealthProbeTimeout: TimeInterval { max(1, runtimeDouble(for: "APP_API_HEALTH_TIMEOUT_SEC", fallback: 3)) }
    private var bodyMemoryWritesPerSync: Int { max(1, runtimeInt(for: "MAX_MEMORY_BODY_SIGNAL_MAX_WRITES_PER_SYNC", fallback: 4)) }
    private var bodyMemoryHRVLowThreshold: Double { max(10, runtimeDouble(for: "MAX_MEMORY_BODY_SIGNAL_HRV_LOW", fallback: 36)) }
    private var bodyMemoryRHRHighThreshold: Double { max(55, runtimeDouble(for: "MAX_MEMORY_BODY_SIGNAL_RHR_HIGH", fallback: 78)) }
    private var bodyMemorySleepLowThreshold: Double { max(30, runtimeDouble(for: "MAX_MEMORY_BODY_SIGNAL_SLEEP_LOW", fallback: 70)) }
    private var bodyMemoryStepsLowThreshold: Double { max(500, runtimeDouble(for: "MAX_MEMORY_BODY_SIGNAL_STEPS_LOW", fallback: 4000)) }
    private var bodyMemoryStepsGoodThreshold: Double { max(1000, runtimeDouble(for: "MAX_MEMORY_BODY_SIGNAL_STEPS_GOOD", fallback: 9000)) }
    private var pendingChatSessionStatsTasks: [String: Task<Void, Never>] = [:]
    private var chatConversationsSupportsSessionId: Bool?
    private let verboseNetworkLogs: Bool = {
#if DEBUG
        if let env = ProcessInfo.processInfo.environment["SUPABASE_VERBOSE_LOG"] {
            return ["1", "true", "yes"].contains(env.lowercased())
        }
        return false
#else
        return false
#endif
    }()

    private func debugNetworkLog(_ message: @autoclosure () -> String) {
        guard verboseNetworkLogs else { return }
        print(message())
    }

    func runtimeString(for key: String) -> String? {
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

    func runtimeInt(for key: String, fallback: Int) -> Int {
        guard let raw = runtimeString(for: key), let value = Int(raw) else {
            return fallback
        }
        return value
    }

    func runtimeDouble(for key: String, fallback: Double) -> Double {
        guard let raw = runtimeString(for: key), let value = Double(raw) else {
            return fallback
        }
        return value
    }

    enum RequestClass {
        case auth
        case restRead
        case restWrite
        case appAPI
        case upload
    }

    struct SupabaseRequestFailure: LocalizedError {
        let service: String
        let context: String
        let method: String
        let endpoint: String
        let statusCode: Int?
        let requestId: String?
        let reason: String
        let responseSnippet: String?
        let retryable: Bool
        let underlyingDescription: String?

        var errorDescription: String? {
            var summary = "请求失败"
            if let statusCode {
                summary += "（\(statusCode)）"
            }
            summary += "：\(reason)"
            return summary
        }
    }

    func requestTimeout(for requestClass: RequestClass, explicit: TimeInterval? = nil) -> TimeInterval {
        if let explicit {
            return max(2, explicit)
        }
        switch requestClass {
        case .auth:
            return supabaseAuthTimeout
        case .restRead:
            return supabaseRestReadTimeout
        case .restWrite:
            return supabaseRestWriteTimeout
        case .appAPI:
            return supabaseAppAPITimeout
        case .upload:
            return supabaseUploadTimeout
        }
    }

    func hardTimeout(for requestTimeout: TimeInterval) -> TimeInterval {
        max(4, requestTimeout + supabaseHardTimeoutPadding)
    }

    private func retryDelayNanoseconds(for attempt: Int) -> UInt64 {
        let safeAttempt = max(1, attempt)
        let exponent = Double(safeAttempt - 1)
        let base = Double(networkRetryDelayNanos)
        let maxDelay = Double(networkRetryMaxDelayNanos)
        let rawDelay = min(maxDelay, base * pow(networkRetryBackoffMultiplier, exponent))
        let jitterFloor = 1 - networkRetryJitterRatio
        let jitterCeil = 1 + networkRetryJitterRatio
        let jitterFactor = Double.random(in: jitterFloor...jitterCeil)
        let jittered = min(maxDelay, max(base, rawDelay * jitterFactor))
        return UInt64(jittered)
    }

    private func requestServiceName(for request: URLRequest?) -> String {
        guard let path = request?.url?.path.lowercased() else { return "network" }
        if path.contains("/auth/v1/") {
            return "supabase-auth"
        }
        if path.contains("/rest/v1/") {
            return "supabase-rest"
        }
        if path.contains("/storage/v1/") {
            return "supabase-storage"
        }
        if path.contains("/api/") {
            return "app-api"
        }
        return "network"
    }

    private func requestEndpoint(for request: URLRequest?) -> String {
        guard let url = request?.url else { return "unknown-endpoint" }
        if let query = url.query, !query.isEmpty {
            return "\(url.path)?\(query)"
        }
        return url.path
    }

    private func requestMethod(for request: URLRequest?) -> String {
        request?.httpMethod ?? "GET"
    }

    private func headerValue(_ name: String, in response: HTTPURLResponse?) -> String? {
        guard let response else { return nil }
        for (key, value) in response.allHeaderFields {
            guard let headerName = key as? String else { continue }
            if headerName.compare(name, options: .caseInsensitive) == .orderedSame {
                let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    private func requestIdentifier(in response: HTTPURLResponse?) -> String? {
        headerValue("x-request-id", in: response)
            ?? headerValue("x-supabase-request-id", in: response)
            ?? headerValue("cf-ray", in: response)
            ?? headerValue("x-amz-cf-id", in: response)
    }

    private func responseSnippet(from data: Data?, maxLength: Int = 240) -> String? {
        guard let data, !data.isEmpty else { return nil }
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        text = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return nil
        }
        if text.count > maxLength {
            return String(text.prefix(maxLength)) + "…"
        }
        return text
    }

    private func serverReason(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let errorDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = ["error_description", "msg", "message", "error", "hint", "details"]
            for key in keys {
                if let value = errorDict[key] as? String {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        return trimmed
                    }
                }
            }
        }
        return responseSnippet(from: data, maxLength: 160)
    }

    func makeRequestFailure(
        context: String,
        request: URLRequest? = nil,
        response: HTTPURLResponse? = nil,
        data: Data? = nil,
        underlying: Error? = nil,
        fallbackReason: String = "请求失败"
    ) -> SupabaseRequestFailure {
        let reason = serverReason(from: data)
            ?? underlying.map(networkErrorSummary)
            ?? fallbackReason
        let retryable: Bool = {
            if let underlying {
                return isRetriableNetworkError(underlying)
            }
            guard let code = response?.statusCode else { return false }
            return code == 408 || code == 409 || code == 425 || code == 429 || code >= 500
        }()

        return SupabaseRequestFailure(
            service: requestServiceName(for: request),
            context: context,
            method: requestMethod(for: request),
            endpoint: requestEndpoint(for: request),
            statusCode: response?.statusCode,
            requestId: requestIdentifier(in: response),
            reason: reason,
            responseSnippet: responseSnippet(from: data),
            retryable: retryable,
            underlyingDescription: underlying.map(networkErrorSummary)
        )
    }

    func isRetryableRequestError(_ error: Error) -> Bool {
        if let failure = error as? SupabaseRequestFailure {
            return failure.retryable
        }
        return isRetriableNetworkError(error)
    }

    func isPermissionDeniedRequestError(_ error: Error) -> Bool {
        guard let failure = error as? SupabaseRequestFailure else { return false }
        if let code = failure.statusCode, code == 401 || code == 403 {
            return true
        }
        let reason = failure.reason.lowercased()
        let snippet = (failure.responseSnippet ?? "").lowercased()
        let combined = reason + " " + snippet
        if combined.contains("row-level security") || combined.contains("violates row-level security policy") {
            return true
        }
        if combined.contains("permission denied") || combined.contains("insufficient_privilege") {
            return true
        }
        return false
    }

    private func shouldFallbackToLegacyConversationInsert(_ error: Error) -> Bool {
        guard let failure = error as? SupabaseRequestFailure else { return false }
        let reason = failure.reason.lowercased()
        let snippet = (failure.responseSnippet ?? "").lowercased()
        let combined = reason + " " + snippet
        guard combined.contains("session_id") else { return false }
        if combined.contains("schema cache") || combined.contains("does not exist") || combined.contains("column") {
            return true
        }
        return false
    }

    func performDataRequestWithRetry(
        for request: URLRequest,
        session: URLSession = NetworkSession.shared,
        context: String,
        maxAttempts: Int? = nil,
        hardTimeout: TimeInterval? = nil
    ) async throws -> (Data, URLResponse) {
        let attempts = max(1, maxAttempts ?? networkRetryAttempts)
        var lastError: Error = URLError(.unknown)

        for attempt in 1...attempts {
            do {
                if let hardTimeout, hardTimeout > 0 {
                    return try await runWithTimeout(seconds: hardTimeout) {
                        try await session.data(for: request)
                    }
                }
                return try await session.data(for: request)
            } catch {
                lastError = error
                let hardTLSFailure = isHardTLSFailure(error)
                let shouldRetry = attempt < attempts && isRetriableNetworkError(error) && !hardTLSFailure
                print("[NetworkRetry] \(context) attempt \(attempt) failed: \(networkErrorSummary(error))")
                if shouldRetry {
                    let delayNanos = retryDelayNanoseconds(for: attempt)
                    print("[NetworkRetry] \(context) attempt \(attempt) scheduling retry in \(String(format: "%.3f", Double(delayNanos) / 1_000_000_000))s")
                    try? await Task.sleep(nanoseconds: delayNanos)
                    continue
                }
                break
            }
        }

        throw lastError
    }

    func runWithTimeout<T>(
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
            guard let result = try await group.next() else {
                throw URLError(.timedOut)
            }
            group.cancelAll()
            return result
        }
    }

    func isRetriableNetworkError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case URLError.Code.networkConnectionLost.rawValue,
             URLError.Code.notConnectedToInternet.rawValue,
             URLError.Code.timedOut.rawValue,
             URLError.Code.cannotConnectToHost.rawValue,
             URLError.Code.cannotFindHost.rawValue,
             URLError.Code.dnsLookupFailed.rawValue:
            return true
        default:
            return false
        }
    }

    func isHardTLSFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case URLError.Code.secureConnectionFailed.rawValue,
             URLError.Code.serverCertificateUntrusted.rawValue,
             URLError.Code.serverCertificateHasBadDate.rawValue,
             URLError.Code.serverCertificateHasUnknownRoot.rawValue:
            return true
        default:
            break
        }

        if let streamCode = nsError.userInfo["_kCFStreamErrorCodeKey"] as? Int, streamCode == -9816 {
            return true
        }
        return false
    }

    func networkErrorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else {
            return nsError.localizedDescription
        }

        if nsError.code == URLError.Code.secureConnectionFailed.rawValue {
            if let streamCode = nsError.userInfo["_kCFStreamErrorCodeKey"] as? Int, streamCode == -9816 {
                return "TLS closed-no-notify (-9816), peer closed handshake."
            }
            return "TLS secure connection failed (\(nsError.code))."
        }

        return nsError.localizedDescription
    }
    
    // MARK: - API 请求辅助

    func validatedSupabaseConfig() throws -> (url: URL, anonKey: String) {
        guard let url = SupabaseConfig.url, let anonKey = SupabaseConfig.anonKey else {
            throw SupabaseError.missingSupabaseConfiguration(keys: SupabaseConfig.missingKeys)
        }
        return (url, anonKey)
    }

    private func ensureAccessToken() async throws -> String {
        if let token = SupabaseCredentialStore.token(for: .access), !token.isEmpty {
            return token
        }

        try await refreshSession()
        guard let refreshed = SupabaseCredentialStore.token(for: .access), !refreshed.isEmpty else {
            throw SupabaseError.notAuthenticated
        }
        return refreshed
    }

    private func buildRestURL(endpoint: String) -> URL? {
        guard let baseURL = SupabaseConfig.url else {
            return nil
        }
        var endpointPath = endpoint
        var query: String?

        if let queryIndex = endpoint.firstIndex(of: "?") {
            endpointPath = String(endpoint[..<queryIndex])
            let nextIndex = endpoint.index(after: queryIndex)
            query = nextIndex < endpoint.endIndex ? String(endpoint[nextIndex...]) : nil
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path ?? ""
        let trimmedBasePath = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let trimmedEndpointPath = endpointPath.hasPrefix("/") ? String(endpointPath.dropFirst()) : endpointPath
        components?.path = "\(trimmedBasePath)/rest/v1/\(trimmedEndpointPath)"
        if let query {
            components?.percentEncodedQuery = sanitizePercentEncodedQuery(query)
        }
        return components?.url
    }

    private func sanitizePercentEncodedQuery(_ query: String) -> String {
        // URLComponents.percentEncodedQuery requires all '%' to be valid percent escapes.
        var output = ""
        let characters = Array(query)
        var index = 0
        while index < characters.count {
            let char = characters[index]
            if char == "%" {
                if index + 2 < characters.count,
                   isHexDigit(characters[index + 1]),
                   isHexDigit(characters[index + 2]) {
                    output.append(char)
                    output.append(characters[index + 1])
                    output.append(characters[index + 2])
                    index += 3
                    continue
                }
                output.append("%25")
                index += 1
                continue
            }
            if char == " " {
                output.append("%20")
                index += 1
                continue
            }
            output.append(char)
            index += 1
        }
        return output
    }

    private func isHexDigit(_ char: Character) -> Bool {
        return ("0"..."9").contains(char) || ("a"..."f").contains(char) || ("A"..."F").contains(char)
    }
    
    func request<T: Decodable>(
        _ endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        prefer: String? = nil
    ) async throws -> T {
        let token = try await ensureAccessToken()
        let config = try validatedSupabaseConfig()
        
        guard let url = buildRestURL(endpoint: endpoint) else {
            throw makeRequestFailure(
                context: "Supabase REST invalid endpoint",
                fallbackReason: "无效接口路径"
            )
        }
        debugNetworkLog("[SupabaseManager.request] URL: \(url.absoluteString)")
        debugNetworkLog("[SupabaseManager.request] Method: \(method)")
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout(for: method == "GET" ? .restRead : .restWrite)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer = prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        } else if method != "GET" {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await performDataRequestWithRetry(
            for: request,
            context: "Supabase REST \(method) \(endpoint)"
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            debugNetworkLog("[SupabaseManager.request] Status: \(httpResponse.statusCode)")
            if let responseStr = String(data: data, encoding: .utf8) {
                debugNetworkLog("[SupabaseManager.request] Response: \(responseStr.prefix(500))")
            }
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await refreshSession()
            let retryToken = try await ensureAccessToken()
            var retryRequest = request
            retryRequest.setValue("Bearer \(retryToken)", forHTTPHeaderField: "Authorization")
            let (retryData, retryResponse) = try await performDataRequestWithRetry(
                for: retryRequest,
                context: "Supabase REST retry \(method) \(endpoint)"
            )
            guard let retryHttp = retryResponse as? HTTPURLResponse, (200...299).contains(retryHttp.statusCode) else {
                throw makeRequestFailure(
                    context: "Supabase REST retry status failure",
                    request: retryRequest,
                    response: retryResponse as? HTTPURLResponse,
                    data: retryData
                )
            }
            return try JSONDecoder().decode(T.self, from: retryData)
        }

        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw makeRequestFailure(
                context: "Supabase REST status failure",
                request: request,
                response: response as? HTTPURLResponse,
                data: data
            )
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    func requestVoid(
        _ endpoint: String,
        method: String = "POST",
        body: Encodable? = nil,
        prefer: String? = nil
    ) async throws {
        let token = try await ensureAccessToken()
        let config = try validatedSupabaseConfig()

        guard let url = buildRestURL(endpoint: endpoint) else {
            throw makeRequestFailure(
                context: "Supabase requestVoid invalid endpoint",
                fallbackReason: "无效接口路径"
            )
        }
        debugNetworkLog("[SupabaseManager.requestVoid] URL: \(url.absoluteString)")
        debugNetworkLog("[SupabaseManager.requestVoid] Method: \(method)")
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout(for: method == "GET" ? .restRead : .restWrite)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer = prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        } else if method != "GET" {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }

        if let body = body {
            let bodyData = try JSONEncoder().encode(body)
            request.httpBody = bodyData
            if let bodyStr = String(data: bodyData, encoding: .utf8) {
                debugNetworkLog("[SupabaseManager.requestVoid] Body: \(bodyStr)")
            }
        }

        let (data, response) = try await performDataRequestWithRetry(
            for: request,
            context: "Supabase requestVoid \(method) \(endpoint)",
            hardTimeout: hardTimeout(for: request.timeoutInterval)
        )
        
        if let httpResponse = response as? HTTPURLResponse {
            debugNetworkLog("[SupabaseManager.requestVoid] Status: \(httpResponse.statusCode)")
            if let responseStr = String(data: data, encoding: .utf8), !responseStr.isEmpty {
                debugNetworkLog("[SupabaseManager.requestVoid] Response: \(responseStr.prefix(500))")
            }
        }
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 401 {
            try await refreshSession()
            let retryToken = try await ensureAccessToken()
            var retryRequest = request
            retryRequest.setValue("Bearer \(retryToken)", forHTTPHeaderField: "Authorization")
            let (_, retryResponse) = try await performDataRequestWithRetry(
                for: retryRequest,
                context: "Supabase requestVoid retry \(method) \(endpoint)",
                hardTimeout: hardTimeout(for: retryRequest.timeoutInterval)
            )
            guard let retryHttp = retryResponse as? HTTPURLResponse, (200...299).contains(retryHttp.statusCode) else {
                throw makeRequestFailure(
                    context: "Supabase requestVoid retry status failure",
                    request: retryRequest,
                    response: retryResponse as? HTTPURLResponse
                )
            }
            return
        }
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw makeRequestFailure(
                context: "Supabase requestVoid status failure",
                request: request,
                response: response as? HTTPURLResponse,
                data: data
            )
        }
    }
    
    // MARK: - Chat API Methods (对话管理)

    private struct ChatConversationRow: Codable {
        let id: FlexibleId
        let user_id: String?
        let role: String
        let content: String
        let session_id: String?
        let created_at: String?
    }

    private struct ChatConversationInsert: Encodable {
        let user_id: String
        let role: String
        let content: String
        let session_id: String?
    }

    private struct ChatSessionRow: Codable {
        let id: FlexibleId
        let user_id: String
        let title: String?
        let summary: String?
        let message_count: Int?
        let last_message_at: String?
        let created_at: String?
        let updated_at: String?
    }

    private struct ChatSessionInsert: Encodable {
        let user_id: String
        let title: String?
    }

    private struct ChatSessionUpdate: Encodable {
        let last_message_at: String
        let message_count: Int?

        enum CodingKeys: String, CodingKey {
            case last_message_at
            case message_count
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(last_message_at, forKey: .last_message_at)
            if let message_count {
                try container.encode(message_count, forKey: .message_count)
            }
        }
    }
    
    /// 获取所有对话列表（优先 chat_sessions）
    func getConversations() async throws -> [Conversation] {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        do {
            let endpoint = "chat_sessions?user_id=eq.\(user.id)&select=*&order=updated_at.desc.nullsfirst"
            let sessions: [ChatSessionRow] = try await request(endpoint)
            if !sessions.isEmpty {
                return sessions.map { session in
                    Conversation(
                        id: session.id.value,
                        user_id: session.user_id,
                        title: session.title ?? "新对话",
                        last_message_at: session.last_message_at ?? session.updated_at,
                        message_count: session.message_count,
                        created_at: session.created_at
                    )
                }
            }
        } catch {
            do {
                let endpoint = "chat_sessions?user_id=eq.\(user.id)&select=*&order=created_at.desc.nullsfirst"
                let sessions: [ChatSessionRow] = try await request(endpoint)
                if !sessions.isEmpty {
                    return sessions.map { session in
                        Conversation(
                            id: session.id.value,
                            user_id: session.user_id,
                            title: session.title ?? "新对话",
                            last_message_at: session.last_message_at ?? session.created_at,
                            message_count: session.message_count,
                            created_at: session.created_at
                        )
                    }
                }
            } catch {
                // fall through
            }
        }
        return try await getChatConversationsFallback(userId: user.id)
    }
    
    /// 创建新对话（优先 chat_sessions）
    func createConversation(title: String = "新对话") async throws -> Conversation {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let body = ChatSessionInsert(user_id: user.id, title: title)
        let endpoint = "chat_sessions"
        let results: [ChatSessionRow] = try await request(endpoint, method: "POST", body: body, prefer: "return=representation")
        guard let session = results.first else {
            throw makeRequestFailure(
                context: "createConversation empty response",
                fallbackReason: "创建会话失败：服务端未返回会话数据"
            )
        }
        return Conversation(
            id: session.id.value,
            user_id: session.user_id,
            title: session.title ?? title,
            last_message_at: session.last_message_at,
            message_count: session.message_count,
            created_at: session.created_at
        )
    }
    
    /// 获取对话历史消息（chat_conversations）
    func getChatHistory(conversationId: String) async throws -> [ChatMessageDTO] {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        if isUUID(conversationId) {
            let endpoint = "chat_conversations?user_id=eq.\(user.id)&session_id=eq.\(conversationId)&select=*&order=created_at.asc"
            let rows: [ChatConversationRow] = try await request(endpoint)
            return rows.map { row in
                ChatMessageDTO(
                    id: row.id.value,
                    conversation_id: conversationId,
                    role: row.role,
                    content: row.content,
                    created_at: row.created_at
                )
            }
        }

        let endpoint = "chat_conversations?user_id=eq.\(user.id)&session_id=is.null&select=*&order=created_at.asc"
        let rows: [ChatConversationRow] = try await request(endpoint)
        return rows.map { row in
            ChatMessageDTO(
                id: row.id.value,
                conversation_id: conversationId,
                role: row.role,
                content: row.content,
                created_at: row.created_at
            )
        }
    }
    
    /// 追加消息到对话（chat_conversations）
    func appendMessage(conversationId: String, role: String, content: String) async throws -> ChatMessageDTO {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        let endpoint = "chat_conversations"
        let usesSessionId = isUUID(conversationId)
        let shouldTrySessionInsert = usesSessionId && (chatConversationsSupportsSessionId ?? true)

        if shouldTrySessionInsert {
            do {
                let body = ChatConversationInsert(
                    user_id: user.id,
                    role: role,
                    content: content,
                    session_id: conversationId
                )
                let results: [ChatConversationRow] = try await request(
                    endpoint,
                    method: "POST",
                    body: body,
                    prefer: "return=representation"
                )
                guard let row = results.first else {
                    throw makeRequestFailure(
                        context: "appendMessage empty response (session)",
                        fallbackReason: "消息写入失败：未返回消息记录"
                    )
                }
                chatConversationsSupportsSessionId = true
                scheduleChatSessionStatsUpdate(sessionId: conversationId)
                return ChatMessageDTO(
                    id: row.id.value,
                    conversation_id: conversationId,
                    role: row.role,
                    content: row.content,
                    created_at: row.created_at
                )
            } catch {
                if shouldFallbackToLegacyConversationInsert(error) {
                    chatConversationsSupportsSessionId = false
                    print("[ChatConversation] ⚠️ session_id unavailable, fallback to legacy insert")
                } else {
                    throw error
                }
            }
        }

        let body = ChatConversationInsert(user_id: user.id, role: role, content: content, session_id: nil)
        let results: [ChatConversationRow] = try await request(
            endpoint,
            method: "POST",
            body: body,
            prefer: "return=representation"
        )
        guard let row = results.first else {
            throw makeRequestFailure(
                context: "appendMessage empty response (legacy)",
                fallbackReason: "消息写入失败：未返回消息记录"
            )
        }
        if usesSessionId {
            scheduleChatSessionStatsUpdate(sessionId: conversationId)
        }
        return ChatMessageDTO(
            id: row.id.value,
            conversation_id: conversationId,
            role: row.role,
            content: row.content,
            created_at: row.created_at
        )
    }

    func appendMessagesBatch(
        conversationId: String,
        messages: [(role: String, content: String)]
    ) async throws -> [ChatMessageDTO] {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        guard isUUID(conversationId), !messages.isEmpty else { return [] }

        let endpoint = "chat_conversations"
        if chatConversationsSupportsSessionId ?? true {
            let body = messages.map { item in
                ChatConversationInsert(
                    user_id: user.id,
                    role: item.role,
                    content: item.content,
                    session_id: conversationId
                )
            }
            do {
                let rows: [ChatConversationRow] = try await request(
                    endpoint,
                    method: "POST",
                    body: body,
                    prefer: "return=representation"
                )
                chatConversationsSupportsSessionId = true
                scheduleChatSessionStatsUpdate(sessionId: conversationId)
                return rows.map { row in
                    ChatMessageDTO(
                        id: row.id.value,
                        conversation_id: conversationId,
                        role: row.role,
                        content: row.content,
                        created_at: row.created_at
                    )
                }
            } catch {
                if shouldFallbackToLegacyConversationInsert(error) {
                    chatConversationsSupportsSessionId = false
                    print("[ChatConversation] ⚠️ session_id unavailable, fallback to legacy batch insert")
                } else {
                    throw error
                }
            }
        }

        let legacyBody = messages.map { item in
            ChatConversationInsert(
                user_id: user.id,
                role: item.role,
                content: item.content,
                session_id: nil
            )
        }
        let rows: [ChatConversationRow] = try await request(
            endpoint,
            method: "POST",
            body: legacyBody,
            prefer: "return=representation"
        )
        scheduleChatSessionStatsUpdate(sessionId: conversationId)
        return rows.map { row in
            ChatMessageDTO(
                id: row.id.value,
                conversation_id: conversationId,
                role: row.role,
                content: row.content,
                created_at: row.created_at
            )
        }
    }
    
    /// 删除对话
    func deleteConversation(conversationId: String) async throws {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        if isUUID(conversationId) {
            let messagesEndpoint = "chat_conversations?user_id=eq.\(user.id)&session_id=eq.\(conversationId)"
            try await requestVoid(messagesEndpoint, method: "DELETE")
            let sessionEndpoint = "chat_sessions?id=eq.\(conversationId)"
            try await requestVoid(sessionEndpoint, method: "DELETE")
        }
    }

    private func getChatConversationsFallback(userId: String) async throws -> [Conversation] {
        let rows: [ChatConversationRow]
        do {
            let endpoint = "chat_conversations?user_id=eq.\(userId)&select=id,user_id,session_id,role,content,created_at&order=created_at.desc&limit=200"
            rows = try await request(endpoint)
        } catch {
            let endpoint = "chat_conversations?user_id=eq.\(userId)&select=id,user_id,role,content,created_at&order=created_at.desc&limit=200"
            rows = try await request(endpoint)
        }
        if rows.isEmpty {
            return []
        }

        var seen: Set<String> = []
        var conversations: [Conversation] = []
        let formatter = ISO8601DateFormatter()

        for row in rows {
            let sessionId = row.session_id ?? "default"
            guard !seen.contains(sessionId) else { continue }
            seen.insert(sessionId)

            let title = row.role == "user" ? String(row.content.prefix(20)) : "新对话"
            let lastMessageAt = row.created_at
            let createdAt = row.created_at ?? formatter.string(from: Date())

            conversations.append(
                Conversation(
                    id: sessionId,
                    user_id: row.user_id ?? userId,
                    title: title.isEmpty ? "新对话" : title,
                    last_message_at: lastMessageAt,
                    message_count: nil,
                    created_at: createdAt
                )
            )
        }

        return conversations
    }

    private func updateChatSessionStats(sessionId: String) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let body = ChatSessionUpdate(last_message_at: now, message_count: nil)
        let endpoint = "chat_sessions?id=eq.\(sessionId)"
        try await requestVoid(endpoint, method: "PATCH", body: body)
    }

    private func scheduleChatSessionStatsUpdate(sessionId: String) {
        pendingChatSessionStatsTasks[sessionId]?.cancel()
        pendingChatSessionStatsTasks[sessionId] = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: chatSessionStatsDebounceNanos)
            if Task.isCancelled { return }
            do {
                try await self.updateChatSessionStats(sessionId: sessionId)
            } catch {
                print("[ChatSession] stats update failed: \(error.localizedDescription)")
            }
            self.pendingChatSessionStatsTasks.removeValue(forKey: sessionId)
        }
    }
    
    // MARK: - Dashboard API Methods
    
    /// 获取最近 7 天的健康日志
    func getWeeklyWellnessLogs() async throws -> [WellnessLog] {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: sevenDaysAgo)
        
        let endpoint = "daily_wellness_logs?user_id=eq.\(user.id)&log_date=gte.\(dateString)&select=*&order=log_date.desc"
        return try await request(endpoint)
    }

    /// 获取最近 30 天的健康日志
    func getMonthlyWellnessLogs() async throws -> [WellnessLog] {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: thirtyDaysAgo)

        let endpoint = "daily_wellness_logs?user_id=eq.\(user.id)&log_date=gte.\(dateString)&select=*&order=log_date.desc"
        return try await request(endpoint)
    }

    private struct FlexibleDouble: Codable {
        let value: Double

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let doubleValue = try? container.decode(Double.self) {
                value = doubleValue
            } else if let intValue = try? container.decode(Int.self) {
                value = Double(intValue)
            } else if let stringValue = try? container.decode(String.self), let parsed = Double(stringValue) {
                value = parsed
            } else {
                value = 0
            }
        }
    }

    private struct DigitalTwinProfileRow: Codable {
        let id: String
        let inferred_scale_scores: [String: FlexibleDouble]?
        let age: Int?
        let gender: String?
        let full_name: String?
        let primary_goal: String?
        let created_at: String?
    }

    private func loadDigitalTwinLocalInput() async throws -> DigitalTwinLocalInput {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let profileEndpoint = "profiles?id=eq.\(user.id)&select=id,inferred_scale_scores,age,gender,full_name,primary_goal,created_at&limit=1"
        async let profileRowsTask: [DigitalTwinProfileRow] = (try? await request(profileEndpoint)) ?? []
        async let logsTask = getMonthlyWellnessLogs()
        async let inquiryTask = fetchDigitalTwinInquiryInsights(userId: user.id)
        async let conversationTask = fetchDigitalTwinConversationSummary(userId: user.id)

        let profileRows = await profileRowsTask
        let profileRow = profileRows.first

        let scores = profileRow?.inferred_scale_scores
        let gad7 = Int(scores?["gad7"]?.value ?? 0)
        let phq9 = Int(scores?["phq9"]?.value ?? 0)
        let isi = Int(scores?["isi"]?.value ?? 0)
        let pss10 = Int(scores?["pss10"]?.value ?? 0)
        let baseline: BaselineScores? = (gad7 + phq9 + isi + pss10) > 0
            ? BaselineScores(gad7: gad7, phq9: phq9, isi: isi, pss10: pss10)
            : nil

        let logs = (try? await logsTask) ?? []
        async let calibrationsTask = fetchDigitalTwinCalibrations(userId: user.id, logs: logs)
        let inquiryInsights = await inquiryTask
        let conversationSummary = await conversationTask
        let calibrations = await calibrationsTask
        let registrationDate = profileRow?.created_at ?? ISO8601DateFormatter().string(from: Date())
        let profile = ProfileSnapshot(
            age: profileRow?.age,
            gender: profileRow?.gender,
            primaryGoal: profileRow?.primary_goal,
            registrationDate: registrationDate,
            fullName: profileRow?.full_name
        )

        return DigitalTwinLocalInput(
            userId: user.id,
            baselineScores: baseline,
            logs: logs,
            calibrations: calibrations,
            inquiryInsights: inquiryInsights,
            conversationSummary: conversationSummary,
            profile: profile,
            now: Date()
        )
    }

    private func fetchDigitalTwinCalibrations(userId: String, logs: [WellnessLog]) async -> [CalibrationData] {
        struct CalibrationRow: Codable {
            let date: String
            let sleep_hours: Double?
            let stress_level: Int?
            let exercise_duration: Int?
            let meal_quality: String?
            let mood_score: Int?
            let water_intake: String?
        }

        let endpoint = "daily_calibrations?user_id=eq.\(userId)&select=date,sleep_hours,stress_level,exercise_duration,meal_quality,mood_score,water_intake&order=date.asc&limit=60"
        let rows: [CalibrationRow] = (try? await request(endpoint)) ?? []

        if !rows.isEmpty {
            return rows.map { row in
                let sleepHours = row.sleep_hours ?? 0
                let sleepQuality = sleepQualityFromHours(sleepHours)
                let mood = normalizeTo10(row.mood_score)
                let stress = normalizeTo10(row.stress_level)
                let energy = estimateEnergyLevel(mood: mood, stress: stress, exercise: row.exercise_duration)
                return CalibrationData(
                    date: row.date,
                    sleepHours: sleepHours,
                    sleepQuality: sleepQuality,
                    moodScore: mood,
                    stressLevel: stress,
                    energyLevel: energy,
                    restingHeartRate: nil,
                    hrv: nil,
                    stepCount: nil,
                    deviceSleepScore: nil,
                    activityScore: nil
                )
            }
        }

        let sortedLogs = logs.sorted { $0.log_date < $1.log_date }
        return sortedLogs.map { log in
            let sleepHours = log.sleepHours
            let sleepQuality = sleepQualityFromLog(log, fallbackHours: sleepHours)
            let mood = moodScoreFromLog(log)
            let stress = normalizeTo10(log.stress_level)
            let energy = log.energy_level ?? log.morning_energy ?? estimateEnergyLevel(mood: mood, stress: stress, exercise: log.exercise_duration_minutes)
            return CalibrationData(
                date: log.log_date,
                sleepHours: sleepHours,
                sleepQuality: sleepQuality,
                moodScore: mood,
                stressLevel: stress,
                energyLevel: normalizeTo10(Int?(energy)),
                restingHeartRate: nil,
                hrv: nil,
                stepCount: nil,
                deviceSleepScore: nil,
                activityScore: nil
            )
        }
    }

    private func fetchDigitalTwinInquiryInsights(userId: String) async -> [InquiryInsight] {
        struct InquiryRow: Codable {
            let question_text: String?
            let question_type: String?
            let user_response: String?
            let data_gaps_addressed: [String]?
            let created_at: String?
            let responded_at: String?
        }

        let endpoint = "inquiry_history?user_id=eq.\(userId)&select=question_text,question_type,user_response,data_gaps_addressed,created_at,responded_at&order=created_at.desc&limit=10"
        let rows: [InquiryRow] = (try? await request(endpoint)) ?? []

        return rows.compactMap { row in
            guard let response = row.user_response, !response.isEmpty else { return nil }
            let date = row.responded_at ?? row.created_at ?? isoDate(Date())
            var indicators: [String: CodableValue] = [:]
            if let gaps = row.data_gaps_addressed {
                for gap in gaps {
                    indicators[gap] = .string(response)
                }
            }
            if indicators.isEmpty, let question = row.question_text {
                indicators["question"] = .string(question)
            }
            return InquiryInsight(
                date: date,
                topic: row.question_type ?? "general",
                userResponse: response,
                extractedIndicators: indicators
            )
        }
    }

    private func fetchDigitalTwinConversationSummary(userId: String) async -> ConversationSummary {
        struct ConversationRow: Codable {
            let role: String?
            let content: String?
            let created_at: String?
        }

        let endpoint = "chat_conversations?user_id=eq.\(userId)&select=role,content,created_at&order=created_at.desc&limit=100"
        let rows: [ConversationRow] = (try? await request(endpoint)) ?? []

        let total = rows.count
        let lastInteraction = rows.first?.created_at ?? isoDate(Date())
        let userMessages = rows.filter { ($0.role ?? "") == "user" }

        let negativeKeywords = ["焦虑", "压力", "紧张", "恐慌", "失眠", "难受", "崩溃", "panic", "anxiety", "stress"]
        let positiveKeywords = ["好转", "改善", "平静", "放松", "舒服", "稳定", "开心", "进步", "calm", "better"]

        var score = 0
        var topicCounts: [String: Int] = [:]
        let topicKeywords: [String: [String]] = [
            "睡眠": ["睡眠", "失眠", "睡不着", "sleep"],
            "压力": ["压力", "紧张", "stress"],
            "焦虑": ["焦虑", "恐慌", "anxiety"],
            "能量": ["能量", "精力", "疲劳", "energy"],
            "运动": ["运动", "锻炼", "exercise"],
            "饮食": ["饮食", "吃", "diet"]
        ]

        for message in userMessages {
            let content = message.content?.lowercased() ?? ""
            for keyword in negativeKeywords where content.contains(keyword) {
                score += 1
            }
            for keyword in positiveKeywords where content.contains(keyword) {
                score -= 1
            }
            for (topic, keywords) in topicKeywords {
                if keywords.contains(where: { content.contains($0) }) {
                    topicCounts[topic, default: 0] += 1
                }
            }
        }

        let emotionalTrend: String
        if score >= 2 {
            emotionalTrend = "declining"
        } else if score <= -2 {
            emotionalTrend = "improving"
        } else {
            emotionalTrend = "stable"
        }

        let frequentTopics = topicCounts
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key }

        return ConversationSummary(
            totalMessages: total,
            emotionalTrend: emotionalTrend,
            frequentTopics: frequentTopics,
            lastInteraction: lastInteraction
        )
    }

    private func moodScoreFromLog(_ log: WellnessLog) -> Int {
        if let mood = log.mood_status?.lowercased() {
            switch mood {
            case "great", "excellent": return 9
            case "good": return 7
            case "okay", "neutral": return 5
            case "bad", "poor": return 3
            case "terrible": return 1
            default: break
            }
        }
        if let anxiety = log.anxiety_level {
            return max(0, 10 - anxiety)
        }
        return 5
    }

    private func sleepQualityFromLog(_ log: WellnessLog, fallbackHours: Double) -> Int {
        if let qualityString = log.sleep_quality {
            if let quality = Int(qualityString) {
                return normalizeTo10(quality)
            }
            switch qualityString.lowercased() {
            case "poor", "bad": return 3
            case "okay", "neutral": return 5
            case "good": return 7
            case "great", "excellent": return 9
            default: break
            }
        }
        return sleepQualityFromHours(fallbackHours)
    }

    private func sleepQualityFromHours(_ hours: Double) -> Int {
        if hours <= 0 { return 0 }
        if hours >= 7 && hours <= 9 { return 10 }
        if hours < 7 {
            let penalty = Int(round((7 - hours) * 2))
            return max(0, 10 - penalty)
        }
        let penalty = Int(round((hours - 9) * 1.5))
        return max(0, 10 - penalty)
    }

    private func estimateEnergyLevel(mood: Int?, stress: Int?, exercise: Int?) -> Int {
        var energy = 5.0
        if let mood {
            energy += Double(mood - 5) * 0.6
        }
        if let stress {
            energy -= Double(stress - 5) * 0.5
        }
        if let exercise, exercise > 0 {
            energy += min(3.0, Double(exercise) / 30.0)
        }
        return normalizeTo10(energy)
    }

    private func normalizeTo10(_ value: Int?) -> Int {
        guard let value else { return 0 }
        if value <= 10 { return max(0, value) }
        if value <= 100 { return max(0, min(10, value / 10)) }
        return 10
    }

    private func normalizeTo10(_ value: Double) -> Int {
        if value <= 10 { return max(0, min(10, Int(round(value)))) }
        if value <= 100 { return max(0, min(10, Int(round(value / 10)))) }
        return 10
    }

    private func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
    
    /// 获取最新的数字孪生分析结果
    func getDigitalTwinAnalysis() async throws -> DigitalTwinAnalysis? {
        let input = try await loadDigitalTwinLocalInput()
        return DigitalTwinLocalEngine.analysis(input: input)
    }

    /// 获取分析历史
    func getAnalysisHistory(limit: Int = 10) async throws -> [AnalysisHistoryRecord] {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let endpoint = "analysis_history?user_id=eq.\(user.id)&select=*&order=created_at.desc&limit=\(max(1, limit))"
        return try await request(endpoint)
    }
    
    /// 获取用户统一画像
    func getUnifiedProfile() async throws -> UnifiedProfile? {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        
        let endpoint = "unified_user_profiles?user_id=eq.\(user.id)&select=*&limit=1"
        let results: [UnifiedProfile] = try await request(endpoint)
        return results.first
    }
    
    /// 获取穿戴设备健康数据
    func getHardwareData() async throws -> HardwareData? {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        if userHealthDataTableAvailable == false { return nil }
        
        let endpoint = "user_health_data?user_id=eq.\(user.id)&select=data_type,value,source,recorded_at&order=recorded_at.desc&limit=20"
        
        struct RawHealthData: Codable {
            let data_type: String
            let value: Double
            let source: String?
            let recorded_at: String
        }
        
        let rawData: [RawHealthData]
        do {
            rawData = try await request(endpoint)
        } catch {
            userHealthDataTableAvailable = false
            print("[SupabaseManager] ⚠️ user_health_data unavailable: \(error)")
            return nil
        }
        
        if rawData.isEmpty { return nil }
        
        var hardware = HardwareData()
        
        for item in rawData {
            let point = HardwareDataPoint(value: item.value, source: item.source, recorded_at: item.recorded_at)
            switch item.data_type {
            case "hrv" where hardware.hrv == nil:
                hardware.hrv = point
            case "resting_heart_rate" where hardware.resting_heart_rate == nil:
                hardware.resting_heart_rate = point
            case "sleep_score" where hardware.sleep_score == nil:
                hardware.sleep_score = point
            case "steps" where hardware.steps == nil:
                hardware.steps = point
            case "spo2" where hardware.spo2 == nil:
                hardware.spo2 = point
            default:
                break
            }
        }
        
        return hardware
    }

    func isUserHealthDataAvailable() -> Bool {
        userHealthDataTableAvailable != false
    }

    // MARK: - Wearable Ingestion Contract (Apple Watch / HealthKit only)

    private struct UserHealthDataInsertRow: Encodable {
        let user_id: String
        let data_type: String
        let value: Double
        let source: String
        let recorded_at: String
    }

    private struct UnifiedProfileWearablePatch: Encodable {
        let ai_inferred_traits: [String: String]
        let last_aggregated_at: String
    }

    private struct DerivedBodyMemoryCandidate {
        let content: String
        let metadata: [String: Any]
    }

    /// Apple Watch/HealthKit 数据入链：持久化 -> 用户画像增强。
    /// 注意：仅允许 Apple Watch / HealthKit 数据源，避免引入未验证设备。
    func syncAppleWatchDataPipeline(_ bundle: AppleWatchIngestionBundle) async throws {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        guard bundle.hasPayload else { return }
        guard isAppleWatchSource(bundle.source) else {
            print("[SupabaseManager] Skip wearable sync for unsupported source: \(bundle.source)")
            return
        }

        let rows = bundle.snapshots.map { snapshot in
            UserHealthDataInsertRow(
                user_id: user.id,
                data_type: snapshot.metricType,
                value: snapshot.value,
                source: snapshot.source,
                recorded_at: snapshot.recordedAt
            )
        }

        do {
            try await requestVoid(
                "user_health_data",
                method: "POST",
                body: rows,
                prefer: "return=minimal"
            )
            userHealthDataTableAvailable = true
        } catch {
            print("[SupabaseManager] ⚠️ wearable data persistence failed: \(error)")
            throw error
        }

        try? await syncWearableTraitsToUnifiedProfile(userId: user.id, bundle: bundle)
        await captureWearableDerivedMemories(userId: user.id, bundle: bundle)
        Self.wearableSummaryCache.removeValue(forKey: user.id)
        let sampleSummary = bundle.snapshots.prefix(4).map { snapshot in
            "\(snapshot.metricType)=\(String(format: "%.1f", snapshot.value))"
        }.joined(separator: ", ")
        await captureUserSignal(
            domain: "wearable",
            action: "synced_apple_watch",
            summary: sampleSummary.isEmpty
                ? "apple_watch sync completed"
                : "apple_watch sync: \(sampleSummary)",
            metadata: [
                "source": bundle.source,
                "snapshot_count": bundle.snapshots.count
            ]
        )
    }

    func buildWearableRAGSummary() async -> String? {
        guard let user = currentUser else { return nil }
        if let cached = Self.wearableSummaryCache[user.id], cached.expiresAt > Date() {
            return cached.summary
        }

        let hardware = (try? await getHardwareData()) ?? nil
        var parts: [String] = []
        if let hrv = hardware?.hrv?.value {
            parts.append("HRV \(Int(hrv.rounded()))")
        }
        if let rhr = hardware?.resting_heart_rate?.value {
            parts.append("静息心率 \(Int(rhr.rounded()))")
        }
        if let steps = hardware?.steps?.value {
            parts.append("步数 \(Int(steps.rounded()))")
        }
        if let sleepScore = hardware?.sleep_score?.value {
            parts.append("睡眠评分 \(Int(sleepScore.rounded()))")
        }
        let summary = parts.isEmpty ? nil : "Apple Watch/HealthKit 最近指标: \(parts.joined(separator: "，"))"
        Self.wearableSummaryCache[user.id] = TimedWearableSummaryCache(
            summary: summary,
            expiresAt: Date().addingTimeInterval(wearableSummaryCacheTTL)
        )
        return summary
    }

    private func captureWearableDerivedMemories(userId: String, bundle: AppleWatchIngestionBundle) async {
        let candidates = buildWearableDerivedMemoryCandidates(bundle: bundle)
        guard !candidates.isEmpty else { return }
        for candidate in candidates.prefix(bodyMemoryWritesPerSync) {
            _ = await MaxMemoryService.storeSensorDerivedMemory(
                userId: userId,
                content: candidate.content,
                metadata: candidate.metadata
            )
        }
    }

    private func buildWearableDerivedMemoryCandidates(bundle: AppleWatchIngestionBundle) -> [DerivedBodyMemoryCandidate] {
        let hrv = latestValue(in: bundle.snapshots, metricType: "hrv")
        let rhr = latestValue(in: bundle.snapshots, metricType: "resting_heart_rate")
        let steps = latestValue(in: bundle.snapshots, metricType: "steps")
        let sleepScore = latestValue(in: bundle.snapshots, metricType: "sleep_score")

        var candidates: [DerivedBodyMemoryCandidate] = []

        var summaryParts: [String] = []
        if let hrv { summaryParts.append("HRV \(Int(hrv.rounded())) ms") }
        if let rhr { summaryParts.append("resting heart rate \(Int(rhr.rounded())) bpm") }
        if let sleepScore { summaryParts.append("sleep score \(Int(sleepScore.rounded()))") }
        if let steps { summaryParts.append("steps \(Int(steps.rounded()))") }

        if !summaryParts.isEmpty {
            candidates.append(DerivedBodyMemoryCandidate(
                content: "Recent body state from Apple Watch: \(summaryParts.joined(separator: ", ")).",
                metadata: [
                    "source": bundle.source,
                    "memory_subtype": "body_snapshot",
                    "snapshot_count": bundle.snapshots.count
                ]
            ))
        }

        if let hrv, let sleepScore,
           hrv <= bodyMemoryHRVLowThreshold,
           sleepScore <= bodyMemorySleepLowThreshold {
            candidates.append(DerivedBodyMemoryCandidate(
                content: "Recent body state suggests low recovery: HRV is suppressed and sleep score is weak, so the user may be physiologically easier to trigger.",
                metadata: [
                    "source": bundle.source,
                    "memory_subtype": "low_recovery",
                    "hrv": hrv,
                    "sleep_score": sleepScore
                ]
            ))
        } else {
            if let hrv, hrv <= bodyMemoryHRVLowThreshold {
                candidates.append(DerivedBodyMemoryCandidate(
                    content: "Recent body state suggests reduced autonomic recovery because HRV is below the user's normal comfort band.",
                    metadata: [
                        "source": bundle.source,
                        "memory_subtype": "hrv_low",
                        "hrv": hrv
                    ]
                ))
            }
            if let sleepScore, sleepScore <= bodyMemorySleepLowThreshold {
                candidates.append(DerivedBodyMemoryCandidate(
                    content: "Recent body state suggests poor sleep recovery, which may amplify anxiety, irritability, and effort cost today.",
                    metadata: [
                        "source": bundle.source,
                        "memory_subtype": "sleep_low",
                        "sleep_score": sleepScore
                    ]
                ))
            }
        }

        if let rhr, rhr >= bodyMemoryRHRHighThreshold {
            candidates.append(DerivedBodyMemoryCandidate(
                content: "Recent body state suggests elevated physiological arousal because resting heart rate is running high.",
                metadata: [
                    "source": bundle.source,
                    "memory_subtype": "rhr_high",
                    "resting_heart_rate": rhr
                ]
            ))
        }

        if let steps, steps < bodyMemoryStepsLowThreshold {
            candidates.append(DerivedBodyMemoryCandidate(
                content: "Recent body state suggests low decompression activity because movement load is low, so gentle walking may carry higher value today.",
                metadata: [
                    "source": bundle.source,
                    "memory_subtype": "steps_low",
                    "steps": steps
                ]
            ))
        } else if let steps, steps >= bodyMemoryStepsGoodThreshold {
            candidates.append(DerivedBodyMemoryCandidate(
                content: "Recent body state shows a stronger activity base today, which may support better regulation capacity after stress.",
                metadata: [
                    "source": bundle.source,
                    "memory_subtype": "steps_good",
                    "steps": steps
                ]
            ))
        }

        var deduped: [DerivedBodyMemoryCandidate] = []
        var seen = Set<String>()
        for candidate in candidates {
            if seen.insert(candidate.content).inserted {
                deduped.append(candidate)
            }
        }
        return deduped
    }

    private func syncWearableTraitsToUnifiedProfile(userId: String, bundle: AppleWatchIngestionBundle) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let existingTraits = (try? await getUnifiedProfile()?.ai_inferred_traits) ?? [:]
        var mergedTraits = existingTraits

        mergedTraits["wearable_source"] = "apple_watch_healthkit"
        mergedTraits["wearable_last_sync_at"] = now
        mergedTraits["wearable_snapshot_count"] = String(bundle.snapshots.count)

        if let latestHRV = latestValue(in: bundle.snapshots, metricType: "hrv") {
            mergedTraits["wearable_hrv"] = String(format: "%.0f", latestHRV)
        }
        if let latestRHR = latestValue(in: bundle.snapshots, metricType: "resting_heart_rate") {
            mergedTraits["wearable_resting_heart_rate"] = String(format: "%.0f", latestRHR)
        }
        if let latestSteps = latestValue(in: bundle.snapshots, metricType: "steps") {
            mergedTraits["wearable_steps"] = String(format: "%.0f", latestSteps)
        }
        if let latestSleepScore = latestValue(in: bundle.snapshots, metricType: "sleep_score") {
            mergedTraits["wearable_sleep_score"] = String(format: "%.0f", latestSleepScore)
        }

        let payload = UnifiedProfileWearablePatch(
            ai_inferred_traits: mergedTraits,
            last_aggregated_at: now
        )
        try await requestVoid(
            "unified_user_profiles?user_id=eq.\(userId)",
            method: "PATCH",
            body: payload,
            prefer: "return=minimal"
        )
    }

    private func latestValue(in snapshots: [WearableMetricSnapshot], metricType: String) -> Double? {
        let filtered = snapshots.filter { $0.metricType == metricType }
        guard !filtered.isEmpty else { return nil }
        return filtered
            .sorted { $0.recordedAt > $1.recordedAt }
            .first?
            .value
    }

    private func isAppleWatchSource(_ source: String) -> Bool {
        let normalized = source.lowercased()
        return normalized.contains("healthkit") || normalized.contains("apple_watch")
    }
    
    /// 获取完整的 Dashboard 数据（聚合调用）
    func getDashboardData() async throws -> DashboardData {
        async let profileTask = getUnifiedProfile()
        async let logsTask = getWeeklyWellnessLogs()
        async let hardwareTask = getHardwareData()
        async let profileSettingsTask = getProfileSettings()

        let profile = try? await profileTask
        let logs = (try? await logsTask) ?? []
        let hardware = try? await hardwareTask
        let profileSettings = try? await profileSettingsTask
        let clinicalScaleScores = profileSettings?.inferred_scale_scores
        
        return DashboardData(
            profile: profile,
            weeklyLogs: logs,
            hardwareData: hardware,
            clinicalScaleScores: clinicalScaleScores
        )
    }

    // MARK: - Profile / Settings

    func getProfileSettings() async throws -> ProfileSettings? {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let baseSelect = "id,full_name,avatar_url,ai_personality,ai_persona_context,ai_settings,preferred_language,primary_goal,current_focus,inferred_scale_scores"
        if reminderPreferencesColumnAvailable == false {
            let legacyEndpoint = "profiles?id=eq.\(user.id)&select=\(baseSelect)&limit=1"
            let results: [ProfileSettings] = try await request(legacyEndpoint)
            return results.first
        }

        let endpoint = "profiles?id=eq.\(user.id)&select=\(baseSelect),reminder_preferences&limit=1"
        do {
            let results: [ProfileSettings] = try await request(endpoint)
            reminderPreferencesColumnAvailable = true
            return results.first
        } catch {
            let originalError = error
            let legacyEndpoint = "profiles?id=eq.\(user.id)&select=\(baseSelect)&limit=1"
            do {
                let results: [ProfileSettings] = try await request(legacyEndpoint)
                reminderPreferencesColumnAvailable = false
                print("[SupabaseManager] ⚠️ profiles.reminder_preferences missing; fallback to legacy profile select")
                return results.first
            } catch {
                throw originalError
            }
        }
    }

    func updateProfileSettings(_ update: ProfileSettingsUpdate) async throws -> ProfileSettings? {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let endpoint = "profiles?id=eq.\(user.id)"
        let results: [ProfileSettings] = try await request(endpoint, method: "PATCH", body: update, prefer: "return=representation")
        let updatedProfile = results.first
        
        // 如果更新后包含量表数据，更新本地状态
        if let scores = updatedProfile?.inferred_scale_scores, !scores.isEmpty {
            self.isClinicalComplete = true
        }

        var updatedFields: [String] = []
        if update.full_name != nil { updatedFields.append("full_name") }
        if update.avatar_url != nil { updatedFields.append("avatar_url") }
        if update.ai_personality != nil { updatedFields.append("ai_personality") }
        if update.ai_persona_context != nil { updatedFields.append("ai_persona_context") }
        if update.ai_settings != nil { updatedFields.append("ai_settings") }
        if update.preferred_language != nil { updatedFields.append("preferred_language") }
        if update.reminder_preferences != nil { updatedFields.append("reminder_preferences") }
        if !updatedFields.isEmpty {
            Task { [weak self] in
                await self?.captureUserSignal(
                    domain: "profile",
                    action: "settings_updated",
                    summary: "updated fields: \(updatedFields.joined(separator: ", "))",
                    metadata: [
                        "updated_fields": updatedFields,
                        "field_count": updatedFields.count
                    ]
                )
            }
        }
        
        return updatedProfile
    }

    func getReminderPreferences() async throws -> ReminderPreferences {
        let profile = try await getProfileSettings()
        return profile?.reminder_preferences ?? ReminderPreferences(morning: false, evening: false, breathing: false)
    }

    func updateReminderPreferences(_ preferences: ReminderPreferences) async throws -> ReminderPreferences {
        let update = ProfileSettingsUpdate(reminder_preferences: preferences)
        let profile = try await updateProfileSettings(update)
        return profile?.reminder_preferences ?? preferences
    }

    func uploadAvatar(imageData: Data, contentType: String = "image/jpeg", fileExtension: String = "jpg") async throws -> String {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        guard let token = SupabaseCredentialStore.token(for: .access) else {
            throw SupabaseError.notAuthenticated
        }
        let config = try validatedSupabaseConfig()

        let baseURL = config.url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let timestamp = Int(Date().timeIntervalSince1970)
        let objectPath = "avatars/\(user.id)/avatar-\(timestamp).\(fileExtension)"
        let encodedPath = objectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? objectPath
        guard let uploadURL = URL(string: "\(baseURL)/storage/v1/object/\(encodedPath)") else {
            throw makeRequestFailure(
                context: "Supabase avatar upload invalid URL",
                fallbackReason: "头像上传地址无效"
            )
        }

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout(for: .upload)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.setValue("3600", forHTTPHeaderField: "cache-control")
        request.httpBody = imageData

        let (data, response) = try await performDataRequestWithRetry(
            for: request,
            context: "Supabase uploadAvatar",
            hardTimeout: hardTimeout(for: request.timeoutInterval)
        )
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw makeRequestFailure(
                context: "Supabase avatar upload status failure",
                request: request,
                response: response as? HTTPURLResponse,
                data: data,
                fallbackReason: "头像上传失败"
            )
        }

        let publicURL = "\(baseURL)/storage/v1/object/public/\(encodedPath)"
        let update = ProfileSettingsUpdate(avatar_url: publicURL)
        _ = try await updateProfileSettings(update)
        return publicURL
    }

    private func isUUID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
    // 🆕 确保 token 有效 - 请求前调用
    private func ensureValidToken() async {
        do {
            try await refreshSession()
            print("[Token] ✅ Token 刷新成功")
        } catch {
            // 刷新失败不抛错，可能 token 还有效
            print("[Token] ⚠️ Token 刷新失败，继续使用现有 token: \(error.localizedDescription)")
        }
    }

    // MARK: - Digital Twin (Local Engine)

    func triggerDigitalTwinAnalysis(forceRefresh: Bool = false) async -> DigitalTwinTriggerResult {
        do {
            let input = try await loadDigitalTwinLocalInput()
            if input.baselineScores == nil {
                return DigitalTwinTriggerResult(triggered: false, reason: "缺少基线评估")
            }
            _ = DigitalTwinLocalEngine.analysis(input: input)
            return DigitalTwinTriggerResult(triggered: true, reason: "Local generated", analysisId: nil)
        } catch {
            return DigitalTwinTriggerResult(triggered: false, reason: error.localizedDescription)
        }
    }

    func getDigitalTwinDashboard() async throws -> DigitalTwinDashboardPayload {
        let input = try await loadDigitalTwinLocalInput()
        return DigitalTwinLocalEngine.dashboardPayload(input: input)
    }

    func getDigitalTwinCurve(devMode: Bool = false) async throws -> DigitalTwinCurveResponse {
        let input = try await loadDigitalTwinLocalInput()
        return DigitalTwinLocalEngine.curveResponse(input: input, conversationTrend: nil)
    }

    func generateDigitalTwinCurve(conversationTrend: String? = nil) async throws -> DigitalTwinCurveResponse {
        let input = try await loadDigitalTwinLocalInput()
        return DigitalTwinLocalEngine.curveResponse(input: input, conversationTrend: conversationTrend)
    }
}

struct DigitalTwinTriggerResult {
    let triggered: Bool
    let reason: String
    let analysisId: String?

    init(triggered: Bool, reason: String, analysisId: String? = nil) {
        self.triggered = triggered
        self.reason = reason
        self.analysisId = analysisId
    }
}

// MARK: - Models

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct AuthUser: Codable, Identifiable {
    let id: String
    let email: String?
    let phone: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, email, phone
        case createdAt = "created_at"
    }
}

// MARK: - Profile / Settings Models

struct AISettings: Codable, Equatable {
    let honesty_level: Double?
    let humor_level: Double?
    let mode: String?
}

struct ReminderPreferences: Codable, Equatable {
    let morning: Bool?
    let evening: Bool?
    let breathing: Bool?
}

struct ProfileSettings: Codable, Equatable {
    let id: String?
    let full_name: String?
    let avatar_url: String?
    let ai_personality: String?
    let ai_persona_context: String?
    let ai_settings: AISettings?
    let preferred_language: String?
    let primary_goal: String?
    let current_focus: String?
    let inferred_scale_scores: [String: Int]?
    let reminder_preferences: ReminderPreferences?
}

struct ProfileSettingsUpdate: Encodable {
    var full_name: String?
    var avatar_url: String?
    var ai_personality: String?
    var ai_persona_context: String?
    var ai_settings: AISettings?
    var preferred_language: String?
    var reminder_preferences: ReminderPreferences?

    enum CodingKeys: String, CodingKey {
        case full_name
        case avatar_url
        case ai_personality
        case ai_persona_context
        case ai_settings
        case preferred_language
        case reminder_preferences
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let full_name { try container.encode(full_name, forKey: .full_name) }
        if let avatar_url { try container.encode(avatar_url, forKey: .avatar_url) }
        if let ai_personality { try container.encode(ai_personality, forKey: .ai_personality) }
        if let ai_persona_context { try container.encode(ai_persona_context, forKey: .ai_persona_context) }
        if let ai_settings { try container.encode(ai_settings, forKey: .ai_settings) }
        if let preferred_language { try container.encode(preferred_language, forKey: .preferred_language) }
        if let reminder_preferences { try container.encode(reminder_preferences, forKey: .reminder_preferences) }
    }
}

struct ProfileRow: Decodable {
    let id: String
}

struct ProfileUpsertPayload: Encodable {
    let id: String
    let email: String?
    let inferred_scale_scores: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case inferred_scale_scores
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        if let email { try container.encode(email, forKey: .email) }
        if let inferred_scale_scores { try container.encode(inferred_scale_scores, forKey: .inferred_scale_scores) }
    }
}

// MARK: - Chat Models

struct ChatRequestMessage: Codable, Equatable {
    let role: String
    let content: String
}

private struct ChatAPIRequest: Codable {
    let messages: [ChatRequestMessage]
    let stream: Bool
    let mode: String
}

private struct ChatAPIResponse: Codable {
    let response: String
}

private struct ChatAPIErrorResponse: Codable {
    let error: String?
}

// MARK: - 计划保存 API
extension SupabaseManager {
    private struct SavedPlanItemPayload: Encodable {
        let id: String
        let text: String
        let completed: Bool
    }

    private struct SavedPlanContentPayload: Encodable {
        let description: String
        let items: [SavedPlanItemPayload]
    }

    private struct SavedPlanPayload: Encodable {
        let user_id: String
        let name: String
        let title: String
        let description: String?
        let category: String
        let status: String
        let progress: Int
        let content: SavedPlanContentPayload
        let difficulty: String?
        let plan_type: String
        let expected_duration_days: Int?
    }

    /// 保存用户选择的计划
    func savePlan(_ plan: PlanOption) async throws {
        guard let user = currentUser else {
            throw SupabaseError.notAuthenticated
        }

        let normalizedItems = plan.displayItems.enumerated().map { index, item in
            SavedPlanItemPayload(
                id: item.id ?? "\(UUID().uuidString)-\(index)",
                text: item.text,
                completed: false
            )
        }

        let inferredCategory = inferPlanCategory(plan: plan, items: normalizedItems)
        let payload = SavedPlanPayload(
            user_id: user.id,
            name: plan.displayTitle,
            title: plan.displayTitle,
            description: plan.description,
            category: inferredCategory,
            status: "active",
            progress: 0,
            content: SavedPlanContentPayload(
                description: plan.description ?? "",
                items: normalizedItems
            ),
            difficulty: plan.difficulty,
            plan_type: "max_customized",
            expected_duration_days: parseDurationDays(plan.duration)
        )

        try await requestVoid("user_plans", method: "POST", body: payload, prefer: "return=representation")
        await captureUserSignal(
            domain: "plans",
            action: "plan_saved",
            summary: plan.displayTitle,
            metadata: [
                "category": inferredCategory,
                "difficulty": plan.difficulty ?? "unknown",
                "items_count": normalizedItems.count,
                "duration_days": parseDurationDays(plan.duration) ?? -1
            ]
        )
        print("✅ 计划已保存到数据库: \(plan.displayTitle)")
    }

    private func inferPlanCategory(plan: PlanOption, items: [SavedPlanItemPayload]) -> String {
        var sourceParts: [String] = []
        if let title = plan.title { sourceParts.append(title) }
        if let description = plan.description { sourceParts.append(description) }
        sourceParts.append(contentsOf: items.map(\.text))
        let pool = sourceParts.map { $0.lowercased() }.joined(separator: " ")

        if pool.contains("睡") || pool.contains("sleep") { return "sleep" }
        if pool.contains("运动") || pool.contains("walk") || pool.contains("exercise") { return "exercise" }
        if pool.contains("饮食") || pool.contains("nutrition") || pool.contains("protein") { return "diet" }
        if pool.contains("焦虑") || pool.contains("压力") || pool.contains("stress") || pool.contains("breath") { return "mental" }
        return "general"
    }

    private func parseDurationDays(_ text: String?) -> Int? {
        guard let text, !text.isEmpty else { return nil }
        let pattern = #"(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[range])
    }
}

// MARK: - 🆕 Starter Questions API
extension SupabaseManager {
    /// 获取个性化起始问题
    func getStarterQuestions() async throws -> [String] {
        let defaults = [
            "今天我的焦虑评分如何？",
            "帮我分析一下最近的睡眠质量",
            "我该如何改善当前的压力水平？",
            "根据我的数据，有什么建议？"
        ]

        guard let user = currentUser else { return defaults }

        var questions: [String] = []
        func appendUnique(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if !questions.contains(trimmed) {
                questions.append(trimmed)
            }
        }

        if let pending = try? await fetchLatestPendingInquiry(userId: user.id),
           let questionText = pending.question_text, !questionText.isEmpty {
            appendUnique(questionText)
        }

        let profile = try? await getProfileSettings()
        let scores = profile?.inferred_scale_scores ?? [:]
        if let gad7 = scores["gad7"], gad7 >= 7 {
            appendUnique("最近最让你焦虑的触发点是什么？")
        }
        if let isi = scores["isi"], isi >= 7 {
            appendUnique("最近入睡困难还是早醒更明显？")
        }
        if let pss10 = scores["pss10"], pss10 >= 14 {
            appendUnique("最近压力主要来自哪件事？")
        }
        if let phq9 = scores["phq9"], phq9 >= 8 {
            appendUnique("近两周情绪低落的高峰在什么场景？")
        }

        let logs = (try? await getMonthlyWellnessLogs()) ?? []
        let calibrations = await fetchDigitalTwinCalibrations(userId: user.id, logs: logs)
        if let latest = calibrations.last {
            if latest.sleepHours > 0, latest.sleepHours < 6 {
                appendUnique("最近睡眠偏少，影响最大的是哪一段？")
            }
            if latest.stressLevel >= 7 {
                appendUnique("当前压力偏高，想先优化哪一块？")
            }
            if latest.energyLevel <= 4 {
                appendUnique("最近精力偏低，你更想提升哪一时段？")
            }
        }

        if let goal = profile?.primary_goal, !goal.isEmpty {
            switch goal {
            case "maintain_energy":
                appendUnique("基于你的目标，怎样提升白天能量？")
            case "improve_sleep":
                appendUnique("基于你的目标，先从睡眠哪个环节优化？")
            case "reduce_stress":
                appendUnique("基于你的目标，先从哪种减压方式开始？")
            default:
                appendUnique("围绕你的目标，我该先给你什么建议？")
            }
        }

        for fallback in defaults where questions.count < 4 {
            appendUnique(fallback)
        }

        return Array(questions.prefix(4))
    }
}

// MARK: - 🆕 Science Feed API
extension SupabaseManager {
    /// 获取科学期刊 Feed
    func getScienceFeed(language: String) async throws -> ScienceFeedResponse {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        struct CuratedFeedAPIItem: Codable {
            let id: String
            let title: String
            let summary: String
            let url: String
            let source: String
            let sourceLabel: String?
            let matchScore: Int?
            let publishedAt: String?
            let author: String?
            let thumbnail: String?
            let language: String?
            let matchedTags: [String]?
            let benefit: String?
            let whyRecommended: String?
            let actionableInsight: String?
            let category: String?
            let isRecommended: Bool?

            enum CodingKeys: String, CodingKey {
                case id, title, summary, url, source, sourceLabel, matchScore, publishedAt, author, thumbnail, language, matchedTags, benefit, whyRecommended, actionableInsight, category
                case isRecommended = "isRecommended"
            }
        }

        struct CuratedFeedAPIResponse: Codable {
            let items: [CuratedFeedAPIItem]
            let nextCursor: Int?
            let total: Int?
            let keywords: [String]?
            let generatedAt: String?
        }

        if let url = appAPIURL(
            path: "api/curated-feed",
            queryItems: [
                URLQueryItem(name: "limit", value: "20"),
                URLQueryItem(name: "cursor", value: "0"),
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "userId", value: user.id)
            ]
        ) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            attachSupabaseCookies(to: &request)
            request.timeoutInterval = requestTimeout(for: .appAPI)

            do {
                let (data, httpResponse) = try await performAppAPIRequest(request)
                if (200...299).contains(httpResponse.statusCode) {
                    let decoded = try JSONDecoder().decode(CuratedFeedAPIResponse.self, from: data)
                    let articles = decoded.items.map { item in
                        ScienceArticle(
                            id: item.id,
                            title: item.title,
                            titleZh: nil,
                            summary: item.summary,
                            summaryZh: nil,
                            sourceType: item.source,
                            sourceUrl: item.url,
                            matchPercentage: item.matchScore,
                            category: item.category,
                            isRecommended: item.isRecommended,
                            whyRecommended: item.benefit ?? item.whyRecommended,
                            actionableInsight: item.actionableInsight,
                            tags: item.matchedTags,
                            createdAt: item.publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }
                        )
                    }
                    return ScienceFeedResponse(
                        success: true,
                        items: articles,
                        data: nil,
                        personalization: FeedPersonalization(ready: true, message: nil, fallback: nil)
                    )
                }
            } catch {
                print("[CuratedFeed] API error: \(error)")
            }
        }

        struct CuratedFeedRow: Codable {
            let id: String
            let content_type: String?
            let title: String
            let summary: String?
            let url: String?
            let source: String
            let relevance_score: Double?
            let relevance_explanation: String?
            let created_at: String?
        }

        let endpoint = "curated_feed_queue?user_id=eq.\(user.id)&select=id,content_type,title,summary,url,source,relevance_score,relevance_explanation,created_at&order=relevance_score.desc.nullsfirst,created_at.desc&limit=20"
        let curatedRows: [CuratedFeedRow] = (try? await request(endpoint)) ?? []

        if !curatedRows.isEmpty {
            let articles = curatedRows.map { row in
                ScienceArticle(
                    id: row.id,
                    title: row.title,
                    titleZh: nil,
                    summary: row.summary,
                    summaryZh: nil,
                    sourceType: row.source,
                    sourceUrl: row.url,
                    matchPercentage: row.relevance_score.map { Int($0 * 100) },
                    category: nil,
                    isRecommended: nil,
                    whyRecommended: row.relevance_explanation,
                    actionableInsight: nil,
                    tags: nil,
                    createdAt: row.created_at.flatMap { ISO8601DateFormatter().date(from: $0) }
                )
            }
            return ScienceFeedResponse(
                success: true,
                items: articles,
                data: nil,
                personalization: FeedPersonalization(ready: true, message: nil, fallback: nil)
            )
        }

        let fallbackQuery = language == "en" ? "anxiety sleep stress" : "焦虑 睡眠 压力"
        let result = await ScientificSearchService.searchScientificTruth(query: fallbackQuery)
        let articles = result.papers.map { paper in
            ScienceArticle(
                id: paper.id,
                title: paper.title,
                titleZh: nil,
                summary: paper.abstract,
                summaryZh: nil,
                sourceType: paper.source.rawValue,
                sourceUrl: paper.url,
                matchPercentage: Int(paper.compositeScore * 100),
                category: nil,
                isRecommended: nil,
                whyRecommended: "基于科学检索匹配",
                actionableInsight: nil,
                tags: nil,
                createdAt: nil
            )
        }

        return ScienceFeedResponse(
            success: !articles.isEmpty,
            items: articles,
            data: nil,
            personalization: FeedPersonalization(
                ready: !articles.isEmpty,
                message: articles.isEmpty ? (language == "en" ? "No curated feed available." : "暂无推荐内容") : nil,
                fallback: articles.isEmpty ? (language == "en" ? "Please check back later." : "请稍后再试") : nil
            )
        )
    }
    
    /// 提交 Feed 反馈
    func submitFeedFeedback(_ feedback: FeedFeedbackInput) async throws {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        struct FeedbackRow: Encodable {
            let user_id: String
            let content_id: String
            let content_url: String?
            let content_title: String?
            let source: String?
            let feedback_type: String
        }

        let payload = FeedbackRow(
            user_id: user.id,
            content_id: feedback.contentId,
            content_url: feedback.contentUrl,
            content_title: feedback.contentTitle,
            source: feedback.source,
            feedback_type: feedback.feedbackType
        )
        try await requestVoid("user_feed_feedback", method: "POST", body: payload)
        print("✅ [FeedFeedback] 反馈已提交")
    }
}

// MARK: - 🆕 Understanding Score API
extension SupabaseManager {
    /// 获取理解度评分
    func getUnderstandingScore(includeHistory: Bool = true, days: Int = 14) async throws -> UnderstandingScoreResponse {
        let queryItems = [
            URLQueryItem(name: "includeHistory", value: includeHistory ? "true" : "false"),
            URLQueryItem(name: "days", value: String(max(1, days)))
        ]
        if let url = appAPIURL(path: "api/understanding-score", queryItems: queryItems) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            attachSupabaseCookies(to: &request)
            request.timeoutInterval = requestTimeout(for: .appAPI)

            do {
                let (data, httpResponse) = try await performAppAPIRequest(request)
                if (200...299).contains(httpResponse.statusCode) {
                    return try JSONDecoder().decode(UnderstandingScoreResponse.self, from: data)
                }
            } catch {
                print("[UnderstandingScore] Remote API failed: \(error)")
            }
        }

        return try await buildUnderstandingScoreLocally(includeHistory: includeHistory, days: days)
    }

    private func buildUnderstandingScoreLocally(includeHistory: Bool, days: Int) async throws -> UnderstandingScoreResponse {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let normalizedDays = max(1, days)
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.date(byAdding: .day, value: -(normalizedDays - 1), to: now) ?? now
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let startString = dateFormatter.string(from: startDate)

        let logs = (try? await getMonthlyWellnessLogs()) ?? []
        let logsInRange = logs.filter { $0.log_date.prefix(10) >= startString }
        let completionRate = min(1.0, Double(logsInRange.count) / Double(normalizedDays))

        struct InquiryRow: Codable {
            let responded_at: String?
            let created_at: String?
        }
        let inquiryEndpoint = "inquiry_history?user_id=eq.\(user.id)&select=responded_at,created_at&created_at=gte.\(startString)"
        let inquiryRows: [InquiryRow] = (try? await request(inquiryEndpoint)) ?? []
        let totalInquiries = inquiryRows.count
        let respondedCount = inquiryRows.filter { ($0.responded_at ?? "").isEmpty == false }.count
        let inquiryRate = totalInquiries == 0 ? 0.4 : min(1.0, Double(respondedCount) / Double(totalInquiries))

        let profile = try? await getProfileSettings()
        var preferenceScore: Double = 0.2
        if let personality = profile?.ai_personality, !personality.isEmpty { preferenceScore += 0.2 }
        if let language = profile?.preferred_language, !language.isEmpty { preferenceScore += 0.2 }
        if let goal = profile?.primary_goal, !goal.isEmpty { preferenceScore += 0.2 }
        if let focus = profile?.current_focus, !focus.isEmpty { preferenceScore += 0.2 }
        preferenceScore = min(1.0, preferenceScore)

        let currentScore = (35 + 65 * (0.45 * completionRate + 0.35 * inquiryRate + 0.2 * preferenceScore)).rounded()

        let breakdown = UnderstandingScoreBreakdown(
            completionPredictionAccuracy: (completionRate * 100).rounded(),
            replacementAcceptanceRate: (inquiryRate * 100).rounded(),
            sentimentPredictionAccuracy: ((completionRate * 0.6 + preferenceScore * 0.4) * 100).rounded(),
            preferencePatternMatch: (preferenceScore * 100).rounded()
        )

        let score = UnderstandingScore(
            current: currentScore,
            breakdown: breakdown,
            isDeepUnderstanding: currentScore >= 70,
            lastUpdated: ISO8601DateFormatter().string(from: now)
        )

        var history: [UnderstandingScoreHistory] = []
        if includeHistory {
            for offset in (0..<normalizedDays).reversed() {
                if let day = calendar.date(byAdding: .day, value: -offset, to: now) {
                    let dayString = dateFormatter.string(from: day)
                    let hasLog = logsInRange.contains { $0.log_date.hasPrefix(dayString) }
                    let hasInquiry = inquiryRows.contains {
                        ($0.responded_at ?? "").hasPrefix(dayString)
                    }
                    let dailyScore = (30 + 70 * ((hasLog ? 0.6 : 0) + (hasInquiry ? 0.4 : 0))).rounded()
                    history.append(UnderstandingScoreHistory(date: dayString, score: dailyScore, factorsChanged: nil))
                }
            }
        }

        return UnderstandingScoreResponse(score: score, history: includeHistory ? history : nil)
    }
}

// MARK: - 🆕 Inquiry API
extension SupabaseManager {
    fileprivate struct InquiryHistoryRow: Codable {
        let id: String
        let user_id: String?
        let question_text: String?
        let question_type: String?
        let priority: String?
        let data_gaps_addressed: [String]?
        let user_response: String?
        let responded_at: String?
        let delivery_method: String?
        let created_at: String?
    }

    fileprivate struct InquiryHistoryInsert: Encodable {
        let user_id: String
        let question_text: String
        let question_type: String
        let priority: String
        let data_gaps_addressed: [String]
        let delivery_method: String
    }

    fileprivate struct InquiryHistoryUpdate: Encodable {
        let user_response: String
        let responded_at: String
    }

    fileprivate struct InquiryGapRow: Codable {
        let data_gaps_addressed: [String]?
    }

    func getInquiryContextSummary(language: String, limit: Int = 8) async throws -> String? {
        guard let user = currentUser else { return nil }

        let endpoint = "inquiry_history?user_id=eq.\(user.id)&select=id,question_text,user_response,data_gaps_addressed,created_at,responded_at&order=created_at.desc&limit=\(max(1, limit))"
        let rows: [InquiryHistoryRow] = (try? await request(endpoint)) ?? []
        guard !rows.isEmpty else { return nil }

        let records = rows.map { row in
            InquiryHistoryRecord(
                id: row.id,
                questionText: row.question_text ?? "",
                userResponse: row.user_response,
                dataGapsAddressed: row.data_gaps_addressed ?? [],
                createdAt: row.created_at ?? "",
                respondedAt: row.responded_at
            )
        }

        let context = InquiryContextService.buildContext(from: records, language: language)
        return InquiryContextService.generateSummary(context, language: language)
    }

    /// 获取待答问询（本地 Supabase 直连）
    func getPendingInquiry(language: String) async throws -> InquiryPendingResponse {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        updateInquirySession(userId: user.id)

        if let existing = try? await fetchLatestPendingInquiry(userId: user.id) {
            Self.hasGeneratedInquiryForSession = true
            let question = resolveInquiryQuestion(from: existing, language: language)
            return InquiryPendingResponse(hasInquiry: question != nil, inquiry: question)
        }

        if Self.hasGeneratedInquiryForSession {
            return InquiryPendingResponse(hasInquiry: false, inquiry: nil)
        }

        let answeredGaps = await fetchAnsweredGapsToday(userId: user.id)

        // 无待答问询，尝试生成新的问询（AI 优先）
        if let inquiry = try await generateProactiveInquiry(language: language, excluding: answeredGaps) {
            Self.hasGeneratedInquiryForSession = true
            return InquiryPendingResponse(hasInquiry: true, inquiry: inquiry)
        }

        return InquiryPendingResponse(hasInquiry: false, inquiry: nil)
    }
    
    /// 提交问询回答（本地 Supabase 直连）
    func respondInquiry(inquiryId: String, response: String) async throws -> InquiryRespondResponse {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        let resolvedId = try await resolveInquiryHistoryId(
            rawInquiryId: inquiryId,
            userId: user.id
        )

        let payload = InquiryHistoryUpdate(
            user_response: response,
            responded_at: ISO8601DateFormatter().string(from: Date())
        )
        let endpoint = "inquiry_history?id=eq.\(resolvedId)"
        let updatedRows: [InquiryHistoryRow] = try await request(endpoint, method: "PATCH", body: payload, prefer: "return=representation")

        if let updated = updatedRows.first {
            await captureUserSignal(
                domain: "inquiry",
                action: "answered",
                summary: "\(updated.question_text ?? "inquiry") -> \(response)",
                metadata: [
                    "inquiry_id": resolvedId,
                    "question_type": updated.question_type ?? "unknown",
                    "priority": updated.priority ?? "unknown"
                ]
            )
        }

        if let gapField = updatedRows.first?.data_gaps_addressed?.first {
            await syncInquiryResponseToCalibration(userId: user.id, gapField: gapField, response: response)
        }
        return InquiryRespondResponse(success: true, message: nil)
    }

    private func resolveInquiryHistoryId(rawInquiryId: String, userId: String) async throws -> String {
        if isUUID(rawInquiryId) {
            return rawInquiryId
        }

        let pending = await fetchInquiryHistory(userId: userId, limit: 5)
            .filter { ($0.responded_at ?? "").isEmpty }

        let inferredType = rawInquiryId
            .replacingOccurrences(of: "inquiry_", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !inferredType.isEmpty,
           let exact = pending.first(where: { ($0.question_type ?? "").lowercased().contains(inferredType) }) {
            return exact.id
        }

        if let latest = pending.first {
            return latest.id
        }

        throw makeRequestFailure(
            context: "resolveInquiryHistoryId no match",
            fallbackReason: "未找到可回应的问题记录"
        )
    }

    private func fetchLatestPendingInquiry(userId: String) async throws -> InquiryHistoryRow? {
        let endpoint = "inquiry_history?user_id=eq.\(userId)&responded_at=is.null&order=created_at.desc&limit=1"
        let rows: [InquiryHistoryRow] = try await request(endpoint)
        return rows.first
    }

    private func updateInquirySession(userId: String) {
        let token = SupabaseCredentialStore.token(for: .access) ?? ""
        let sessionKey = "\(userId)|\(token)"
        if Self.inquirySessionKey != sessionKey {
            Self.inquirySessionKey = sessionKey
            Self.hasGeneratedInquiryForSession = false
        }
    }

    private func fetchInquiryHistory(userId: String, limit: Int) async -> [InquiryHistoryRow] {
        let endpoint = "inquiry_history?user_id=eq.\(userId)&select=id,question_text,question_type,priority,data_gaps_addressed,user_response,responded_at,created_at&order=created_at.desc&limit=\(max(1, limit))"
        return (try? await request(endpoint)) ?? []
    }

    private func storeInquiry(question: InquiryQuestion, userId: String) async throws -> InquiryQuestion {
        let payload = InquiryHistoryInsert(
            user_id: userId,
            question_text: question.questionText,
            question_type: question.questionType,
            priority: question.priority,
            data_gaps_addressed: question.dataGapsAddressed,
            delivery_method: "in_app"
        )

        let rows: [InquiryHistoryRow] = try await request(
            "inquiry_history",
            method: "POST",
            body: payload,
            prefer: "return=representation"
        )

        let storedId: String
        if let firstId = rows.first?.id {
            storedId = firstId
        } else {
            storedId = try await resolveInquiryHistoryId(rawInquiryId: question.id, userId: userId)
        }
        return InquiryQuestion(
            id: storedId,
            questionText: question.questionText,
            questionType: question.questionType,
            priority: question.priority,
            dataGapsAddressed: question.dataGapsAddressed,
            options: question.options,
            feedContent: question.feedContent
        )
    }

    private func resolveInquiryQuestion(from row: InquiryHistoryRow, language: String) -> InquiryQuestion? {
        guard let questionText = row.question_text,
              let questionType = row.question_type,
              let priority = row.priority else {
            return nil
        }

        let gaps = row.data_gaps_addressed ?? []
        var resolvedText = questionText
        var options: [InquiryOption]?
        if let gap = gaps.first,
           let template = InquiryEngine.inquiryTemplate(
            for: DataGap(field: gap, importance: .medium, description: gap, lastUpdated: row.created_at),
            language: language
           ) {
            resolvedText = template.questionText
            options = template.options
        }

        return InquiryQuestion(
            id: row.id,
            questionText: resolvedText,
            questionType: questionType,
            priority: priority,
            dataGapsAddressed: gaps,
            options: options,
            feedContent: nil
        )
    }

    private func generateInquiryFromGaps(
        language: String,
        excluding answeredGaps: Set<String> = []
    ) async throws -> InquiryQuestion? {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let recentData = await collectRecentInquiryData(userId: user.id)
        let gaps = InquiryEngine.identifyDataGaps(recentData: recentData, staleThresholdHours: 24)
        let filtered = gaps.filter { gap in
            !answeredGaps.contains(gap.field)
        }
        let prioritized = InquiryEngine.prioritizeDataGaps(filtered)

        guard let gap = prioritized.first,
              let inquiry = InquiryEngine.inquiryTemplate(for: gap, language: language) else {
            return nil
        }

        let payload = InquiryHistoryInsert(
            user_id: user.id,
            question_text: inquiry.questionText,
            question_type: inquiry.questionType,
            priority: inquiry.priority,
            data_gaps_addressed: inquiry.dataGapsAddressed,
            delivery_method: "in_app"
        )

        _ = try? await requestVoid("inquiry_history", method: "POST", body: payload, prefer: "return=representation")
        return inquiry
    }

    private func fetchAnsweredGapsToday(userId: String) async -> Set<String> {
        let dayString = utcDayString(for: Date())
        let endpoint = "inquiry_history?user_id=eq.\(userId)&user_response=not.is.null&responded_at=gte.\(dayString)T00:00:00Z&select=data_gaps_addressed"
        let rows: [InquiryGapRow] = (try? await request(endpoint)) ?? []
        var gaps = Set<String>()
        for row in rows {
            row.data_gaps_addressed?.forEach { gaps.insert($0) }
        }
        return gaps
    }

    private func utcDayString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    private func syncInquiryResponseToCalibration(userId: String, gapField: String, response: String) async {
        let now = Date()
        var payload: [String: AnyCodable] = [
            "user_id": AnyCodable(userId),
            "date": AnyCodable(utcDayString(for: now)),
            "updated_at": AnyCodable(ISO8601DateFormatter().string(from: now))
        ]

        switch gapField {
        case "sleep_hours":
            let map: [String: Double] = [
                "under_6": 5,
                "6_7": 6.5,
                "7_8": 7.5,
                "over_8": 8.5
            ]
            if let value = map[response] {
                payload["sleep_hours"] = AnyCodable(value)
            }
        case "stress_level":
            let map: [String: Int] = [
                "low": 3,
                "medium": 6,
                "high": 9
            ]
            if let value = map[response] {
                payload["stress_level"] = AnyCodable(value)
            }
        case "exercise_duration":
            let map: [String: Int] = [
                "none": 0,
                "light": 15,
                "moderate": 30,
                "intense": 60
            ]
            if let value = map[response] {
                payload["exercise_duration"] = AnyCodable(value)
            }
        case "mood":
            let map: [String: Int] = [
                "bad": 3,
                "okay": 6,
                "great": 9
            ]
            if let value = map[response] {
                payload["mood_score"] = AnyCodable(value)
            }
        case "meal_quality":
            payload["meal_quality"] = AnyCodable(response)
        case "water_intake":
            payload["water_intake"] = AnyCodable(response)
        default:
            break
        }

        guard payload.keys.count > 3 else { return }

        do {
            try await requestVoid(
                "daily_calibrations?on_conflict=user_id,date",
                method: "POST",
                body: payload,
                prefer: "resolution=merge-duplicates,return=representation"
            )
        } catch {
            print("[Inquiry] daily_calibrations sync warning: \(error)")
        }
    }

    private func collectRecentInquiryData(userId: String) async -> [String: (value: String, timestamp: String)] {
        var data: [String: (value: String, timestamp: String)] = [:]

        if let recentLogs = try? await getWeeklyWellnessLogs() {
            for log in recentLogs {
                let timestamp = log.log_date
                if let minutes = log.sleep_duration_minutes {
                    data["sleep_hours"] = (value: String(format: "%.1f", Double(minutes) / 60.0), timestamp: timestamp)
                }
                if let stress = log.stress_level {
                    data["stress_level"] = (value: "\(stress)", timestamp: timestamp)
                }
                if let exercise = log.exercise_duration_minutes {
                    data["exercise_duration"] = (value: "\(exercise)", timestamp: timestamp)
                }
                if let mood = log.mood_status {
                    data["mood"] = (value: mood, timestamp: timestamp)
                }
                if let energy = log.energy_level {
                    data["energy_level"] = (value: "\(energy)", timestamp: timestamp)
                }
            }
        }

        // 日常校准表的补充（如果存在）
        struct CalibrationRow: Codable {
            let date: String
            let sleep_hours: Double?
            let stress_level: Int?
            let exercise_duration: Int?
            let meal_quality: String?
            let mood_score: Int?
            let water_intake: String?
        }
        let calibrationEndpoint = "daily_calibrations?user_id=eq.\(userId)&select=date,sleep_hours,stress_level,exercise_duration,meal_quality,mood_score,water_intake&order=date.desc&limit=7"
        if let rows: [CalibrationRow] = try? await request(calibrationEndpoint) {
            for row in rows {
                let timestamp = row.date
                if let sleepHours = row.sleep_hours {
                    data["sleep_hours"] = (value: String(format: "%.1f", sleepHours), timestamp: timestamp)
                }
                if let stress = row.stress_level {
                    data["stress_level"] = (value: "\(stress)", timestamp: timestamp)
                }
                if let exercise = row.exercise_duration {
                    data["exercise_duration"] = (value: "\(exercise)", timestamp: timestamp)
                }
                if let meal = row.meal_quality {
                    data["meal_quality"] = (value: meal, timestamp: timestamp)
                }
                if let moodScore = row.mood_score {
                    data["mood"] = (value: "\(moodScore)", timestamp: timestamp)
                }
                if let water = row.water_intake {
                    data["water_intake"] = (value: water, timestamp: timestamp)
                }
            }
        }

        return data
    }
}

// MARK: - 🆕 Bayesian API
extension SupabaseManager {
    private struct BayesianBeliefRow: Codable {
        let id: String
        let belief_context: String?
        let prior_score: Double
        let posterior_score: Double
        let evidence_stack: [EvidenceItem]?
        let calculation_details: [String: CodableValue]?
        let created_at: String?
    }

    func getBayesianHistory(range: BayesianHistoryRange, context: String? = nil) async throws -> BayesianHistoryResponse {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        var endpoint = "bayesian_beliefs?user_id=eq.\(user.id)&select=*&order=created_at.asc"
        if let startDate = bayesianStartDate(range: range) {
            endpoint += "&created_at=gte.\(startDate)"
        }
        if let context, !context.isEmpty {
            endpoint += "&belief_context=eq.\(context)"
        }

        let rows: [BayesianBeliefRow] = (try? await request(endpoint)) ?? []
        let points: [BayesianHistoryPoint] = rows.compactMap { row in
            let exaggeration: Double
            if let details = row.calculation_details,
               case .number(let value) = details["exaggeration_factor"] {
                exaggeration = value
            } else {
                exaggeration = row.posterior_score > 0 ? (row.prior_score / row.posterior_score) : 1
            }
            return BayesianHistoryPoint(
                id: row.id,
                date: row.created_at ?? ISO8601DateFormatter().string(from: Date()),
                beliefContext: row.belief_context,
                priorScore: row.prior_score,
                posteriorScore: row.posterior_score,
                evidenceStack: row.evidence_stack,
                exaggerationFactor: exaggeration
            )
        }

        let summary = summarizeBayesianHistory(points: points)
        let data = BayesianHistoryData(points: points, summary: summary)
        return BayesianHistoryResponse(success: true, data: data, error: nil)
    }

    func triggerBayesianNudge(actionType: String, durationMinutes: Int?) async throws -> BayesianNudgeResponse {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let correction = calculateNudgeCorrection(actionType: actionType, durationMinutes: durationMinutes)
        let message = generateNudgeMessage(actionType: actionType, correction: correction)

        let endpoint = "bayesian_beliefs?user_id=eq.\(user.id)&select=*&order=created_at.desc&limit=1"
        let rows: [BayesianBeliefRow] = (try? await request(endpoint)) ?? []

        guard let latest = rows.first else {
            return BayesianNudgeResponse(
                success: true,
                data: BayesianNudgeData(correction: correction, newPosterior: clampBayesian(50 + correction), message: message),
                error: nil
            )
        }

        let newPosterior = clampBayesian(latest.posterior_score + correction)
        var updatedStack = latest.evidence_stack ?? []
        updatedStack.append(EvidenceItem(id: UUID(), type: .action, value: message, weight: correction))

        let updatePayload: [String: AnyCodable] = [
            "posterior_score": AnyCodable(newPosterior),
            "evidence_stack": AnyCodable(updatedStack.map { ["type": $0.type.rawValue, "value": $0.value, "weight": $0.weight ?? 0] })
        ]
        _ = try? await requestVoid(
            "bayesian_beliefs?id=eq.\(latest.id)",
            method: "PATCH",
            body: updatePayload,
            prefer: "return=representation"
        )
        await captureUserSignal(
            domain: "bayesian",
            action: "nudge_triggered",
            summary: "\(actionType) correction \(Int(correction))",
            metadata: [
                "action_type": actionType,
                "duration_minutes": durationMinutes ?? -1,
                "new_posterior": newPosterior
            ]
        )

        return BayesianNudgeResponse(
            success: true,
            data: BayesianNudgeData(correction: correction, newPosterior: newPosterior, message: message),
            error: nil
        )
    }

    func runBayesianRitual(context: String, priorScore: Int, customQuery: String?) async throws -> BayesianRitualResponse {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let query = (customQuery?.isEmpty == false ? customQuery! : context)
        let papersResult = await ScientificSearchService.searchScientificTruth(query: query)
        let hrvValue = try? await getHardwareData()?.hrv?.value

        let likelihood = BayesianEngine.calculateLikelihood(hrvData: BayesianHRVData(rmssd: hrvValue, lf_hf_ratio: nil))
        let evidenceWeight = BayesianEngine.calculateEvidenceWeight(
            papers: papersResult.papers.map {
                BayesianPaper(id: $0.id, title: $0.title, relevanceScore: $0.compositeScore, url: $0.url)
            }
        )
        let posterior = BayesianEngine.calculateBayesianPosterior(
            prior: Double(priorScore),
            likelihood: likelihood,
            evidence: evidenceWeight
        )

        var evidenceStack: [EvidenceItem] = []
        if let hrvValue {
            evidenceStack.append(EvidenceItem(id: UUID(), type: .bio, value: "HRV \(Int(hrvValue))", weight: likelihood))
        }
        for paper in papersResult.papers.prefix(3) {
            evidenceStack.append(EvidenceItem(id: UUID(), type: .science, value: paper.title, weight: paper.compositeScore))
        }

        let exaggeration = posterior > 0 ? (Double(priorScore) / posterior) : 1
        let payload: [String: AnyCodable] = [
            "user_id": AnyCodable(user.id),
            "belief_context": AnyCodable(context),
            "prior_score": AnyCodable(Double(priorScore)),
            "posterior_score": AnyCodable(posterior),
            "evidence_stack": AnyCodable(evidenceStack.map { ["type": $0.type.rawValue, "value": $0.value, "weight": $0.weight ?? 0] }),
            "calculation_details": AnyCodable([
                "exaggeration_factor": exaggeration,
                "evidence_weight": evidenceWeight,
                "likelihood": likelihood
            ])
        ]

        var insertedId = UUID().uuidString
        if let rows: [[String: AnyCodable]] = try? await request("bayesian_beliefs", method: "POST", body: payload, prefer: "return=representation"),
           let first = rows.first,
           let idValue = first["id"]?.value as? String {
            insertedId = idValue
        }

        let message = "概率已调整至 \(Int(posterior))%"
        await captureUserSignal(
            domain: "bayesian",
            action: "ritual_ran",
            summary: "\(context) prior \(priorScore) -> posterior \(Int(posterior))",
            metadata: [
                "context": context,
                "prior": priorScore,
                "posterior": posterior,
                "evidence_count": evidenceStack.count
            ]
        )
        let data = BayesianRitualData(
            id: insertedId,
            priorScore: Double(priorScore),
            posteriorScore: posterior,
            evidenceStack: evidenceStack,
            exaggerationFactor: exaggeration,
            message: message
        )
        return BayesianRitualResponse(success: true, data: data, error: nil)
    }

    private func bayesianStartDate(range: BayesianHistoryRange) -> String? {
        let now = Date()
        let calendar = Calendar.current
        let date: Date?
        switch range {
        case .days7:
            date = calendar.date(byAdding: .day, value: -7, to: now)
        case .days30:
            date = calendar.date(byAdding: .day, value: -30, to: now)
        case .days90:
            date = calendar.date(byAdding: .day, value: -90, to: now)
        case .all:
            date = nil
        }
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }

    private func summarizeBayesianHistory(points: [BayesianHistoryPoint]) -> BayesianHistorySummary {
        let total = points.count
        let averagePrior = total > 0 ? points.reduce(0) { $0 + $1.priorScore } / Double(total) : 0
        let averagePosterior = total > 0 ? points.reduce(0) { $0 + $1.posteriorScore } / Double(total) : 0
        let averageReduction = averagePrior - averagePosterior
        let trend = calculateBayesianTrend(points: points)

        return BayesianHistorySummary(
            totalEntries: total,
            averagePrior: round1(averagePrior),
            averagePosterior: round1(averagePosterior),
            averageReduction: round1(averageReduction),
            trend: trend
        )
    }

    private func calculateBayesianTrend(points: [BayesianHistoryPoint]) -> String {
        guard points.count >= 3 else { return "stable" }
        let recent = points.suffix(5)
        let older = points.dropLast(5).suffix(5)
        guard !older.isEmpty else { return "stable" }
        let recentAvg = recent.reduce(0) { $0 + $1.posteriorScore } / Double(recent.count)
        let olderAvg = older.reduce(0) { $0 + $1.posteriorScore } / Double(older.count)
        let diff = recentAvg - olderAvg
        if diff < -5 { return "improving" }
        if diff > 5 { return "worsening" }
        return "stable"
    }

    private func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private func calculateNudgeCorrection(actionType: String, durationMinutes: Int?) -> Double {
        let base: [String: Double] = [
            "breathing_exercise": -5,
            "meditation": -8,
            "exercise": -10,
            "sleep_improvement": -7,
            "hydration": -3,
            "journaling": -4,
            "stretching": -3
        ]
        var correction = base[actionType] ?? -2
        if let durationMinutes, durationMinutes > 10 {
            correction = max(correction * 1.5, -20)
        }
        correction = max(-20, min(-1, correction.rounded()))
        return correction
    }

    private func generateNudgeMessage(actionType: String, correction: Double) -> String {
        let names: [String: String] = [
            "breathing_exercise": "呼吸练习",
            "meditation": "冥想",
            "exercise": "运动",
            "sleep_improvement": "睡眠改善",
            "hydration": "补水",
            "journaling": "日记",
            "stretching": "拉伸"
        ]
        let name = names[actionType] ?? "减压动作"
        return "\(name)完成。皮质醇风险概率修正：\(Int(correction))%"
    }

    private func clampBayesian(_ value: Double) -> Double {
        min(100, max(0, value))
    }
}

// MARK: - 🆕 Insight / Voice / Debug API
extension SupabaseManager {
    private struct ProactiveInquiryContext: Codable {
        let recentData: [String: String]
        let dataGaps: [DataGap]
        let timeOfDay: String
        let dayOfWeek: Int
    }

    private struct ProactiveInquiryHistoryItem: Codable {
        let questionText: String
        let questionType: String
        let answer: String?
        let createdAt: String?
    }

    private struct ProactiveInquiryPayload: Codable {
        let context: ProactiveInquiryContext
        let language: String
        let history: [ProactiveInquiryHistoryItem]
    }

    private struct ProactiveInquiryResponse: Codable {
        let question: InquiryQuestion
    }

    func generateProactiveInquiry(
        language: String,
        excluding answeredGaps: Set<String> = []
    ) async throws -> InquiryQuestion? {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let recentData = await collectRecentInquiryData(userId: user.id)
        let dataGaps = InquiryEngine.identifyDataGaps(recentData: recentData, staleThresholdHours: 24)
            .filter { !answeredGaps.contains($0.field) }

        if let inquiry = try await generateProactiveInquiryFromAI(
            userId: user.id,
            language: language,
            recentData: recentData,
            dataGaps: dataGaps
        ) {
            return inquiry
        }

        return try await generateInquiryFromGaps(language: language, excluding: answeredGaps)
    }

    private func generateProactiveInquiryFromAI(
        userId: String,
        language: String,
        recentData: [String: (value: String, timestamp: String)],
        dataGaps: [DataGap]
    ) async throws -> InquiryQuestion? {
        guard let url = appAPIURL(path: "api/ai/generate-inquiry") else { return nil }

        let context = ProactiveInquiryContext(
            recentData: recentData.mapValues { $0.value },
            dataGaps: dataGaps,
            timeOfDay: currentTimeOfDay(),
            dayOfWeek: Calendar.current.component(.weekday, from: Date())
        )

        let history = await fetchInquiryHistory(userId: userId, limit: 5).map {
            ProactiveInquiryHistoryItem(
                questionText: $0.question_text ?? "",
                questionType: $0.question_type ?? "diagnostic",
                answer: $0.user_response,
                createdAt: $0.created_at
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachSupabaseCookies(to: &request)
        request.httpBody = try JSONEncoder().encode(
            ProactiveInquiryPayload(
                context: context,
                language: language,
                history: history
            )
        )

        request.timeoutInterval = requestTimeout(for: .appAPI)

        do {
            let (data, httpResponse) = try await performAppAPIRequest(request)
            if (200...299).contains(httpResponse.statusCode) {
                let decoded = try JSONDecoder().decode(ProactiveInquiryResponse.self, from: data)
                return try await storeInquiry(question: decoded.question, userId: userId)
            }
        } catch {
            print("[ProactiveInquiry] AI generation failed: \(error)")
        }

        return nil
    }

    private func currentTimeOfDay() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 { return "morning" }
        if hour >= 12 && hour < 18 { return "afternoon" }
        return "evening"
    }

    private func isAIConfigured() -> Bool {
        guard let key = Bundle.main.infoDictionary?["OPENAI_API_KEY"] as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard let base = Bundle.main.infoDictionary?["OPENAI_API_BASE"] as? String,
              !base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    private func extractJSONPayload(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let jsonString = String(text[start...end])
        return jsonString.data(using: .utf8)
    }

    func analyzeVoiceInput(_ input: VoiceAnalysisInput) async throws -> VoiceAnalysisResponse {
        if let url = appAPIURL(path: "api/ai/analyze-voice-input") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            attachSupabaseCookies(to: &request)
            request.httpBody = try JSONEncoder().encode(input)

            request.timeoutInterval = requestTimeout(for: .appAPI)

            do {
                let (data, httpResponse) = try await performAppAPIRequest(request)
                if (200...299).contains(httpResponse.statusCode) {
                    return try JSONDecoder().decode(VoiceAnalysisResponse.self, from: data)
                }
            } catch {
                print("[VoiceAnalysis] Remote API failed: \(error)")
            }
        }

        return try await analyzeVoiceInputLocally(input)
    }

    func generateInsight(_ input: InsightGenerateInput) async throws -> String {
        if let url = appAPIURL(path: "api/insight/generate") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            attachSupabaseCookies(to: &request)
            request.httpBody = try JSONEncoder().encode(input)

            request.timeoutInterval = requestTimeout(for: .appAPI)

            do {
                let (data, httpResponse) = try await performAppAPIRequest(request)
                if (200...299).contains(httpResponse.statusCode) {
                    return String(data: data, encoding: .utf8) ?? ""
                }
            } catch {
                print("[Insight] Remote API failed: \(error)")
            }
        }

        return try await generateInsightLocally(input)
    }

    func fetchInsightSummary() async throws -> InsightSummaryResponse {
        if let url = appAPIURL(path: "api/insight") {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            attachSupabaseCookies(to: &request)

            request.timeoutInterval = requestTimeout(for: .appAPI)

            do {
                let (data, httpResponse) = try await performAppAPIRequest(request)
                if (200...299).contains(httpResponse.statusCode) {
                    return try JSONDecoder().decode(InsightSummaryResponse.self, from: data)
                }
            } catch {
                print("[InsightSummary] Remote API failed: \(error)")
            }
        }

        return try await fetchInsightSummaryLocally()
    }

    func getDeepInference(analysisResult: [String: Any], recentLogs: [[String: Any]]) async throws -> String {
        if let url = appAPIURL(path: "api/ai/deep-inference") {
            let payload: [String: Any] = [
                "analysisResult": analysisResult,
                "recentLogs": recentLogs
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            attachSupabaseCookies(to: &request)
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            request.timeoutInterval = requestTimeout(for: .appAPI)

            do {
                let (data, httpResponse) = try await performAppAPIRequest(request)
                if (200...299).contains(httpResponse.statusCode) {
                    if let object = try? JSONSerialization.jsonObject(with: data),
                       let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) {
                        return String(data: prettyData, encoding: .utf8) ?? ""
                    }
                    return String(data: data, encoding: .utf8) ?? ""
                }
            } catch {
                print("[DeepInference] Remote API failed: \(error)")
            }
        }

        return try await getDeepInferenceLocally(analysisResult: analysisResult, recentLogs: recentLogs)
    }

    func explainRecommendation(
        recommendationId: String,
        title: String,
        description: String,
        science: String,
        language: String,
        category: String? = nil
    ) async throws -> String {
        if let url = appAPIURL(path: "api/digital-twin/explain-recommendation") {
            var payload: [String: Any] = [
                "recommendationId": recommendationId,
                "title": title,
                "description": description,
                "science": science,
                "language": language
            ]
            if let category, !category.isEmpty {
                payload["category"] = category
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            attachSupabaseCookies(to: &request)
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

            request.timeoutInterval = requestTimeout(for: .appAPI)

            do {
                let (data, httpResponse) = try await performAppAPIRequest(request)
                if (200...299).contains(httpResponse.statusCode) {
                    struct ExplainResponse: Codable { let explanation: String }
                    let decoded = try JSONDecoder().decode(ExplainResponse.self, from: data)
                    return decoded.explanation
                }
            } catch {
                print("[ExplainRecommendation] Remote API failed: \(error)")
            }
        }

        return try await explainRecommendationLocally(
            recommendationId: recommendationId,
            title: title,
            description: description,
            science: science,
            language: language,
            category: category
        )
    }

    private func analyzeVoiceInputLocally(_ input: VoiceAnalysisInput) async throws -> VoiceAnalysisResponse {
        let transcript = input.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            return VoiceAnalysisResponse(formUpdates: [:], summary: "未检测到语音内容。", confidence: 0.1)
        }

        if isAIConfigured() {
            let currentStateData = (try? JSONEncoder().encode(input.currentFormState)) ?? Data()
            let currentState = String(data: currentStateData, encoding: .utf8) ?? "{}"
            let systemPrompt = """
你是反焦虑跟进助手，负责从用户口述中提取结构化校准数据。
请只输出 JSON，格式如下：
{
  "formUpdates": { "sleepDuration": "...", "sleepQuality": "...", "exerciseDuration": "...", "moodStatus": "...", "stressLevel": "...", "notes": "..." },
  "summary": "...",
  "confidence": 0.0
}
要求：
- formUpdates 只包含你能确定的字段，其余省略
- 数值用字符串表达
- summary 用中文简短总结，聚焦焦虑触发与可执行动作
- confidence 在 0~1 之间
"""
            let userPrompt = """
Transcript:
\(transcript)

CurrentFormState:
\(currentState)
"""
            let response = try await AIManager.shared.chatCompletion(
                messages: [ChatMessage(role: .user, content: userPrompt)],
                systemPrompt: systemPrompt,
                model: .deepseekV3Exp,
                temperature: 0.2
            )
            if let data = extractJSONPayload(from: response),
               let parsed = try? JSONDecoder().decode(VoiceAnalysisResponse.self, from: data) {
                return parsed
            }
        }

        return heuristicVoiceAnalysis(input)
    }

    private func heuristicVoiceAnalysis(_ input: VoiceAnalysisInput) -> VoiceAnalysisResponse {
        let transcript = input.transcript.lowercased()
        var updates: [String: String] = [:]

        func match(_ pattern: String) -> String? {
            let regex = try? NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(transcript.startIndex..<transcript.endIndex, in: transcript)
            if let match = regex?.firstMatch(in: transcript, options: [], range: range),
               let matchRange = Range(match.range(at: 1), in: transcript) {
                return String(transcript[matchRange])
            }
            return nil
        }

        if let sleep = match("(\\d+(?:\\.\\d+)?)\\s*(?:小时|h)") {
            updates["sleepDuration"] = sleep
        }
        if let exercise = match("(\\d+(?:\\.\\d+)?)\\s*(?:分钟|min)") {
            updates["exerciseDuration"] = exercise
        }
        if transcript.contains("压力"), let stress = match("压力\\D{0,6}(\\d+)") {
            updates["stressLevel"] = stress
        }
        if transcript.contains("心情"), let mood = match("心情\\D{0,6}(\\d+)") {
            updates["moodStatus"] = mood
        }

        let summary = updates.isEmpty ? "暂未识别到可填写的数据。" : "已从描述中提取可更新字段。"
        let confidence = updates.isEmpty ? 0.2 : 0.45
        return VoiceAnalysisResponse(formUpdates: updates, summary: summary, confidence: confidence)
    }

    private func generateInsightLocally(_ input: InsightGenerateInput) async throws -> String {
        if isAIConfigured() {
            let systemPrompt = """
你是反焦虑数据洞察助手。请基于输入的睡眠、HRV、压力、运动数据，输出 3 条洞察和 2 条建议。
要求：中文、简洁、可执行，且与焦虑缓解直接相关；不做医疗诊断。
"""
            let userPrompt = """
sleepHours: \(input.sleepHours)
hrv: \(input.hrv)
stressLevel: \(input.stressLevel)
exerciseMinutes: \(input.exerciseMinutes ?? 0)
"""
            let response = try await AIManager.shared.chatCompletion(
                messages: [ChatMessage(role: .user, content: userPrompt)],
                systemPrompt: systemPrompt,
                model: .deepseekV3Exp,
                temperature: 0.4
            )
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var lines: [String] = []
        if input.sleepHours < 6 {
            lines.append("睡眠时长偏低，可能影响恢复与情绪稳定。")
        } else if input.sleepHours > 8.5 {
            lines.append("睡眠时长偏高，注意是否存在睡眠效率下降。")
        } else {
            lines.append("睡眠时长处于合理区间，保持节律更重要。")
        }
        if input.stressLevel >= 7 {
            lines.append("压力水平偏高，建议增加呼吸练习或短时放松。")
        } else {
            lines.append("压力水平可控，可以继续保持当前节奏。")
        }
        if let exercise = input.exerciseMinutes, exercise < 20 {
            lines.append("运动量偏少，建议每天安排 20 分钟轻度运动。")
        }
        lines.append("建议：固定作息 + 1 次短时呼吸练习。")
        return lines.joined(separator: "\n")
    }

    private func fetchInsightSummaryLocally() async throws -> InsightSummaryResponse {
        let dashboard = try? await getDashboardData()
        let logs = dashboard?.weeklyLogs ?? []
        let avgSleep = logs.compactMap { $0.sleep_duration_minutes }.reduce(0, +)
        let avgSleepHours = logs.isEmpty ? 0 : Double(avgSleep) / Double(logs.count) / 60.0
        let avgStress = logs.compactMap { $0.stress_level }.reduce(0, +)
        let avgStressScore = logs.isEmpty ? 0 : Double(avgStress) / Double(logs.count)

        let baseSummary = "近7天平均睡眠 \(String(format: "%.1f", avgSleepHours)) 小时，平均压力 \(String(format: "%.1f", avgStressScore))。"

        if isAIConfigured() {
            let systemPrompt = """
你是反焦虑周报助手。基于输入统计摘要，给出 3 条洞察和 1 个重点建议。
要求：中文、简洁、可执行，强调持续跟进。
"""
            let response = try await AIManager.shared.chatCompletion(
                messages: [ChatMessage(role: .user, content: baseSummary)],
                systemPrompt: systemPrompt,
                model: .deepseekV3Exp,
                temperature: 0.4
            )
            return InsightSummaryResponse(insight: response.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return InsightSummaryResponse(insight: baseSummary + " 建议保持作息一致，并安排放松练习。")
    }

    private func getDeepInferenceLocally(analysisResult: [String: Any], recentLogs: [[String: Any]]) async throws -> String {
        let analysisData = (try? JSONSerialization.data(withJSONObject: analysisResult, options: [.prettyPrinted])) ?? Data()
        let logsData = (try? JSONSerialization.data(withJSONObject: recentLogs, options: [.prettyPrinted])) ?? Data()
        let analysisString = String(data: analysisData, encoding: .utf8) ?? "{}"
        let logsString = String(data: logsData, encoding: .utf8) ?? "[]"

        if isAIConfigured() {
            let systemPrompt = """
你是反焦虑趋势分析助手。请基于分析结果和最近日志，输出：1) 主要趋势 2) 可能驱动因素 3) 3 条行动建议。
要求：中文、结构化、可执行、避免医疗诊断。
"""
            let userPrompt = """
analysisResult:
\(analysisString)

recentLogs:
\(logsString)
"""
            let response = try await AIManager.shared.chatCompletion(
                messages: [ChatMessage(role: .user, content: userPrompt)],
                systemPrompt: systemPrompt,
                model: .deepseekV3Exp,
                temperature: 0.4
            )
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return "暂无可用的深度推断结果（AI 未配置）。"
    }

    private func explainRecommendationLocally(
        recommendationId: String,
        title: String,
        description: String,
        science: String,
        language: String,
        category: String? = nil
    ) async throws -> String {
        if isAIConfigured() {
            let systemPrompt = language == "en"
                ? "You are Max. Explain why the recommendation helps, in 3 concise bullets, avoid medical claims."
                : "你是 Max，请用 3 条要点解释该建议为何有效，避免医疗诊断。"
            let userPrompt = """
title: \(title)
description: \(description)
science: \(science)
category: \(category ?? "")
"""
            let response = try await AIManager.shared.chatCompletion(
                messages: [ChatMessage(role: .user, content: userPrompt)],
                systemPrompt: systemPrompt,
                model: .deepseekV3Exp,
                temperature: 0.4
            )
            return response.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return "该建议有助于稳定节律与降低压力反应，可先尝试 1-2 周观察变化。"
    }

    func sendDebugPayload(path: String, payload: String) async throws -> String {
        guard let url = appAPIURL(path: path) else {
            throw SupabaseError.missingAppApiBaseUrl
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachSupabaseCookies(to: &request)
        request.timeoutInterval = requestTimeout(for: .appAPI)
        request.httpBody = payload.data(using: .utf8)

        let (data, httpResponse) = try await performAppAPIRequest(request)

        if (200...299).contains(httpResponse.statusCode) {
            if let object = try? JSONSerialization.jsonObject(with: data),
               let prettyData = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]) {
                return String(data: prettyData, encoding: .utf8) ?? ""
            }
            return String(data: data, encoding: .utf8) ?? ""
        }

        throw makeRequestFailure(
            context: "sendDebugPayload status failure",
            request: request,
            response: httpResponse,
            data: data
        )
    }
}

// MARK: - 🆕 Daily AI Recommendations API
extension SupabaseManager {
    func prewarmProactiveCare(language: String? = nil, force: Bool = false) async {
        guard currentUser != nil else { return }

        if !force,
           let last = Self.proactivePrewarmAt,
           Date().timeIntervalSince(last) < proactivePrewarmDebounceTTL {
            return
        }
        Self.proactivePrewarmAt = Date()

        let resolvedLanguage: String = {
            if let language,
               !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return language == "en" ? "en" : "zh"
            }
            let appLanguage = AppLanguage.fromStored(UserDefaults.standard.string(forKey: "app_language"))
            return appLanguage == .en ? "en" : "zh"
        }()

        await triggerDailyRecommendations(force: false, language: resolvedLanguage)
        _ = try? await generateProactiveCareBrief(
            language: resolvedLanguage,
            forceRefresh: false
        )
    }

    func getDailyRecommendations(date: Date = Date()) async throws -> [DailyAIRecommendationItem] {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }
        let dayString = recommendationDateString(date)
        let endpoint = "daily_ai_recommendations?user_id=eq.\(user.id)&recommendation_date=eq.\(dayString)&select=id,recommendation_date,recommendations&limit=1"
        let rows: [DailyAIRecommendationsRow] = try await request(endpoint)
        return rows.first?.recommendations ?? []
    }

    func triggerDailyRecommendations(force: Bool = false, language: String? = nil) async {
        guard let url = appAPIURL(path: "api/recommendations/daily") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachSupabaseCookies(to: &request)
        request.timeoutInterval = requestTimeout(for: .appAPI)

        let payload: [String: Any] = [
            "force": force,
            "language": language ?? "zh"
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, httpResponse) = try await performAppAPIRequest(request)
            if !(200...299).contains(httpResponse.statusCode) {
                print("[Recommendations] trigger failed: \(httpResponse.statusCode)")
            }
        } catch {
            print("[Recommendations] trigger error: \(error)")
        }
    }

    func recommendationDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private struct ProactiveSignalSnapshot {
        let lines: [String]
        let primaryFocus: String
        let scientificQuery: String
    }

    private struct ProactiveBriefLLMResponse: Decodable {
        let title: String?
        let understanding: String?
        let mechanism: String?
        let micro_action: String?
        let follow_up_question: String?
        let evidence_title: String?
        let evidence_url: String?
        let confidence: Double?
    }

    func captureUserSignal(
        domain: String,
        action: String,
        summary: String,
        metadata: [String: Any]? = nil
    ) async {
        guard let user = currentUser else { return }
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSummary.isEmpty else { return }

        let cleanedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanedAction = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanedDomain.isEmpty, !cleanedAction.isEmpty else { return }

        var mergedMetadata = metadata ?? [:]
        mergedMetadata["domain"] = cleanedDomain
        mergedMetadata["action"] = cleanedAction
        mergedMetadata["source"] = "ios"
        mergedMetadata["captured_at"] = ISO8601DateFormatter().string(from: Date())

        let content = "[\(cleanedDomain)] \(cleanedAction): \(trimmedSummary)"
        _ = await MaxMemoryService.storeCategorizedMemory(
            userId: user.id,
            content: content,
            role: "user",
            kind: .behaviorSignal,
            metadata: mergedMetadata
        )
    }

    func generateProactiveCareBrief(
        language: String,
        forceRefresh: Bool = false
    ) async throws -> ProactiveCareBrief {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let lang = language == "en" ? "en" : "zh"
        let dayKey = recommendationDateString(Date())
        let cacheKey = "\(user.id)|\(lang)|\(dayKey)"
        if !forceRefresh,
           let cached = Self.proactiveBriefCache[cacheKey],
           cached.expiresAt > Date() {
            return cached.brief
        }

        // Keep this path fully stable on simulator/runtime upgrades.
        // Sequential awaits avoid async-let teardown crashes observed in production traces.
        let profile = try? await getProfileSettings()
        let dashboard = try? await getDashboardData()
        let inquirySummary = try? await getInquiryContextSummary(language: lang, limit: 8)
        let memories = await MaxMemoryService.retrieveRecentMemories(userId: user.id, limit: 10)

        let snapshot = buildProactiveSignalSnapshot(
            profile: profile,
            dashboard: dashboard,
            inquirySummary: inquirySummary,
            memories: memories,
            language: lang
        )
        let scientific = await ScientificSearchService.searchScientificTruth(query: snapshot.scientificQuery)
        let topEvidence = Array(scientific.papers.prefix(3))

        let generatedAt = ISO8601DateFormatter().string(from: Date())
        var finalBrief: ProactiveCareBrief?
        if isAIConfigured() {
            let evidenceLines = topEvidence.map { paper in
                let year = paper.year.map(String.init) ?? "n/a"
                return "- \(paper.title) | \(year) | \(paper.source.rawValue) | \(paper.url)"
            }.joined(separator: "\n")
            let memoryLines = memories.prefix(4).map { record in
                let snippet = String(record.content_text.replacingOccurrences(of: "\n", with: " ").prefix(120))
                return "- [\(record.role)] \(snippet)"
            }.joined(separator: "\n")

            let systemPrompt = lang == "en" ? """
You are a clinical-grade anti-anxiety copilot.
Generate one proactive care brief for this user without sounding generic.
Return JSON only with keys:
title, understanding, mechanism, micro_action, follow_up_question, evidence_title, evidence_url, confidence
Rules:
- Keep it personal and concrete.
- One low-friction action that can start today.
- Follow-up question must be measurable (0-10 or minutes).
- confidence is 0~1.
""" : """
你是临床级反焦虑协作助手。
请基于用户画像生成一条主动关怀简报，不能空泛。
只返回 JSON，包含键：
title, understanding, mechanism, micro_action, follow_up_question, evidence_title, evidence_url, confidence
要求：
- 必须个性化、具体。
- 只给一个今天可执行的低阻力动作。
- 跟进问题必须可量化（0-10 或分钟）。
- confidence 范围 0~1。
"""
            let userPrompt = """
[USER SIGNALS]
\(snapshot.lines.joined(separator: "\n"))

[INQUIRY SUMMARY]
\(inquirySummary ?? (lang == "en" ? "none" : "无"))

[RECENT MEMORIES]
\(memoryLines.isEmpty ? (lang == "en" ? "- none" : "- 无") : memoryLines)

[SCIENTIFIC EVIDENCE CANDIDATES]
\(evidenceLines.isEmpty ? (lang == "en" ? "- none" : "- 无") : evidenceLines)

[PRIMARY FOCUS]
\(snapshot.primaryFocus)
"""

            do {
                let response = try await AIManager.shared.chatCompletion(
                    messages: [ChatMessage(role: .user, content: userPrompt)],
                    systemPrompt: systemPrompt,
                    model: .gpt5ChatLatest,
                    temperature: 0.45,
                    timeout: 16
                )
                if let parsed = parseProactiveCareBrief(
                    response,
                    generatedAt: generatedAt,
                    language: lang,
                    evidenceFallback: topEvidence.first
                ) {
                    finalBrief = parsed
                }
            } catch {
                print("[ProactiveBrief] AI generation failed: \(error)")
            }
        }

        let brief = finalBrief ?? buildFallbackProactiveCareBrief(
            generatedAt: generatedAt,
            language: lang,
            snapshot: snapshot,
            evidence: topEvidence.first
        )

        Self.proactiveBriefCache[cacheKey] = TimedProactiveBriefCache(
            brief: brief,
            expiresAt: Date().addingTimeInterval(proactiveBriefCacheTTL)
        )

        // Persist assistant proactive output as a dedicated strategy memory.
        _ = await MaxMemoryService.storeCategorizedMemory(
            userId: user.id,
            content: "\(brief.title) | \(brief.mechanism) | action: \(brief.microAction)",
            role: "assistant",
            kind: .proactiveBrief,
            metadata: [
                "source": "proactive_brief",
                "language": lang,
                "confidence": brief.confidence ?? 0.55
            ]
        )

        return brief
    }

    private func buildProactiveSignalSnapshot(
        profile: ProfileSettings?,
        dashboard: DashboardData?,
        inquirySummary: String?,
        memories: [MaxMemoryRecord],
        language: String
    ) -> ProactiveSignalSnapshot {
        let isEn = language == "en"
        var lines: [String] = []

        var avgSleepHours: Double?
        var avgStress: Double?
        var avgAnxiety: Double?
        if let logs = dashboard?.weeklyLogs, !logs.isEmpty {
            let sleepSamples = logs.compactMap { $0.sleep_duration_minutes }.map { Double($0) / 60.0 }
            let stressSamples = logs.compactMap { $0.stress_level }.map(Double.init)
            let anxietySamples = logs.compactMap { $0.anxiety_level }.map(Double.init)

            if !sleepSamples.isEmpty {
                avgSleepHours = sleepSamples.reduce(0, +) / Double(sleepSamples.count)
            }
            if !stressSamples.isEmpty {
                avgStress = stressSamples.reduce(0, +) / Double(stressSamples.count)
            }
            if !anxietySamples.isEmpty {
                avgAnxiety = anxietySamples.reduce(0, +) / Double(anxietySamples.count)
            }
        }

        if let focus = profile?.current_focus ?? profile?.primary_goal, !focus.isEmpty {
            lines.append(isEn ? "- Focus: \(focus)" : "- 当前关注：\(focus)")
        }
        if let avgSleepHours {
            lines.append(isEn ? "- Avg sleep (7d): \(String(format: "%.1f", avgSleepHours))h" : "- 近7天平均睡眠：\(String(format: "%.1f", avgSleepHours))小时")
        }
        if let avgStress {
            lines.append(isEn ? "- Avg stress (7d): \(String(format: "%.1f", avgStress))/10" : "- 近7天平均压力：\(String(format: "%.1f", avgStress))/10")
        }
        if let avgAnxiety {
            lines.append(isEn ? "- Avg anxiety (7d): \(String(format: "%.1f", avgAnxiety))/10" : "- 近7天平均焦虑：\(String(format: "%.1f", avgAnxiety))/10")
        }
        if let inquirySummary, !inquirySummary.isEmpty {
            lines.append(isEn ? "- Inquiry summary available" : "- 已有主动问询摘要")
        }
        if !memories.isEmpty {
            let topTags = memories.prefix(3).map { memory in
                String(memory.content_text.replacingOccurrences(of: "\n", with: " ").prefix(32))
            }
            lines.append((isEn ? "- Recent memory cues: " : "- 最近记忆线索：") + topTags.joined(separator: " | "))
        }

        let focusLower = (profile?.current_focus ?? profile?.primary_goal ?? "").lowercased()
        let memoryText = memories.prefix(6).map { $0.content_text.lowercased() }.joined(separator: " ")

        let primaryFocus: String
        let scientificQuery: String
        if let avgSleepHours, avgSleepHours < 6.5
            || focusLower.contains("sleep")
            || memoryText.contains("sleep")
            || memoryText.contains("insomnia")
            || memoryText.contains("失眠")
            || memoryText.contains("睡眠") {
            primaryFocus = isEn ? "sleep stabilization" : "睡眠节律稳定"
            scientificQuery = "sleep duration anxiety regulation circadian light intervention randomized trial"
        } else if let avgStress, avgStress >= 7
            || focusLower.contains("stress")
            || memoryText.contains("stress")
            || memoryText.contains("压力")
            || memoryText.contains("心慌") {
            primaryFocus = isEn ? "physiological down-regulation" : "生理唤醒下调"
            scientificQuery = "slow breathing heart rate variability stress reduction randomized trial anxiety"
        } else if let avgAnxiety, avgAnxiety >= 6
            || focusLower.contains("anxiety")
            || memoryText.contains("anxiety")
            || memoryText.contains("焦虑")
            || memoryText.contains("panic")
            || memoryText.contains("惊恐") {
            primaryFocus = isEn ? "anxiety trigger regulation" : "焦虑触发调节"
            scientificQuery = "behavioral activation anxiety treatment meta analysis daily implementation"
        } else {
            primaryFocus = isEn ? "rhythm and consistency" : "节律与一致性"
            scientificQuery = "daily routine consistency anxiety stress resilience prospective study"
        }

        if lines.isEmpty {
            lines = [isEn ? "- Signals are limited; prioritize low-friction action." : "- 当前信号有限，优先低阻力动作。"]
        }

        return ProactiveSignalSnapshot(
            lines: lines,
            primaryFocus: primaryFocus,
            scientificQuery: scientificQuery
        )
    }

    private func parseProactiveCareBrief(
        _ raw: String,
        generatedAt: String,
        language: String,
        evidenceFallback: RankedScientificPaper?
    ) -> ProactiveCareBrief? {
        let payloadData = extractJSONPayload(from: raw) ?? raw.data(using: .utf8)
        guard let payloadData,
              let parsed = try? JSONDecoder().decode(ProactiveBriefLLMResponse.self, from: payloadData) else {
            return nil
        }

        let title = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let understanding = parsed.understanding?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mechanism = parsed.mechanism?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let action = parsed.micro_action?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let followUp = parsed.follow_up_question?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty, !understanding.isEmpty, !mechanism.isEmpty, !action.isEmpty, !followUp.isEmpty else {
            return nil
        }

        let confidence = min(0.98, max(0.3, parsed.confidence ?? 0.62))
        let evidenceTitle = (parsed.evidence_title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? parsed.evidence_title
            : evidenceFallback?.title
        let evidenceURL = (parsed.evidence_url?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? parsed.evidence_url
            : evidenceFallback?.url

        return ProactiveCareBrief(
            id: UUID().uuidString,
            title: title,
            understanding: understanding,
            mechanism: mechanism,
            microAction: action,
            followUpQuestion: followUp,
            evidenceTitle: evidenceTitle,
            evidenceURL: evidenceURL,
            confidence: confidence,
            generatedAt: generatedAt
        )
    }

    private func buildFallbackProactiveCareBrief(
        generatedAt: String,
        language: String,
        snapshot: ProactiveSignalSnapshot,
        evidence: RankedScientificPaper?
    ) -> ProactiveCareBrief {
        let isEn = language == "en"
        let title: String
        let understanding: String
        let mechanism: String
        let action: String
        let followUp: String

        if snapshot.primaryFocus.contains("睡眠") || snapshot.primaryFocus.contains("sleep") {
            title = isEn ? "Stabilize tonight's sleep window" : "先稳住今晚睡眠窗口"
            understanding = isEn
                ? "Your recent pattern suggests sleep rhythm is likely amplifying daytime anxiety reactivity."
                : "你最近的节律提示：睡眠窗口不稳，正在放大白天焦虑反应。"
            mechanism = isEn
                ? "When sleep timing drifts, threat sensitivity and autonomic arousal rise; consistency lowers this load."
                : "当睡眠时点漂移时，威胁敏感性与自主神经唤醒会上升；节律一致性能降低这部分负荷。"
            action = isEn
                ? "Set a fixed bedtime tonight and do 3 minutes of slow breathing before bed."
                : "今晚固定入睡时间，睡前做 3 分钟慢呼吸。"
            followUp = isEn
                ? "Tomorrow morning, how rested do you feel on a 0-10 scale?"
                : "明天早晨你的恢复感是几分（0-10）？"
        } else if snapshot.primaryFocus.contains("唤醒") || snapshot.primaryFocus.contains("regulation") {
            title = isEn ? "Lower arousal before problem-solving" : "先降唤醒，再做问题处理"
            understanding = isEn
                ? "Your recent signals point to high arousal load rather than lack of effort."
                : "你最近更像是处在高唤醒负荷，而不是“做得不够”。"
            mechanism = isEn
                ? "High arousal narrows attention and exaggerates threat signals; short down-regulation restores control."
                : "高唤醒会收窄注意并放大威胁信号；短时下调能先恢复可控感。"
            action = isEn
                ? "Do 2 rounds of inhale-4s / exhale-6s, then take an 8-minute walk."
                : "先做 2 轮吸4秒-呼6秒呼吸，再快走 8 分钟。"
            followUp = isEn
                ? "After the action, how much did tension drop (0-10)?"
                : "动作后你的紧张度下降了几分（0-10）？"
        } else {
            title = isEn ? "Keep one low-friction rhythm anchor" : "先守住一个低阻力节律锚点"
            understanding = isEn
                ? "Your current trajectory benefits most from consistency, not intensity."
                : "你当前最需要的是一致性，而不是强度。"
            mechanism = isEn
                ? "Small repeatable behaviors reduce uncertainty and gradually retrain anxiety loops."
                : "可重复的小动作会降低不确定感，并逐步重塑焦虑回路。"
            action = isEn
                ? "Pick one 10-minute action and complete it at the same time today."
                : "选一个 10 分钟动作，并在今天固定时段完成。"
            followUp = isEn
                ? "Did you complete it on schedule, and what was your body score (0-10)?"
                : "你是否按时完成？完成后体感评分是多少（0-10）？"
        }

        return ProactiveCareBrief(
            id: UUID().uuidString,
            title: title,
            understanding: understanding,
            mechanism: mechanism,
            microAction: action,
            followUpQuestion: followUp,
            evidenceTitle: evidence?.title,
            evidenceURL: evidence?.url,
            confidence: 0.58,
            generatedAt: generatedAt
        )
    }
}

// MARK: - Errors

enum SupabaseError: LocalizedError {
    case authenticationFailed
    case notAuthenticated
    case requestFailed
    case decodingFailed
    case missingSupabaseConfiguration(keys: [String])
    case missingAppApiBaseUrl
    case appApiRequiresRemote
    case appApiCircuitOpen
    
    var errorDescription: String? {
        switch self {
        case .authenticationFailed: return "登录失败，请检查邮箱和密码"
        case .notAuthenticated: return "请先登录"
        case .requestFailed: return "请求失败"
        case .decodingFailed: return "数据解析失败"
        case .missingSupabaseConfiguration(let keys):
            let joined = keys.isEmpty ? "SUPABASE_URL, SUPABASE_ANON_KEY" : keys.joined(separator: ", ")
            return "Supabase 配置缺失：\(joined)"
        case .missingAppApiBaseUrl: return "未配置 APP_API_BASE_URL"
        case .appApiRequiresRemote: return "Max 云端暂不可用，已切换本地模式；请检查 APP_API_BASE_URL 或网络后重试"
        case .appApiCircuitOpen: return "云端连接已短暂熔断，正在快速恢复中，请稍后重试"
        }
    }
}
