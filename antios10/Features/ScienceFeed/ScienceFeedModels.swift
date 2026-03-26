// ScienceFeedModels.swift
// 科学期刊辅助数据模型
// 注意: ScienceArticle, ScienceFeedResponse, FeedPersonalization, FeedFeedbackInput
// 定义在 SupabaseManager.swift 中，此文件只包含 UI 辅助模型

import Foundation

/// 平台来源信息（UI 展示用）
struct PlatformInfo {
    let name: String
    let nameZh: String
    let icon: String
    let color: String  // Hex color
    
    static func forType(_ type: String?) -> PlatformInfo {
        switch type?.lowercased() {
        case "pubmed":
            return PlatformInfo(name: "PubMed", nameZh: "PubMed", icon: "📚", color: "#326599")
        case "semantic_scholar":
            return PlatformInfo(name: "Semantic Scholar", nameZh: "Semantic Scholar", icon: "🔬", color: "#1857B6")
        case "nature":
            return PlatformInfo(name: "Nature", nameZh: "Nature", icon: "🧬", color: "#C41E3A")
        case "science":
            return PlatformInfo(name: "Science", nameZh: "Science", icon: "⚗️", color: "#1A5276")
        case "lancet":
            return PlatformInfo(name: "The Lancet", nameZh: "The Lancet", icon: "🏥", color: "#00457C")
        case "cell":
            return PlatformInfo(name: "Cell", nameZh: "Cell", icon: "🔬", color: "#00A651")
        case "x":
            return PlatformInfo(name: "X", nameZh: "X", icon: "𝕏", color: "#111827")
        case "reddit":
            return PlatformInfo(name: "Reddit", nameZh: "Reddit", icon: "R", color: "#FF4500")
        default:
            return PlatformInfo(name: "Research", nameZh: "研究", icon: "📄", color: "#6B7280")
        }
    }
}

enum ScienceFeedCategory: String, CaseIterable, Identifiable {
    case all
    case sleep
    case anxiety
    case mindfulness
    case recommended

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch self {
        case .all:
            return language == .en ? "All" : "全部"
        case .sleep:
            return language == .en ? "Sleep" : "睡眠"
        case .anxiety:
            return language == .en ? "Anxiety" : "焦虑"
        case .mindfulness:
            return language == .en ? "Mindfulness" : "正念"
        case .recommended:
            return language == .en ? "Recommended" : "推荐"
        }
    }

    func matches(article: ScienceArticle) -> Bool {
        if self == .all { return true }
        if self == .recommended {
            return article.isRecommended == true
        }
        if let backendCategory = article.category?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !backendCategory.isEmpty {
            return backendCategory == rawValue
        }

        let text = [
            article.titleZh ?? article.title,
            article.summaryZh ?? article.summary,
            article.tags?.joined(separator: " ")
        ]
        .compactMap { $0?.lowercased() }
        .joined(separator: " ")
        return fallbackMatch(text)
    }

    private func fallbackMatch(_ text: String) -> Bool {
        switch self {
        case .sleep:
            return text.contains("sleep") || text.contains("睡眠") || text.contains("失眠")
        case .anxiety:
            return text.contains("anxiety") || text.contains("stress") || text.contains("焦虑") || text.contains("压力")
        case .mindfulness:
            return text.contains("mindfulness") || text.contains("meditation") || text.contains("正念") || text.contains("冥想") || text.contains("呼吸")
        case .recommended:
            return false
        case .all:
            return true
        }
    }
}

extension ScienceArticle {
    func applyingOverrides(
        whyRecommended: String?,
        actionableInsight: String?,
        matchPercentage: Int?,
        matchReasons: [String]? = nil,
        scoreBreakdown: ScienceArticleScoreBreakdown? = nil
    ) -> ScienceArticle {
        ScienceArticle(
            id: id,
            title: title,
            titleZh: titleZh,
            summary: summary,
            summaryZh: summaryZh,
            sourceType: sourceType,
            sourceUrl: sourceUrl,
            matchPercentage: matchPercentage ?? self.matchPercentage,
            category: category,
            isRecommended: isRecommended,
            whyRecommended: whyRecommended ?? self.whyRecommended,
            actionableInsight: actionableInsight ?? self.actionableInsight,
            tags: tags,
            createdAt: createdAt,
            matchReasons: matchReasons ?? self.matchReasons,
            scoreBreakdown: scoreBreakdown ?? self.scoreBreakdown
        )
    }
}
