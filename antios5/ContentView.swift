// ContentView.swift
// 主内容视图 - iOS 26 悬浮导航
//
// 审美: Neuro-Glass 界面

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var appSettings: AppSettings
    @State private var selectedTab: Tab = .dashboard
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
            case .dashboard: return L10n.text("闭环", "Loop", language: language)
            case .report: return L10n.text("解释", "Evidence", language: language)
            case .max: return "Max"
            case .plans: return L10n.text("行动", "Actions", language: language)
            case .settings: return L10n.text("设置", "Settings", language: language)
            }
        }
    }
    
    var body: some View {
        GeometryReader { proxy in
            let metrics = ScreenMetrics(size: proxy.size, safeAreaInsets: proxy.safeAreaInsets)

            Group {
            Group {
                if !supabase.isSessionRestored {
                    // 启动加载页
                    ZStack {
                        AuroraBackground().ignoresSafeArea()
                        VStack(spacing: 20) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 60))
                                .foregroundColor(.liquidGlassAccent)
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .transition(.opacity)
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
                    .forcedGlobalLeftShift(20)
            }
            .fullScreenCover(isPresented: $isBreathingPresented) {
                BreathingSessionView(durationMinutes: breathingDurationMinutes)
                    .forcedGlobalLeftShift(20)
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
                    .tag(Tab.dashboard)
                    .tabItem {
                        Label(Tab.dashboard.title(language: appSettings.language), systemImage: Tab.dashboard.icon)
                    }
                ReportView()
                    .tag(Tab.report)
                    .tabItem {
                        Label(Tab.report.title(language: appSettings.language), systemImage: Tab.report.icon)
                    }
                MaxChatView()
                    .tag(Tab.max)
                    .tabItem {
                        Label(Tab.max.title(language: appSettings.language), systemImage: Tab.max.icon)
                    }
                PlansView()
                    .tag(Tab.plans)
                    .tabItem {
                        Label(Tab.plans.title(language: appSettings.language), systemImage: Tab.plans.icon)
                    }
                SettingsView()
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
        .preferredColorScheme(.dark)
    }
}

private struct CustomTabBar: View {
    @Environment(\.screenMetrics) private var metrics
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
    }

    private var tabBarBackground: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.26),
                                Color.white.opacity(0.07),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.42), Color.white.opacity(0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.liquidGlassAccent.opacity(0.2))
                    .blur(radius: 20)
                    .offset(y: 10)
            )
            .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func tabButton(_ tab: ContentView.Tab, itemHeight: CGFloat) -> some View {
        let isSelected = selection == tab

        Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(tab.title(language: appSettings.language))
                    .font(.system(size: 11, weight: isSelected ? .bold : .semibold))
            }
            .foregroundColor(isSelected ? .liquidGlassAccent : .textTertiary)
            .frame(maxWidth: .infinity, minHeight: itemHeight)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.white.opacity(0.22) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var centerAxisOverlay: some View {
        Group {
            if LayoutDebug.enabled {
                GeometryReader { proxy in
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

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(SupabaseManager.shared)
            .environmentObject(AppSettings())
    }
}
