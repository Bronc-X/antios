import XCTest
@testable import antios5

final class antios5Tests: XCTestCase {
    func testAntiAnxietyLoopStatusInitialContract() {
        let status = AntiAnxietyLoopStatus.initial(now: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(status.currentStep, .proactiveInquiry)
        XCTAssertTrue(status.completedSteps.isEmpty)
        XCTAssertTrue(status.blockedReasons.isEmpty)
        XCTAssertTrue(status.updatedAt.contains("1970"))
    }

    func testScientificSoothingResponseValidation() {
        let valid = ScientificSoothingResponse(
            understandingConclusion: "你处在可干预的焦虑高唤醒阶段。",
            mechanismExplanation: "睡眠不足叠加认知过警觉会放大紧张反应。",
            evidenceSources: [
                ScientificEvidenceCitation(
                    source: "knowledge_base",
                    title: "CBT-I and Anxiety Coupling",
                    year: "2022",
                    confidence: "medium"
                )
            ],
            executableActions: ["今晚固定 23:30 上床并做 3 分钟呼吸。"],
            followUpQuestion: "执行后你的入睡潜伏期是否缩短？"
        )
        XCTAssertTrue(valid.isValid)

        let invalid = ScientificSoothingResponse(
            understandingConclusion: "  ",
            mechanismExplanation: "机制解释",
            evidenceSources: [],
            executableActions: [],
            followUpQuestion: ""
        )
        XCTAssertFalse(invalid.isValid)
    }

    func testAppleWatchIngestionBundlePayloadFlag() {
        let emptyBundle = AppleWatchIngestionBundle(
            collectedAt: "2026-02-12T00:00:00Z",
            snapshots: [],
            source: "apple_watch_healthkit"
        )
        XCTAssertFalse(emptyBundle.hasPayload)

        let payloadBundle = AppleWatchIngestionBundle(
            collectedAt: "2026-02-12T00:00:00Z",
            snapshots: [
                WearableMetricSnapshot(
                    metricType: "hrv",
                    value: 42,
                    unit: "ms",
                    recordedAt: "2026-02-12T00:00:00Z",
                    source: "apple_watch_healthkit"
                )
            ],
            source: "apple_watch_healthkit"
        )
        XCTAssertTrue(payloadBundle.hasPayload)
    }

    func testMaxPromptBuilderIncludesClosedLoopSectionsInChinese() {
        let input = MaxPromptInput(
            conversationState: MaxConversationStateTracker.initial(),
            aiSettings: AISettings(honesty_level: 90, humor_level: 30, mode: "max"),
            aiPersonaContext: nil,
            personality: "max",
            healthFocus: "工作场景触发焦虑",
            inquirySummary: "最近两天晚间焦虑升高",
            memoryContext: "上次执行了呼吸训练",
            playbookContext: "证据库建议先做低阻力动作",
            contextBlock: "[CONTEXT BLOCK]",
            language: "zh"
        )

        let prompt = MaxPromptBuilder.build(input: input)
        XCTAssertTrue(prompt.contains("[ANTI-ANXIETY RESPONSE FORMAT]"))
        XCTAssertTrue(prompt.contains("1. 理解结论 / Understanding Conclusion"))
        XCTAssertTrue(prompt.contains("小节标题使用中文"))
        XCTAssertTrue(prompt.contains("[USER FOCUS]"))
        XCTAssertTrue(prompt.contains("工作场景触发焦虑"))
    }

    func testMaxPromptBuilderIncludesEnglishOutputRules() {
        let input = MaxPromptInput(
            conversationState: MaxConversationStateTracker.initial(),
            aiSettings: nil,
            aiPersonaContext: nil,
            personality: nil,
            healthFocus: nil,
            inquirySummary: nil,
            memoryContext: nil,
            playbookContext: nil,
            contextBlock: nil,
            language: "en"
        )
        let prompt = MaxPromptBuilder.build(input: input)
        XCTAssertTrue(prompt.contains("- Output final answer in English"))
        XCTAssertTrue(prompt.contains("- Use the English section titles exactly as listed above"))
    }

    func testConversationStateTrackerDetectsStructuredResponseAndCitation() {
        let messages: [ChatMessage] = [
            ChatMessage(role: .user, content: "我最近总是心慌，晚上难以入睡。"),
            ChatMessage(role: .assistant, content: """
理解结论：你处在高唤醒状态。
机制解释：睡眠剥夺会放大杏仁核反应。
证据来源：[1] "Sleep and Amygdala Reactivity"
可执行动作：今晚先做 3 分钟呼吸训练。
跟进问题：执行后入睡时间有变化吗？
""")
        ]

        let state = MaxConversationStateTracker.extractState(from: messages)
        XCTAssertEqual(state.turnCount, 1)
        XCTAssertEqual(state.usedFormats.last, "full_structured")
        XCTAssertTrue(state.citedPaperIds.contains("sleep and amygdala reactivity"))
        XCTAssertEqual(state.lastResponseStructure?.hasEvidence, true)
        XCTAssertEqual(state.lastResponseStructure?.hasActionAdvice, true)
    }

    func testContextOptimizerFiltersRepeatedPapersAndUsesReminder() {
        let state = MaxConversationState(
            turnCount: 2,
            mentionedHealthContext: true,
            citedPaperIds: ["paper a"],
            usedFormats: [],
            usedEndearments: [],
            lastResponseStructure: nil,
            establishedContext: [],
            userSharedDetails: ["夜间惊醒"]
        )

        let decision = MaxContextOptimizer.optimize(
            state: state,
            healthFocus: "睡前焦虑",
            scientificPapers: [
                ScientificPaperLite(title: "Paper A", year: 2024),
                ScientificPaperLite(title: "Paper B", year: 2023)
            ]
        )

        XCTAssertFalse(decision.includeFullHealthContext)
        XCTAssertTrue(decision.includeHealthReminder)
        XCTAssertEqual(decision.filteredPapers.count, 1)
        XCTAssertEqual(decision.filteredPapers.first?.title, "Paper B")
        XCTAssertTrue(decision.contextSummary.contains("对话轮次: 2"))

        let contextBlock = MaxContextOptimizer.buildContextBlock(decision: decision)
        XCTAssertTrue(contextBlock.contains("ANTI-ANXIETY REMINDER"))
        XCTAssertTrue(contextBlock.contains("Paper B"))
    }

    func testResponseVariationStrategyForFirstTurnAndLaterTurn() {
        let initialState = MaxConversationStateTracker.initial()
        let firstStrategy = MaxResponseVariation.selectVariationStrategy(state: initialState)
        XCTAssertEqual(firstStrategy.formatStyle, .structured)
        XCTAssertEqual(firstStrategy.citationStyle, .formal)
        XCTAssertTrue(firstStrategy.shouldMentionHealthContext)

        let laterState = MaxConversationState(
            turnCount: 4,
            mentionedHealthContext: true,
            citedPaperIds: ["a", "b", "c"],
            usedFormats: ["structured"],
            usedEndearments: ["朋友"],
            lastResponseStructure: nil,
            establishedContext: [],
            userSharedDetails: []
        )
        let laterStrategy = MaxResponseVariation.selectVariationStrategy(state: laterState)
        XCTAssertEqual(laterStrategy.citationStyle, .minimal)
        XCTAssertFalse(laterStrategy.shouldMentionHealthContext)

        let instructions = MaxResponseVariation.generateVariationInstructions(strategy: laterStrategy)
        XCTAssertTrue(instructions.contains("不要重复提及用户的焦虑重点"))
    }

    func testInquiryEnginePrioritizationAndTriggerTemplate() {
        let gaps = InquiryEngine.identifyDataGaps(recentData: [:], staleThresholdHours: 24)
        let prioritized = InquiryEngine.prioritizeDataGaps(gaps)
        XCTAssertEqual(prioritized.first?.importance, .high)

        let template = InquiryEngine.inquiryTemplate(
            for: DataGap(field: "meal_quality", importance: .medium, description: "焦虑触发场景数据", lastUpdated: nil),
            language: "zh"
        )
        XCTAssertNotNil(template)
        XCTAssertTrue(template?.questionText.contains("焦虑触发点") == true)
        XCTAssertTrue(template?.options?.contains(where: { $0.label.contains("工作/学习压力") }) == true)
    }
}
