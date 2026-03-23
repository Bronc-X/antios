import SwiftUI

struct A10LocalizedText: Hashable {
    let zh: String
    let en: String

    func resolve(_ language: AppLanguage) -> String {
        L10n.text(zh, en, language: language)
    }
}

struct A10SpatialMetric: Identifiable {
    let id: String
    let title: A10LocalizedText
    let value: String
}

struct A10FloatingMenuAction: Identifiable {
    let id: String
    let symbol: String
    let title: A10LocalizedText
}

struct A10EmotionPetal: Identifiable {
    let id: String
    let title: A10LocalizedText
    let score: Int
    let intensity: CGFloat
    let tint: Color
}

struct A10AuraChartAnnotation: Identifiable {
    let id: String
    let pointIndex: Int
    let text: A10LocalizedText
    let xOffset: CGFloat
    let yOffset: CGFloat
}

struct A10AuraChartSnapshot: Identifiable {
    let id: String
    let xLabel: A10LocalizedText
    let primaryValue: String
    let secondaryValue: String
}

struct A10AuraLineChartModel {
    let values: [Double]
    let minValue: Double
    let maxValue: Double
    let xLabels: [A10LocalizedText]
    let yLabels: [String]
    let annotations: [A10AuraChartAnnotation]
    let snapshots: [A10AuraChartSnapshot]
    let interactionHint: A10LocalizedText
}

struct A10DashboardSpatialHeroModel {
    let eyebrow: A10LocalizedText
    let actionTitle: A10LocalizedText
    let actionDetail: A10LocalizedText
    let statusBadge: A10LocalizedText?
    let statusTint: Color
    let topMetrics: [A10SpatialMetric]
    let chart: A10AuraLineChartModel
    let waveSamples: [CGFloat]
}

enum A10FloatingMenuPresentation {
    case collapsed
    case expanded
}

struct A10FloatingMenuDay: Identifiable {
    let id: Int
    let shortLabel: String
}

struct A10FloatingMenuModel {
    let stageMode: A10SpatialStageMode
    let streamCountLabel: A10LocalizedText
    let progressLabel: String
    let days: [A10FloatingMenuDay]
    let selectedDay: Int
    let presentation: A10FloatingMenuPresentation
    let actions: [A10FloatingMenuAction]
}

struct A10EmotionShortcut: Identifiable {
    let id: String
    let symbol: String
    let title: A10LocalizedText
}

struct A10InsightCardModel {
    let eyebrow: A10LocalizedText
    let body: A10LocalizedText
}

struct A10DockAction: Identifiable {
    let id: String
    let symbol: String
    let isPrimary: Bool
}

struct A10EmotionWheelModel {
    let brandTitle: String
    let shortcuts: [A10EmotionShortcut]
    let maxScore: Int
    let petals: [A10EmotionPetal]
    let insight: A10InsightCardModel
    let leadingDockAction: A10DockAction
    let centerDockAction: A10DockAction
    let trailingDockActions: [A10DockAction]
}

struct A10ShowcaseCopyBlock {
    let title: A10LocalizedText
    let subtitle: A10LocalizedText
}

enum A10VisualRecipeFactory {
    static func intro() -> A10ShowcaseCopyBlock {
        A10ShowcaseCopyBlock(
            title: A10LocalizedText(
                zh: "A10 空间视觉系统",
                en: "A10 Spatial Visual System"
            ),
            subtitle: A10LocalizedText(
                zh: "第二步：把第一阶段的视觉原型收敛成可复用 contract，继续保持不接入现有功能入口。",
                en: "Step two: convert the first-pass visual prototypes into reusable contracts without wiring them into the existing feature entry points."
            )
        )
    }

    static func maxSection() -> A10ShowcaseCopyBlock {
        A10ShowcaseCopyBlock(
            title: A10LocalizedText(
                zh: "Max / 空间悬浮菜单",
                en: "Max / Spatial Floating Menu"
            ),
            subtitle: A10LocalizedText(
                zh: "对齐真实使用态：浅灰编辑底和暗景内容底都作为正式变体保留。",
                en: "Aligned to actual usage states: both the pale editing canvas and the dark scenic backdrop remain first-class variants."
            )
        )
    }

    static func insightSection() -> A10ShowcaseCopyBlock {
        A10ShowcaseCopyBlock(
            title: A10LocalizedText(
                zh: "Insight / 花瓣轮盘",
                en: "Insight / Petal Wheel"
            ),
            subtitle: A10LocalizedText(
                zh: "将情绪轮盘、记忆卡片和底部操作坞拆成独立 contract，便于后续接真实数据。",
                en: "The emotion wheel, memory card, and bottom dock are separated into independent contracts so real data can plug in later."
            )
        )
    }

    static func dashboard(language: AppLanguage) -> A10DashboardSpatialHeroModel {
        A10DashboardSpatialHeroModel(
            eyebrow: A10LocalizedText(zh: "今日行动", en: "Today's action"),
            actionTitle: A10LocalizedText(zh: "先补一杯水，然后再继续今天安排", en: "Start with a glass of water, then continue your day"),
            actionDetail: A10LocalizedText(zh: "先做一个最轻的动作，再让 Max 帮你判断后面还要不要继续。", en: "Do one light step first, then let Max decide whether anything else is needed."),
            statusBadge: A10LocalizedText(zh: "Max 可接手", en: "Max ready"),
            statusTint: Color.liquidGlassAccent,
            topMetrics: [
                A10SpatialMetric(
                    id: "current",
                    title: A10LocalizedText(zh: "当前状态", en: "Current state"),
                    value: "68"
                ),
                A10SpatialMetric(
                    id: "remaining",
                    title: A10LocalizedText(zh: "预计用时", en: "Est. time"),
                    value: "3 min"
                )
            ],
            chart: A10AuraLineChartModel(
                values: [64, 58, 61, 54, 67, 63, 68],
                minValue: 0,
                maxValue: 100,
                xLabels: [
                    A10LocalizedText(zh: "3/14", en: "3/14"),
                    A10LocalizedText(zh: "3/15", en: "3/15"),
                    A10LocalizedText(zh: "3/16", en: "3/16"),
                    A10LocalizedText(zh: "3/17", en: "3/17"),
                    A10LocalizedText(zh: "3/18", en: "3/18"),
                    A10LocalizedText(zh: "3/19", en: "3/19"),
                    A10LocalizedText(zh: "今天", en: "Today")
                ],
                yLabels: ["100", "75", "50", "25", "0"],
                annotations: [],
                snapshots: [
                    A10AuraChartSnapshot(id: "d1", xLabel: A10LocalizedText(zh: "3/14", en: "3/14"), primaryValue: "64", secondaryValue: "睡眠偏少，状态一般"),
                    A10AuraChartSnapshot(id: "d2", xLabel: A10LocalizedText(zh: "3/15", en: "3/15"), primaryValue: "58", secondaryValue: "紧张感升高，先减负"),
                    A10AuraChartSnapshot(id: "d3", xLabel: A10LocalizedText(zh: "3/16", en: "3/16"), primaryValue: "61", secondaryValue: "恢复一点，但还不稳定"),
                    A10AuraChartSnapshot(id: "d4", xLabel: A10LocalizedText(zh: "3/17", en: "3/17"), primaryValue: "54", secondaryValue: "状态下滑，建议先休息"),
                    A10AuraChartSnapshot(id: "d5", xLabel: A10LocalizedText(zh: "3/18", en: "3/18"), primaryValue: "67", secondaryValue: "开始回稳，可以做轻动作"),
                    A10AuraChartSnapshot(id: "d6", xLabel: A10LocalizedText(zh: "3/19", en: "3/19"), primaryValue: "63", secondaryValue: "还有波动，先别加码"),
                    A10AuraChartSnapshot(id: "today", xLabel: A10LocalizedText(zh: "今天", en: "Today"), primaryValue: "68", secondaryValue: "适合先做一个 3 分钟的小动作")
                ]
                ,
                interactionHint: A10LocalizedText(zh: "点按或滑动折线，查看每天的变化。", en: "Tap or drag the line to inspect each day.")
            ),
            waveSamples: [
                0.22, 0.31, 0.26, 0.43, 0.35, 0.48, 0.39, 0.57, 0.46,
                0.33, 0.41, 0.29, 0.52, 0.61, 0.44, 0.68, 0.55, 0.63,
                0.36, 0.49, 0.27, 0.42, 0.31, 0.58
            ]
        )
    }

    static func maxLight(language: AppLanguage) -> A10FloatingMenuModel {
        A10FloatingMenuModel(
            stageMode: .lightCanvas,
            streamCountLabel: A10LocalizedText(zh: "3 个直播", en: "3 streams"),
            progressLabel: "4 / 6",
            days: daySet(),
            selectedDay: 6,
            presentation: .collapsed,
            actions: maxActions()
        )
    }

    static func maxDark(language: AppLanguage) -> A10FloatingMenuModel {
        A10FloatingMenuModel(
            stageMode: .darkBackdrop,
            streamCountLabel: A10LocalizedText(zh: "3 个直播", en: "3 streams"),
            progressLabel: "6 / 6",
            days: daySet(),
            selectedDay: 6,
            presentation: .expanded,
            actions: maxActions()
        )
    }

    static func insight(language: AppLanguage) -> A10EmotionWheelModel {
        A10EmotionWheelModel(
            brandTitle: "trove",
            shortcuts: [
                A10EmotionShortcut(id: "release", symbol: "sun.min.fill", title: A10LocalizedText(zh: "释放", en: "Release")),
                A10EmotionShortcut(id: "calm", symbol: "sparkles", title: A10LocalizedText(zh: "平静", en: "Calm")),
                A10EmotionShortcut(id: "feeling", symbol: "heart.fill", title: A10LocalizedText(zh: "感受", en: "Feeling")),
                A10EmotionShortcut(id: "body", symbol: "atom", title: A10LocalizedText(zh: "身体", en: "Body")),
                A10EmotionShortcut(id: "check", symbol: "dial.low.fill", title: A10LocalizedText(zh: "校准", en: "Check"))
            ],
            maxScore: 12,
            petals: [
                A10EmotionPetal(id: "hopeful", title: A10LocalizedText(zh: "有希望", en: "Hopeful"), score: 8, intensity: 0.78, tint: A10SpatialPalette.wheelPetals[0]),
                A10EmotionPetal(id: "calm", title: A10LocalizedText(zh: "平静", en: "Calm"), score: 12, intensity: 0.92, tint: A10SpatialPalette.wheelPetals[1]),
                A10EmotionPetal(id: "alert", title: A10LocalizedText(zh: "警觉", en: "Alert"), score: 10, intensity: 0.84, tint: A10SpatialPalette.wheelPetals[2]),
                A10EmotionPetal(id: "fragile", title: A10LocalizedText(zh: "脆弱", en: "Fragile"), score: 9, intensity: 0.72, tint: A10SpatialPalette.wheelPetals[3]),
                A10EmotionPetal(id: "heavy", title: A10LocalizedText(zh: "沉重", en: "Heavy"), score: 6, intensity: 0.64, tint: A10SpatialPalette.wheelPetals[4]),
                A10EmotionPetal(id: "distant", title: A10LocalizedText(zh: "疏离", en: "Distant"), score: 7, intensity: 0.7, tint: A10SpatialPalette.wheelPetals[5]),
                A10EmotionPetal(id: "soft", title: A10LocalizedText(zh: "柔软", en: "Soft"), score: 12, intensity: 0.88, tint: A10SpatialPalette.wheelPetals[6]),
                A10EmotionPetal(id: "steady", title: A10LocalizedText(zh: "稳定", en: "Steady"), score: 5, intensity: 0.62, tint: A10SpatialPalette.wheelPetals[7])
            ],
            insight: A10InsightCardModel(
                eyebrow: A10LocalizedText(zh: "在记忆里", en: "In Memories"),
                body: A10LocalizedText(
                    zh: "这种感受可能正和之前几个夜晚的记忆叠在一起。",
                    en: "This feeling might be blending with memories from previous evenings."
                )
            ),
            leadingDockAction: A10DockAction(id: "close", symbol: "xmark", isPrimary: false),
            centerDockAction: A10DockAction(id: "cards", symbol: "square.on.square", isPrimary: true),
            trailingDockActions: [
                A10DockAction(id: "mute", symbol: "speaker.slash", isPrimary: false),
                A10DockAction(id: "download", symbol: "arrow.down", isPrimary: false)
            ]
        )
    }

    private static func daySet() -> [A10FloatingMenuDay] {
        [
            A10FloatingMenuDay(id: 4, shortLabel: "T"),
            A10FloatingMenuDay(id: 5, shortLabel: "W"),
            A10FloatingMenuDay(id: 6, shortLabel: "T"),
            A10FloatingMenuDay(id: 7, shortLabel: "F"),
            A10FloatingMenuDay(id: 8, shortLabel: "S")
        ]
    }

    private static func maxActions() -> [A10FloatingMenuAction] {
        [
            A10FloatingMenuAction(id: "apps", symbol: "app.badge.fill", title: A10LocalizedText(zh: "应用", en: "Apps")),
            A10FloatingMenuAction(id: "group", symbol: "person.2.fill", title: A10LocalizedText(zh: "人群", en: "People")),
            A10FloatingMenuAction(id: "gallery", symbol: "mountain.2.fill", title: A10LocalizedText(zh: "图库", en: "Gallery"))
        ]
    }
}
