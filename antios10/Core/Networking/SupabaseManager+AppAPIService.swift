import Foundation

extension SupabaseManager {
    // MARK: - App API Service

    enum AppAPIConfig {
        static let cachedBaseURLKey = "app_api_base_url_cached"
        static let overrideBaseURLKey = "app_api_base_url_override"
        static let resolvedAtKey = "app_api_base_url_resolved_at"
        static let healthPath = "api/health"
        static var maxChatPath: String {
            if let path = Bundle.main.infoDictionary?["APP_API_MAX_CHAT_PATH"] as? String {
                let sanitized = path.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sanitized.isEmpty {
                    return sanitized
                }
            }
            return "api/chat"
        }
        static var enforceSingleSource: Bool {
#if targetEnvironment(simulator)
            true
#else
            false
#endif
        }
        static var allowFallbackWhenUnreachable: Bool {
#if DEBUG
#if targetEnvironment(simulator)
            true
#else
            false
#endif
#else
            false
#endif
        }
        static var fallbackBaseURLs: [String] {
            var defaults = [
                "https://www.antianxiety.app",
                "https://antianxiety.app"
            ]
            if let raw = Bundle.main.infoDictionary?["APP_API_FALLBACK_BASE_URLS"] as? String {
                let extras = raw
                    .replacingOccurrences(of: "\\", with: "")
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                defaults.append(contentsOf: extras)
            }

            var seen: Set<String> = []
            return defaults.filter { candidate in
                let key = candidate.lowercased()
                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }
        }

        static var simulatorLocalFallbackBaseURLs: [String] {
#if DEBUG
#if targetEnvironment(simulator)
            [
                "http://localhost:3001",
                "http://127.0.0.1:3001",
                "http://localhost:3000",
                "http://127.0.0.1:3000"
            ]
#else
            []
#endif
#else
            []
#endif
        }
    }

    func refreshAppAPIBaseURL() async {
        if isAppAPICircuitOpen() {
            if let reason = Self.appAPICircuitReason {
                print("[AppAPI] Circuit open, skip refresh: \(reason)")
            }
            return
        }

        if AppAPIConfig.enforceSingleSource {
            guard let infoBase = appAPIBaseURLFromInfoPlist(),
                  let infoURL = URL(string: infoBase) else {
                print("[AppAPI] APP_API_BASE_URL missing.")
                return
            }
            if await isAppAPIHealthy(baseURL: infoURL) {
                cacheAppAPIBaseURL(infoURL)
                resetAppAPIFailureState()
                print("[AppAPI] Using fixed base URL: \(infoURL.absoluteString)")
                return
            }
            print("[AppAPI] Fixed base URL is unreachable: \(infoURL.absoluteString)")
            if AppAPIConfig.allowFallbackWhenUnreachable {
                let fallbackCandidates = appAPIFallbackCandidates(primary: infoURL)
                if let candidate = await firstHealthyAppAPIBaseURL(from: fallbackCandidates) {
                    cacheAppAPIBaseURL(candidate)
                    resetAppAPIFailureState()
                    print("[AppAPI] Fallback base URL: \(candidate.absoluteString)")
                    return
                }
                print("[AppAPI] No healthy fallback base URL found.")
                if let localRaw = AppAPIConfig.simulatorLocalFallbackBaseURLs.first,
                   let localURL = URL(string: localRaw) {
                    cacheAppAPIBaseURL(localURL)
                    print("[AppAPI] Force local fallback base URL: \(localURL.absoluteString)")
                    return
                }
            }
            registerAppAPIFailure(reason: "Fixed base unreachable", hardFailure: false)
            return
        }

        let candidates = appAPIBaseURLCandidates()
        guard !candidates.isEmpty else {
            print("[AppAPI] No base URL candidates.")
            return
        }

        if let candidate = await firstHealthyAppAPIBaseURL(from: candidates) {
            cacheAppAPIBaseURL(candidate)
            resetAppAPIFailureState()
            print("[AppAPI] Selected base URL: \(candidate.absoluteString)")
            return
        }

        if AppAPIConfig.allowFallbackWhenUnreachable,
           let localRaw = AppAPIConfig.simulatorLocalFallbackBaseURLs.first,
           let localURL = URL(string: localRaw) {
            cacheAppAPIBaseURL(localURL)
            print("[AppAPI] Force local base URL after remote failures: \(localURL.absoluteString)")
            return
        }

        registerAppAPIFailure(reason: "No healthy base URL found", hardFailure: false)
        print("[AppAPI] No healthy base URL found.")
    }

    func appAPIURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        guard let baseURL = currentAppAPIBaseURL() else {
            print("[appAPIURL] APP_API_BASE_URL missing.")
            return nil
        }
        return buildAppAPIURL(baseURL: baseURL, path: path, queryItems: queryItems)
    }

    func currentAppAPIBaseURLString() -> String? {
        currentAppAPIBaseURL()?.absoluteString
    }

    func clearAppAPINetworkState() {
        Self.appAPIHealthCooldownUntil.removeAll()
        resetAppAPIFailureState()
    }

    func resolveMaxAgentBaseURL() async throws -> URL {
        if let current = currentAppAPIBaseURL(), !isPrivateHost(current.host) {
            return current
        }

        let candidates = maxAgentBaseURLCandidates()
        guard !candidates.isEmpty else {
            print("[MaxAgent] ❌ 没有可用的远程 App API")
            throw SupabaseError.appApiRequiresRemote
        }

        if let candidate = await firstHealthyAppAPIBaseURL(from: candidates) {
            print("[MaxAgent] ✅ 使用远程 App API: \(candidate.absoluteString)")
            return candidate
        }

        print("[MaxAgent] ❌ 远程 App API 不可达")
        throw SupabaseError.appApiRequiresRemote
    }

    func buildAppAPIURL(baseURL: URL, path: String, queryItems: [URLQueryItem] = []) -> URL? {
        let baseString = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
        let sanitizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullURLString = sanitizedPath.isEmpty ? baseString : "\(baseString)/\(sanitizedPath)"

        var components = URLComponents(string: fullURLString)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        return components?.url
    }

    func attachSupabaseCookies(to request: inout URLRequest) {
        if let accessToken = SupabaseCredentialStore.token(for: .access) {
            let refreshToken = SupabaseCredentialStore.token(for: .refresh) ?? ""
            request.setValue("sb-access-token=\(accessToken); sb-refresh-token=\(refreshToken)", forHTTPHeaderField: "Cookie")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
            if let userId = currentUser?.id, !userId.isEmpty {
                request.setValue(userId, forHTTPHeaderField: "X-User-Id")
            }
            print("[SupabaseManager] 已附加认证信息到请求")
        } else {
            print("[SupabaseManager] ⚠️ 未找到 access_token，请先登录")
        }
    }

    func performAppAPIRequest(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        if isAppAPICircuitOpen() {
            throw SupabaseError.appApiCircuitOpen
        }

        do {
            return try await performAppAPIRequestOnce(request)
        } catch {
            registerAppAPIFailure(reason: networkErrorSummary(error), hardFailure: isHardTLSFailure(error))
            if shouldRetryAppAPIRequest(error, request: request) {
                await refreshAppAPIBaseURL()
                if let newBase = currentAppAPIBaseURL(),
                   let retryRequest = rebuildAppAPIRequest(request, baseURL: newBase) {
                    return try await performAppAPIRequestOnce(retryRequest)
                }
            }
            throw error
        }
    }

    func requestAppAPIRaw(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        timeout: TimeInterval = 0,
        contentType: String? = "application/json"
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = appAPIURL(path: path, queryItems: queryItems) else {
            throw SupabaseError.missingAppApiBaseUrl
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        let explicitTimeout = timeout > 0 ? timeout : nil
        request.timeoutInterval = requestTimeout(for: .appAPI, explicit: explicitTimeout)
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        attachSupabaseCookies(to: &request)
        request.httpBody = body
        return try await performAppAPIRequest(request)
    }

    private func currentAppAPIBaseURL() -> URL? {
        if AppAPIConfig.enforceSingleSource {
            if let overrideURL = loadAppAPIBaseURL(forKey: AppAPIConfig.overrideBaseURLKey) {
                return overrideURL
            }
            if let cachedURL = loadAppAPIBaseURL(forKey: AppAPIConfig.cachedBaseURLKey) {
                return cachedURL
            }
            if let infoBase = appAPIBaseURLFromInfoPlist(),
               let infoURL = URL(string: infoBase) {
                return infoURL
            }
            return nil
        }

        if let overrideURL = loadAppAPIBaseURL(forKey: AppAPIConfig.overrideBaseURLKey) {
            return overrideURL
        }
        if let cachedURL = loadAppAPIBaseURL(forKey: AppAPIConfig.cachedBaseURLKey) {
            if isSimulator, isPrivateHost(cachedURL.host) {
                let port = cachedURL.port ?? 3001
                return URL(string: "http://localhost:\(port)")
            }
            return cachedURL
        }

        if let infoBase = appAPIBaseURLFromInfoPlist(),
           let infoURL = URL(string: infoBase) {
            if !isSimulator, isPrivateHost(infoURL.host), let fallback = fallbackRemoteBaseURL() {
                return fallback
            }
            if isSimulator, isPrivateHost(infoURL.host) {
                let port = infoURL.port ?? 3001
                return URL(string: "http://localhost:\(port)")
            }
            return infoURL
        }

        if isSimulator {
            return URL(string: "http://localhost:3001") ?? URL(string: "http://localhost:3000")
        }

        return fallbackRemoteBaseURL()
    }

    private func appAPIBaseURLCandidates() -> [URL] {
        if AppAPIConfig.enforceSingleSource {
            if let infoBase = appAPIBaseURLFromInfoPlist(),
               let infoURL = URL(string: infoBase) {
                return [infoURL]
            }
            return []
        }

        var candidates: [URL] = []
        var seen: Set<String> = []

        func addCandidate(_ raw: String?) {
            guard let raw = raw,
                  let sanitized = sanitizeAppAPIBaseURLString(raw),
                  let url = URL(string: sanitized),
                  url.scheme != nil,
                  url.host != nil else {
                return
            }
            let key = sanitized.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                candidates.append(url)
            }
        }

        addCandidate(UserDefaults.standard.string(forKey: AppAPIConfig.overrideBaseURLKey))
        addCandidate(UserDefaults.standard.string(forKey: AppAPIConfig.cachedBaseURLKey))

        if isSimulator {
            addCandidate("http://localhost:3001")
            addCandidate("http://localhost:3000")
        }

        if let infoBase = appAPIBaseURLFromInfoPlist() {
            addCandidate(infoBase)
            if let infoURL = URL(string: infoBase),
               let host = infoURL.host,
               let scheme = infoURL.scheme,
               let port = infoURL.port {
                let altPort: Int?
                if port == 3001 {
                    altPort = 3000
                } else if port == 3000 {
                    altPort = 3001
                } else {
                    altPort = nil
                }
                if let altPort = altPort {
                    addCandidate("\(scheme)://\(host):\(altPort)")
                }
            }
        }

        AppAPIConfig.fallbackBaseURLs.forEach { addCandidate($0) }

        return candidates
    }

    private func maxAgentBaseURLCandidates() -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func addCandidate(_ raw: String?) {
            guard let raw = raw,
                  let sanitized = sanitizeAppAPIBaseURLString(raw),
                  let url = URL(string: sanitized),
                  url.scheme != nil,
                  url.host != nil else {
                return
            }
            let key = sanitized.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                candidates.append(url)
            }
        }

        addCandidate(UserDefaults.standard.string(forKey: AppAPIConfig.overrideBaseURLKey))
        addCandidate(UserDefaults.standard.string(forKey: AppAPIConfig.cachedBaseURLKey))
        addCandidate(appAPIBaseURLFromInfoPlist())
        AppAPIConfig.fallbackBaseURLs.forEach { addCandidate($0) }

        return candidates.filter { !isPrivateHost($0.host) }
    }

    private func appAPIBaseURLFromInfoPlist() -> String? {
        guard let baseURLString = Bundle.main.infoDictionary?["APP_API_BASE_URL"] as? String else {
            return nil
        }
        return sanitizeAppAPIBaseURLString(baseURLString)
    }

    private func sanitizeAppAPIBaseURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "")
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        guard let url = URL(string: normalized),
              let scheme = url.scheme,
              !scheme.isEmpty,
              url.host != nil else {
            return nil
        }
        return normalized
    }

    private func clearAppAPIOverrides() {
        UserDefaults.standard.removeObject(forKey: AppAPIConfig.overrideBaseURLKey)
        UserDefaults.standard.removeObject(forKey: AppAPIConfig.cachedBaseURLKey)
        UserDefaults.standard.removeObject(forKey: AppAPIConfig.resolvedAtKey)
    }

    private func loadAppAPIBaseURL(forKey key: String) -> URL? {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let sanitized = sanitizeAppAPIBaseURLString(raw),
              let url = URL(string: sanitized) else {
            return nil
        }
        return url
    }

    private func cacheAppAPIBaseURL(_ url: URL) {
        var resolvedURL = url
        if isSimulator, isPrivateHost(resolvedURL.host) {
            let port = resolvedURL.port ?? 3001
            if let localURL = URL(string: "http://localhost:\(port)") {
                resolvedURL = localURL
            }
        }
        let value = resolvedURL.absoluteString.hasSuffix("/") ? String(resolvedURL.absoluteString.dropLast()) : resolvedURL.absoluteString
        UserDefaults.standard.set(value, forKey: AppAPIConfig.cachedBaseURLKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppAPIConfig.resolvedAtKey)
    }

    private func fallbackRemoteBaseURL() -> URL? {
        for raw in AppAPIConfig.fallbackBaseURLs {
            guard let sanitized = sanitizeAppAPIBaseURLString(raw),
                  let url = URL(string: sanitized),
                  url.scheme != nil,
                  url.host != nil else {
                continue
            }
            return url
        }
        return nil
    }

    private func isAppAPIHealthy(baseURL: URL) async -> Bool {
        if isAppAPICircuitOpen() {
            return false
        }

        let cooldownKey = appAPIHealthCooldownKey(for: baseURL)
        if let cooldownUntil = Self.appAPIHealthCooldownUntil[cooldownKey], cooldownUntil > Date() {
            return false
        }

        guard let url = buildAppAPIURL(baseURL: baseURL, path: AppAPIConfig.healthPath) else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = appAPIHealthProbeTimeout

        do {
            let (data, response) = try await performDataRequestWithRetry(
                for: request,
                session: NetworkSession.appAPI,
                context: "AppAPI health \(baseURL.host ?? "unknown")",
                maxAttempts: 1,
                hardTimeout: hardTimeout(for: request.timeoutInterval)
            )
            if let httpResponse = response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    Self.appAPIHealthCooldownUntil[cooldownKey] = Date().addingTimeInterval(appAPIHealthCooldownTTL)
                    registerAppAPIFailure(reason: "Health status \(httpResponse.statusCode)", hardFailure: false)
                    return false
                }
                if let payload = try? JSONDecoder().decode(AppAPIHealthPayload.self, from: data) {
                    if let healthSupabase = payload.supabaseUrl,
                       let healthHost = URL(string: healthSupabase)?.host?.lowercased(),
                       let localHost = SupabaseConfig.url?.host?.lowercased(),
                       healthHost != localHost {
                        print("[AppAPI] Health check mismatch: \(healthHost) != \(localHost)")
                        Self.appAPIHealthCooldownUntil[cooldownKey] = Date().addingTimeInterval(appAPIHealthCooldownTTL)
                        registerAppAPIFailure(reason: "Health host mismatch", hardFailure: false)
                        return false
                    }
                }
                Self.appAPIHealthCooldownUntil.removeValue(forKey: cooldownKey)
                resetAppAPIFailureState()
                return true
            }
        } catch {
            let summary = networkErrorSummary(error)
            print("[AppAPI] Health check failed for \(baseURL.absoluteString): \(summary)")
            Self.appAPIHealthCooldownUntil[cooldownKey] = Date().addingTimeInterval(appAPIHealthCooldownTTL)
            registerAppAPIFailure(reason: summary, hardFailure: isHardTLSFailure(error))
            return false
        }
        return false
    }

    private func appAPIHealthCooldownKey(for baseURL: URL) -> String {
        let host = baseURL.host?.lowercased() ?? baseURL.absoluteString.lowercased()
        if let port = baseURL.port {
            return "\(host):\(port)"
        }
        return host
    }

    private func appAPIFallbackCandidates(primary: URL) -> [URL] {
        var candidates: [URL] = []
        var seen: Set<String> = []

        func addCandidate(_ raw: String?) {
            guard let raw = raw,
                  let sanitized = sanitizeAppAPIBaseURLString(raw),
                  let url = URL(string: sanitized),
                  url.scheme != nil,
                  url.host != nil,
                  !isPrivateHost(url.host) else {
                return
            }
            let key = sanitized.lowercased()
            if !seen.contains(key) && url.absoluteString != primary.absoluteString {
                seen.insert(key)
                candidates.append(url)
            }
        }

        AppAPIConfig.fallbackBaseURLs.forEach { addCandidate($0) }

        AppAPIConfig.simulatorLocalFallbackBaseURLs.forEach { raw in
            guard let sanitized = sanitizeAppAPIBaseURLString(raw),
                  let url = URL(string: sanitized),
                  url.scheme != nil,
                  url.host != nil else {
                return
            }
            let key = sanitized.lowercased()
            if !seen.contains(key) && url.absoluteString != primary.absoluteString {
                seen.insert(key)
                candidates.append(url)
            }
        }

        return candidates
    }

    private func firstHealthyAppAPIBaseURL(from candidates: [URL]) async -> URL? {
        guard !candidates.isEmpty else { return nil }

        return await withTaskGroup(of: URL?.self, returning: URL?.self) { group in
            for candidate in candidates {
                group.addTask { [self] in
                    await isAppAPIHealthy(baseURL: candidate) ? candidate : nil
                }
            }

            for await result in group {
                if let healthy = result {
                    group.cancelAll()
                    return healthy
                }
            }
            return nil
        }
    }

    private func isAppAPICircuitOpen() -> Bool {
        if let until = Self.appAPICircuitUntil, until > Date() {
            return true
        }

        if Self.appAPICircuitUntil != nil {
            Self.appAPICircuitUntil = nil
            Self.appAPICircuitReason = nil
            Self.appAPIFailureCount = 0
        }
        return false
    }

    private func resetAppAPIFailureState() {
        Self.appAPIFailureCount = 0
        Self.appAPICircuitUntil = nil
        Self.appAPICircuitReason = nil
    }

    private func registerAppAPIFailure(reason: String, hardFailure: Bool) {
        if hardFailure {
            Self.appAPIFailureCount = appAPIFailureThreshold
        } else {
            Self.appAPIFailureCount += 1
        }

        guard Self.appAPIFailureCount >= appAPIFailureThreshold else { return }
        Self.appAPICircuitReason = reason
        Self.appAPICircuitUntil = Date().addingTimeInterval(appAPICircuitTTL)
        print("[AppAPI] Circuit opened for \(Int(appAPICircuitTTL))s: \(reason)")
    }

    private struct AppAPIHealthPayload: Decodable {
        let ok: Bool?
        let timestamp: String?
        let supabaseUrl: String?
    }

    private func ensureAppAPIBaseURLReady() async {
        if let current = currentAppAPIBaseURL(), isPrivateHost(current.host) {
            await refreshAppAPIBaseURL()
        }
    }

    private var isSimulator: Bool {
#if targetEnvironment(simulator)
        true
#else
        false
#endif
    }

    private func isPrivateHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        if host == "localhost" || host == "127.0.0.1" { return true }
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count > 1, let second = Int(parts[1]) {
                return (16...31).contains(second)
            }
        }
        return false
    }

    private func performAppAPIRequestOnce(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await performDataRequestWithRetry(
            for: request,
            session: NetworkSession.appAPI,
            context: "AppAPI \(request.httpMethod ?? "GET") \(request.url?.path ?? "")",
            maxAttempts: 1,
            hardTimeout: hardTimeout(for: request.timeoutInterval)
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw makeRequestFailure(
                context: "AppAPI invalid response",
                request: request,
                data: data
            )
        }

        if httpResponse.statusCode == 401 {
            try await refreshSession()
            var retryRequest = request
            attachSupabaseCookies(to: &retryRequest)
            let (retryData, retryResponse) = try await performDataRequestWithRetry(
                for: retryRequest,
                session: NetworkSession.appAPI,
                context: "AppAPI retry \(retryRequest.httpMethod ?? "GET") \(retryRequest.url?.path ?? "")",
                maxAttempts: 1,
                hardTimeout: hardTimeout(for: retryRequest.timeoutInterval)
            )
            guard let retryHttp = retryResponse as? HTTPURLResponse else {
                throw makeRequestFailure(
                    context: "AppAPI retry invalid response",
                    request: retryRequest,
                    data: retryData
                )
            }
            resetAppAPIFailureState()
            return (retryData, retryHttp)
        }

        resetAppAPIFailureState()
        return (data, httpResponse)
    }

    private func shouldRetryAppAPIRequest(_ error: Error, request: URLRequest) -> Bool {
        if isHardTLSFailure(error) {
            return false
        }

        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }

        switch nsError.code {
        case URLError.Code.cannotConnectToHost.rawValue,
             URLError.Code.cannotFindHost.rawValue,
             URLError.Code.notConnectedToInternet.rawValue,
             URLError.Code.networkConnectionLost.rawValue,
             URLError.Code.timedOut.rawValue,
             URLError.Code.dnsLookupFailed.rawValue:
            return true
        default:
            if let url = request.url, isPrivateHost(url.host), nsError.code == URLError.Code.badServerResponse.rawValue {
                return true
            }
            return false
        }
    }

    private func rebuildAppAPIRequest(_ request: URLRequest, baseURL: URL) -> URLRequest? {
        guard let originalURL = request.url else { return nil }
        let originalComponents = URLComponents(url: originalURL, resolvingAgainstBaseURL: false)
        let path = originalComponents?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let queryItems = originalComponents?.queryItems ?? []
        guard let newURL = buildAppAPIURL(baseURL: baseURL, path: path, queryItems: queryItems) else {
            return nil
        }
        var newRequest = request
        newRequest.url = newURL
        return newRequest
    }
}
