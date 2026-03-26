import Foundation

struct SciencePersonalizationContext {
    let language: AppLanguage
    let userId: String?
    let profile: ProfileSettings?
    let dashboard: DashboardData?
}

enum SciencePersonalizationEngine {
    private static let memorySimilarityThreshold = 0.58
    private static let personalizationLimit = 5

    static func personalize(
        articles: [ScienceArticle],
        context: SciencePersonalizationContext
    ) async -> [ScienceArticle] {
        guard !articles.isEmpty else { return [] }

        var enrichedPairs: [(Int, ScienceArticle)] = []
        enrichedPairs.reserveCapacity(articles.count)

        await withTaskGroup(of: (Int, ScienceArticle).self) { group in
            for (index, article) in articles.enumerated() {
                group.addTask {
                    let enriched: ScienceArticle
                    if index < personalizationLimit {
                        enriched = await enrichArticle(article, context: context, useMemoryRetrieval: true)
                    } else {
                        enriched = await enrichArticle(article, context: context, useMemoryRetrieval: false)
                    }
                    return (index, enriched)
                }
            }

            for await pair in group {
                enrichedPairs.append(pair)
            }
        }

        let ordered = enrichedPairs
            .sorted { $0.0 < $1.0 }
            .map(\.1)

        return ordered.sorted { lhs, rhs in
            let left = lhs.scoreBreakdown?.total ?? lhs.matchPercentage ?? 0
            let right = rhs.scoreBreakdown?.total ?? rhs.matchPercentage ?? 0
            if left == right {
                return lhs.createdAt ?? .distantPast > rhs.createdAt ?? .distantPast
            }
            return left > right
        }
    }

    private static func enrichArticle(
        _ article: ScienceArticle,
        context: SciencePersonalizationContext,
        useMemoryRetrieval: Bool
    ) async -> ScienceArticle {
        let articleText = [
            article.titleZh ?? article.title,
            article.summaryZh ?? article.summary,
            (article.tags ?? []).joined(separator: " ")
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        let memoryHit = await resolveMemoryHit(
            userId: context.userId,
            query: articleText,
            enabled: useMemoryRetrieval
        )
        let dominantTopic = detectDominantTopic(in: articleText)
        let signalInsight = signalInsight(from: context.dashboard)
        let focusLabel = normalizedFocus(from: context.profile, language: context.language)

        let historyScore = historyAlignmentScore(memoryHit: memoryHit, focusLabel: focusLabel)
        let signalScore = signalAlignmentScore(topic: dominantTopic, insight: signalInsight)
        let topicScore = topicAlignmentScore(topic: dominantTopic, focusLabel: focusLabel, articleText: articleText, tags: article.tags)
        let recencyScore = recencyScore(for: article.createdAt)
        let authorityScore = authorityScore(for: article.sourceType)

        let weightedTotal = (
            Double(historyScore) * 0.34 +
            Double(signalScore) * 0.26 +
            Double(topicScore) * 0.18 +
            Double(recencyScore) * 0.12 +
            Double(authorityScore) * 0.10
        )
        let total = Int(round(max(58, min(97, weightedTotal))))

        let breakdown = ScienceArticleScoreBreakdown(
            historyAlignment: historyScore,
            signalAlignment: signalScore,
            topicAlignment: topicScore,
            recency: recencyScore,
            authority: authorityScore,
            total: total
        )

        let reasons = buildReasons(
            topic: dominantTopic,
            focusLabel: focusLabel,
            signalInsight: signalInsight,
            memoryHit: memoryHit,
            sourceType: article.sourceType,
            language: context.language
        )
        let why = shouldReplaceReason(article.whyRecommended)
            ? reasons.joined(separator: " · ")
            : (article.whyRecommended ?? reasons.joined(separator: " · "))
        let actionable = actionableInsight(
            topic: dominantTopic,
            signalInsight: signalInsight,
            language: context.language
        )

        return article.applyingOverrides(
            whyRecommended: why,
            actionableInsight: actionable,
            matchPercentage: total,
            matchReasons: reasons,
            scoreBreakdown: breakdown
        )
    }

    private static func shouldReplaceReason(_ reason: String?) -> Bool {
        guard let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else {
            return true
        }

        let lowered = reason.lowercased()
        return lowered.contains("基于科学检索匹配")
            || lowered.contains("based on scientific retrieval")
            || lowered.contains("science retrieval")
            || lowered.count < 18
    }

    private static func resolveMemoryHit(
        userId: String?,
        query: String,
        enabled: Bool
    ) async -> (snippet: String, similarity: Double)? {
        guard enabled,
              let userId,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let memories = await MaxMemoryService.retrieveMemories(
            userId: userId,
            query: query,
            limit: 4
        )
        guard let best = memories.max(by: { ($0.similarity ?? 0) < ($1.similarity ?? 0) }),
              let similarity = best.similarity,
              similarity >= memorySimilarityThreshold else {
            return nil
        }

        let snippet = best.renderedContent
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !snippet.isEmpty else { return nil }
        let limited = snippet.count > 22 ? "\(snippet.prefix(22))…" : snippet
        return (limited, similarity)
    }

    private static func normalizedFocus(
        from profile: ProfileSettings?,
        language: AppLanguage
    ) -> String? {
        guard let raw = A10NonEmpty(profile?.current_focus) ?? A10NonEmpty(profile?.primary_goal) else {
            return nil
        }

        let isEn = language == .en
        switch raw {
        case "reduce_stress": return isEn ? "stress relief" : "减压"
        case "improve_sleep": return isEn ? "sleep repair" : "睡眠恢复"
        case "maintain_energy": return isEn ? "energy recovery" : "能量恢复"
        case "anxiety": return isEn ? "anxiety relief" : "焦虑缓解"
        case "sleep": return isEn ? "sleep repair" : "睡眠恢复"
        case "stress": return isEn ? "stress relief" : "压力管理"
        default: return raw
        }
    }

    private enum ArticleTopic {
        case sleep
        case stress
        case anxiety
        case mood
        case energy
        case recovery
        case general
    }

    private struct SignalInsight {
        let sleepLow: Bool
        let stressHigh: Bool
        let energyLow: Bool
        let readinessLow: Bool
        let hrvLow: Bool
        let restingHeartRateHigh: Bool
        let stepsLow: Bool
        let averageSleepHours: Double
        let stressScore: Int
        let energyScore: Int
        let readinessScore: Int
    }

    private static func detectDominantTopic(in text: String) -> ArticleTopic {
        let lowered = text.lowercased()
        if lowered.contains("sleep") || lowered.contains("insomnia") || lowered.contains("circadian") || lowered.contains("睡眠") || lowered.contains("失眠") {
            return .sleep
        }
        if lowered.contains("stress") || lowered.contains("cortisol") || lowered.contains("压力") || lowered.contains("皮质醇") {
            return .stress
        }
        if lowered.contains("anxiety") || lowered.contains("panic") || lowered.contains("焦虑") || lowered.contains("恐慌") {
            return .anxiety
        }
        if lowered.contains("mood") || lowered.contains("depression") || lowered.contains("情绪") || lowered.contains("抑郁") {
            return .mood
        }
        if lowered.contains("energy") || lowered.contains("fatigue") || lowered.contains("能量") || lowered.contains("疲劳") {
            return .energy
        }
        if lowered.contains("recovery") || lowered.contains("breathing") || lowered.contains("mindfulness") || lowered.contains("恢复") || lowered.contains("呼吸") || lowered.contains("正念") {
            return .recovery
        }
        return .general
    }

    private static func signalInsight(from dashboard: DashboardData?) -> SignalInsight {
        let avgSleep = dashboard?.averageSleepHours ?? 0
        let stress = dashboard?.todayLog?.anxiety_level
            ?? dashboard?.todayLog?.stress_level
            ?? Int((dashboard?.averageStress ?? 0).rounded())
        let energy = dashboard?.todayLog?.energy_level ?? dashboard?.todayLog?.morning_energy ?? 5
        let readiness = dashboard?.todayLog?.overall_readiness ?? 50
        let hrv = dashboard?.hardwareData?.hrv?.value ?? 0
        let rhr = dashboard?.hardwareData?.resting_heart_rate?.value ?? 0
        let steps = dashboard?.hardwareData?.steps?.value ?? 0

        return SignalInsight(
            sleepLow: avgSleep > 0 && avgSleep < 6.5,
            stressHigh: stress >= 6,
            energyLow: energy > 0 && energy <= 4,
            readinessLow: readiness > 0 && readiness < 55,
            hrvLow: hrv > 0 && hrv < 34,
            restingHeartRateHigh: rhr > 0 && rhr >= 72,
            stepsLow: steps > 0 && steps < 4500,
            averageSleepHours: avgSleep,
            stressScore: stress,
            energyScore: energy,
            readinessScore: readiness
        )
    }

    private static func historyAlignmentScore(
        memoryHit: (snippet: String, similarity: Double)?,
        focusLabel: String?
    ) -> Int {
        if let memoryHit {
            return Int(round(min(96, max(62, memoryHit.similarity * 100))))
        }
        if focusLabel != nil {
            return 72
        }
        return 58
    }

    private static func signalAlignmentScore(
        topic: ArticleTopic,
        insight: SignalInsight
    ) -> Int {
        switch topic {
        case .sleep:
            return insight.sleepLow ? 95 : (insight.readinessLow ? 78 : 62)
        case .stress, .anxiety, .recovery:
            if insight.stressHigh { return 94 }
            if insight.hrvLow || insight.restingHeartRateHigh { return 82 }
            return 64
        case .energy:
            if insight.energyLow { return 92 }
            if insight.stepsLow { return 76 }
            return 62
        case .mood:
            return insight.stressHigh ? 84 : 63
        case .general:
            if insight.readinessLow { return 76 }
            return 60
        }
    }

    private static func topicAlignmentScore(
        topic: ArticleTopic,
        focusLabel: String?,
        articleText: String,
        tags: [String]?
    ) -> Int {
        guard let focusLabel else {
            return topic == .general ? 60 : 68
        }

        let focusTerms = focusLabel
            .lowercased()
            .split(separator: " ")
            .map(String.init)
        let tagTerms = (tags ?? []).map { $0.lowercased() }
        let searchSpace = "\(articleText.lowercased()) \(tagTerms.joined(separator: " "))"
        let matches = focusTerms.filter { term in
            !term.isEmpty && searchSpace.contains(term)
        }

        if matches.count >= 2 { return 92 }
        if matches.count == 1 { return 80 }

        switch (topic, focusLabel) {
        case (.sleep, let label) where label.contains("睡眠") || label.contains("sleep"):
            return 88
        case (.stress, let label) where label.contains("减压") || label.contains("压力") || label.contains("stress") || label.contains("anxiety"),
             (.anxiety, let label) where label.contains("减压") || label.contains("压力") || label.contains("stress") || label.contains("anxiety"),
             (.recovery, let label) where label.contains("减压") || label.contains("压力") || label.contains("stress") || label.contains("anxiety"):
            return 86
        case (.energy, let label) where label.contains("能量") || label.contains("energy"):
            return 84
        default:
            return 64
        }
    }

    private static func recencyScore(for date: Date?) -> Int {
        guard let date else { return 58 }
        let days = Date().timeIntervalSince(date) / 86_400
        if days <= 14 { return 92 }
        if days <= 60 { return 82 }
        if days <= 180 { return 72 }
        if days <= 365 { return 62 }
        return 50
    }

    private static func authorityScore(for sourceType: String?) -> Int {
        switch sourceType?.lowercased() {
        case "nature", "science": return 98
        case "lancet", "cell": return 96
        case "pubmed": return 95
        case "semantic_scholar", "openalex": return 84
        case "journal": return 76
        case "research_institution", "university": return 72
        case "healthline": return 68
        default: return 60
        }
    }

    private static func buildReasons(
        topic: ArticleTopic,
        focusLabel: String?,
        signalInsight: SignalInsight,
        memoryHit: (snippet: String, similarity: Double)?,
        sourceType: String?,
        language: AppLanguage
    ) -> [String] {
        let isEn = language == .en
        var reasons: [String] = []

        if let memoryHit {
            reasons.append(
                isEn
                    ? "It aligns with your recent history \"\(memoryHit.snippet)\"."
                    : "它和你近期记录「\(memoryHit.snippet)」高度相关。"
            )
        }

        switch topic {
        case .sleep where signalInsight.sleepLow:
            reasons.append(
                isEn
                    ? String(format: "Your recent sleep average is %.1fh, and this article directly targets sleep repair.", signalInsight.averageSleepHours)
                    : String(format: "你近 7 天平均睡眠约 %.1f 小时，这篇文章直接对应睡眠恢复。", signalInsight.averageSleepHours)
            )
        case .stress, .anxiety, .recovery:
            if signalInsight.stressHigh {
                reasons.append(
                    isEn
                        ? "Your current stress/anxiety signal is elevated, and this paper targets regulation rather than generic motivation."
                        : "你当前压力/焦虑信号偏高，这篇文章瞄准的是调节机制，而不是泛泛鼓励。"
                )
            }
        case .energy where signalInsight.energyLow:
            reasons.append(
                isEn
                    ? "Your energy signal is low today, and this content focuses on restoring output without overloading you."
                    : "你今天的能量信号偏低，这篇内容更偏向低负担恢复，而不是继续加码。"
            )
        default:
            break
        }

        if let focusLabel, !focusLabel.isEmpty {
            reasons.append(
                isEn
                    ? "It overlaps with your current focus: \(focusLabel)."
                    : "它和你当前聚焦的「\(focusLabel)」高度重合。"
            )
        }

        if let sourceType = A10NonEmpty(sourceType) {
            reasons.append(
                isEn
                    ? "Its source quality is relatively strong (\(sourceType))."
                    : "它的来源质量相对更强（\(sourceType)）。"
            )
        }

        return Array(reasons.prefix(3))
    }

    private static func actionableInsight(
        topic: ArticleTopic,
        signalInsight: SignalInsight,
        language: AppLanguage
    ) -> String {
        let isEn = language == .en
        switch topic {
        case .sleep:
            return isEn
                ? "Tonight, anchor one stable bedtime and get 10 minutes of morning light tomorrow."
                : "今晚先固定一个入睡时间，明早补 10 分钟自然光。"
        case .stress, .anxiety, .recovery:
            return isEn
                ? "Start with 3 to 5 minutes of slow breathing before trying to solve the problem cognitively."
                : "先做 3 到 5 分钟慢呼吸，再去处理问题本身。"
        case .energy:
            return isEn
                ? "Use one 10-minute brisk walk or light mobility block instead of pushing intensity."
                : "先用 10 分钟快走或轻活动提能量，不要直接上强度。"
        case .mood:
            return isEn
                ? "Track one mood trigger today and pair it with a tiny recovery action."
                : "今天先记录一个情绪触发点，并配一个最小恢复动作。"
        case .general:
            if signalInsight.readinessLow {
                return isEn
                    ? "Favor recovery-first actions today and delay high-intensity decisions."
                    : "今天优先恢复动作，把高负担决定往后放。"
            }
            return isEn
                ? "Use the paper as evidence for one small change today, not a full routine rebuild."
                : "把这篇文章当作今天一个小改变的依据，不要一次性重构全部习惯。"
        }
    }
}
