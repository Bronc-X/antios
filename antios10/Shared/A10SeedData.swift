import Foundation
import SwiftData

@MainActor
enum A10SeedData {
    static func ensureSeedData(context: ModelContext, language: AppLanguage) {
        do {
            var snapshotDescriptor = FetchDescriptor<A10LoopSnapshot>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            snapshotDescriptor.fetchLimit = 1
            let hasSnapshot = try !context.fetch(snapshotDescriptor).isEmpty

            var planDescriptor = FetchDescriptor<A10ActionPlan>(sortBy: [SortDescriptor(\.sortOrder)])
            planDescriptor.fetchLimit = 1
            let hasPlans = try !context.fetch(planDescriptor).isEmpty

            var preferenceDescriptor = FetchDescriptor<A10PreferenceRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            preferenceDescriptor.fetchLimit = 1
            let existingPreferences = try context.fetch(preferenceDescriptor).first

            if !hasSnapshot {
                context.insert(
                    A10LoopSnapshot(
                        headline: L10n.text("先让系统知道你今天最难的点。", "Let the system understand your hardest point today first.", language: language),
                        summary: L10n.text("新壳层先围绕一个问题、一条解释、一个动作来组织信息。", "The new shell starts by organizing the experience around one question, one explanation, and one action.", language: language),
                        nextActionTitle: L10n.text("用 20 秒说出触发点", "Name the trigger in 20 seconds", language: language),
                        nextActionDetail: L10n.text("例如：今天开会前胸口发紧，注意力被拉走。", "Example: before today's meeting my chest tightened and my attention drifted away.", language: language),
                        evidenceNote: L10n.text("壳层启动后会用远端证据替换这条占位摘要。", "Shell startup will replace this placeholder summary with remote evidence.", language: language),
                        currentStageRaw: A10LoopStage.inquiry.rawValue,
                        stressScore: 6
                    )
                )
            }

            if !hasPlans {
                context.insert(
                    A10ActionPlan(
                        title: L10n.text("做 3 分钟呼吸", "Do a 3-minute breathing reset", language: language),
                        detail: L10n.text("不用追求完整闭环，先做最低阻力动作。", "Do not chase the full loop yet. Start with the lowest-friction action.", language: language),
                        effortLabel: L10n.text("低负担", "Low load", language: language),
                        estimatedMinutes: 3,
                        sortOrder: 0
                    )
                )
                context.insert(
                    A10ActionPlan(
                        title: L10n.text("记录一句触发语境", "Log one trigger sentence", language: language),
                        detail: L10n.text("保留最真实的上下文，后面给解释和行动用。", "Capture the most real context for later explanation and action.", language: language),
                        effortLabel: L10n.text("1 句话", "1 line", language: language),
                        estimatedMinutes: 1,
                        sortOrder: 1
                    )
                )
            }

            if let existingPreferences {
                existingPreferences.languageCode = language.rawValue
                existingPreferences.updatedAt = .now
            } else {
                context.insert(
                    A10PreferenceRecord(
                        languageCode: language.rawValue,
                        healthSyncEnabled: true,
                        notificationsEnabled: true,
                        dailyCheckInHour: 21
                    )
                )
            }

            try context.save()
        } catch {
            print("[A10SeedData] failed: \(error)")
        }
    }

    static func createPreferences(context: ModelContext, language: AppLanguage) -> A10PreferenceRecord {
        let record = A10PreferenceRecord(
            languageCode: language.rawValue,
            healthSyncEnabled: true,
            notificationsEnabled: true,
            dailyCheckInHour: 21
        )
        context.insert(record)
        return record
    }
}
