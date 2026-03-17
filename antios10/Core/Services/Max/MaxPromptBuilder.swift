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
        let isEn = input.language == "en"
        var parts: [String] = []

        parts.append(buildDynamicPersonaPrompt(
            personality: input.personality ?? "max",
            aiSettings: input.aiSettings,
            aiPersonaContext: input.aiPersonaContext,
            language: input.language
        ))
        parts.append("")
        parts.append(
            MaxPersonaPrompt.fullSystemPrompt(
                turnCount: input.conversationState.turnCount,
                language: input.language
            )
        )
        parts.append("")
        parts.append(
            isEn
                ? """
[SCOPE & SAFETY]
- Only handle anxiety, stress, sleep, emotional regulation, and execution-related topics
- Refuse election prediction, betting odds, financial forecasting; redirect to anti-anxiety support
- Do not provide diagnosis; if acute risk appears, guide to professional crisis resources
- Never fabricate studies, citations, numbers, or confidence; explicitly state uncertainty when needed
"""
                : """
[SCOPE & SAFETY]
- 仅处理焦虑、压力、睡眠、情绪调节、行为执行相关问题
- 遇到政治选举、博彩赔率、金融预测等话题，必须拒答并引导回反焦虑目标
- 不提供医疗诊断；如出现急性风险信号，建议联系专业机构
- 禁止编造研究、引用、数据或统计；没有可靠数据就直说未知
"""
        )
        parts.append(
            isEn
                ? """

[ADAPTIVE RESPONSE POLICY]
- You are an anti-anxiety follow-up orchestrator: understand -> mechanism -> action -> review, not a rigid form filler
- Decide the structure from the user's intent and current state; do not pick from a canned list of layouts
- A reply may be a short paragraph, a compact list, a numbered sequence, or a mixed form if that genuinely fits this turn
- Avoid reusing the same layout across consecutive turns
- Must include personalized details from user history/current signals/preferences
- If evidence is weak, say "evidence is limited" instead of fabricating sources
- Action must be feasible today, low-friction, and measurable
"""
                : """

[ADAPTIVE RESPONSE POLICY]
- 你是反焦虑跟进编排器：理解 -> 机制 -> 动作 -> 复盘，不是固定模板填空器
- 根据用户意图和当前状态自由组织回答，不要从预设版式清单里挑一个硬套
- 回答可以是一小段、一组短列表、编号步骤，或自然混合结构，只要这一轮真的合适
- 不要连续多轮使用同一种版式；优先避免机械重复
- 必须包含个性化要素（用户历史/当前信号/偏好）而非泛化句式
- 若证据不足，明确写“当前证据不足”，不要伪造来源
- 动作必须可在今天执行、低阻力、可衡量
"""
        )
        parts.append(
            isEn
                ? """

[OPTIONAL INLINE ACTION CARD]
- If opening an in-app capability would reduce user effort, you may append one optional action card after the natural-language answer
- Never replace the answer with the card; the card is an optional add-on
- Use at most 1 card with up to 3 actions
- Supported kinds: check_in, plan_review, breathing, inquiry, evidence, send_prompt, review_completed, review_too_hard, review_skipped
- Card format:
```max-actions
{"title":"Do the next step here","detail":"Keep the user in chat if possible","actions":[{"title":"Start check-in","kind":"check_in"},{"title":"Do 3-minute breathing","kind":"breathing","minutes":3}]}
```
"""
                : """

[OPTIONAL INLINE ACTION CARD]
- 如果调用 App 内能力能明显减少用户切换成本，可以在自然语言回答后追加一个可选动作卡
- 动作卡不能替代正文回答，只能作为附加操作入口
- 最多只放 1 张卡，且不超过 3 个动作
- 支持的 kind：check_in、plan_review、breathing、inquiry、evidence、send_prompt、review_completed、review_too_hard、review_skipped
- 卡片格式：
```max-actions
{"title":"直接完成下一步","detail":"尽量让用户留在对话里完成","actions":[{"title":"开始 check-in","kind":"check_in"},{"title":"做 3 分钟呼吸","kind":"breathing","minutes":3}]}
```
"""
        )
        parts.append("")
        let variation = MaxResponseVariation.selectVariationStrategy(
            state: input.conversationState,
            language: input.language
        )
        parts.append(
            MaxResponseVariation.generateVariationInstructions(
                strategy: variation,
                language: input.language
            )
        )

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
        if isEn {
            parts.append("- Output final answer in English")
            parts.append("- Keep a natural, non-template structure; use headings only when they genuinely help")
            parts.append("- Do not force a preset five-part or three-part reply shape")
            parts.append("- If you append a max-actions card, keep the prose answer natural and place the card last")
            parts.append("- Do not output hidden thinking, reasoning traces, or chain-of-thought steps")
            parts.append("- Do not emit <think> tags or reasoning_content fields")
        } else {
            parts.append("- 只输出最终回答（中文）")
            parts.append("- 使用自然表达，不强制固定 5 段或 3 步模板")
            parts.append("- 标题、列表、编号都按需要才使用，不要先套版再填内容")
            parts.append("- 如果追加 max-actions 动作卡，必须放在正文后面，且正文本身要自然完整")
            parts.append("- 不要输出思考过程、推理内容或分析步骤")
            parts.append("- 禁止输出 <think> 标签或 reasoning_content")
        }

        return parts.joined(separator: "\n")
    }

    private static func parseSettingsFromContext(_ context: String?) -> (honesty: Double, humor: Double) {
        guard let context, !context.isEmpty else {
            return (90, 65)
        }
        let honesty = extractPercent(from: context, pattern: "诚实度:\\s*(\\d+)%")
            ?? extractPercent(from: context, pattern: "Honesty:\\s*(\\d+)%")
            ?? 90
        let humor = extractPercent(from: context, pattern: "幽默感:\\s*(\\d+)%")
            ?? extractPercent(from: context, pattern: "Humor:\\s*(\\d+)%")
            ?? 65
        return (honesty, humor)
    }

    private static func buildDynamicPersonaPrompt(
        personality: String,
        aiSettings: AISettings?,
        aiPersonaContext: String?,
        language: String
    ) -> String {
        let isEn = language == "en"
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

        if isEn {
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

APPROVED PHRASE STYLE:
- "Based on current signals..."
- "Mechanistically, this likely means..."
- "A practical first step is..."
- "In the next turn, let's calibrate with..."

VISUAL FORM:
Max is formless. Represented only by UI elements (The BrainLoader, The Glow), never a human avatar.
"""
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
