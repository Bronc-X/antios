import SwiftUI

struct MaxGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(L10n.text("Max 对话说明", "How to use Max", language: appSettings.language))
                        .font(GlassTypography.cnLovi(22, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .padding(10)
                            .background(Color.surfaceGlass(for: colorScheme))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                maxBullet(L10n.text("先描述“今天最明显的不适”，再让 Max 给一个最小动作。", "Start with the strongest discomfort today, then let Max give you one smallest action.", language: appSettings.language))
                maxBullet(L10n.text("动作执行后直接反馈体感变化（0-10），会触发下一轮优化。", "After the action, report the body change on a 0-10 scale to trigger the next optimization step.", language: appSettings.language))
                maxBullet(L10n.text("如果只想快问快答，单条问题控制在 1 个目标。", "If you want a quick exchange, keep each turn focused on one goal.", language: appSettings.language))

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func maxBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Color.liquidGlassAccent)
                .frame(width: 6, height: 6)
                .padding(.top, 7)
            Text(text)
                .font(GlassTypography.cnLovi(15, weight: .regular))
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MaxExecutionOverviewCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let surface: MaxAgentSurfaceModel
    let language: AppLanguage

    private struct OverviewRow: Identifiable {
        let id: String
        let title: String
        let value: String
        let tint: Color
    }

    private var rows: [OverviewRow] {
        [
            OverviewRow(
                id: "inquiry",
                title: L10n.text("待回答问题", "Question waiting", language: language),
                value: surface.inquiry.question?.questionText ?? surface.inquiry.detail,
                tint: .liquidGlassAccent
            ),
            OverviewRow(
                id: "plan",
                title: L10n.text("计划推进", "Plan progress", language: language),
                value: surface.plan.detail,
                tint: .liquidGlassSecondary
            ),
            OverviewRow(
                id: "evidence",
                title: L10n.text("原因说明", "Reasoning", language: language),
                value: surface.evidence.sourceTitle ?? surface.evidence.headline,
                tint: .liquidGlassWarm
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text("当前对话", "Current conversation", language: language))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.textPrimary)
                    Text(L10n.text("这里会保留你正在聊的内容、正在做的计划和原因说明，回来还能接着聊。", "Keep your current question, plan, and reasoning here so you can come back and continue anytime.", language: language))
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(L10n.text("会话保留", "Session kept", language: language))
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.liquidGlassAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.liquidGlassAccent.opacity(0.12))
                    .clipShape(Capsule())
            }

            VStack(spacing: 10) {
                ForEach(rows) { row in
                    overviewRow(row)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.surfaceGlass(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 1)
                )
        )
    }

    private func overviewRow(_ row: OverviewRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(row.tint.opacity(0.88))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(row.tint)
                Text(row.value)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.44))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18), lineWidth: 1)
                )
        )
    }
}

struct MaxLoopBridgeSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenMetrics) private var metrics

    let stage: A10LoopStage
    let title: String
    let detail: String
    let language: AppLanguage
    let statusItems: [String]
    let primaryTitle: String
    let onPrimaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            introBlock
            stageRail
            detailBlock
            statusRail
            primaryActionButton
        }
        .padding(18)
        .background(cardBackground)
    }

    private var stageColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: metrics.isCompactWidth ? 2 : 4)
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("从首页继续", "Continue from Home", language: language))
                .font(.caption.weight(.semibold))
                .foregroundColor(.liquidGlassAccent)
            Text(L10n.text("Max 会接手下一步，你不用自己判断该点哪里。", "Max takes the next step so you do not have to decide where to tap next.", language: language))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stageRail: some View {
        LazyVGrid(columns: stageColumns, alignment: .leading, spacing: 8) {
            ForEach(A10LoopStage.allCases) { item in
                MaxLoopStagePill(
                    title: item.title(language: language),
                    isSelected: item == stage
                )
            }
        }
    }

    private var detailBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var statusRail: some View {
        if !statusItems.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(statusItems, id: \.self) { item in
                        MaxStatusChip(title: item)
                    }
                }
            }
        }
    }

    private var primaryActionButton: some View {
        MaxAgentButton(
            title: primaryTitle,
            systemImage: "sparkles",
            prominence: .primary,
            action: onPrimaryAction
        )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Color.surfaceGlass(for: colorScheme).opacity(0.92))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

struct MaxLoopStagePill: View {
    let title: String
    let isSelected: Bool

    private var foregroundColor: Color {
        isSelected ? .white.opacity(0.96) : .textSecondary
    }

    private var fillColor: Color {
        isSelected ? Color.liquidGlassAccent.opacity(0.22) : Color.white.opacity(0.06)
    }

    private var strokeColor: Color {
        isSelected ? Color.liquidGlassAccent.opacity(0.3) : Color.white.opacity(0.08)
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(backgroundShape)
    }

    private var backgroundShape: some View {
        Capsule()
            .fill(fillColor)
            .overlay(
                Capsule()
                    .stroke(strokeColor, lineWidth: 1)
            )
    }
}

struct MaxStatusChip: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(backgroundShape)
    }

    private var backgroundShape: some View {
        Capsule()
            .fill(Color.white.opacity(0.08))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

struct MaxAgentThreadSurface: View {
    let surface: MaxAgentSurfaceModel
    let language: AppLanguage
    let onCheckIn: () -> Void
    let onExplainBody: () -> Void
    let onInquiryAction: () -> Void
    let onPlanAction: () -> Void
    let onOpenProactive: () -> Void
    let onContinueProactive: () -> Void
    let onEvidenceAction: () -> Void
    let onActionReview: (MaxActionReviewOutcome) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Max")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.liquidGlassAccent)
                    Text(L10n.text("Max 会先看你的身体状态，再继续今天的问题、建议和计划。", "Max starts from your body state, then continues with today's questions, guidance, and plan.", language: language))
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .padding(10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            MaxAgentCard(
                icon: "waveform.path.ecg",
                title: surface.body.headline,
                detail: surface.body.detail,
                accent: .liquidGlassWarm
            ) {
                HStack(spacing: 10) {
                    MaxAgentButton(
                        title: L10n.text("记录状态", "Record state", language: language),
                        systemImage: "slider.horizontal.3",
                        prominence: .primary,
                        action: onCheckIn
                    )
                    MaxAgentButton(
                        title: L10n.text("解读信号", "Explain signals", language: language),
                        systemImage: surface.body.hasSignals ? "sparkles" : "arrow.triangle.2.circlepath",
                        prominence: .secondary,
                        action: onExplainBody
                    )
                }
            }

            MaxAgentCard(
                icon: "bubble.left.and.exclamationmark.bubble.right",
                title: surface.inquiry.headline,
                detail: surface.inquiry.detail,
                accent: .liquidGlassAccent
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if let evidenceTitle = surface.inquiry.evidenceTitle,
                       !evidenceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MaxAgentKeyValueRow(
                            title: L10n.text("关联线索", "Related clue", language: language),
                            value: evidenceTitle
                        )
                    }

                    MaxAgentButton(
                        title: surface.inquiry.primaryTitle,
                        systemImage: surface.inquiry.hasPendingInquiry ? "list.bullet.clipboard" : "plus.bubble",
                        prominence: .primary,
                        action: onInquiryAction
                    )
                }
            }

            MaxAgentCard(
                icon: "checklist.checked",
                title: surface.plan.headline,
                detail: surface.plan.detail,
                accent: .liquidGlassAccent
            ) {
                MaxAgentButton(
                    title: surface.plan.ctaTitle,
                    systemImage: surface.plan.hasActivePlan ? "checkmark.circle" : "plus.circle",
                    prominence: .primary,
                    action: onPlanAction
                )
            }

            MaxAgentCard(
                icon: "bolt.heart",
                title: surface.proactive.headline,
                detail: surface.proactive.detail,
                accent: .liquidGlassSecondary
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    MaxAgentKeyValueRow(
                        title: L10n.text("今日动作", "Today's action", language: language),
                        value: surface.proactive.microAction
                    )
                    MaxAgentKeyValueRow(
                        title: L10n.text("跟进问题", "Follow-up", language: language),
                        value: surface.proactive.followUpQuestion
                    )

                    HStack(spacing: 10) {
                        if let secondaryTitle = surface.proactive.secondaryTitle {
                            MaxAgentButton(
                                title: secondaryTitle,
                                systemImage: "text.bubble",
                                prominence: .secondary,
                                action: onOpenProactive
                            )
                        }
                        MaxAgentButton(
                            title: surface.proactive.primaryTitle,
                            systemImage: surface.proactive.hasBrief ? "checkmark.circle" : "sparkles",
                            prominence: .primary,
                            action: onContinueProactive
                        )
                    }

                    if surface.actionReview.hasAction {
                        MaxAgentActionReviewRow(
                            summary: surface.actionReview,
                            language: language,
                            onSelect: onActionReview
                        )
                    }
                }
            }

            MaxAgentCard(
                icon: "cross.case",
                title: surface.evidence.headline,
                detail: surface.evidence.detail,
                accent: .liquidGlassWarm
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if let sourceTitle = surface.evidence.sourceTitle,
                       !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MaxAgentKeyValueRow(
                            title: L10n.text("参考内容", "Reference", language: language),
                            value: sourceTitle
                        )
                    }
                    if let confidenceText = surface.evidence.confidenceText {
                        MaxAgentKeyValueRow(
                            title: L10n.text("解释置信度", "Confidence", language: language),
                            value: confidenceText
                        )
                    }

                    MaxAgentButton(
                        title: surface.evidence.primaryTitle,
                        systemImage: surface.evidence.hasEvidence ? "doc.text.magnifyingglass" : "sparkles",
                        prominence: .primary,
                        action: onEvidenceAction
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.surfaceGlass(for: .dark).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

struct MaxAgentActionReviewRow: View {
    let summary: MaxAgentActionReviewSummary
    let language: AppLanguage
    let onSelect: (MaxActionReviewOutcome) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MaxAgentKeyValueRow(
                title: L10n.text("动作反馈", "Action review", language: language),
                value: summary.actionLabel
            )

            HStack(spacing: 8) {
                MaxAgentChipButton(
                    title: summary.completedTitle,
                    systemImage: "checkmark.circle",
                    accent: .liquidGlassAccent
                ) {
                    onSelect(.completed)
                }
                MaxAgentChipButton(
                    title: summary.tooHardTitle,
                    systemImage: "tortoise",
                    accent: .liquidGlassWarm
                ) {
                    onSelect(.tooHard)
                }
                MaxAgentChipButton(
                    title: summary.skippedTitle,
                    systemImage: "arrowshape.turn.up.right",
                    accent: .liquidGlassSecondary
                ) {
                    onSelect(.skipped)
                }
            }
        }
    }
}

struct MaxAgentKeyValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.liquidGlassAccent)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MaxAgentChipButton: View {
    let title: String
    let systemImage: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MaxAgentCard<Actions: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let title: String
    let detail: String
    let accent: Color
    let actions: Actions

    init(
        icon: String,
        title: String,
        detail: String,
        accent: Color,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.detail = detail
        self.accent = accent
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 34, height: 34)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.surfaceGlass(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(accent.opacity(0.16), lineWidth: 1)
                )
        )
    }
}

struct MaxAgentButton: View {
    @Environment(\.colorScheme) private var colorScheme

    enum Prominence {
        case primary
        case secondary
    }

    let title: String
    let systemImage: String
    let prominence: Prominence
    let action: () -> Void

    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: prominence == .primary ? .medium : .light)
            impact.impactOccurred()
            action()
        }) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16, height: 16, alignment: .center)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundColor(prominence == .primary ? .white.opacity(0.96) : .textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        prominence == .primary
                            ? Color(hex: "#1E222A")
                            : Color.surfaceGlass(for: colorScheme)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                prominence == .primary
                                    ? Color.white.opacity(0.08)
                                    : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct MaxAgentCheckInSheet: View {
    let language: AppLanguage
    let onContinueWithMax: (DailyCalibrationResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CalibrationViewModel()
    @State private var sliderSelections: [String: Double] = [:]

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("每日状态记录", "Daily state note", language: language))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("先补上今天最必要的状态信息，Max 才能更贴近你地继续。", "Add the minimum state details first so Max can continue in a more relevant way.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isLoading && viewModel.questions.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.liquidGlassAccent)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else {
                    content
                }
            }
            .padding(20)
        }
        .task {
            guard viewModel.questions.isEmpty else { return }
            await viewModel.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .welcome, .questions:
            questionContent
        case .analyzing:
            VStack(alignment: .leading, spacing: 14) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.liquidGlassAccent)
                Text(L10n.text("正在整理这次记录，并保存到你的对话记录里。", "Processing this update and saving it to your conversation record.", language: language))
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .result:
            if let result = viewModel.result {
                resultContent(result)
            }
        }
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView(value: Double(viewModel.currentQuestionIndex + 1), total: Double(max(viewModel.questions.count, 1)))
                .tint(.liquidGlassAccent)

            if let question = viewModel.currentQuestion {
                Text(question.text)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.textPrimary)

                if question.type == .slider {
                    sliderBlock(question)
                } else {
                    optionButtons(question)
                }
            }
        }
    }

    private func optionButtons(_ question: CalibrationQuestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(question.options ?? []) { option in
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    viewModel.answerQuestion(questionId: question.id, value: option.value)
                } label: {
                    HStack {
                        Text(option.label)
                            .font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundColor(.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sliderBlock(_ question: CalibrationQuestion) -> some View {
        let minValue = Double(question.min ?? 0)
        let maxValue = Double(question.max ?? 10)
        let value = Binding<Double>(
            get: {
                sliderSelections[question.id] ?? minValue
            },
            set: { newValue in
                sliderSelections[question.id] = newValue
            }
        )

        return VStack(alignment: .leading, spacing: 14) {
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.textPrimary)

            Slider(value: value, in: minValue...maxValue, step: 1)
                .tint(.liquidGlassAccent)

            Button {
                viewModel.answerQuestion(questionId: question.id, value: Int(value.wrappedValue))
            } label: {
                Text(L10n.text("继续", "Continue", language: language))
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.liquidGlassAccent.opacity(0.22))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func resultContent(_ result: DailyCalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("这次记录已经保存好了。", "This update has been saved.", language: language))
                .font(.title3.weight(.semibold))
                .foregroundColor(.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                summaryRow(L10n.text("Daily Index", "Daily Index", language: language), "\(result.dailyIndex)")
                summaryRow("GAD2", "\(result.gad2Score)")
                summaryRow(L10n.text("压力", "Stress", language: language), "\(result.stressScore)")
                summaryRow(L10n.text("睡眠时长得分", "Sleep duration score", language: language), "\(result.sleepDurationScore)")
                summaryRow(L10n.text("睡眠质量得分", "Sleep quality score", language: language), "\(result.sleepQualityScore)")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
            )

            Button {
                onContinueWithMax(result)
                dismiss()
            } label: {
                Text(L10n.text("让 Max 基于这次记录继续", "Let Max continue from this update", language: language))
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.liquidGlassAccent.opacity(0.22))
                    )
            }
            .buttonStyle(.plain)

            Button {
                dismiss()
            } label: {
                Text(L10n.text("稍后处理", "Maybe later", language: language))
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)
        }
    }
}

struct MaxAgentPlanReviewSheet: View {
    let language: AppLanguage
    let onContinueWithMax: (_ planName: String, _ completedItems: [String], _ remainingCount: Int) -> Void
    let onNeedNewPlan: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = PlansViewModel()
    @State private var planDrafts: [String: [PlanItemData]] = [:]
    @State private var savingPlanId: String?

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("计划进度", "Plan Progress", language: language))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("在 Max 里直接勾选完成项，然后让 Max 接着跟进。", "Check off completed items in Max, then let Max continue the follow-up.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.isLoading && viewModel.plans.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.liquidGlassAccent)
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if viewModel.activePlans.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("还没有进行中的计划。", "There is no active plan yet.", language: language))
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("直接让 Max 按你现在的状态生成今天的微计划，比手动填写更省心。", "Let Max generate today's micro-plan from your current state. It is easier than filling it in by hand.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)

                        Button {
                            onNeedNewPlan()
                            dismiss()
                        } label: {
                            Text(L10n.text("让 Max 生成今天微计划", "Ask Max for today's micro-plan", language: language))
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.liquidGlassAccent.opacity(0.22))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(viewModel.activePlans) { plan in
                                planReviewCard(plan)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .task {
            await viewModel.loadPlans()
            seedDrafts()
        }
    }

    private func planReviewCard(_ plan: PlanData) -> some View {
        let items = planDrafts[plan.id] ?? plan.items
        let completedCount = items.filter { $0.completed }.count
        let remainingCount = max(items.count - completedCount, 0)
        let progress = items.isEmpty ? 0 : Int((Double(completedCount) / Double(items.count)) * 100)

        return MaxAgentPlanDraftCard(
            language: language,
            planName: plan.name,
            items: items,
            completedCount: completedCount,
            progress: progress,
            isSaving: savingPlanId == plan.id,
            onToggleItem: { index in
                toggleItem(planId: plan.id, index: index)
            },
            onSave: {
                Task {
                    await save(plan: plan, items: items, remainingCount: remainingCount)
                }
            }
        )
    }

    private func seedDrafts() {
        for plan in viewModel.activePlans {
            if planDrafts[plan.id] == nil {
                planDrafts[plan.id] = plan.items
            }
        }
    }

    private func toggleItem(planId: String, index: Int) {
        guard var draft = planDrafts[planId], draft.indices.contains(index) else { return }
        draft[index].completed.toggle()
        planDrafts[planId] = draft
    }

    private func save(plan: PlanData, items: [PlanItemData], remainingCount: Int) async {
        savingPlanId = plan.id
        let completedCount = items.filter { $0.completed }.count
        let status: PlanCompletionStatus
        if completedCount == 0 {
            status = .skipped
        } else if completedCount == items.count {
            status = .completed
        } else {
            status = .partial
        }

        await viewModel.updateItems(planId: plan.id, items: items, status: status)
        savingPlanId = nil

        guard viewModel.error == nil else { return }
        let completedItems = items.filter { $0.completed }.map { $0.text }
        onContinueWithMax(plan.name, completedItems, remainingCount)
        dismiss()
    }
}

struct MaxAgentPlanDraftCard: View {
    let language: AppLanguage
    let planName: String
    let items: [PlanItemData]
    let completedCount: Int
    let progress: Int
    let isSaving: Bool
    let onToggleItem: (Int) -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(planName)
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Text(progressText)
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                Spacer()
                Text("\(progress)%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.liquidGlassAccent)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onToggleItem(index)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(item.completed ? .liquidGlassAccent : .textTertiary)
                                .font(.system(size: 18, weight: .semibold))
                            Text(item.text)
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(itemBackground)
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(action: onSave) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.textPrimary)
                    }
                    Text(L10n.text("保存并让 Max 继续", "Save and let Max continue", language: language))
                        .font(.headline)
                }
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.liquidGlassAccent.opacity(0.22))
                )
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
        }
        .padding(18)
        .background(cardBackground)
    }

    private var progressText: String {
        language == .en
            ? "Completed \(completedCount) / \(items.count)"
            : "已完成 \(completedCount) / \(items.count)"
    }

    private var itemBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

struct MaxAgentInquirySheet: View {
    let language: AppLanguage
    let inquiry: InquiryQuestion?
    let onAnswered: (InquiryQuestion, InquiryOption) -> Void
    let onNeedQuestion: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("继续了解你", "Keep learning about you", language: language))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("先补最关键的一条信号，再让 Max 决定下一步动作。", "Fill the single highest-value signal first, then let Max decide the next action.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                if let inquiry {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(runtime(inquiry.questionText))
                                .font(.title3.weight(.semibold))
                                .foregroundColor(.textPrimary)

                            if let feed = inquiry.feedContent {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(L10n.text("关联线索", "Related clue", language: language))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.liquidGlassAccent)
                                    Text(runtime(feed.title))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.textPrimary)
                                    Text(runtime(feed.source))
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                    if let summary = feed.summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(runtime(summary))
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                    if let urlString = feed.url,
                                       let url = URL(string: urlString),
                                       !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Link(destination: url) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "link")
                                                Text(L10n.text("打开相关内容", "Open related content", language: language))
                                            }
                                            .font(.caption.weight(.medium))
                                            .foregroundColor(.liquidGlassAccent)
                                        }
                                    }
                                }
                                .padding(14)
                                .background(sheetCardBackground)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(resolvedOptions(for: inquiry), id: \.value) { option in
                                    Button {
                                        submit(inquiry: inquiry, option: option)
                                    } label: {
                                        HStack {
                                            Text(runtime(option.label))
                                                .foregroundColor(.textPrimary)
                                                .multilineTextAlignment(.leading)
                                            Spacer()
                                            if isSubmitting {
                                                ProgressView()
                                                    .progressViewStyle(.circular)
                                                    .tint(.liquidGlassAccent)
                                            } else {
                                                Image(systemName: "chevron.right")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundColor(.textTertiary)
                                            }
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                        .background(sheetCardBackground)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isSubmitting)
                                }
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(L10n.text("当前没有待回答问题。", "There is no question waiting right now.", language: language))
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("如果你想把下一步再缩小一点，直接让 Max 再问一个关键问题。", "If you want to narrow the next step further, let Max ask one more key question.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)

                        Button {
                            onNeedQuestion()
                            dismiss()
                        } label: {
                            Text(L10n.text("让 Max 继续追问", "Let Max ask the next question", language: language))
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.liquidGlassAccent.opacity(0.22))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .background(sheetCardBackground)
                    Spacer()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.statusWarning)
                }
            }
            .padding(20)
        }
    }

    private var sheetCardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }

    private func resolvedOptions(for inquiry: InquiryQuestion) -> [InquiryOption] {
        inquiry.options ?? [
            InquiryOption(
                label: L10n.text("是", "Yes", language: language),
                value: "yes"
            ),
            InquiryOption(
                label: L10n.text("否", "No", language: language),
                value: "no"
            )
        ]
    }

    private func runtime(_ text: String) -> String {
        L10n.runtime(text, language: language)
    }

    private func submit(inquiry: InquiryQuestion, option: InquiryOption) {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                _ = try await SupabaseManager.shared.respondInquiry(inquiryId: inquiry.id, response: option.value)
                await MainActor.run {
                    onAnswered(inquiry, option)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

struct MaxAgentEvidenceSheet: View {
    let language: AppLanguage
    let evidence: MaxAgentEvidenceSummary
    let onExplain: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("原因说明", "Why this", language: language))
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.textPrimary)
                        Text(L10n.text("先看原因和参考内容，再让 Max 结合你的状态把它讲透。", "Review the reason and references first, then let Max explain it through your current state.", language: language))
                            .font(.subheadline)
                            .foregroundColor(.textSecondary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .padding(10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 12) {
                    evidenceRow(
                        title: L10n.text("原因说明", "Reason", language: language),
                        value: evidence.detail
                    )
                    if let sourceTitle = evidence.sourceTitle,
                       !sourceTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        evidenceRow(
                            title: L10n.text("参考内容", "Reference", language: language),
                            value: sourceTitle
                        )
                    }
                    if let confidenceText = evidence.confidenceText {
                        evidenceRow(
                            title: L10n.text("解释置信度", "Confidence", language: language),
                            value: confidenceText
                        )
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )

                HStack(spacing: 10) {
                    if let urlString = evidence.sourceURL,
                       let url = URL(string: urlString),
                       !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Link(destination: url) {
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                Text(L10n.text("打开原文", "Open source", language: language))
                            }
                            .font(.caption.weight(.medium))
                            .foregroundColor(.liquidGlassAccent)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.08))
                            )
                        }
                    }

                    Button {
                        onExplain()
                        dismiss()
                    } label: {
                        Text(evidence.primaryTitle)
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.liquidGlassAccent.opacity(0.22))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(20)
        }
    }

    private func evidenceRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.liquidGlassAccent)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
