import Foundation

enum MaxFormatStyle: String {
    case structured
    case conversational
    case concise
    case detailed
    case plan
}

enum MaxCitationStyle: String {
    case formal
    case casual
    case minimal
}

struct MaxVariationStrategy {
    let formatStyle: MaxFormatStyle
    let endearment: String?
    let citationStyle: MaxCitationStyle
    let shouldMentionHealthContext: Bool
    let responseTemplate: String
}

enum MaxResponseVariation {
    private static let endearmentPoolZh = ["朋友", "同伴", "你"]
    private static let endearmentPoolEn = ["friend", "partner", "you"]
    private static let formatTemplatesZh: [MaxFormatStyle: String] = [
        .structured: """
输出偏好：
- 可以使用短标题，但不要固定成同一模板
- 优先“理解 + 机制 + 动作 + 跟进”流程
- 每轮只保留最必要的结构
""",
        .conversational: """
回复风格：
- 自然但保持结构完整
- 避免空泛安慰
- 每轮都能推动进展
""",
        .concise: """
回复风格：
- 简洁直接
- 不重复已知信息
- 优先给 1 个低阻力动作
""",
        .detailed: """
回复风格：
- 详细解释
- 优先机制与证据
- 结尾收敛到可执行动作
""",
        .plan: """
回复格式：
- 可使用 1-3 个编号步骤
- 每步都要可执行、可跟踪
- 结尾给一个可量化复盘问题
"""
    ]

    private static let formatTemplatesEn: [MaxFormatStyle: String] = [
        .structured: """
Response preference:
- Short headings are optional, but avoid fixed repeated templates
- Prefer a compact flow of understanding -> mechanism -> action -> follow-up
- Keep only the structure that is necessary for this turn
""",
        .conversational: """
Response style:
- Natural flow with clinical clarity
- Avoid empty reassurance
- Move progress forward in this turn
""",
        .concise: """
Response style:
- Concise and direct
- Do not repeat known context
- Prioritize one low-friction action
""",
        .detailed: """
Response style:
- More detail when needed
- Prioritize mechanism and evidence quality
- Converge to a concrete action at the end
""",
        .plan: """
Response format:
- Use up to 1-3 numbered steps when useful
- Each step must be executable and trackable
- End with one measurable review question
"""
    ]

    private static let citationTemplatesZh: [MaxCitationStyle: String] = [
        .formal: "引用格式：使用 [1], [2] 标注，末尾列出参考文献",
        .casual: "引用格式：自然地提及研究发现，如\"研究表明...\"",
        .minimal: "引用格式：仅在必要时简短提及，不重复已引用的论文"
    ]

    private static let citationTemplatesEn: [MaxCitationStyle: String] = [
        .formal: "Citation style: use [1], [2] tags and list references only when truly needed",
        .casual: "Citation style: natural phrasing like \"evidence suggests...\" without bibliography overload",
        .minimal: "Citation style: keep citations minimal and avoid repeating already-cited studies"
    ]

    static func selectVariationStrategy(
        state: MaxConversationState,
        language: String = "zh"
    ) -> MaxVariationStrategy {
        let formatStyle = selectFormatStyle(turnCount: state.turnCount, usedFormats: state.usedFormats)
        let endearment = selectEndearment(
            turnCount: state.turnCount,
            usedEndearments: state.usedEndearments,
            language: language
        )
        let citationStyle = selectCitationStyle(turnCount: state.turnCount, citedCount: state.citedPaperIds.count)
        let shouldMentionHealthContext = state.turnCount <= 1 && !state.mentionedHealthContext
        let isEn = language == "en"
        let responseTemplate = (isEn ? formatTemplatesEn : formatTemplatesZh)[formatStyle] ?? ""

        return MaxVariationStrategy(
            formatStyle: formatStyle,
            endearment: endearment,
            citationStyle: citationStyle,
            shouldMentionHealthContext: shouldMentionHealthContext,
            responseTemplate: responseTemplate
        )
    }

    static func generateVariationInstructions(
        strategy: MaxVariationStrategy,
        language: String = "zh"
    ) -> String {
        let isEn = language == "en"
        var parts: [String] = []
        parts.append(isEn ? "[RESPONSE VARIATION INSTRUCTIONS]" : "[RESPONSE VARIATION INSTRUCTIONS - 回复变化指令]")
        parts.append("")
        parts.append(strategy.responseTemplate)
        parts.append("")
        parts.append((isEn ? citationTemplatesEn : citationTemplatesZh)[strategy.citationStyle] ?? "")
        if let endearment = strategy.endearment {
            parts.append(
                isEn
                    ? "\nAddressing: you may use \"\(endearment)\" occasionally, but not every sentence"
                    : "\n称呼：可以使用\"\(endearment)\"，但不要每句都用"
            )
        } else {
            parts.append(
                isEn
                    ? "\nAddressing: skip explicit endearments in this turn and keep it natural"
                    : "\n称呼：这次不使用特定称呼语，保持自然"
            )
        }

        if !strategy.shouldMentionHealthContext {
            if isEn {
                parts.append("\nImportant: do not restate the same anxiety focus that was already mentioned in prior turns")
                parts.append("Answer directly; avoid starting with \"Considering your XXX condition...\"")
            } else {
                parts.append("\n⚠️ 重要：不要重复提及用户的焦虑重点，已经在之前的对话中说过了")
                parts.append("直接回答问题，不要以\"考虑到你的XXX状况\"开头")
            }
        }

        if isEn {
            parts.append("\nAvoid repetition:")
            parts.append("- Do not reuse the exact same response structure as the last reply")
            parts.append("- Do not repeat studies already cited unless there is new angle")
            parts.append("- Do not re-explain concepts already established")
        } else {
            parts.append("\n⚠️ 避免重复：")
            parts.append("- 不要使用和上一条回复相同的格式结构")
            parts.append("- 不要重复引用已经引用过的论文")
            parts.append("- 不要重复解释已经解释过的概念")
        }

        return parts.joined(separator: "\n")
    }

    private static func selectFormatStyle(turnCount: Int, usedFormats: [String]) -> MaxFormatStyle {
        if turnCount <= 1 {
            return .structured
        }
        let lastFormat = usedFormats.last
        let rotation: [MaxFormatStyle] = [.conversational, .concise, .detailed, .structured]
        for format in rotation {
            if format.rawValue != lastFormat {
                return format
            }
        }
        return .conversational
    }

    private static func selectEndearment(
        turnCount: Int,
        usedEndearments: [String],
        language: String
    ) -> String? {
        if turnCount % 3 != 1 {
            return nil
        }
        let pool = language == "en" ? endearmentPoolEn : endearmentPoolZh
        let unused = pool.filter { !usedEndearments.contains($0) }
        if unused.isEmpty {
            let lastUsed = usedEndearments.last
            let available = pool.filter { $0 != lastUsed }
            guard !available.isEmpty else { return nil }
            let index = (turnCount + usedEndearments.count) % available.count
            return available[index]
        }
        let index = (turnCount + usedEndearments.count) % unused.count
        return unused[index]
    }

    private static func selectCitationStyle(turnCount: Int, citedCount: Int) -> MaxCitationStyle {
        if turnCount <= 1 {
            return .formal
        }
        if citedCount >= 3 {
            return .minimal
        }
        return .casual
    }
}
