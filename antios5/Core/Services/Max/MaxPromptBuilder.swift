import Foundation

struct MaxPromptInput {
    let conversationState: MaxConversationState
    let aiSettings: AISettings?
    let aiPersonaContext: String?
    let personality: String?
    let healthFocus: String?
    let inquirySummary: String?
    let memoryContext: String?
    let playbookContext: String?
    let contextBlock: String?
    let language: String
}

enum MaxPromptBuilder {
    static func build(input: MaxPromptInput) -> String {
        var parts: [String] = []
        parts.append(buildDynamicPersonaPrompt(
            personality: input.personality ?? "max",
            aiSettings: input.aiSettings,
            aiPersonaContext: input.aiPersonaContext
        ))
        parts.append("")
        parts.append(MaxPersonaPrompt.fullSystemPrompt(turnCount: input.conversationState.turnCount))
        parts.append("")
        parts.append("""
[SCOPE & SAFETY]
- 仅处理焦虑、压力、睡眠、情绪调节、行为执行相关问题
- 遇到政治选举、博彩赔率、金融预测等话题，必须拒答并引导回反焦虑目标
- 不提供医疗诊断；如出现急性风险信号，建议联系专业机构
- 禁止编造研究、引用、数据或统计；没有可靠数据就直说未知
""")
        parts.append("""

[ANTI-ANXIETY RESPONSE FORMAT]
- 你是闭环编排器：理解 -> 机制解释 -> 证据 -> 动作 -> 跟进
- 回答必须严格包含以下 5 个小节（按顺序）：
1. 理解结论 / Understanding Conclusion
2. 机制解释 / Mechanism Explanation
3. 证据来源 / Evidence Sources
4. 可执行动作 / Executable Actions
5. 跟进问题 / Follow-up Question
- 禁止输出空小节；若证据不足，明确写“当前证据不足”
- 可执行动作必须 1-3 条、可在今天开始、低阻力且可追踪
- 跟进问题只能 1 条，并用于下一轮校准或行动复盘
""")
        parts.append("")
        let variation = MaxResponseVariation.selectVariationStrategy(state: input.conversationState)
        parts.append(MaxResponseVariation.generateVariationInstructions(strategy: variation))

        if let focus = input.healthFocus, !focus.isEmpty {
            parts.append("\n[USER FOCUS]")
            parts.append(focus)
        }

        if let inquirySummary = input.inquirySummary, !inquirySummary.isEmpty {
            parts.append("\n[INQUIRY CONTEXT]")
            parts.append(inquirySummary)
        }

        if let memoryContext = input.memoryContext, !memoryContext.isEmpty {
            parts.append("\n[MEMORY CONTEXT]")
            parts.append(memoryContext)
        }

        if let playbookContext = input.playbookContext, !playbookContext.isEmpty {
            parts.append("\n[PLAYBOOK CONTEXT]")
            parts.append(playbookContext)
        }

        if let contextBlock = input.contextBlock, !contextBlock.isEmpty {
            parts.append("\n" + contextBlock)
        }

        parts.append("\n[FINAL ANSWER ONLY]")
        if input.language == "en" {
            parts.append("- Output final answer in English")
            parts.append("- Use the English section titles exactly as listed above")
        } else {
            parts.append("- 只输出最终回答（中文）")
            parts.append("- 小节标题使用中文：理解结论 / 机制解释 / 证据来源 / 可执行动作 / 跟进问题")
        }
        parts.append("- 不要输出思考过程、推理内容或分析步骤")
        parts.append("- 禁止输出 <think> 标签或 reasoning_content")

        return parts.joined(separator: "\n")
    }

    private static func parseSettingsFromContext(_ context: String?) -> (honesty: Double, humor: Double) {
        guard let context, !context.isEmpty else {
            return (90, 65)
        }
        let honesty = extractPercent(from: context, pattern: "诚实度:\\s*(\\d+)%") ?? 90
        let humor = extractPercent(from: context, pattern: "幽默感:\\s*(\\d+)%") ?? 65
        return (honesty, humor)
    }

    private static func buildDynamicPersonaPrompt(
        personality: String,
        aiSettings: AISettings?,
        aiPersonaContext: String?
    ) -> String {
        var settings = aiSettings
        if settings?.honesty_level == nil {
            let parsed = parseSettingsFromContext(aiPersonaContext)
            settings = AISettings(honesty_level: parsed.honesty, humor_level: parsed.humor, mode: personality)
        }

        let honesty = settings?.honesty_level ?? 90
        let humor = settings?.humor_level ?? 65

        let modeStyles: [String: String] = [
            "max": "Prioritize brevity and dry, intellectual humor. Use Bayesian reasoning. Be crisp and to the point.",
            "zen_master": "Use calming, philosophical language. Guide with wisdom and patience. Speak with tranquility.",
            "dr_house": "Be blunt and diagnostic. Cut through the noise. Use medical expertise and evidence-based analysis."
        ]
        let modeStyle = modeStyles[personality] ?? modeStyles["max"]!
        let personalityName = (personality == "zen_master" ? "Zen Master" : personality == "dr_house" ? "Dr. House" : "MAX")

        let humorInstruction = humorInstructionText(humor)
        let honestyInstruction: String
        if honesty >= 90 {
            honestyInstruction = "Be direct and precise"
        } else if honesty >= 70 {
            honestyInstruction = "Be honest but tactful"
        } else if honesty >= 40 {
            honestyInstruction = "Be diplomatic and gentle"
        } else {
            honestyInstruction = "Be very gentle and supportive"
        }

        return """
[AI CONFIGURATION - \(personalityName)]

Current Settings:
- Honesty: \(Int(honesty))% (\(honestyInstruction))
- Humor: \(Int(humor))% - \(humorInstruction)
- Mode: \(personalityName) - \(modeStyle)

VOICE & TONE CALIBRATION:
- Honesty Calibration: \(honesty >= 70 ? "Speak truth clearly and avoid vague reassurance." : "Be supportive and frame things positively while remaining truthful.")
- Humor Calibration: \(humorInstruction)
- Relationship Style: calm, respectful, non-judgmental, never mock anxiety experiences

FORBIDDEN BEHAVIORS:
- Do not joke about the user's anxiety or panic episodes
- Do not fabricate papers, references, numbers, or certainty
- Do not give generic slogans without concrete actions

APPROVED PHRASES:
- "当前数据提示..."
- "机制上可以这样理解..."
- "可先执行这一步..."
- "我们下一轮用这个问题校准..."

VISUAL FORM:
Max is formless. Represented only by UI elements (The BrainLoader, The Glow), never a human avatar.
"""
    }

    private static func humorInstructionText(_ level: Double) -> String {
        if level >= 100 {
            return "High lightness allowed, but keep scientific rigor and respect."
        }
        if level >= 80 {
            return "HIGH LIGHTNESS: occasional playful analogies are acceptable"
        }
        if level >= 60 {
            return "MODERATE LIGHTNESS: one light remark at most"
        }
        if level >= 40 {
            return "LIGHT HUMOR: rare lightness while staying professional"
        }
        return "MINIMAL HUMOR: serious, calm and supportive"
    }

    private static func extractPercent(from text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: range),
           match.numberOfRanges > 1,
           let valueRange = Range(match.range(at: 1), in: text) {
            return Double(text[valueRange])
        }
        return nil
    }
}
