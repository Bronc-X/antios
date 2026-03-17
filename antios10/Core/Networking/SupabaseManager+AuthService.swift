import Foundation

extension SupabaseManager {
    // MARK: - Auth Service

    func signUp(email: String, password: String) async throws {
        let config = try validatedSupabaseConfig()
        let url = config.url.appendingPathComponent("auth/v1/signup")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout(for: .auth)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")

        let body = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performDataRequestWithRetry(
            for: request,
            context: "Supabase signUp",
            hardTimeout: hardTimeout(for: request.timeoutInterval)
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw makeRequestFailure(
                context: "Supabase signUp invalid response",
                request: request,
                data: data
            )
        }

        if (200...299).contains(httpResponse.statusCode) {
            if let authResponse = try? JSONDecoder().decode(AuthResponse.self, from: data) {
                UserDefaults.standard.set(authResponse.accessToken, forKey: "supabase_access_token")
                UserDefaults.standard.set(authResponse.refreshToken, forKey: "supabase_refresh_token")
                currentUser = authResponse.user
                cacheAuthUser(authResponse.user)
                isAuthenticated = true
                triggerMemoryPipelineMaintenance()
                await ensureProfileRow()
                await checkClinicalStatus()
            } else {
                try await signIn(email: email, password: password)
            }
        } else {
            throw makeRequestFailure(
                context: "Supabase signUp status failure",
                request: request,
                response: httpResponse,
                data: data,
                fallbackReason: "注册失败"
            )
        }
    }

    func signIn(email: String, password: String) async throws {
        let config = try validatedSupabaseConfig()
        guard var components = URLComponents(url: config.url.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false) else {
            throw makeRequestFailure(
                context: "Supabase signIn invalid URL components",
                fallbackReason: "登录地址无效"
            )
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]

        guard let requestURL = components.url else {
            throw makeRequestFailure(
                context: "Supabase signIn invalid request URL",
                fallbackReason: "登录地址无效"
            )
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout(for: .auth)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")

        let body = ["email": email, "password": password]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performDataRequestWithRetry(
            for: request,
            context: "Supabase signIn",
            hardTimeout: hardTimeout(for: request.timeoutInterval)
        )

        #if DEBUG
        print("[SupabaseManager] signIn response bytes=\(data.count)")
        #endif

        guard let httpResponse = response as? HTTPURLResponse else {
            throw makeRequestFailure(
                context: "Supabase signIn invalid response",
                request: request,
                data: data,
                fallbackReason: "登录失败"
            )
        }

        if httpResponse.statusCode == 200 {
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            UserDefaults.standard.set(authResponse.accessToken, forKey: "supabase_access_token")
            UserDefaults.standard.set(authResponse.refreshToken, forKey: "supabase_refresh_token")

            currentUser = authResponse.user
            cacheAuthUser(authResponse.user)
            applyCachedClinicalCompletion(for: authResponse.user.id)

            await ensureProfileRow()
            await checkClinicalStatus()

            isAuthenticated = true
            triggerMemoryPipelineMaintenance()
        } else {
            throw makeRequestFailure(
                context: "Supabase signIn status failure",
                request: request,
                response: httpResponse,
                data: data,
                fallbackReason: "登录失败"
            )
        }
    }

    func signOut() async {
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_refresh_token")
        UserDefaults.standard.removeObject(forKey: cachedAuthUserKey)
        currentUser = nil
        isAuthenticated = false
        isClinicalComplete = false
        habitsBackendCache = nil
        reminderPreferencesColumnAvailable = nil
        Self.inquirySummaryCache.removeAll()
        Self.userContextCache.removeAll()
        Self.dashboardCache.removeAll()
        Self.ragContextCache.removeAll()
        Self.scientificBlockCache.removeAll()
        Self.profileCache.removeAll()
        Self.wearableSummaryCache.removeAll()
        clearAppAPINetworkState()
    }

    func checkSession() async {
        guard let token = UserDefaults.standard.string(forKey: "supabase_access_token") else {
            isAuthenticated = false
            isSessionRestored = true
            return
        }

        do {
            let user = try await getUser(token: token)
            currentUser = user
            applyCachedClinicalCompletion(for: user.id)
            isAuthenticated = true
            triggerMemoryPipelineMaintenance()
            await ensureProfileRow()
            await checkClinicalStatus()
        } catch {
            print("[SupabaseManager] access_token 无效，尝试刷新...")
            do {
                try await refreshSession()
                print("[SupabaseManager] ✅ Token 刷新成功")
            } catch let refreshError {
                print("[SupabaseManager] ❌ Token 刷新失败: \(refreshError)")
                if (isRetriableNetworkError(refreshError) || isHardTLSFailure(refreshError)),
                   let cachedUser = loadCachedAuthUser() {
                    currentUser = cachedUser
                    applyCachedClinicalCompletion(for: cachedUser.id)
                    isAuthenticated = true
                    triggerMemoryPipelineMaintenance()
                    print("[SupabaseManager] ⚠️ Supabase 网络不可达，已恢复本地缓存会话 userId=\(cachedUser.id)")
                } else {
                    isAuthenticated = false
                    isClinicalComplete = false
                }
            }
        }
        isSessionRestored = true
    }

    func refreshSession() async throws {
        guard let refreshToken = UserDefaults.standard.string(forKey: "supabase_refresh_token") else {
            throw SupabaseError.notAuthenticated
        }

        let config = try validatedSupabaseConfig()
        let url = config.url.appendingPathComponent("auth/v1/token")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw makeRequestFailure(
                context: "Supabase refreshSession invalid URL components",
                fallbackReason: "会话刷新地址无效"
            )
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        guard let requestURL = components.url else {
            throw makeRequestFailure(
                context: "Supabase refreshSession invalid request URL",
                fallbackReason: "会话刷新地址无效"
            )
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout(for: .auth)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")

        let body = ["refresh_token": refreshToken]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await performDataRequestWithRetry(
            for: request,
            context: "Supabase refreshSession",
            hardTimeout: hardTimeout(for: request.timeoutInterval)
        )

        guard let httpResponse = response as? HTTPURLResponse else {
            throw makeRequestFailure(
                context: "Supabase refreshSession invalid response",
                request: request,
                data: data,
                fallbackReason: "会话刷新失败"
            )
        }
        guard httpResponse.statusCode == 200 else {
            throw makeRequestFailure(
                context: "Supabase refreshSession status failure",
                request: request,
                response: httpResponse,
                data: data,
                fallbackReason: "会话刷新失败"
            )
        }

        let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
        UserDefaults.standard.set(authResponse.accessToken, forKey: "supabase_access_token")
        UserDefaults.standard.set(authResponse.refreshToken, forKey: "supabase_refresh_token")

        currentUser = authResponse.user
        cacheAuthUser(authResponse.user)
        applyCachedClinicalCompletion(for: authResponse.user.id)
        isAuthenticated = true
        triggerMemoryPipelineMaintenance()
        await ensureProfileRow()
        await checkClinicalStatus()
    }

    private func triggerMemoryPipelineMaintenance() {
        Task(priority: .utility) {
            MaxMemoryService.triggerPendingFlush()
        }
    }

    private func getUser(token: String) async throws -> AuthUser {
        let config = try validatedSupabaseConfig()
        let url = config.url.appendingPathComponent("auth/v1/user")
        var request = URLRequest(url: url)
        request.timeoutInterval = requestTimeout(for: .auth)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await performDataRequestWithRetry(
            for: request,
            context: "Supabase getUser",
            hardTimeout: hardTimeout(for: request.timeoutInterval)
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw makeRequestFailure(
                context: "Supabase getUser invalid response",
                request: request,
                data: data
            )
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw makeRequestFailure(
                context: "Supabase getUser status failure",
                request: request,
                response: httpResponse,
                data: data,
                fallbackReason: "获取用户信息失败"
            )
        }
        let user = try JSONDecoder().decode(AuthUser.self, from: data)
        cacheAuthUser(user)
        return user
    }

    private func cacheAuthUser(_ user: AuthUser) {
        guard let encoded = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(encoded, forKey: cachedAuthUserKey)
    }

    private func loadCachedAuthUser() -> AuthUser? {
        guard let encoded = UserDefaults.standard.data(forKey: cachedAuthUserKey),
              let user = try? JSONDecoder().decode(AuthUser.self, from: encoded) else {
            return nil
        }
        return user
    }
}
