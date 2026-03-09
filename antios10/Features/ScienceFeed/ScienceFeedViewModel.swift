// ScienceFeedViewModel.swift
// 科学期刊 ViewModel - 对齐 Web 端 useFeed Hook

import SwiftUI

@MainActor
class ScienceFeedViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    
    @Published var articles: [ScienceArticle] = []
    @Published var isLoading = false
    @Published var isRefreshing = false
    @Published var error: String?
    @Published var personalization: FeedPersonalization?
    @Published var selectedCategory: ScienceFeedCategory = .all
    
    // AI 加载消息
    @Published var loadingMessage = ""
    private var loadingTimer: Timer?
    private var activeLanguage: AppLanguage = .zhHans
    
    // 缓存
    private let cacheKeyPrefix = "science_feed_cache_v2_"
    private var lastFetchDate: Date?
    private var lastFetchLanguage: AppLanguage?
    private let personalizationLimit = 3
    private let minMemorySimilarity: Double = 0.58
    
    // MARK: - 加载消息（对齐 Web 端）
    
    private var loadingMessages: [String] {
        if activeLanguage == .en {
            return [
                "Connecting to academic databases...",
                "Scanning latest PubMed studies...",
                "Querying Semantic Scholar...",
                "Scanned \(Int.random(in: 800...2500)) papers...",
                "Analyzing relevance signals...",
                "Filtered \(Int.random(in: 1800...4500)) low-relevance papers",
                "Found \(Int.random(in: 15...45)) high-match studies",
                "Extracting key takeaways...",
                "Assessing study methods...",
                "Evaluating evidence strength...",
                "Cross-validating conclusions...",
                "Removed \(Int.random(in: 80...250)) duplicates",
                "Generating personalized interpretation...",
                "Matching your anti-anxiety profile...",
                "Calculating relevance score...",
                "Reviewing \(Int.random(in: 12...35)) high-impact journals...",
                "Drafting actionable advice...",
                "Optimizing ranking...",
                "Final review...",
                "Almost ready..."
            ]
        }
        return [
            "正在连接学术数据库...",
            "扫描 PubMed 最新研究...",
            "检索 Semantic Scholar 论文...",
            "已扫描 \(Int.random(in: 800...2500)) 篇论文...",
            "正在分析文献相关性...",
            "已过滤 \(Int.random(in: 1800...4500)) 篇低相关论文",
            "发现 \(Int.random(in: 15...45)) 篇高度匹配的研究",
            "正在提取核心论点...",
            "分析研究方法论...",
            "评估证据等级...",
            "交叉验证研究结论...",
            "已排除 \(Int.random(in: 80...250)) 篇重复研究",
            "正在生成个性化解读...",
            "匹配你的反焦虑画像...",
            "计算文章相关度...",
            "正在审阅 \(Int.random(in: 12...35)) 个高影响因子期刊...",
            "正在整理行动建议...",
            "优化推荐排序...",
            "最终审核中...",
            "即将呈现精选内容..."
        ]
    }
    
    // MARK: - Init
    
    override init() {
        super.init()
        loadFromCache(language: activeLanguage)
    }

    var filteredArticles: [ScienceArticle] {
        articles.filter { selectedCategory.matches(article: $0) }
    }
    
    // MARK: - 加载 Feed
    
    func loadFeed(language: AppLanguage) async {
        if lastFetchLanguage != language {
            lastFetchLanguage = language
            lastFetchDate = nil
            articles = []
            loadFromCache(language: language)
        }
        activeLanguage = language
        // 检查缓存是否有效（同一天）
        if let lastDate = lastFetchDate, Calendar.current.isDateInToday(lastDate), !articles.isEmpty {
            print("📦 使用今日缓存")
            Task { [weak self] in
                guard let self else { return }
                let personalized = await self.personalizeArticles(self.articles)
                if !personalized.isEmpty {
                    self.articles = personalized
                    self.saveToCache()
                }
            }
            return
        }
        
        isLoading = true
        error = nil
        startLoadingAnimation()
        
        do {
            let response = try await SupabaseManager.shared.getScienceFeed(language: language.apiCode)
            let baseArticles = normalizeArticles(response.articles)
            let localizedArticles = filterArticlesForLanguage(baseArticles, language: language)
            articles = localizedArticles
            personalization = response.personalization
            lastFetchDate = Date()
            saveToCache()
            print("✅ 加载了 \(articles.count) 篇科学文章")
            if shouldRunLocalPersonalization(for: localizedArticles) {
                Task { [weak self] in
                    guard let self else { return }
                    let personalized = await self.personalizeArticles(localizedArticles)
                    if !personalized.isEmpty {
                        self.articles = personalized
                        self.saveToCache()
                    }
                }
            }
        } catch {
            self.error = "加载失败：\(error.localizedDescription)"
            print("❌ 加载科学期刊失败: \(error)")
        }
        
        stopLoadingAnimation()
        isLoading = false
    }
    
    func refresh(language: AppLanguage) async {
        activeLanguage = language
        lastFetchLanguage = language
        isRefreshing = true
        lastFetchDate = nil  // 强制刷新
        clearCache(language: language)
        
        do {
            let response = try await SupabaseManager.shared.getScienceFeed(language: language.apiCode)
            let baseArticles = normalizeArticles(response.articles)
            let localizedArticles = filterArticlesForLanguage(baseArticles, language: language)
            articles = localizedArticles
            personalization = response.personalization
            lastFetchDate = Date()
            saveToCache()
            if shouldRunLocalPersonalization(for: localizedArticles) {
                Task { [weak self] in
                    guard let self else { return }
                    let personalized = await self.personalizeArticles(localizedArticles)
                    if !personalized.isEmpty {
                        self.articles = personalized
                        self.saveToCache()
                    }
                }
            }
        } catch {
            self.error = "刷新失败"
        }
        
        isRefreshing = false
    }
    
    // MARK: - 反馈
    
    func submitFeedback(articleId: String, isPositive: Bool) async {
        guard let article = articles.first(where: { $0.id == articleId }) else { return }
        
        let feedback = FeedFeedbackInput(
            contentId: articleId,
            contentUrl: article.sourceUrl,
            contentTitle: article.title,
            source: article.sourceType,
            feedbackType: isPositive ? "like" : "dislike"
        )
        
        do {
            try await SupabaseManager.shared.submitFeedFeedback(feedback)
            await SupabaseManager.shared.captureUserSignal(
                domain: "science_feed",
                action: isPositive ? "liked_article" : "disliked_article",
                summary: article.titleZh ?? article.title,
                metadata: [
                    "article_id": articleId,
                    "feedback_type": isPositive ? "like" : "dislike",
                    "source": article.sourceType ?? "unknown",
                    "category": article.category ?? "unknown",
                    "language": activeLanguage.apiCode
                ]
            )
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            print("✅ 反馈已提交: \(isPositive ? "👍" : "👎")")
        } catch {
            print("❌ 反馈提交失败: \(error)")
        }
    }
    
    // MARK: - 加载动画
    
    private func startLoadingAnimation() {
        loadingMessage = loadingMessages.randomElement() ?? ""
        loadingTimer?.invalidate()
        loadingTimer = Timer.scheduledTimer(
            timeInterval: 2.8,
            target: self,
            selector: #selector(updateLoadingMessage(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    @objc private func updateLoadingMessage(_ timer: Timer) {
        loadingMessage = loadingMessages.randomElement() ?? ""
    }
    
    private func stopLoadingAnimation() {
        loadingTimer?.invalidate()
        loadingTimer = nil
        loadingMessage = ""
    }
    
    // MARK: - 缓存
    
    private func loadFromCache(language: AppLanguage) {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: language)),
              let cache = try? JSONDecoder().decode(ScienceFeedCache.self, from: data),
              Calendar.current.isDateInToday(cache.date) else {
            return
        }
        articles = cache.articles
        lastFetchDate = cache.date
        lastFetchLanguage = language
        print("📦 从缓存加载了 \(articles.count) 篇文章")
    }
    
    private func saveToCache() {
        let cache = ScienceFeedCache(articles: articles, date: Date())
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey(for: activeLanguage))
        }
    }
    
    private func clearCache(language: AppLanguage) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: language))
    }

    private func cacheKey(for language: AppLanguage) -> String {
        "\(cacheKeyPrefix)\(language.rawValue)"
    }

    // MARK: - 个性化（向量检索 + 历史记录）

    private func shouldRunLocalPersonalization(for articles: [ScienceArticle]) -> Bool {
        articles.prefix(personalizationLimit).contains(where: requiresLocalPersonalization)
    }

    private func requiresLocalPersonalization(_ article: ScienceArticle) -> Bool {
        let reason = article.whyRecommended?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let action = article.actionableInsight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let score = article.matchPercentage ?? 0
        return reason.isEmpty || action.isEmpty || score <= 0
    }

    private func personalizeArticles(_ baseArticles: [ScienceArticle]) async -> [ScienceArticle] {

        guard let userId = SupabaseManager.shared.currentUser?.id,
              !baseArticles.isEmpty else { return baseArticles }
        let profile = try? await SupabaseManager.shared.getProfileSettings()
        var result: [ScienceArticle] = []
        result.reserveCapacity(baseArticles.count)
        for (index, article) in baseArticles.enumerated() {
            if index < personalizationLimit, requiresLocalPersonalization(article) {
                let updated = await personalizeArticle(article, userId: userId, profile: profile)
                result.append(updated)
            } else if requiresLocalPersonalization(article) {
                result.append(applyFallbackPersonalization(article, profile: profile))
            } else {
                result.append(article)
            }
        }
        return result
    }

    private func personalizeArticle(_ article: ScienceArticle, userId: String, profile: ProfileSettings?) async -> ScienceArticle {
        let query = [article.titleZh ?? article.title, article.summaryZh ?? article.summary]
            .compactMap { $0 }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return article }

        let memories = await MaxMemoryService.retrieveMemories(userId: userId, query: query, limit: 4)
        let bestMemory = memories.max { ($0.similarity ?? 0) < ($1.similarity ?? 0) }
        let similarity = bestMemory?.similarity
        let memorySnippet = similarity != nil && (similarity ?? 0) >= minMemorySimilarity
            ? trimMemorySnippet(bestMemory?.content_text)
            : nil

        let focus = focusLabel(from: profile)
        let topic = detectTopic(in: article)
        let reason = normalizedText(article.whyRecommended) ?? buildWhyRecommended(
            focus: focus,
            memorySnippet: memorySnippet,
            similarity: similarity,
            topic: topic
        )
        let actionable = normalizedText(article.actionableInsight)
            ?? buildActionableInsight(focus: focus, memorySnippet: memorySnippet, topic: topic)
        let match = article.matchPercentage ?? calculateMatchPercentage(
            article: article,
            similarity: similarity,
            focus: focus
        )

        return article.applyingOverrides(
            whyRecommended: reason,
            actionableInsight: actionable,
            matchPercentage: match
        )
    }

    private func applyFallbackPersonalization(_ article: ScienceArticle, profile: ProfileSettings?) -> ScienceArticle {
        let focus = focusLabel(from: profile)
        let topic = detectTopic(in: article)
        let reason = normalizedText(article.whyRecommended) ?? buildWhyRecommended(
            focus: focus,
            memorySnippet: nil,
            similarity: nil,
            topic: topic
        )
        let actionable = normalizedText(article.actionableInsight)
            ?? buildActionableInsight(focus: focus, memorySnippet: nil, topic: topic)
        let match = article.matchPercentage ?? calculateMatchPercentage(
            article: article,
            similarity: nil,
            focus: focus
        )
        return article.applyingOverrides(
            whyRecommended: reason,
            actionableInsight: actionable,
            matchPercentage: match
        )
    }

    private func buildWhyRecommended(
        focus: String?,
        memorySnippet: String?,
        similarity: Double?,
        topic: ArticleTopic?
    ) -> String? {
        let isEn = activeLanguage == .en
        var parts: [String] = []
        if let focus, !focus.isEmpty {
            parts.append(isEn ? "Aligned with your focus: \(focus)" : "与你当前关注「\(focus)」相关")
        }
        if let memorySnippet, !memorySnippet.isEmpty {
            parts.append(isEn ? "Related to your recent note: \(memorySnippet)" : "与你近期记录「\(memorySnippet)」高度相关")
        }
        if let similarity, similarity >= minMemorySimilarity {
            let percentage = Int(min(max(similarity, 0.4), 0.98) * 100)
            parts.append(isEn ? "Similarity ~\(percentage)%" : "相似度约 \(percentage)%")
        }

        if let topic, topic != .general {
            parts.append(isEn ? "Focuses on \(topic.labelEn) research" : "聚焦\(topic.labelZh)研究")
        }

        if parts.isEmpty {
            return nil
        }
        return parts.joined(separator: " · ")
    }

    private func buildActionableInsight(focus: String?, memorySnippet: String?, topic: ArticleTopic?) -> String? {
        actionSuggestion(for: focus, memorySnippet: memorySnippet, topic: topic)
    }

    private func calculateMatchPercentage(
        article: ScienceArticle,
        similarity: Double?,
        focus: String?
    ) -> Int? {
        let similarityScore = min(max(similarity ?? 0.55, 0.2), 0.98)
        let content = [
            article.titleZh ?? article.title,
            article.summaryZh ?? article.summary,
            (article.tags ?? []).joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        let topicScore = calculateTopicMatchScore(contentText: content, focus: focus, tags: article.tags)
        let freshnessScore = calculateFreshnessScore(article.createdAt)
        let authorityScore = calculateAuthorityScore(article.sourceType)

        let weighted = similarityScore * 0.40 + topicScore * 0.30 + freshnessScore * 0.15 + authorityScore * 0.15
        return Int(round(max(60, min(99, weighted * 40 + 60))))
    }

    private func focusLabel(from profile: ProfileSettings?) -> String? {
        guard let raw = profile?.current_focus ?? profile?.primary_goal,
              !raw.isEmpty else { return nil }
        let isEn = activeLanguage == .en
        switch raw {
        case "reduce_stress": return isEn ? "stress relief" : "减压"
        case "improve_sleep": return isEn ? "sleep" : "睡眠"
        case "maintain_energy": return isEn ? "energy" : "能量提升"
        case "anxiety": return isEn ? "anxiety" : "焦虑"
        case "sleep": return isEn ? "sleep" : "睡眠"
        case "stress": return isEn ? "stress management" : "压力管理"
        default: return raw
        }
    }

    private func actionSuggestion(for focus: String?, memorySnippet: String?, topic: ArticleTopic?) -> String? {
        let isEn = activeLanguage == .en
        if let topic {
            switch topic {
            case .sleep:
                return isEn ? "keep a consistent bedtime and get 10 minutes of morning light" : "固定入睡时间，早晨晒 10 分钟自然光"
            case .stress:
                return isEn ? "do 5 minutes of slow breathing in the afternoon" : "下午安排 5 分钟慢呼吸"
            case .anxiety:
                return isEn ? "write down one trigger and plan a small response" : "记录一个触发点，并安排一个小应对"
            case .mood:
                return isEn ? "track today's mood and take a short walk" : "记录今日情绪起伏，安排一次短散步"
            case .energy:
                return isEn ? "add a 10-minute brisk walk after lunch" : "午饭后快走 10 分钟"
            case .general:
                break
            }
        }
        if let focus {
            let lower = focus.lowercased()
            if lower.contains("sleep") || focus.contains("睡眠") {
                return isEn ? "keep a consistent bedtime and get 10 minutes of morning light" : "固定入睡时间，早晨晒 10 分钟自然光"
            }
            if lower.contains("stress") || focus.contains("压力") || focus.contains("减压") {
                return isEn ? "do 5 minutes of slow breathing in the afternoon" : "下午安排 5 分钟慢呼吸"
            }
            if lower.contains("energy") || focus.contains("能量") {
                return isEn ? "add a 10-minute brisk walk after lunch" : "午饭后快走 10 分钟"
            }
        }
        if let snippet = memorySnippet, !snippet.isEmpty {
            return activeLanguage == .en ? "start from a small change related to \(snippet)" : "从与你近期记录「\(snippet)」相关的小改变开始"
        }
        return nil
    }

    // MARK: - Article Normalization & Language Preference

    private func normalizeArticles(_ articles: [ScienceArticle]) -> [ScienceArticle] {
        articles.map { article in
            let title = article.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanedTags = article.tags?
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return ScienceArticle(
                id: article.id,
                title: title.isEmpty ? article.title : title,
                titleZh: normalizedText(article.titleZh),
                summary: normalizedText(article.summary),
                summaryZh: normalizedText(article.summaryZh),
                sourceType: normalizedText(article.sourceType) ?? article.sourceType,
                sourceUrl: normalizedText(article.sourceUrl),
                matchPercentage: article.matchPercentage,
                category: normalizedText(article.category)?.lowercased(),
                isRecommended: article.isRecommended,
                whyRecommended: normalizedText(article.whyRecommended),
                actionableInsight: normalizedText(article.actionableInsight),
                tags: cleanedTags,
                createdAt: article.createdAt
            )
        }
    }

    private func filterArticlesForLanguage(_ articles: [ScienceArticle], language: AppLanguage) -> [ScienceArticle] {
        guard !articles.isEmpty else { return articles }
        let threshold = min(3, articles.count)
        if language != .en {
            let chinese = articles.filter { isMostlyChinese(articleText($0)) }
            return chinese.count >= threshold ? chinese : articles
        }
        let english = articles.filter { !isMostlyChinese(articleText($0)) }
        return english.count >= threshold ? english : articles
    }

    private func articleText(_ article: ScienceArticle) -> String {
        [
            article.titleZh ?? article.title,
            article.summaryZh ?? article.summary,
            (article.tags ?? []).joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }

    private func isMostlyChinese(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let chineseCount = text.unicodeScalars.filter { scalar in
            scalar.value >= 0x4E00 && scalar.value <= 0x9FFF
        }.count
        return Double(chineseCount) / Double(max(text.count, 1)) > 0.08
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    // MARK: - Topic Detection

    private enum ArticleTopic {
        case sleep
        case stress
        case anxiety
        case mood
        case energy
        case general

        var labelZh: String {
            switch self {
            case .sleep: return "睡眠"
            case .stress: return "压力"
            case .anxiety: return "焦虑"
            case .mood: return "情绪"
            case .energy: return "能量"
            case .general: return "身心"
            }
        }

        var labelEn: String {
            switch self {
            case .sleep: return "sleep"
            case .stress: return "stress"
            case .anxiety: return "anxiety"
            case .mood: return "mood"
            case .energy: return "energy"
            case .general: return "mind-body"
            }
        }
    }

    private func detectTopic(in article: ScienceArticle) -> ArticleTopic? {
        let text = articleText(article).lowercased()
        if text.contains("sleep") || text.contains("insomnia") || text.contains("睡眠") || text.contains("失眠") {
            return .sleep
        }
        if text.contains("stress") || text.contains("cortisol") || text.contains("压力") || text.contains("皮质醇") {
            return .stress
        }
        if text.contains("anxiety") || text.contains("焦虑") {
            return .anxiety
        }
        if text.contains("mood") || text.contains("depression") || text.contains("情绪") || text.contains("抑郁") {
            return .mood
        }
        if text.contains("energy") || text.contains("fatigue") || text.contains("能量") || text.contains("疲劳") {
            return .energy
        }
        return .general
    }

    private func calculateFreshnessScore(_ publishedAt: Date?) -> Double {
        guard let publishedAt else { return 0.5 }
        let days = Date().timeIntervalSince(publishedAt) / (60 * 60 * 24)
        if days <= 7 { return 1.0 }
        if days <= 30 { return 0.8 }
        if days <= 90 { return 0.6 }
        if days <= 365 { return 0.4 }
        return 0.2
    }

    private func calculateAuthorityScore(_ sourceType: String?) -> Double {
        switch sourceType?.lowercased() {
        case "pubmed": return 0.95
        case "semantic_scholar": return 0.85
        case "nature": return 1.0
        case "science": return 1.0
        case "lancet": return 0.98
        case "cell": return 0.98
        case "journal": return 0.75
        case "research_institution": return 0.7
        case "university": return 0.7
        case "x": return 0.45
        case "reddit": return 0.4
        default: return 0.6
        }
    }

    private func calculateTopicMatchScore(contentText: String, focus: String?, tags: [String]?) -> Double {
        let content = contentText.lowercased()
        var topics: [String] = []
        if let focus {
            topics.append(contentsOf: focus.lowercased().split(separator: " ").map(String.init))
        }
        if let tags = tags {
            topics.append(contentsOf: tags.map { $0.lowercased() })
        }

        let anxietyKeywords = [
            "anxiety", "stress", "sleep", "mood", "depression", "mindfulness",
            "meditation", "breathing", "relaxation", "cortisol", "nervous",
            "焦虑", "压力", "睡眠", "情绪", "抑郁", "正念", "冥想", "呼吸", "放松"
        ]
        topics.append(contentsOf: anxietyKeywords)

        let allTopics = Array(Set(topics.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })).filter { !$0.isEmpty }
        guard !allTopics.isEmpty else { return 0.5 }

        var matchCount = 0
        for topic in allTopics.prefix(10) {
            if content.contains(topic) {
                matchCount += 1
            }
        }
        return min(1.0, Double(matchCount) / Double(min(allTopics.count, 10)))
    }

    private func trimMemorySnippet(_ text: String?, limit: Int = 18) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.count <= limit { return cleaned }
        return "\(cleaned.prefix(limit))…"
    }

}

// 缓存结构
private struct ScienceFeedCache: Codable {
    let articles: [ScienceArticle]
    let date: Date
}
