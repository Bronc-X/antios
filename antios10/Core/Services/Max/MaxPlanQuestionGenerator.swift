import Foundation

@MainActor
enum MaxPlanQuestionGenerator {
    private enum QuestionType: String, CaseIterable {
        case concern
        case sleep
        case stress
        case energy
        case mood
        case lifestyle
        case exercise
        case goal
    }

    private struct QuestionTemplate {
        let zh: String
        let en: String
    }

    private static let maxQuestions = 5

    private static let priority: [QuestionType: Int] = [
        .concern: 1,
        .sleep: 2,
        .stress: 3,
        .energy: 4,
        .mood: 5,
        .lifestyle: 6,
        .exercise: 7,
        .goal: 8
    ]

    private static let templates: [QuestionType: QuestionTemplate] = [
        .concern: QuestionTemplate(
            zh: "最近有什么让你感到不舒服或困扰的地方吗？",
            en: "Is there anything bothering you lately?"
        ),
        .sleep: QuestionTemplate(
            zh: "最近睡眠情况怎么样？",
            en: "How has your sleep been lately?"
        ),
        .stress: QuestionTemplate(
            zh: "最近感觉压力大吗？",
            en: "How stressed have you been feeling lately?"
        ),
        .energy: QuestionTemplate(
            zh: "今天精力如何？",
            en: "How is your energy level today?"
        ),
        .mood: QuestionTemplate(
            zh: "现在心情怎么样？",
            en: "How are you feeling right now?"
        ),
        .lifestyle: QuestionTemplate(
            zh: "你的日常作息是怎样的？",
            en: "What is your daily routine like?"
        ),
        .exercise: QuestionTemplate(
            zh: "你平时运动多吗？",
            en: "How often do you exercise?"
        ),
        .goal: QuestionTemplate(
            zh: "这次计划你最想改善什么？",
            en: "What would you most like to improve with this plan?"
        )
    ]

    static func generateStarterQuestions(language: AppLanguage) async -> [String] {
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            return fallbackQuestions(language: language)
        }

        let data = await MaxPlanEngine.aggregatePlanData(userId: userId)
        let inquirySummary = try? await SupabaseManager.shared.getInquiryContextSummary(
            language: language.apiCode,
            limit: 8
        )
        let ragQuestions = await generateRAGStarterQuestions(
            language: language,
            userId: userId,
            data: data,
            inquirySummary: inquirySummary
        )

        guard ragQuestions.count >= 3 else {
            return fallbackQuestions(language: language)
        }
        return Array(ragQuestions.prefix(maxQuestions))
    }

    private static func fallbackQuestions(language: AppLanguage) -> [String] {
        if language == .en {
            return [
                "How is your sleep lately?",
                "What's your biggest stress trigger right now?",
                "Which part of your day needs more energy?",
                "What should we optimize first?",
                "What habit would you like to build?"
            ]
        }
        return [
            "最近睡眠情况怎么样？",
            "当前压力最大的来源是什么？",
            "你更想提升哪一段精力？",
            "先从哪一件事优化？",
            "你最想养成哪个习惯？"
        ]
    }

    private static func generateRAGStarterQuestions(
        language: AppLanguage,
        userId: String,
        data: AggregatedPlanData,
        inquirySummary: String?
    ) async -> [String] {
        let query = ragStarterQuestionQuery(language: language, data: data)
        let ragContext = await MaxRAGService.buildContext(
            userId: userId,
            query: query,
            language: language.apiCode,
            depth: .full
        )
        let confidence = ragConfidenceScore(
            ragContext: ragContext,
            data: data,
            inquirySummary: inquirySummary
        )
        guard confidence >= 0.45 else { return [] }

        let prompt = ragStarterQuestionPrompt(
            language: language,
            data: data,
            ragContext: ragContext,
            inquirySummary: inquirySummary
        )
        guard !prompt.isEmpty else { return [] }

        do {
            let response = try await SupabaseManager.shared.chatWithMax(
                messages: [ChatRequestMessage(role: "user", content: prompt)],
                mode: "fast"
            )
            let parsed = parseGeneratedQuestions(response, language: language)
            return parsed.count >= 3 ? Array(parsed.prefix(maxQuestions)) : []
        } catch {
            return []
        }
    }

    private static func ragStarterQuestionQuery(
        language: AppLanguage,
        data: AggregatedPlanData
    ) -> String {
        let isEn = language == .en

        var fragments: [String] = []
        if let concern = data.profile?.primaryConcern, !concern.isEmpty {
            fragments.append(concern)
        }
        if let goals = data.profile?.healthGoals, !goals.isEmpty {
            fragments.append(goals.prefix(3).joined(separator: " "))
        }
        if let calibration = data.calibration {
            if calibration.sleepHours > 0, calibration.sleepHours < 6.7 {
                fragments.append(isEn ? "sleep debt recovery" : "睡眠债 恢复")
            }
            if calibration.stressLevel >= 6 {
                fragments.append(isEn ? "stress regulation anxiety" : "压力 调节 焦虑")
            }
            if calibration.energyLevel > 0, calibration.energyLevel <= 4 {
                fragments.append(isEn ? "low energy recovery" : "低能量 恢复")
            }
        }
        if let hrv = data.hrv, hrv.avgHrv > 0 {
            fragments.append(isEn ? "hrv stress resilience" : "HRV 压力恢复")
        }
        if let topic = data.inquiry?.topic, !topic.isEmpty {
            fragments.append(topic)
        }
        return fragments.joined(separator: " ")
    }

    private static func ragConfidenceScore(
        ragContext: MaxRAGContext,
        data: AggregatedPlanData,
        inquirySummary: String?
    ) -> Double {
        var score = 0.0
        if let memoryBlock = ragContext.memoryBlock, !memoryBlock.isEmpty {
            score += 0.45
        }
        if let playbookBlock = ragContext.playbookBlock, !playbookBlock.isEmpty {
            score += 0.20
        }
        if let inquirySummary, !inquirySummary.isEmpty {
            score += 0.15
        }
        if data.dataStatus.hasInquiryData {
            score += 0.10
        }
        if data.dataStatus.hasCalibrationData || data.dataStatus.hasHrvData {
            score += 0.10
        }
        return score
    }

    private static func ragStarterQuestionPrompt(
        language: AppLanguage,
        data: AggregatedPlanData,
        ragContext: MaxRAGContext,
        inquirySummary: String?
    ) -> String {
        let isEn = language == .en

        var sections: [String] = []
        if let concern = data.profile?.primaryConcern, !concern.isEmpty {
            sections.append(isEn ? "[PRIMARY CONCERN]\n\(concern)" : "[主要困扰]\n\(concern)")
        }
        if let goals = data.profile?.healthGoals, !goals.isEmpty {
            sections.append(
                isEn
                    ? "[GOALS]\n\(goals.joined(separator: ", "))"
                    : "[目标]\n\(goals.joined(separator: "、"))"
            )
        }
        if let calibration = data.calibration {
            sections.append(
                isEn
                    ? "[RECENT SIGNALS]\nSleep \(String(format: "%.1f", calibration.sleepHours))h, stress \(calibration.stressLevel)/10, energy \(calibration.energyLevel)/10, mood \(calibration.moodScore)/10"
                    : "[近期信号]\n睡眠 \(String(format: "%.1f", calibration.sleepHours)) 小时，压力 \(calibration.stressLevel)/10，精力 \(calibration.energyLevel)/10，情绪 \(calibration.moodScore)/10"
            )
        }
        if let hrv = data.hrv, hrv.avgHrv > 0 {
            sections.append(
                isEn
                    ? "[WEARABLE]\nAverage HRV \(Int(hrv.avgHrv)), resting HR \(Int(hrv.restingHr)), trend \(hrv.hrvTrend)"
                    : "[穿戴设备]\n平均 HRV \(Int(hrv.avgHrv))，静息心率 \(Int(hrv.restingHr))，趋势 \(hrv.hrvTrend)"
            )
        }
        if let inquirySummary, !inquirySummary.isEmpty {
            sections.append(
                isEn
                    ? "[INQUIRY HISTORY]\n\(inquirySummary)"
                    : "[问询历史]\n\(inquirySummary)"
            )
        }
        if let memoryBlock = ragContext.memoryBlock, !memoryBlock.isEmpty {
            sections.append(
                isEn
                    ? "[RETRIEVED MEMORIES]\n\(memoryBlock)"
                    : "[检索到的记忆]\n\(memoryBlock)"
            )
        }
        if let playbookBlock = ragContext.playbookBlock, !playbookBlock.isEmpty {
            sections.append(
                isEn
                    ? "[RETRIEVED CONTEXT]\n\(playbookBlock)"
                    : "[检索到的上下文]\n\(playbookBlock)"
            )
        }

        let instruction = isEn
            ? """
[TASK]
Generate 4 starter questions for Max.
Hard rules:
- Every question must be grounded in the retrieved history, signals, or memories above.
- Do not ask generic intake questions.
- Prefer the next highest-value unknown that would reduce anxiety or clarify the next action.
- Questions must be short, specific, and non-judgmental.
- Output only 4 bullet lines, each line one question.
"""
            : """
[任务]
请为 Max 生成 4 条起始问题。
硬规则：
- 每个问题都必须扎根于上面的历史、信号或检索记忆。
- 不要提通用 intake 模板问题。
- 优先追问“最能降低焦虑、最能澄清下一步”的那个未知点。
- 问题要短、具体、无评判。
- 只输出 4 行项目符号，每行一个问题。
"""

        sections.append(instruction)
        return sections.joined(separator: "\n\n")
    }

    private static func parseGeneratedQuestions(_ response: String, language: AppLanguage) -> [String] {
        let rawLines = response
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let cleaned = rawLines.compactMap { line -> String? in
            let stripped = line.replacingOccurrences(
                of: #"^[-•\d\.\)\s]+"#,
                with: "",
                options: .regularExpression
            )
            let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard trimmed.contains("?") || trimmed.contains("？") else { return nil }
            return trimmed
        }

        if !cleaned.isEmpty {
            return cleaned
        }
        return fallbackQuestions(language: language)
    }
}
