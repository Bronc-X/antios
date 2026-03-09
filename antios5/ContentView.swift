// ContentView.swift
// 主内容视图 - iOS 26 悬浮导航
//
// 审美: Neuro-Glass 界面

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var appSettings: AppSettings
    @State private var selectedTab: Tab
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false
    @State private var isCalibrationPresented = false
    @State private var isBreathingPresented = false
    @State private var breathingDurationMinutes = 5
    
    enum Tab: CaseIterable, Identifiable {
        case dashboard, report, max, plans, settings
        
        var id: Self { self }
        
        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .report: return "doc.text.magnifyingglass"
            case .max: return "bubble.left.and.bubble.right.fill"
            case .plans: return "list.bullet.clipboard.fill"
            case .settings: return "gearshape.fill"
            }
        }
        
        func title(language: AppLanguage) -> String {
            switch self {
            case .dashboard: return L10n.text("进展", "Progress", language: language)
            case .report: return L10n.text("解释", "Evidence", language: language)
            case .max: return "Max"
            case .plans: return L10n.text("行动", "Actions", language: language)
            case .settings: return L10n.text("设置", "Settings", language: language)
            }
        }

        var accessibilityIdentifier: String {
            switch self {
            case .dashboard: return "tab.dashboard"
            case .report: return "tab.report"
            case .max: return "tab.max"
            case .plans: return "tab.plans"
            case .settings: return "tab.settings"
            }
        }

        var screenIdentifier: String {
            switch self {
            case .dashboard: return "screen.dashboard"
            case .report: return "screen.report"
            case .max: return "screen.max"
            case .plans: return "screen.plans"
            case .settings: return "screen.settings"
            }
        }
    }

    init() {
        _selectedTab = State(initialValue: Self.initialTabFromEnvironment())
    }
    
    var body: some View {
        GeometryReader { proxy in
            let metrics = ScreenMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            Group {
            Group {
                if !supabase.isSessionRestored {
                    LoviLaunchSplashView()
                        .transition(.opacity)
                } else if !supabase.isAuthenticated {
                    AuthView()
                        .transition(.opacity)
                } else if !supabase.isClinicalComplete {
                    ClinicalOnboardingView(isComplete: $supabase.isClinicalComplete)
                        .transition(.opacity)
                } else if !isOnboardingComplete {
                    OnboardingView(isComplete: $isOnboardingComplete)
                        .transition(.opacity)
                } else {
                    mainInterface()
                        .transition(.opacity)
                }
            }
            }
            .environment(\.screenMetrics, metrics)
            .animation(.easeInOut, value: supabase.isAuthenticated)
            .animation(.easeInOut, value: isOnboardingComplete)
            .onReceive(NotificationCenter.default.publisher(for: .openDashboard)) { _ in
                selectedTab = .dashboard
            }
            .onReceive(NotificationCenter.default.publisher(for: .openMaxChat)) { _ in
                selectedTab = .max
            }
            .onReceive(NotificationCenter.default.publisher(for: .startCalibration)) { _ in
                isCalibrationPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .startBreathing)) { notification in
                if let duration = notification.userInfo?["duration"] as? Int {
                    breathingDurationMinutes = max(1, duration)
                }
                isBreathingPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .askMax)) { notification in
                if notification.userInfo?["forwarded"] as? Bool == true {
                    return
                }
                if let question = notification.userInfo?["question"] as? String,
                   !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selectedTab = .max
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        NotificationCenter.default.post(
                            name: .askMax,
                            object: nil,
                            userInfo: ["question": question, "forwarded": true]
                        )
                    }
                }
            }
            .fullScreenCover(isPresented: $isCalibrationPresented) {
                CalibrationView(autoStart: true)
            }
            .fullScreenCover(isPresented: $isBreathingPresented) {
                BreathingSessionView(durationMinutes: breathingDurationMinutes)
            }
        }
        .ignoresSafeArea()
    }
    
    // MARK: - 主界面
    private func mainInterface() -> some View {
        ZStack {
            // 1. 全局背景
            AuroraBackground()
                .ignoresSafeArea() // 确保背景填满顶部灵动岛区域
            
            // 2. 原生 TabView
            TabView(selection: $selectedTab) {
                DashboardView()
                    .overlay(alignment: .topLeading) {
                        UITestMarker(identifier: Tab.dashboard.screenIdentifier)
                    }
                    .tag(Tab.dashboard)
                    .tabItem {
                        Label(Tab.dashboard.title(language: appSettings.language), systemImage: Tab.dashboard.icon)
                    }
                ReportView()
                    .overlay(alignment: .topLeading) {
                        UITestMarker(identifier: Tab.report.screenIdentifier)
                    }
                    .tag(Tab.report)
                    .tabItem {
                        Label(Tab.report.title(language: appSettings.language), systemImage: Tab.report.icon)
                    }
                MaxChatView()
                    .overlay(alignment: .topLeading) {
                        UITestMarker(identifier: Tab.max.screenIdentifier)
                    }
                    .tag(Tab.max)
                    .tabItem {
                        Label(Tab.max.title(language: appSettings.language), systemImage: Tab.max.icon)
                    }
                PlansView()
                    .overlay(alignment: .topLeading) {
                        UITestMarker(identifier: Tab.plans.screenIdentifier)
                    }
                    .tag(Tab.plans)
                    .tabItem {
                        Label(Tab.plans.title(language: appSettings.language), systemImage: Tab.plans.icon)
                    }
                SettingsView()
                    .overlay(alignment: .topLeading) {
                        UITestMarker(identifier: Tab.settings.screenIdentifier)
                    }
                    .tag(Tab.settings)
                    .tabItem {
                        Label(Tab.settings.title(language: appSettings.language), systemImage: Tab.settings.icon)
                    }
            }
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selectedTab != .max {
                    CustomTabBar(tabs: Tab.allCases, selection: $selectedTab)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .overlay(alignment: .topLeading) {
            UITestMarker(identifier: "screen.main")
        }
    }

    private static func initialTabFromEnvironment() -> Tab {
        guard let rawValue = LaunchOverrides.stringValue("UI_TEST_INITIAL_TAB")?.lowercased() else {
            return .dashboard
        }

        switch rawValue {
        case "report":
            return .report
        case "max":
            return .max
        case "plans":
            return .plans
        case "settings":
            return .settings
        default:
            return .dashboard
        }
    }
}

private struct LoviLaunchSplashView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var drift = false
    @State private var logoFloat = false
    @State private var revealContent = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#1A1230"), Color(hex: "#311745"), Color(hex: "#21163D")]
                    : [Color(hex: "#FFFEFF"), Color(hex: "#FDEFFF"), Color(hex: "#F4EEFF")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(hex: "#E2AAFF").opacity(colorScheme == .dark ? 0.34 : 0.28))
                .frame(width: 420, height: 420)
                .blur(radius: 118)
                .offset(x: drift ? -120 : -22, y: drift ? -210 : -132)

            Circle()
                .fill(Color(hex: "#FFC3EA").opacity(colorScheme == .dark ? 0.30 : 0.25))
                .frame(width: 442, height: 442)
                .blur(radius: 126)
                .offset(x: drift ? 126 : 36, y: drift ? 228 : 148)

            Circle()
                .fill(Color(hex: "#89E8B8").opacity(colorScheme == .dark ? 0.15 : 0.11))
                .frame(width: 220, height: 220)
                .blur(radius: 66)
                .offset(x: drift ? 138 : 88, y: drift ? -108 : -142)

            Circle()
                .fill(Color(hex: "#F6EAFF").opacity(colorScheme == .dark ? 0.07 : 0.18))
                .frame(width: 322, height: 322)
                .blur(radius: 92)
                .offset(x: drift ? 36 : -24, y: drift ? 34 : 102)

            VStack(spacing: 18) {
                Spacer()

                LoviSplashMark(scaleUp: logoFloat)
                    .padding(.bottom, 2)

                VStack(spacing: 8) {
                    Text("Science-backed 情绪伙伴")
                        .font(GlassTypography.cnLovi(20, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : Color(hex: "#72679C"))
                }
                .opacity(revealContent ? 1 : 0)
                .offset(y: revealContent ? 0 : 8)

                Spacer()

                HStack(spacing: 6) {
                    Circle().fill(Color(hex: "#D7A2FF")).frame(width: 6, height: 6).opacity(0.95)
                    Circle().fill(Color(hex: "#F4B5E2")).frame(width: 6, height: 6).opacity(0.76)
                    Circle().fill(Color(hex: "#85E6B5")).frame(width: 6, height: 6).opacity(0.62)
                    Text("正在准备你的个性化体验")
                        .font(GlassTypography.cnLovi(13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.8) : Color(hex: "#7A6EA3"))
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.surfaceGlass(for: colorScheme))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.surfaceStroke(for: colorScheme), lineWidth: 1)
                        )
                        .shadow(color: Color(hex: "#748CFF").opacity(colorScheme == .dark ? 0.24 : 0.16), radius: 12, y: 7)
                )
                .padding(.horizontal, 44)
                .padding(.bottom, 64)
                .opacity(revealContent ? 1 : 0)
                .offset(y: revealContent ? 0 : 10)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                drift.toggle()
            }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                logoFloat.toggle()
            }
            withAnimation(.easeOut(duration: 0.55).delay(0.18)) {
                revealContent = true
            }
        }
        .accessibilityIdentifier("screen.splash")
    }
}

private struct CustomTabBar: View {
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings
    let tabs: [ContentView.Tab]
    @Binding var selection: ContentView.Tab

    var body: some View {
        let itemHeight: CGFloat = metrics.isCompactHeight ? 52 : 58
        let topPadding: CGFloat = metrics.isCompactHeight ? 6 : 8
        let bottomPadding = max(10, metrics.safeAreaInsets.bottom)
        let sidePadding = metrics.tabBarHorizontalPadding
        // 使用像素对齐的固定宽度，避免亚像素漂移
        let containerWidth = alignToPixel(metrics.fixedScreenWidth)
        let extraWidth: CGFloat = 16  // 左右各自加宽 8
        let barWidth = alignToPixel(min(containerWidth, metrics.tabBarWidth + extraWidth))
        let totalHeight = itemHeight + topPadding + bottomPadding

        // 使用 ZStack 创建显式居中容器，确保背景与内容共享同一锚点
        ZStack {
            // 背景层 - 使用相同的 barWidth
            tabBarBackground
                .frame(width: barWidth, height: totalHeight)

            // 内容层 - 使用相同的 barWidth
            VStack(spacing: 0) {
                Color.clear.frame(height: topPadding)
                HStack(spacing: 0) {
                    ForEach(tabs, id: \.self) { tab in
                        tabButton(tab, itemHeight: itemHeight)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, sidePadding)
                .frame(width: barWidth, height: itemHeight)
                Color.clear.frame(height: bottomPadding)
            }
            .frame(width: barWidth, height: totalHeight)
        }
        .frame(width: containerWidth, height: totalHeight)  // 容器锚定到物理屏幕宽度
        .overlay(centerAxisOverlay)
        .accessibilityIdentifier("tabbar.custom")
    }

    private var tabBarBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.clear)
            .liquidGlassRoundedChrome(cornerRadius: 30, shadow: true)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.liquidGlassAccent.opacity(colorScheme == .dark ? 0.14 : 0.1))
                    .blur(radius: colorScheme == .dark ? 16 : 12)
                    .offset(y: colorScheme == .dark ? 8 : 6)
            )
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func tabButton(_ tab: ContentView.Tab, itemHeight: CGFloat) -> some View {
        let isSelected = selection == tab

        Button {
            if selection != tab {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            } else {
                let feedback = UISelectionFeedbackGenerator()
                feedback.selectionChanged()
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(tab.title(language: appSettings.language))
                    .font(GlassTypography.cnLovi(11, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .liquidGlassAccent : .textTertiary)
            .frame(maxWidth: .infinity, minHeight: itemHeight)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(colorScheme == .dark ? 0.22 : 0.34) : Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.white.opacity(colorScheme == .dark ? 0.38 : 0.5) : Color.clear, lineWidth: 1)
                    )
            )
            .scaleEffect(isSelected ? 1.02 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tab.accessibilityIdentifier)
    }

    private var centerAxisOverlay: some View {
        Group {
            if LayoutDebug.enabled {
                GeometryReader { proxy in
                    // ui-audit: ignore-next-line layout-geometry-width-basis
                    let centerX = proxy.size.width / 2
                    Rectangle()
                        .fill(Color.yellow.opacity(0.7))
                        .frame(width: 1)
                        .offset(x: centerX)
                }
            }
        }
    }

    private func alignToPixel(_ value: CGFloat) -> CGFloat {
        #if os(iOS)
        let scale = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.scale ?? 2.0
        #else
        let scale: CGFloat = 2.0
        #endif
        return (value * scale).rounded() / scale
    }
}

private struct UITestMarker: View {
    let identifier: String

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(identifier)
            .allowsHitTesting(false)
    }
}

private struct LoviSplashMark: View {
    @Environment(\.colorScheme) private var colorScheme
    let scaleUp: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 118, height: 118)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.splashMarkOuterStroke(for: colorScheme), lineWidth: 1)
                )
                .shadow(
                    color: Color(hex: "#8D80FF").opacity(colorScheme == .dark ? 0.3 : 0.18),
                    radius: 24,
                    y: 10
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.splashMarkPlateFill(for: colorScheme))
                .frame(width: 86, height: 86)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.splashMarkPlateStroke(for: colorScheme), lineWidth: 1)
                )

            Text("lóvi")
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.splashLogoPrimary(for: colorScheme),
                            Color.splashLogoSecondary(for: colorScheme)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .kerning(-1.2)
                .scaleEffect(scaleUp ? 1.03 : 0.98)
                .shadow(
                    color: Color(hex: "#C6A7EF").opacity(colorScheme == .dark ? 0.12 : 0.18),
                    radius: 8,
                    y: 2
                )
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SupabaseManager.shared)
            .environmentObject(AppSettings())
    }
}
