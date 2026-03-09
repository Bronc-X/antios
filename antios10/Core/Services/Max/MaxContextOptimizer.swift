import Foundation

struct MaxContextDecision {
    let includeFullHealthContext: Bool
    let includeHealthReminder: Bool
    let healthContextText: String
    let excludePaperIds: [String]
    let filteredPapers: [ScientificPaperLite]
    let contextSummary: String
}

struct ScientificPaperLite: Equatable {
    let title: String
    let year: Int?
}

enum MaxContextOptimizer {
    static func optimize(
        state: MaxConversationState,
        healthFocus: String?,
        scientificPapers: [ScientificPaperLite],
        language: String = "zh"
    ) -> MaxContextDecision {
        var includeFull = false
        var includeReminder = false
        var healthText = ""
        if let focus = healthFocus, !focus.isEmpty {
            let decision = decideHealthContextInjection(
                state: state,
                healthFocus: focus,
                language: language
            )
            includeFull = decision.includeFull
            includeReminder = decision.includeReminder
            healthText = decision.text
        }

        let paperDecision = decidePaperInjection(state: state, papers: scientificPapers)
        let summary = generateContextSummary(
            state: state,
            healthFocus: healthFocus,
            language: language
        )

        return MaxContextDecision(
            includeFullHealthContext: includeFull,
            includeHealthReminder: includeReminder,
            healthContextText: healthText,
            excludePaperIds: paperDecision.excludeIds,
            filteredPapers: paperDecision.filteredPapers,
            contextSummary: summary
        )
    }

    static func buildContextBlock(decision: MaxContextDecision, language: String = "zh") -> String {
        let isEn = language == "en"
        var parts: [String] = []
        if !decision.healthContextText.isEmpty {
            parts.append(decision.healthContextText)
        }
        if !decision.filteredPapers.isEmpty {
            parts.append(isEn ? "\n[SCIENTIFIC CONTEXT]" : "\n[SCIENTIFIC CONTEXT - 科学上下文]")
            parts.append(
                isEn
                    ? "Candidate papers to cite (\(decision.filteredPapers.count)):"
                    : "可引用的新论文 (\(decision.filteredPapers.count)篇):"
            )
            for (index, paper) in decision.filteredPapers.prefix(5).enumerated() {
                parts.append("[\(index + 1)] \"\(paper.title)\" (\(paper.year.map(String.init) ?? "N/A"))")
            }
            if !decision.excludePaperIds.isEmpty {
                parts.append(
                    isEn
                        ? "\nPreviously cited papers (avoid full repeat citation):"
                        : "\n⚠️ 以下论文已在之前引用过，请勿重复完整引用："
                )
                parts.append(decision.excludePaperIds.prefix(3).joined(separator: ", "))
            }
        }
        if !decision.contextSummary.isEmpty {
            parts.append("\n[CONTEXT SUMMARY] \(decision.contextSummary)")
        }
        return parts.joined(separator: "\n")
    }

    private static func decideHealthContextInjection(
        state: MaxConversationState,
        healthFocus: String,
        language: String
    ) -> (includeFull: Bool, includeReminder: Bool, text: String) {
        if state.turnCount <= 1 && !state.mentionedHealthContext {
            return (true, false, buildFullHealthContext(healthFocus, language: language))
        }
        if state.mentionedHealthContext {
            return (false, true, buildHealthReminder(healthFocus, language: language))
        }
        return (false, true, buildHealthReminder(healthFocus, language: language))
    }

    private static func buildFullHealthContext(_ focus: String, language: String) -> String {
        if language == "en" {
            return """
[CRITICAL ANTI-ANXIETY CONTEXT]
Top current anxiety focus: \(focus)

Highest-priority handling requirements:
1. Keep this focus central in response planning.
2. If behavior likely worsens arousal, clearly flag the risk.
3. Output one executable action and one follow-up calibration question.

Note: first mention is allowed to reference this focus explicitly.
"""
        }
        return """
[CRITICAL ANTI-ANXIETY CONTEXT - 关键跟进上下文]
🚨 用户当前焦虑重点: \(focus)

⚠️ 这是最高优先级的上下文！你必须：
1. 在回答时优先围绕这个焦虑重点
2. 如果用户行为可能加重紧张反应，必须提醒风险
3. 输出可执行动作，并保留下一轮跟进问题

注意：这是第一次提及，可以在回复中说明\"考虑到你当前的\(focus)重点...\"
"""
    }

    private static func buildHealthReminder(_ focus: String, language: String) -> String {
        if language == "en" {
            return """
[ANTI-ANXIETY REMINDER]
User focus: \(focus)
Important: this focus was already mentioned in previous turns.
Do not start again with repetitive framing.
Answer directly and account for this focus implicitly.
"""
        }
        return """
[ANTI-ANXIETY REMINDER - 跟进提醒（内部参考）]
用户焦虑重点: \(focus)
⚠️ 重要：你已经在之前的对话中提及过这个重点了！
❌ 不要再次以\"考虑到你的XXX状况\"开头
✅ 直接回答问题，在必要时隐式考虑触发限制
"""
    }

    private static func decidePaperInjection(
        state: MaxConversationState,
        papers: [ScientificPaperLite]
    ) -> (excludeIds: [String], filteredPapers: [ScientificPaperLite]) {
        let cited = Set(state.citedPaperIds.map { $0.lowercased() })
        let filtered = papers.filter { !cited.contains($0.title.lowercased()) }
        let excludeIds = papers
            .filter { cited.contains($0.title.lowercased()) }
            .map { $0.title.lowercased() }
        return (excludeIds, filtered)
    }

    private static func generateContextSummary(state: MaxConversationState, healthFocus: String?) -> String {
        generateContextSummary(state: state, healthFocus: healthFocus, language: "zh")
    }

    private static func generateContextSummary(
        state: MaxConversationState,
        healthFocus: String?,
        language: String
    ) -> String {
        let isEn = language == "en"
        var parts: [String] = []
        if state.turnCount > 0 {
            parts.append(isEn ? "turns: \(state.turnCount)" : "对话轮次: \(state.turnCount)")
        }
        if !state.citedPaperIds.isEmpty {
            parts.append(
                isEn
                    ? "cited papers: \(state.citedPaperIds.count)"
                    : "已引用论文: \(state.citedPaperIds.count)篇"
            )
        }
        if !state.userSharedDetails.isEmpty {
            parts.append(
                isEn
                    ? "user details: \(state.userSharedDetails.prefix(3).joined(separator: ", "))"
                    : "用户分享的细节: \(state.userSharedDetails.prefix(3).joined(separator: ", "))"
            )
        }
        if let focus = healthFocus, !focus.isEmpty {
            parts.append(isEn ? "focus: \(focus)" : "用户目标/关注: \(focus)")
        }
        return parts.joined(separator: " | ")
    }
}
