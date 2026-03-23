import SwiftUI
import PhotosUI
import Speech
import AVFoundation

// MARK: - Message Bubble (🆕 支持 Markdown)
struct MessageBubble: View {
    let message: ChatMessage
    var onPlanConfirm: ((PlanOption) -> Void)? = nil
    var onInlineAction: ((MaxInlineAction) -> Void)? = nil
    @EnvironmentObject private var appSettings: AppSettings
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme

    private var visibleAssistantContent: String {
        guard message.role == .assistant else { return message.content }
        return stripMaxInlineActionCard(from: message.content)
    }

    private var inlineActionCard: MaxInlineActionCard? {
        guard message.role == .assistant else { return nil }
        return parseMaxInlineActionCard(from: message.content)
    }

    private var planOptions: [PlanOption]? {
        guard message.role == .assistant else { return nil }
        return parsePlanOptions(from: visibleAssistantContent)
    }

    private var scientificSoothing: ScientificSoothingResponse? {
        guard message.role == .assistant else { return nil }
        return parseScientificSoothingResponse(from: visibleAssistantContent)
    }

    private var bubbleMaxWidth: CGFloat {
        let widthRatio: CGFloat = message.role == .user ? 0.9 : 0.94
        return min(metrics.safeWidth * widthRatio, metrics.safeWidth - 42)
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(Color.surfaceGlass(for: colorScheme))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundColor(.liquidGlassAccent)
                }
            } else {
                Spacer()
            }
            
            // 消息气泡 - 根据内容类型选择渲染方式
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .frame(maxWidth: bubbleMaxWidth, alignment: message.role == .user ? .trailing : .leading)

                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
                    .padding(.horizontal, 4)
            }
            
            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.liquidGlassSecondary)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
    
    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var bubbleContent: some View {
        let trimmedVisibleContent = visibleAssistantContent.trimmingCharacters(in: .whitespacesAndNewlines)

        if let options = planOptions, options.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                PlanSelectorView(options: options) { selectedPlan in
                    onPlanConfirm?(selectedPlan)
                }
                if let inlineActionCard {
                    MaxInlineActionCardView(card: inlineActionCard, onAction: onInlineAction)
                }
            }
        } else if let soothing = scientificSoothing {
            VStack(alignment: .leading, spacing: 10) {
                ScientificSoothingCard(response: soothing, language: appSettings.language)
                if let inlineActionCard {
                    MaxInlineActionCardView(card: inlineActionCard, onAction: onInlineAction)
                }
            }
        } else {
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
                if message.role == .user || !trimmedVisibleContent.isEmpty {
                    Group {
                        if message.role == .assistant {
                            MarkdownText(
                                content: trimmedVisibleContent,
                                baseColor: .textPrimary
                            )
                        } else {
                            Text(message.content)
                        }
                    }
                    .font(.body)
                    .foregroundColor(message.role == .user ? .white.opacity(0.95) : .textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                message.role == .user
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "#2B323A"), Color(hex: "#1E222A")],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    : AnyShapeStyle(Color.surfaceGlass(for: colorScheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        message.role == .user
                                            ? Color.white.opacity(0.08)
                                            : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.role == .assistant ? trimmedVisibleContent : message.content
                            let notification = UINotificationFeedbackGenerator()
                            notification.notificationOccurred(.success)
                        } label: {
                            Label(
                                L10n.text("复制消息", "Copy message", language: appSettings.language),
                                systemImage: "doc.on.doc"
                            )
                        }
                    }
                }

                if let inlineActionCard {
                    MaxInlineActionCardView(card: inlineActionCard, onAction: onInlineAction)
                }
            }
        }
    }

    private func parseScientificSoothingResponse(from content: String) -> ScientificSoothingResponse? {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let sectionAliases: [(key: String, aliases: [String])] = [
            ("understanding", ["理解结论", "理解結論", "Understanding Conclusion"]),
            ("mechanism", ["机制解释", "機制解釋", "Mechanism Explanation"]),
            ("evidence", ["证据来源", "證據來源", "Evidence Sources"]),
            ("actions", ["可执行动作", "可執行動作", "Executable Actions"]),
            ("followUp", ["跟进问题", "跟進問題", "Follow-up Question"])
        ]

        var buckets: [String: [String]] = Dictionary(uniqueKeysWithValues: sectionAliases.map { ($0.key, []) })
        var currentKey: String?

        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let (key, remainder) = matchSectionLine(trimmed, aliases: sectionAliases) {
                currentKey = key
                if !remainder.isEmpty {
                    buckets[key, default: []].append(remainder)
                }
                continue
            }

            if let currentKey {
                buckets[currentKey, default: []].append(trimmed)
            }
        }

        let understanding = buckets["understanding", default: []].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let mechanism = buckets["mechanism", default: []].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let evidenceLines = buckets["evidence", default: []]
        let actionLines = buckets["actions", default: []]
        let followUp = buckets["followUp", default: []].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        let evidence = evidenceLines.compactMap { line -> ScientificEvidenceCitation? in
            let clean = stripListPrefix(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return nil }
            return ScientificEvidenceCitation(
                source: clean,
                title: clean,
                year: nil,
                confidence: nil
            )
        }

        let actions = actionLines
            .map { stripListPrefix($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let response = ScientificSoothingResponse(
            understandingConclusion: understanding,
            mechanismExplanation: mechanism,
            evidenceSources: evidence,
            executableActions: actions,
            followUpQuestion: followUp
        )
        return response.isValid ? response : nil
    }

    private func matchSectionLine(
        _ line: String,
        aliases: [(key: String, aliases: [String])]
    ) -> (String, String)? {
        let normalizedLine = line
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "###", with: "")
            .replacingOccurrences(of: "##", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for item in aliases {
            for alias in item.aliases {
                let candidates = [
                    alias,
                    "\(alias):",
                    "\(alias)："
                ]
                for candidate in candidates {
                    if normalizedLine.hasPrefix(candidate) {
                        let remainder = normalizedLine
                            .replacingOccurrences(of: candidate, with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        return (item.key, remainder)
                    }
                }
            }
        }
        return nil
    }

    private func stripListPrefix(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
            return String(trimmed.dropFirst(2))
        }
        if let match = trimmed.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) {
            return String(trimmed[match.upperBound...])
        }
        return trimmed
    }
}

private struct MaxInlineActionCardView: View {
    @Environment(\.colorScheme) private var colorScheme

    let card: MaxInlineActionCard
    let onAction: ((MaxInlineAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.textPrimary)

            if let detail = card.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(Array(card.actions.prefix(3).enumerated()), id: \.element.id) { index, action in
                    MaxInlineActionButton(
                        action: action,
                        prominence: index == 0 ? .primary : .secondary,
                        onTap: onAction
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.surfaceGlass(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16), lineWidth: 1)
                )
        )
    }
}

private struct MaxInlineActionButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: MaxInlineAction
    let prominence: MaxAgentButton.Prominence
    let onTap: ((MaxInlineAction) -> Void)?

    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: prominence == .primary ? .medium : .light)
            impact.impactOccurred()
            onTap?(action)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(prominence == .primary ? .white.opacity(0.96) : .liquidGlassAccent)
                    .frame(width: 16, height: 16)
                    .padding(.top, action.detail == nil ? 1 : 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(prominence == .primary ? .white.opacity(0.96) : .textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = action.detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(prominence == .primary ? .white.opacity(0.78) : .textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        prominence == .primary
                            ? Color(hex: "#1E222A")
                            : Color.surfaceGlass(for: colorScheme)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                prominence == .primary
                                    ? Color.white.opacity(0.08)
                                    : Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch action.kind {
        case .checkIn:
            return "waveform.path.ecg"
        case .planReview:
            return "checklist"
        case .breathing:
            return "wind"
        case .inquiry:
            return "questionmark.circle"
        case .evidence:
            return "doc.text.magnifyingglass"
        case .sendPrompt:
            return "sparkles"
        case .reviewCompleted:
            return "checkmark.circle.fill"
        case .reviewTooHard:
            return "arrow.down.circle"
        case .reviewSkipped:
            return "forward.circle"
        }
    }
}

private struct ScientificSoothingCard: View {
    let response: ScientificSoothingResponse
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            soothingRow(title("先说结论", "Summary"), response.understandingConclusion)
            soothingRow(title("为什么会这样", "Why"), response.mechanismExplanation)
            soothingRow(title("我参考了什么", "Reference"), response.evidenceSources.map { $0.title }.joined(separator: "；"))
            soothingRow(title("可执行动作", "Actions"), response.executableActions.joined(separator: "；"))
            soothingRow(title("跟进问题", "Follow-up"), response.followUpQuestion)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func soothingRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.liquidGlassAccent)
            Text(value)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
        }
    }

    private func title(_ zh: String, _ en: String) -> String {
        L10n.text(zh, en, language: language)
    }
}

// MARK: - 🆕 P3 思考过程动画
struct TypingIndicator: View {
    let language: AppLanguage
    @State private var dotOffset = 0.0
    @State private var pulseScale = 1.0
    @State private var rotation = 0.0
    @State private var thinkingPhase = 0

    private var thinkingTexts: [String] {
        [
            L10n.text("正在理解你的焦虑场景...", "Understanding your anxiety context...", language: language),
            L10n.text("正在整理触发点和身体感觉...", "Organizing your triggers and body feelings...", language: language),
            L10n.text("正在查找相关内容...", "Finding relevant references...", language: language),
            L10n.text("正在整理原因和行动建议...", "Preparing reasons and next actions...", language: language),
            L10n.text("准备下一轮跟进问题...", "Preparing next follow-up question...", language: language)
        ]
    }
    
    private let timer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // AI 头像 - 带脉冲光晕和旋转
            ZStack {
                // 脉冲光圈
                Circle()
                    .fill(Color.liquidGlassAccent.opacity(0.15))
                    .frame(width: 50, height: 50)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
                
                Circle()
                    .fill(Color.liquidGlassAccent.opacity(0.25))
                    .frame(width: 40, height: 40)
                    .scaleEffect(pulseScale * 0.9)
                    .animation(
                        .easeInOut(duration: 1.0).repeatForever(autoreverses: true).delay(0.2),
                        value: pulseScale
                    )
                
                // 大脑图标 - 轻微旋转
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.liquidGlassAccent.opacity(0.5), lineWidth: 1.5))
                    .rotationEffect(.degrees(rotation))
                    .animation(
                        .easeInOut(duration: 2.0).repeatForever(autoreverses: true),
                        value: rotation
                    )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                // 思考阶段文字
                Text(thinkingTexts[thinkingPhase % thinkingTexts.count])
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                    .animation(.easeInOut(duration: 0.3), value: thinkingPhase)
                
                // 三点跳动动画
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.liquidGlassAccent)
                            .frame(width: 8, height: 8)
                            .offset(y: dotOffset)
                            .animation(
                                .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15),
                                value: dotOffset
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.liquidGlassAccent.opacity(0.3), lineWidth: 1)
                    )
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            dotOffset = -6
            pulseScale = 1.2
            rotation = 5
        }
        .onReceive(timer) { _ in
            withAnimation {
                thinkingPhase += 1
            }
        }
    }
}

// MARK: - Immersive Starter View
struct ImmersiveStarterView: View {
    let questions: [String]
    let onSelect: (String) -> Void
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealCards = false

    private let icons = [
        "sparkles",
        "waveform.path.ecg",
        "checklist",
        "bookmark",
        "ellipsis.message"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(questions.prefix(5).enumerated()), id: \.offset) { index, question in
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onSelect(question)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icons[index % icons.count])
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color.textSecondary(for: colorScheme))
                            Text(question)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(Color.textPrimary(for: colorScheme))
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Capsule()
                                .fill(Color.surfaceGlass(for: colorScheme).opacity(0.88))
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .opacity(revealCards ? 1 : 0)
                    .offset(y: revealCards ? 0 : 10)
                    .animation(
                        .spring(response: 0.36, dampingFraction: 0.84).delay(Double(index) * 0.04),
                        value: revealCards
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            revealCards = true
        }
    }
}

struct MaxOpenClawWelcomeSurface: View {
    let stage: A10LoopStage
    let questions: [String]
    let onSelect: (String) -> Void

    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    private var capabilityPills: [String] {
        [
            L10n.text("建议", "Guidance", language: appSettings.language),
            L10n.text("计划", "Plans", language: appSettings.language),
            L10n.text("记录", "Logging", language: appSettings.language),
            L10n.text("推荐", "Recommendations", language: appSettings.language)
        ]
    }

    private var stageBadgeTitle: String {
        switch stage {
        case .calibration:
            return L10n.text("先接住当下", "Start with the present", language: appSettings.language)
        case .inquiry:
            return L10n.text("继续追问", "Continue inquiry", language: appSettings.language)
        case .evidence:
            return L10n.text("展开解释", "Expand explanation", language: appSettings.language)
        case .action:
            return L10n.text("推进动作", "Advance action", language: appSettings.language)
        }
    }

    private var primaryTitle: String {
        L10n.text("你只管说发生了什么", "Just tell Max what is happening", language: appSettings.language)
    }

    private var bodyText: String {
        switch stage {
        case .calibration:
            return L10n.text(
                "Max 会先理解你现在的体感，再自己整理建议、生成计划、记录变化，并推荐和你相关的信息。",
                "Max starts from your body state, then organizes guidance, generates a plan, logs changes, and recommends relevant information.",
                language: appSettings.language
            )
        case .inquiry:
            return L10n.text(
                "直接回答或补充一句，Max 会自己继续追问并决定下一步，不需要你切模块。",
                "Reply in one sentence. Max will continue the inquiry and decide the next step without sending you to another module.",
                language: appSettings.language
            )
        case .evidence:
            return L10n.text(
                "如果你有疑问，就直接说出来。Max 会把原因、参考内容和动作讲清楚，再替你安排下一步。",
                "If anything feels unclear, say it directly. Max will explain the reason, references, and action, then finish the next step for you.",
                language: appSettings.language
            )
        case .action:
            return L10n.text(
                "告诉 Max 你刚做完后的体感变化，它会自己复盘、记录并更新接下来的建议。",
                "Tell Max how your body feels after the action. It will review, log, and update the next recommendation on its own.",
                language: appSettings.language
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Label("Max", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.liquidGlassAccent)

                Spacer()

                Text(stageBadgeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.surfaceGlass(for: colorScheme))
                    .clipShape(Capsule())
            }

            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.26 : 0.08))
                    .frame(height: metrics.isCompactHeight ? 166 : 184)

                Group {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.26),
                                    Color.liquidGlassAccent.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 72, height: 126)
                        .rotationEffect(.degrees(-22))
                        .offset(x: -58, y: -4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.3),
                                    Color.liquidGlassWarm.opacity(0.1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 76, height: 134)
                        .offset(y: -14)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.26),
                                    Color.liquidGlassSecondary.opacity(0.08)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 72, height: 126)
                        .rotationEffect(.degrees(22))
                        .offset(x: 58, y: -4)

                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 82, height: 82)
                        .blur(radius: 8)
                }

                VStack(spacing: 10) {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 58, height: 58)
                        .overlay(
                            Image(systemName: "sparkles")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white.opacity(0.92))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )

                    Text(L10n.text("Chat & Action", "Chat & Action", language: appSettings.language))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white.opacity(0.72))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(primaryTitle)
                    .font(.system(size: metrics.isCompactWidth ? 24 : 26, weight: .bold))
                    .foregroundColor(.textPrimary)

                Text(bodyText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(capabilityPills, id: \.self) { pill in
                        Text(pill)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.surfaceGlass(for: colorScheme))
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.14), lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(questions.prefix(3).enumerated()), id: \.offset) { _, question in
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        onSelect(question)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.liquidGlassAccent)

                            Text(question)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.textPrimary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 8)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.surfaceGlass(for: colorScheme))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.surfaceGlass(for: colorScheme))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16), lineWidth: 1)
                )
        )
    }
}

// MARK: - History Drawer
struct HistoryDrawer: View {
    let conversations: [Conversation]
    let currentConversationId: String?
    let onSelect: (Conversation) -> Void
    let onNew: () -> Void
    let onDelete: (Conversation) -> Void
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerView
            contentView

            Spacer()
        }
        .padding(.top, metrics.safeAreaInsets.top + 12)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(drawerBackground)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text("历史记录", "Conversation history", language: appSettings.language))
                    .font(.headline)
                    .foregroundColor(Color.textPrimary(for: colorScheme))
                Text(L10n.text("最近上下文", "Recent context", language: appSettings.language))
                    .font(.caption2.weight(.medium))
                    .foregroundColor(Color.textSecondary(for: colorScheme))
            }
            Spacer()
            Button(action: onNew) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.textPrimary(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .background(Color.surfaceGlass(for: colorScheme))
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .clipShape(Circle())
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if conversations.isEmpty {
            Text(L10n.text("还没有对话记录", "No chat history yet", language: appSettings.language))
                .font(.subheadline)
                .foregroundColor(Color.textSecondary(for: colorScheme))
                .padding(.top, 12)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(conversations) { conversation in
                        conversationRow(conversation)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func conversationRow(_ conversation: Conversation) -> some View {
        Button {
            onSelect(conversation)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(conversation.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.textPrimary(for: colorScheme))
                        .lineLimit(1)
                    Text(conversationDateLabel(conversation))
                        .font(.caption2)
                        .foregroundColor(Color.textTertiary(for: colorScheme))
                }
                Spacer()
                if conversation.id == currentConversationId {
                    Circle()
                        .fill(Color.liquidGlassAccent)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(conversation.id == currentConversationId
                          ? Color.liquidGlassAccent.opacity(0.16)
                          : Color.surfaceGlass(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                conversation.id == currentConversationId
                                    ? Color.liquidGlassAccent.opacity(0.24)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                onDelete(conversation)
            } label: {
                Label(
                    L10n.text("删除对话", "Delete chat", language: appSettings.language),
                    systemImage: "trash"
                )
            }
        }
    }

    private var drawerBackground: some View {
        ZStack {
            AuroraBackground()
            Rectangle()
                .fill(Color.surfaceGlass(for: colorScheme).opacity(0.92))
        }
        .ignoresSafeArea()
    }

    private func conversationDateLabel(_ conversation: Conversation) -> String {
        guard let date = conversation.lastMessageDate else {
            return L10n.text("刚刚", "Just now", language: appSettings.language)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: appSettings.language.localeIdentifier)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - 🆕 Input Bar V3 (支持图片上传和语音输入)
struct InputBarV2: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isTyping: Bool
    let isMinimal: Bool
    let placeholder: String
    let onSend: () -> Void
    let onStop: () -> Void
    var onImageSelected: ((UIImage) -> Void)? = nil
    var onVoiceInput: ((String) -> Void)? = nil
    
    @State private var showImagePicker = false
    @State private var showVoiceRecorder = false
    @State private var isRecording = false
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings
    
    private var controlSize: CGFloat { isMinimal ? 50 : (metrics.isCompactWidth ? 42 : 46) }
    private var iconSize: CGFloat { metrics.isCompactWidth ? 17 : 19 }
    private var sendSize: CGFloat { isMinimal ? 40 : (metrics.isCompactWidth ? 34 : 36) }
    private var fieldHorizontalPadding: CGFloat { metrics.isCompactWidth ? 16 : 18 }
    private var fieldVerticalPadding: CGFloat { isMinimal ? 22 : (metrics.isCompactHeight ? 15 : 17) }
    private var barCornerRadius: CGFloat { isMinimal ? 34 : (metrics.isCompactWidth ? 28 : 32) }
    private var barMaxWidth: CGFloat { max(280, min(metrics.safeWidth - 32, 680)) }
    private var rowSpacing: CGFloat { 12 }

    var body: some View {
        let sidePadding = max(18, metrics.horizontalPadding)

        return ViewThatFits(in: .horizontal) {
            barContainer(
                content: barContent(),
                sidePadding: sidePadding
            )
            barContainer(
                content: barContent(),
                sidePadding: sidePadding
            )
        }
        // 🆕 图片选择器 Sheet
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView { image in
                onImageSelected?(image)
            }
        }
        // 🆕 语音录入 Sheet
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderView { transcribedText in
                text = transcribedText
            }
        }
    }

    @ViewBuilder
    private func barContent() -> some View {
        barRow()
    }

    private func barContainer(content: some View, sidePadding: CGFloat) -> some View {
        content
            .padding(.horizontal, isMinimal ? 18 : 16)
            .padding(.vertical, isMinimal ? 18 : 14)
            .frame(maxWidth: barMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: barCornerRadius)
                    .fill(Color.surfaceGlass(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: barCornerRadius)
                            .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.18), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 22, y: 10)
            .padding(.horizontal, sidePadding)
            .padding(.top, 8)
            .padding(.bottom, max(isMinimal ? 20 : 14, metrics.safeAreaInsets.bottom + 10))
    }

    @ViewBuilder
    private func barRow() -> some View {
        HStack(alignment: .bottom, spacing: rowSpacing) {
            if !isMinimal {
                plusButton
            }
            inputField
            micButton
        }
    }

    private var plusButton: some View {
        Button(action: {
            lightImpact()
            showImagePicker = true
        }) {
            Image(systemName: "plus")
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(.textPrimary)
                .frame(width: controlSize, height: controlSize)
                .background(Color.surfaceGlass(for: colorScheme))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .disabled(isTyping)
        .opacity(isTyping ? 0.5 : 1)
    }

    private var micButton: some View {
        Button(action: {
            lightImpact()
            showVoiceRecorder = true
        }) {
            Image(systemName: "mic.fill")
                .font(.system(size: iconSize))
                .foregroundColor(.textPrimary)
                .frame(width: controlSize, height: controlSize)
                .background(Color.surfaceGlass(for: colorScheme))
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .disabled(isTyping)
        .opacity(isTyping ? 0.5 : 1)
    }

    private var inputField: some View {
        HStack(spacing: 10) {
            Group {
                if #available(iOS 16.0, *) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(1...4)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .focused(isFocused)
            .textFieldStyle(.plain)
            .foregroundColor(Color.textPrimary(for: colorScheme))
            .submitLabel(.send)
            .onSubmit {
                if !isTyping {
                    onSend()
                }
            }
            .layoutPriority(1)

            if isTyping {
                Button(action: {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    onStop()
                }) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: sendSize))
                        .foregroundStyle(.red.opacity(0.9))
                        .shadow(color: .red.opacity(0.4), radius: 6)
                }
            } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { onSend() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: sendSize))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color(hex: "#1E222A"))
                        .shadow(color: Color.black.opacity(0.24), radius: 8)
                }
            }
        }
        .padding(.horizontal, fieldHorizontalPadding)
        .padding(.vertical, fieldVerticalPadding)
        .frame(maxWidth: .infinity)
        .frame(minHeight: isMinimal ? 94 : (metrics.isCompactHeight ? 66 : 72), alignment: .center)
    }

    private func lightImpact() {
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
}

// MARK: - 🆕 图片选择器 (PHPickerViewController)

struct ImagePickerView: UIViewControllerRepresentable {
    let onImageSelected: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePickerView
        
        init(_ parent: ImagePickerView) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            guard let result = results.first else { return }
            
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                if let image = object as? UIImage {
                    DispatchQueue.main.async {
                        self.parent.onImageSelected(image)
                    }
                }
            }
        }
    }
}

// MARK: - 🆕 语音录入视图

struct VoiceRecorderView: View {
    let onTranscription: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appSettings: AppSettings
    
    @State private var isRecording = false
    @State private var transcribedText = ""
    @State private var audioEngine = AVAudioEngine()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    @State private var pulseScale = 1.0
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                
                VStack(spacing: 32) {
                    Spacer()
                    
                    // 录音指示器
                    ZStack {
                        // 脉冲环
                        if isRecording {
                            Circle()
                                .stroke(Color.liquidGlassAccent.opacity(0.3), lineWidth: 4)
                                .frame(width: 160, height: 160)
                                .scaleEffect(pulseScale)
                            
                            Circle()
                                .stroke(Color.liquidGlassAccent.opacity(0.5), lineWidth: 3)
                                .frame(width: 130, height: 130)
                                .scaleEffect(pulseScale * 0.9)
                        }
                        
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.8) : Color.liquidGlassAccent)
                            .frame(width: 100, height: 100)
                            .shadow(color: isRecording ? .red.opacity(0.5) : .liquidGlassAccent.opacity(0.5), radius: 20)
                        
                        Image(systemName: isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    }
                    .onTapGesture {
                        toggleRecording()
                    }
                    
                    Text(
                        isRecording
                        ? L10n.text("点击停止录音", "Tap to stop recording", language: appSettings.language)
                        : L10n.text("点击开始录音", "Tap to start recording", language: appSettings.language)
                    )
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                    
                    // 转录结果
                    if !transcribedText.isEmpty {
                        Text(transcribedText)
                            .font(.body)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .padding(.horizontal)
                    }
                    
                    Spacer()
                    
                    // 确认按钮
                    if !transcribedText.isEmpty && !isRecording {
                        Button {
                            onTranscription(transcribedText)
                            dismiss()
                        } label: {
                            Text(L10n.text("使用此文本", "Use this text", language: appSettings.language))
                                .font(.headline)
                                .foregroundColor(.bgPrimary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.liquidGlassAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle(L10n.text("语音输入", "Voice input", language: appSettings.language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.text("取消", "Cancel", language: appSettings.language)) {
                        stopRecording()
                        dismiss()
                    }
                    .foregroundColor(.liquidGlassAccent)
                }
            }
            .onAppear {
                speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: appSettings.language.localeIdentifier))
                requestSpeechAuthorization()
            }
            .onDisappear {
                stopRecording()
            }
            .onChange(of: isRecording) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                        pulseScale = 1.3
                    }
                } else {
                    pulseScale = 1.0
                }
            }
        }
    }
    
    private func requestSpeechAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            // 授权处理
        }
    }
    
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }
        
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            isRecording = true
            
            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    transcribedText = result.bestTranscription.formattedString
                }
                
                if error != nil || result?.isFinal == true {
                    stopRecording()
                }
            }
        } catch {
            print("❌ 语音录制失败: \(error)")
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isRecording = false
    }
}

// MARK: - Preview
struct MaxChatView_Previews: PreviewProvider {
    static var previews: some View {
        MaxChatView()
            .preferredColorScheme(.dark)
    }
}

// MARK: - MarkdownText 组件
/// Markdown 文本渲染 - 使用 iOS 原生 AttributedString
struct MarkdownText: View {
    let content: String
    let baseColor: Color
    
    var body: some View {
        if #available(iOS 15.0, *) {
            Text(attributedContent)
                .textSelection(.enabled)
        } else {
            Text(content)
        }
    }
    
    @available(iOS 15.0, *)
    private var attributedContent: AttributedString {
        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            
            var attributed = try AttributedString(markdown: content, options: options)
            attributed.foregroundColor = baseColor
            
            for run in attributed.runs {
                if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                    attributed[run.range].foregroundColor = baseColor
                }
                if run.inlinePresentationIntent?.contains(.emphasized) == true {
                    attributed[run.range].foregroundColor = baseColor.opacity(0.92)
                }
                if run.inlinePresentationIntent?.contains(.code) == true {
                    attributed[run.range].foregroundColor = baseColor.opacity(0.9)
                    attributed[run.range].backgroundColor = .white.opacity(0.1)
                }
            }
            return attributed
        } catch {
            return AttributedString(content)
        }
    }
}

// MARK: - StarterQuestionsView 组件
/// 个性化起始问题卡片视图
struct StarterQuestionsView: View {
    let questions: [String]
    let onSelect: (String) -> Void
    @EnvironmentObject private var appSettings: AppSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundColor(.liquidGlassAccent)
                Text(L10n.text("快速开始", "Quick start", language: appSettings.language))
                    .font(.headline)
                    .foregroundColor(.textPrimary)
            }
            .padding(.bottom, 4)
            
            ForEach(questions.prefix(4), id: \.self) { question in
                StarterQuestionCard(question: question) {
                    onSelect(question)
                }
            }
        }
        .padding(.vertical, 16)
    }
}

/// 单个问题卡片
struct StarterQuestionCard: View {
    let question: String
    let onTap: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onTap()
        }) {
            HStack {
                Text(question)
                    .font(.subheadline)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.leading)
                
                Spacer()
                
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

/// 按压缩放按钮样式
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
