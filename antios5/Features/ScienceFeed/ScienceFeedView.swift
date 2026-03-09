// ScienceFeedView.swift
// 定制科学期刊视图 - 完全对齐 Web 端 ScienceFeed.tsx

import SwiftUI

struct ScienceFeedView: View {
    @StateObject private var viewModel = ScienceFeedViewModel()
    @State private var showFeedGuideSheet = false
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings

    private var language: AppLanguage { appSettings.language }
    
    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                centerAxisHeader

                if viewModel.isLoading && viewModel.articles.isEmpty {
                    AILoadingView(message: viewModel.loadingMessage, language: language)
                        .frame(maxWidth: .infinity)
                } else if viewModel.articles.isEmpty {
                    EmptyFeedView(language: language, onRefresh: {
                        Task { await viewModel.refresh(language: language) }
                    })
                } else {
                    ScrollView {
                        VStack(spacing: metrics.sectionSpacing) {
                            // Header
                            FeedHeaderView(
                                language: language,
                                isRefreshing: viewModel.isRefreshing,
                                onRefresh: { Task { await viewModel.refresh(language: language) } }
                            )

                            FeedCategoryTabs(
                                language: language,
                                selectedCategory: viewModel.selectedCategory,
                                onSelect: { category in
                                    viewModel.selectedCategory = category
                                }
                            )

                            if viewModel.filteredArticles.isEmpty {
                                CategoryEmptyView(language: language, category: viewModel.selectedCategory)
                            } else {
                                ForEach(Array(viewModel.filteredArticles.enumerated()), id: \.element.id) { index, article in
                                    NavigationLink(destination: ArticleReaderView(article: article)) {
                                        ArticleCard(
                                            article: article,
                                            index: index,
                                            language: language,
                                            onFeedback: { isPositive in
                                                Task { await viewModel.submitFeedback(articleId: article.id, isPositive: isPositive) }
                                            }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            // 刷新按钮
                            RefreshButton(
                                language: language,
                                isRefreshing: viewModel.isRefreshing,
                                onRefresh: { Task { await viewModel.refresh(language: language) } }
                            )
                        }
                        .liquidGlassPageWidth()
                        .padding(.vertical, metrics.verticalPadding)
                    }
                    .refreshable {
                        await viewModel.refresh(language: language)
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.loadFeed(language: language)
        }
        .sheet(isPresented: $showFeedGuideSheet) {
            FeedGuideSheet()
                .presentationDetents([.fraction(0.42), .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
        }
        .onChange(of: language) { _, newLanguage in
            Task { await viewModel.refresh(language: newLanguage) }
        }
    }

    private var centerAxisHeader: some View {
        let sideSlotWidth: CGFloat = 44
        return ZStack {
            HStack(spacing: 0) {
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .liquidGlassCircleBadge(padding: 8)
                }
                .frame(width: sideSlotWidth, alignment: .leading)
                Spacer()
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .soft)
                    impact.impactOccurred()
                    showFeedGuideSheet = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.liquidGlassAccent)
                        .liquidGlassCircleBadge(padding: 8)
                }
                .frame(width: sideSlotWidth, alignment: .trailing)
            }

            Text(L10n.text("科学期刊", "Science Journal", language: language))
                .font(.headline)
                .foregroundColor(.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)
                .offset(x: metrics.centerAxisOffset)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.top, metrics.safeAreaInsets.top + 12)
        .padding(.bottom, 12)
    }
}

// MARK: - Feed Header
struct FeedHeaderView: View {
    let language: AppLanguage
    let isRefreshing: Bool
    let onRefresh: () -> Void
    
    private var todayString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .en ? "en_US_POSIX" : "zh_CN")
        formatter.dateFormat = language == .en ? "MMM d" : "M月d日"
        return formatter.string(from: Date())
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L10n.text("今日精选 · \(todayString)", "Today's Picks · \(todayString)", language: language))
                    .font(.caption)
                    .tracking(2)
                    .foregroundColor(.liquidGlassAccent)
                
                Spacer()
                
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    onRefresh()
                } label: {
                    HStack(spacing: 4) {
                        if isRefreshing {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(L10n.text("刷新", "Refresh", language: language))
                    }
                    .font(.caption)
                    .foregroundColor(.liquidGlassAccent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.liquidGlassAccent.opacity(0.1))
                    .clipShape(Capsule())
                }
                .disabled(isRefreshing)
            }
            
            Text(L10n.text("为你量身定制的科学", "Science Tailored for You", language: language))
                .font(.title.bold())
                .foregroundColor(.textPrimary)
            
            Text(L10n.text("每篇文章都经过 AI 分析，解释为什么它对你重要", "Each article is analyzed by AI to explain why it matters to you.", language: language))
                .font(.subheadline)
                .foregroundColor(.textSecondary)
            
            Text(L10n.text("📅 每天下午 2:00（UTC+8）更新推荐", "📅 Updates daily at 2:00 PM (UTC+8)", language: language))
                .font(.caption2)
                .foregroundColor(.textTertiary)
        }
    }
}

struct FeedCategoryTabs: View {
    let language: AppLanguage
    let selectedCategory: ScienceFeedCategory
    let onSelect: (ScienceFeedCategory) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ScienceFeedCategory.allCases) { category in
                    Button {
                        let feedback = UISelectionFeedbackGenerator()
                        feedback.selectionChanged()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            onSelect(category)
                        }
                    } label: {
                        Text(category.title(language: language))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(
                                selectedCategory == category
                                ? .textOnAccent
                                : Color.textSecondary(for: colorScheme)
                            )
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == category
                                ? Color.liquidGlassAccent
                                : Color.mutedSurfaceFill(for: colorScheme)
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedCategory == category
                                        ? Color.clear
                                        : Color.surfaceStroke(for: colorScheme),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

struct CategoryEmptyView: View {
    let language: AppLanguage
    let category: ScienceFeedCategory
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(.textTertiary)
            Text(L10n.text("当前分类暂无内容", "No content in this category", language: language))
                .font(.subheadline.weight(.medium))
                .foregroundColor(.textSecondary)
            Text(category.title(language: language))
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.mutedSurfaceFill(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Article Card
struct ArticleCard: View {
    let article: ScienceArticle
    let index: Int
    let language: AppLanguage
    let onFeedback: (Bool) -> Void
    
    private var isLight: Bool { index % 2 == 0 }
    private var platform: PlatformInfo { PlatformInfo.forType(article.sourceType) }
    private var cardBackground: Color { isLight ? Color.brandPaper : Color(hex: "#241B3F") }
    private var cardPrimaryText: Color { isLight ? Color.deepGreen : Color.brandPaper }
    private var cardSecondaryText: Color { isLight ? Color(hex: "#4A665A") : Color.brandPaper.opacity(0.75) }
    private var cardTertiaryText: Color { isLight ? Color(hex: "#7A8F70") : Color.brandPaper.opacity(0.55) }
    private var cardBorder: Color { isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.12) }
    private var titleText: String { language == .en ? article.title : (article.titleZh ?? article.title) }
    private var summaryText: String {
        let base = language == .en ? (article.summary ?? article.summaryZh) : (article.summaryZh ?? article.summary)
        let trimmed = base?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return L10n.text("摘要生成中", "Summary unavailable", language: language)
    }
    private var whyText: String? { normalizedText(article.whyRecommended) }
    private var actionText: String? { normalizedText(article.actionableInsight) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Platform + Match
            HStack {
                PlatformBadge(platform: platform, language: language)
                Spacer()
                MatchBadge(percentage: article.matchPercentage, language: language)
            }
            
            // Title
            if let url = article.sourceUrl, let link = URL(string: url) {
                Link(destination: link) {
                    HStack(alignment: .top) {
                        Text(titleText)
                            .font(.headline)
                            .foregroundColor(cardPrimaryText)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(cardTertiaryText)
                    }
                }
            } else {
                Text(titleText)
                    .font(.headline)
                    .foregroundColor(cardPrimaryText)
            }
            
            // 摘要
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text("摘要", "Summary", language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(cardTertiaryText)
                ExpandableText(
                    text: summaryText,
                    lineLimit: 3,
                    language: language,
                    textColor: cardSecondaryText,
                    font: .subheadline,
                    toggleColor: cardTertiaryText
                )
            }
            
            // 为什么推荐给你
            if let why = whyText {
                InsightBox(
                    icon: "sparkles",
                    title: L10n.text("为什么推荐给你", "Why Recommended", language: language),
                    content: why,
                    language: language,
                    accentColor: .liquidGlassAccent,
                    textColor: cardSecondaryText,
                    backgroundColor: .liquidGlassAccent.opacity(isLight ? 0.12 : 0.2)
                )
            }

            // 你可以这样做
            if let action = actionText {
                InsightBox(
                    icon: "checkmark.circle.fill",
                    title: L10n.text("你可以这样做", "What You Can Do", language: language),
                    content: action,
                    language: language,
                    accentColor: .liquidGlassSecondary,
                    textColor: cardSecondaryText,
                    backgroundColor: .liquidGlassSecondary.opacity(isLight ? 0.12 : 0.2)
                )
            }
            
            // Tags
            if let tags = article.tags, !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(isLight ? Color.gray.opacity(0.1) : Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Divider().opacity(0.3)
            
            // Actions
            HStack {
                if let url = article.sourceUrl, let link = URL(string: url) {
                    Link(destination: link) {
                        HStack(spacing: 4) {
                            Image(systemName: "book.fill")
                            Text(L10n.text("阅读全文", "Read Full Text", language: language))
                            Image(systemName: "arrow.up.right")
                                .font(.caption2)
                        }
                        .font(.subheadline)
                        .foregroundColor(.liquidGlassAccent)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 16) {
                    Button { onFeedback(true) } label: {
                        Image(systemName: "hand.thumbsup")
                            .foregroundColor(cardTertiaryText)
                    }
                    
                    Button { onFeedback(false) } label: {
                        Image(systemName: "hand.thumbsdown")
                            .foregroundColor(cardTertiaryText)
                    }
                }
            }
        }
        .padding()
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(cardBorder, lineWidth: 1)
        )
    }

    private func normalizedText(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}

// MARK: - Platform Badge
struct PlatformBadge: View {
    let platform: PlatformInfo
    let language: AppLanguage
    
    var body: some View {
        HStack(spacing: 6) {
            Text(platform.icon)
            Text(language == .en ? platform.name : platform.nameZh)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(hex: platform.color).opacity(0.2))
        .foregroundColor(Color(hex: platform.color))
        .clipShape(Capsule())
    }
}

// MARK: - Match Badge
struct MatchBadge: View {
    let percentage: Int?
    let language: AppLanguage
    
    var body: some View {
        if let pct = percentage {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption2)
                Text(language == .en ? "\(pct)% Match" : "\(pct)% 匹配")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(badgeColor.opacity(0.15))
            .foregroundColor(badgeColor)
            .clipShape(Capsule())
        }
    }
    
    private var badgeColor: Color {
        guard let pct = percentage else { return .blue }
        if pct >= 95 { return .green }
        if pct >= 90 { return .orange }
        return .blue
    }
}

// MARK: - Insight Box
struct InsightBox: View {
    let icon: String
    let title: String
    let content: String
    let language: AppLanguage
    let accentColor: Color
    var textColor: Color = .textSecondary
    var backgroundColor: Color? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(accentColor)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(accentColor)
            }
            ExpandableText(
                text: content,
                lineLimit: 3,
                language: language,
                textColor: textColor,
                font: .subheadline,
                toggleColor: accentColor
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor ?? accentColor.opacity(0.1))
        .overlay(
            Rectangle()
                .fill(accentColor)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Expandable Text
struct ExpandableText: View {
    let text: String
    let lineLimit: Int
    let language: AppLanguage
    let textColor: Color
    let font: Font
    var toggleColor: Color = .textSecondary
    var minimumCharactersForToggle: Int = 120
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(font)
                .foregroundColor(textColor)
                .lineLimit(isExpanded ? nil : lineLimit)
                .animation(.easeInOut(duration: 0.2), value: isExpanded)

            if text.count >= minimumCharactersForToggle {
                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded
                             ? L10n.text("收起", "Collapse", language: language)
                             : L10n.text("展开", "More", language: language))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(toggleColor)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - AI Loading View
struct AILoadingView: View {
    let message: String
    let language: AppLanguage
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenMetrics) private var metrics
    @State private var progress: CGFloat = 0
    
    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .stroke(Color.liquidGlassAccent.opacity(0.2), lineWidth: 4)
                        .frame(width: 60, height: 60)

                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.liquidGlassAccent)
                }

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut, value: message)

                // Progress bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.mutedSurfaceFill(for: colorScheme))
                    .frame(width: 200, height: 4)
                    .overlay(
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.liquidGlassAccent)
                                // ui-audit: ignore-next-line layout-geometry-width-basis
                                .frame(width: geo.size.width * progress)
                        },
                        alignment: .leading
                    )

                Text(L10n.text("这可能需要 10-20 秒", "This may take 10-20 seconds", language: language))
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(x: metrics.centerAxisOffset)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding()
        .onAppear {
            withAnimation(.linear(duration: 25)) {
                progress = 1
            }
        }
    }
}

// MARK: - Empty Feed View
struct EmptyFeedView: View {
    let language: AppLanguage
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "newspaper")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text(L10n.text("暂时没有个性化内容", "No personalized content yet", language: language))
                .font(.title3.bold())
                .foregroundColor(.textPrimary)
            
            Text(L10n.text("完成每日校准，即可开始接收 AI 精选研究", "Complete daily check-ins to receive AI-curated research.", language: language))
                .font(.subheadline)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(L10n.text("刷新", "Refresh", language: language), action: onRefresh)
                .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
        }
        .padding()
    }
}

// MARK: - Refresh Button
struct RefreshButton: View {
    let language: AppLanguage
    let isRefreshing: Bool
    let onRefresh: () -> Void
    
    var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            onRefresh()
        } label: {
            HStack(spacing: 8) {
                if isRefreshing {
                    ProgressView()
                        .tint(.liquidGlassAccent)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(isRefreshing
                     ? L10n.text("刷新中...", "Refreshing...", language: language)
                     : L10n.text("刷新文章", "Refresh Articles", language: language))
            }
            .font(.subheadline)
            .foregroundColor(.textPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.liquidGlassAccent.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(Color.liquidGlassAccent.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(isRefreshing)
    }
}

private struct FeedGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("科学期刊说明")
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

                feedBullet("优先查看“为什么推荐给你”，它和你最近状态直接相关。")
                feedBullet("每次阅读后做正负反馈，下一批推荐会更精准。")
                feedBullet("建议每天只看 1-2 篇并执行一个可落地动作。")

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func feedBullet(_ text: String) -> some View {
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

// MARK: - Flow Layout (简化版)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }
    
    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let width = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        
        return (CGSize(width: width, height: y + rowHeight), positions)
    }
}

// MARK: - Preview
struct ScienceFeedView_Previews: PreviewProvider {
    static var previews: some View {
        ScienceFeedView()
            .preferredColorScheme(.dark)
            .environmentObject(AppSettings())
    }
}
