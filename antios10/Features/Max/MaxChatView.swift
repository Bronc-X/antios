// MaxChatView.swift
// Max AI 对话视图 - 支持 P1 功能

import SwiftUI

enum MaxChatRootPresentation {
    case standalone
    case modal
}

struct MaxChatView: View {
    @StateObject private var viewModel: MaxChatViewModel
    @FocusState private var isInputFocused: Bool
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentationMode) private var presentationMode
    @EnvironmentObject private var appSettings: AppSettings
    @State private var isHistoryOpen = false
    @State private var showChatGuide = false
    @State private var animateAura = false
    private let rootPresentation: MaxChatRootPresentation
    private let onBack: (() -> Void)?

    init(
        viewModel: MaxChatViewModel? = nil,
        rootPresentation: MaxChatRootPresentation = .standalone,
        onBack: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? MaxChatViewModel())
        self.rootPresentation = rootPresentation
        self.onBack = onBack
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            immersiveBackground

            VStack(spacing: 0) {
                chatHeader

                if let errorBannerText {
                    compactErrorBanner(text: errorBannerText)
                        .padding(.horizontal, metrics.horizontalPadding)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                            if viewModel.messages.isEmpty {
                                if let fusionRuntime = viewModel.fusionRuntime {
                                    MaxFusionReplyCard(
                                        runtime: fusionRuntime,
                                        language: appSettings.language,
                                        onPrimaryAction: { viewModel.continueFromFusionReply() },
                                        onSecondaryAction: { viewModel.overrideFusionPlan() },
                                        onDiscomfortAction: { viewModel.reportFusionDiscomfort() },
                                        onExplainAction: { viewModel.reviewFusionExplanation() }
                                    )
                                }

                                if let followUpRuntime = viewModel.followUpRuntime {
                                    MaxFollowUpCard(
                                        runtime: followUpRuntime,
                                        language: appSettings.language
                                    ) {
                                        viewModel.openFollowUpFlow()
                                    }
                                }

                                if !viewModel.hasStructuredEntrySurface,
                                   !viewModel.starterQuestions.isEmpty {
                                    ImmersiveStarterView(questions: Array(viewModel.starterQuestions.prefix(3))) { question in
                                        viewModel.inputText = question
                                        viewModel.sendMessage()
                                    }
                                }
                            }

                            ForEach(viewModel.messages) { message in
                                MessageBubble(
                                    message: message,
                                    onPlanConfirm: { selectedPlan in
                                        viewModel.savePlan(selectedPlan)
                                    },
                                    onInlineAction: { action in
                                        viewModel.handleInlineAction(action)
                                    }
                                )
                                .id(message.id)
                            }
                            if viewModel.isTyping { TypingIndicator(language: appSettings.language) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, max(metrics.horizontalPadding - 6, 8))
                        .padding(.top, 2)
                        .padding(.bottom, max(metrics.verticalPadding, 8))
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: viewModel.messages.count) { _, _ in
                        if let lastMessage = viewModel.messages.last {
                            withAnimation { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
                        }
                    }
                }

                InputBarV2(
                    text: $viewModel.inputText,
                    isFocused: $isInputFocused,
                    isTyping: viewModel.isTyping,
                    isMinimal: viewModel.messages.isEmpty,
                    placeholder: composerPlaceholder,
                    onSend: { viewModel.handleInputSubmission() },
                    onStop: { viewModel.stopGeneration() }
                )
            }

            if isHistoryOpen {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isHistoryOpen = false
                        }
                    }

                HistoryDrawer(
                    conversations: viewModel.conversations,
                    currentConversationId: viewModel.currentConversationId,
                    onSelect: { conversation in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isHistoryOpen = false
                        }
                        Task {
                            await viewModel.switchConversation(conversation.id)
                        }
                    },
                    onNew: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isHistoryOpen = false
                        }
                        viewModel.startNewConversation()
                    },
                    onDelete: { conversation in
                        Task {
                            _ = await viewModel.deleteConversation(conversation.id)
                        }
                    }
                )
                .frame(width: historyDrawerWidth)
                .shadow(color: Color.black.opacity(0.38), radius: 18, x: 8, y: 0)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(30)
            }
        }
        .sheet(isPresented: $showChatGuide) {
            MaxGuideSheet()
                .presentationDetents([.fraction(0.42), .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
        }
        .sheet(item: $viewModel.pendingExecutionRequest) { sheet in
            switch sheet {
            case .checkIn:
                MaxAgentCheckInSheet(language: appSettings.language) { result in
                    viewModel.continueFromCheckIn(result)
                }
                .presentationDetents([.medium, .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
            case .planReview:
                MaxAgentPlanReviewSheet(language: appSettings.language) { planName, completedItems, remainingCount in
                    viewModel.continueFromPlanReview(
                        planName: planName,
                        completedItems: completedItems,
                        remainingCount: remainingCount
                    )
                } onNeedNewPlan: {
                    viewModel.sendPreparedPrompt(viewModel.agentSurface.plan.prompt)
                }
                .presentationDetents([.large])
                .liquidGlassSheetChrome(cornerRadius: 28)
            case .breathing(let minutes):
                BreathingSessionView(durationMinutes: minutes)
                    .presentationDetents([.large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
            case .inquiry:
                MaxAgentInquirySheet(
                    language: appSettings.language,
                    inquiry: viewModel.agentSurface.inquiry.question
                ) { question, option in
                    viewModel.continueFromInquiry(question: question, selectedOption: option)
                } onNeedQuestion: {
                    viewModel.requestFocusedInquiry()
                }
                .presentationDetents([.medium, .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
            case .evidence:
                MaxAgentEvidenceSheet(
                    language: appSettings.language,
                    evidence: viewModel.agentSurface.evidence
                ) {
                    viewModel.explainAgentEvidence()
                }
                .presentationDetents([.medium, .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .askMax)) { notification in
            viewModel.handleAskMaxNotification(userInfo: notification.userInfo ?? [:])
        }
        .onReceive(NotificationCenter.default.publisher(for: .startCalibration)) { _ in
            viewModel.pendingExecutionRequest = .checkIn
        }
        .onReceive(NotificationCenter.default.publisher(for: .startBreathing)) { notification in
            let duration = (notification.userInfo?["duration"] as? Int).flatMap { max(1, $0) } ?? 5
            viewModel.pendingExecutionRequest = .breathing(minutes: duration)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) {
                animateAura = true
            }
            Task {
                await viewModel.refreshAgentSurface()
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var bridgeLoopStage: A10LoopStage {
        if !viewModel.agentSurface.body.hasSignals {
            return .calibration
        }
        if viewModel.agentSurface.inquiry.hasPendingInquiry {
            return .inquiry
        }
        if viewModel.agentSurface.proactive.hasBrief || viewModel.agentSurface.plan.hasActivePlan {
            return .action
        }
        if viewModel.agentSurface.evidence.hasEvidence {
            return .evidence
        }
        return .action
    }

    private var composerPlaceholder: String {
        switch bridgeLoopStage {
        case .calibration:
            return L10n.text("直接告诉 Max 你现在最明显的不适", "Tell Max the strongest discomfort right now", language: appSettings.language)
        case .inquiry:
            return L10n.text("直接回答 Max 正在追问的重点", "Reply to the point Max is asking about", language: appSettings.language)
        case .evidence:
            return L10n.text("告诉 Max 哪一点最让你不确定", "Tell Max which part still feels uncertain", language: appSettings.language)
        case .action:
            return L10n.text("告诉 Max 这一步做完后的体感变化", "Tell Max how your body feels after this step", language: appSettings.language)
        }
    }

    private var immersiveBackground: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            Circle()
                .fill(Color.liquidGlassAccent.opacity(0.2))
                .frame(width: 280, height: 280)
                .blur(radius: 54)
                .offset(
                    x: animateAura ? -max(metrics.safeWidth * 0.7, 220) : -max(metrics.safeWidth * 0.56, 180),
                    y: animateAura ? -max(metrics.size.height * 0.22, 180) : -max(metrics.size.height * 0.18, 150)
                )
                .scaleEffect(animateAura ? 1.08 : 0.92)

            Circle()
                .fill(Color.liquidGlassWarm.opacity(0.12))
                .frame(width: 240, height: 240)
                .blur(radius: 52)
                .offset(
                    x: animateAura ? max(metrics.safeWidth * 0.44, 140) : max(metrics.safeWidth * 0.34, 110),
                    y: animateAura ? -max(metrics.size.height * 0.03, 24) : max(metrics.size.height * 0.04, 28)
                )
                .scaleEffect(animateAura ? 0.96 : 1.08)
        }
        .allowsHitTesting(false)
    }

    private var showsBackButton: Bool {
        true
    }

    private var leadingHeaderIcon: String {
        rootPresentation == .standalone ? "house.fill" : "chevron.left"
    }

    private var trailingHeaderIcon: String {
        isHistoryOpen ? "rectangle.compress.vertical" : "sidebar.right"
    }

    private var chatHeader: some View {
        let sidePadding = metrics.horizontalPadding
        let sideSlotWidth: CGFloat = 56
        return ZStack {
            HStack {
                Group {
                    if showsBackButton {
                        maxHeaderButton(symbol: leadingHeaderIcon, action: handleLeadingHeaderAction)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: sideSlotWidth, alignment: .leading)

                Spacer()

                Button {
                    let impact = UIImpactFeedbackGenerator(style: .soft)
                    impact.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        isHistoryOpen.toggle()
                    }
                } label: {
                    maxHeaderButton(symbol: trailingHeaderIcon)
                }
                .frame(width: sideSlotWidth, alignment: .trailing)
            }

            Text("Max")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, sidePadding)
        .padding(.top, max(metrics.safeAreaInsets.top - 39, 2))
        .padding(.bottom, 2)
    }

    private func maxHeaderButton(symbol: String, action: (() -> Void)? = nil) -> some View {
        Group {
            if let action {
                Button(action: action) {
                    maxHeaderButtonChrome(symbol: symbol)
                }
            } else {
                maxHeaderButtonChrome(symbol: symbol)
            }
        }
        .buttonStyle(.plain)
    }

    private func maxHeaderButtonChrome(symbol: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                        .blur(radius: 0.2)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 18, y: 10)

            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.textPrimary)
        }
        .frame(width: 52, height: 52)
    }

    private var historyDrawerWidth: CGFloat {
        min(max(metrics.safeWidth * 0.74, 280), 336)
    }

    private var errorBannerText: String? {
        guard let error = viewModel.error else { return nil }
        let normalized = error
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        guard !normalized.isEmpty else { return nil }

        let lowercased = normalized.lowercased()
        if normalized.contains("无效的令牌")
            || lowercased.contains("auth error")
            || lowercased.contains("aihttperror")
            || lowercased.contains("unknown context")
            || normalized.contains("401") {
            return L10n.text(
                "在线回复暂不可用，已切换本地回复。",
                "Online reply is unavailable. Switched to local reply.",
                language: appSettings.language
            )
        }

        if normalized.count > 120 {
            return L10n.text(
                "在线服务暂不可用，已切换本地回复。",
                "Online service is temporarily unavailable. Switched to local reply.",
                language: appSettings.language
            )
        }

        return normalized
    }

    private func compactErrorBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Color(red: 0.76, green: 0.22, blue: 0.22))

            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundColor(.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                viewModel.error = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.textSecondary)
                    .padding(6)
                    .background(Color.white.opacity(0.22))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.96, green: 0.86, blue: 0.85).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.red.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func handleLeadingHeaderAction() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        if let onBack {
            onBack()
        } else if rootPresentation == .standalone {
            NotificationCenter.default.post(name: .openDashboard, object: nil)
        } else if presentationMode.wrappedValue.isPresented {
            presentationMode.wrappedValue.dismiss()
        } else {
            dismiss()
        }
    }
}
