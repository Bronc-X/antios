import Foundation

extension SupabaseManager {
    // MARK: - Clinical Service

    func clinicalCompletionKey(for userId: String) -> String {
        clinicalCompletionCachePrefix + userId
    }

    func cachedClinicalCompletion(for userId: String) -> Bool? {
        let key = clinicalCompletionKey(for: userId)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.bool(forKey: key)
    }

    func setCachedClinicalCompletion(_ complete: Bool, for userId: String) {
        let key = clinicalCompletionKey(for: userId)
        UserDefaults.standard.set(complete, forKey: key)
    }

    func applyCachedClinicalCompletion(for userId: String) {
        guard let cached = cachedClinicalCompletion(for: userId) else { return }
        isClinicalComplete = cached
    }

    func persistClinicalCompletionForCurrentUserIfNeeded() {
        guard let userId = currentUser?.id, !userId.isEmpty else { return }
        setCachedClinicalCompletion(isClinicalComplete, for: userId)
    }

    func ensureProfileRow() async {
        guard let user = currentUser else { return }

        do {
            let endpoint = "profiles?id=eq.\(user.id)&select=id&limit=1"
            let results: [ProfileRow] = try await request(endpoint)
            if !results.isEmpty { return }
        } catch {
            print("[SupabaseManager] ⚠️ ensureProfileRow select failed: \(error)")
        }

        do {
            let payload = ProfileUpsertPayload(id: user.id, email: user.email, inferred_scale_scores: nil)
            try await requestVoid(
                "profiles?on_conflict=id",
                method: "POST",
                body: payload,
                prefer: "resolution=merge-duplicates,return=representation"
            )
            print("[SupabaseManager] ✅ profile row ensured")
        } catch {
            print("[SupabaseManager] ⚠️ ensureProfileRow upsert failed: \(error)")
        }
    }

    func upsertClinicalScores(_ scores: [String: Int]) async throws {
        guard let user = currentUser else { throw SupabaseError.notAuthenticated }

        let payload = ProfileUpsertPayload(id: user.id, email: user.email, inferred_scale_scores: scores)
        try await requestVoid(
            "profiles?on_conflict=id",
            method: "POST",
            body: payload,
            prefer: "resolution=merge-duplicates,return=representation"
        )
        isClinicalComplete = true
        await captureUserSignal(
            domain: "clinical",
            action: "scores_upserted",
            summary: scores.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "),
            metadata: [
                "scores": scores,
                "score_count": scores.count
            ]
        )
    }

    func checkClinicalStatus() async {
        print("[SupabaseManager] 开始检查临床量表状态...")
        guard let user = currentUser else {
            isClinicalComplete = false
            return
        }
        let cachedCompletion = cachedClinicalCompletion(for: user.id)
        do {
            var profile = try await getProfileSettings()
            if profile == nil {
                await ensureProfileRow()
                profile = try await getProfileSettings()
            }
            guard let profile else {
                print("[SupabaseManager] ❌ 未获取到 profile")
                isClinicalComplete = cachedCompletion ?? false
                return
            }
            print("[SupabaseManager] 获取到 profile，inferred_scale_scores = \(String(describing: profile.inferred_scale_scores))")
            if let scores = profile.inferred_scale_scores, !scores.isEmpty {
                isClinicalComplete = true
                print("[SupabaseManager] ✅ isClinicalComplete = true")
            } else if cachedCompletion == true {
                isClinicalComplete = true
                print("[SupabaseManager] ⚠️ profile 暂无 scores，保留本地已完成状态")
            } else {
                isClinicalComplete = false
                print("[SupabaseManager] ⚠️ isClinicalComplete = false (no scores)")
            }
        } catch {
            print("[SupabaseManager] ❌ Check clinical status error: \(error)")
            if let cached = cachedCompletion {
                isClinicalComplete = cached
                print("[SupabaseManager] ⚠️ 使用本地临床状态缓存：\(cached)")
            }
        }
    }
}
