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
        let calibration = data.calibration
        let profile = data.profile

        let hasHealthKitSleep = await hasLocalSleepData()

        var missing: [QuestionType] = []
        var questions: [String] = []
        let isEn = language == .en

        func appendUnique(_ question: String?) {
            guard let question else { return }
            let normalized = question.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            guard !questions.contains(normalized) else { return }
            questions.append(normalized)
        }

        // 1) 优先提问：直接基于用户的真实状态与问题
        if let concern = profile?.primaryConcern, !concern.isEmpty {
            appendUnique(
                isEn
                    ? "You mentioned \"\(concern)\". What feels hardest about it this week?"
                    : "你提到「\(concern)」，这周最困扰你的具体场景是什么？"
            )
        }

        if !data.dataStatus.hasInquiryData {
            missing.append(.concern)
        }

        let needsSleep = (calibration?.sleepHours ?? 0) <= 0 && !hasHealthKitSleep
        let needsStress = (calibration?.stressLevel ?? 0) <= 0
        let needsEnergy = (calibration?.energyLevel ?? 0) <= 0
        let needsMood = (calibration?.moodScore ?? 0) <= 0

        if needsSleep { missing.append(.sleep) }
        if needsStress { missing.append(.stress) }
        if needsEnergy { missing.append(.energy) }
        if needsMood { missing.append(.mood) }

        if let calibration {
            if calibration.sleepHours > 0 {
                if calibration.sleepHours < 6.5 {
                    appendUnique(
                        isEn
                            ? "Your recent sleep is about \(String(format: "%.1f", calibration.sleepHours))h. What is blocking earlier sleep?"
                            : "你最近睡眠约 \(String(format: "%.1f", calibration.sleepHours)) 小时，阻碍你更早入睡的主要原因是什么？"
                    )
                } else {
                    appendUnique(
                        isEn
                            ? "Sleep is relatively stable. What would make your wake-up quality better?"
                            : "你的睡眠相对稳定，你更想优化“起床后的状态”还是“夜间睡眠深度”？"
                    )
                }
            }

            if calibration.stressLevel >= 7 {
                appendUnique(
                    isEn
                        ? "Your stress score is high recently (\(calibration.stressLevel)/10). Which time block is the toughest?"
                        : "你最近压力值偏高（\(calibration.stressLevel)/10），一天里最难受的是哪个时段？"
                )
            }

            if calibration.energyLevel > 0 && calibration.energyLevel <= 4 {
                appendUnique(
                    isEn
                        ? "Your energy looks low (\(calibration.energyLevel)/10). Do you want to improve morning or afternoon energy first?"
                        : "你当前精力偏低（\(calibration.energyLevel)/10），想先提升上午精力还是下午精力？"
                )
            }
        }

        if let hrv = data.hrv, hrv.avgHrv > 0 {
            appendUnique(
                isEn
                    ? "Wearable data shows HRV around \(Int(hrv.avgHrv)). Have you noticed any stress trigger in the same period?"
                    : "穿戴数据显示 HRV 约 \(Int(hrv.avgHrv))，这段时间你是否观察到固定的压力触发点？"
            )
        }

        if let goals = profile?.healthGoals, let firstGoal = goals.first, !firstGoal.isEmpty {
            appendUnique(
                isEn
                    ? "For your goal \"\(firstGoal)\", what is the smallest action you can commit to daily?"
                    : "围绕你的目标「\(firstGoal)」，你愿意每天固定执行的最小动作是什么？"
            )
        }

        for type in [QuestionType.lifestyle, .exercise, .goal] where !missing.contains(type) {
            missing.append(type)
        }

        let sorted = missing.sorted { (priority[$0] ?? 99) < (priority[$1] ?? 99) }
        let selected = Array(sorted.prefix(maxQuestions * 2))

        for type in selected {
            guard let template = templates[type] else { continue }
            appendUnique(isEn ? template.en : template.zh)
        }

        for fallback in fallbackQuestions(language: language) where questions.count < maxQuestions {
            appendUnique(fallback)
        }

        let final = Array(questions.prefix(maxQuestions))
        return final.isEmpty ? fallbackQuestions(language: language) : final
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

    private static func hasLocalSleepData() async -> Bool {
        let healthKit = HealthKitService.shared
        guard healthKit.isAvailable, healthKit.isAuthorizedForRead() else { return false }
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        do {
            let sleepMinutes = try await healthKit.querySleepDuration(from: start, to: now)
            return sleepMinutes > 0
        } catch {
            return false
        }
    }
}
