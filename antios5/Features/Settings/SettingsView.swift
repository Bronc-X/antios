// SettingsView.swift
// 设置视图 - Liquid Glass 风格

import SwiftUI
import UserNotifications
import LocalAuthentication

struct SettingsView: View {
    private enum LightweightSheet: String, Identifiable {
        case dataExport
        case privacyPolicy
        case helpCenter
        case debugSession

        var id: String { rawValue }
    }

    @StateObject private var viewModel = SettingsViewModel()
    @ObservedObject var supabase = SupabaseManager.shared
    @ObservedObject var themeManager = ThemeManager.shared
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @State private var showWhatsNewSheet = false
    @State private var showSettingsGuide = false
    @State private var lightweightSheet: LightweightSheet?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 统一背景体系
                AuroraBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
                        // ==========================================
                        // 用户资料卡片
                        // ==========================================
                        userProfileCard

                        // ==========================================
                        // 会员与授权
                        // ==========================================
                        membershipSection
                        
                        // ==========================================
                        // 健康数据
                        // ==========================================
                        healthDataSection
                        
                        // ==========================================
                        // 通知设置
                        // ==========================================
                        notificationSection
                        
                        // ==========================================
                        // 隐私与安全
                        // ==========================================
                        privacySection
                        
                        // ==========================================
                        // 外观
                        // ==========================================
                        appearanceSection
                        
                        // ==========================================
                        // 语言
                        // ==========================================
                        languageSection
                        
                        // ==========================================
                        // 关于
                        // ==========================================
                        aboutSection
                        
                        // ==========================================
                        // 退出登录
                        // ==========================================
                        logoutButton
                    }
                    .liquidGlassPageWidth()
                    .padding(.top, metrics.isCompactHeight ? 8 : 12)
                    .padding(.bottom, metrics.bottomContentInset)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        let haptic = UIImpactFeedbackGenerator(style: .soft)
                        haptic.impactOccurred()
                        showSettingsGuide = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.liquidGlassAccent)
                            .liquidGlassCircleBadge(padding: 6)
                    }
                    .buttonStyle(.plain)
                }
                ToolbarItem(placement: .principal) {
                    Text("设置")
                    
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                }
            }
            .alert(
                "提示",
                isPresented: Binding(
                    get: { viewModel.alertMessage != nil },
                    set: { _ in viewModel.alertMessage = nil }
                )
            ) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(viewModel.alertMessage ?? "")
            }
            .onChange(of: viewModel.notificationsEnabled) { _, newValue in
                viewModel.handleNotificationsChanged(newValue)
            }
            .onChange(of: viewModel.dailyReminderEnabled) { _, newValue in
                viewModel.handleDailyReminderChanged(newValue)
            }
            .onChange(of: viewModel.biometricEnabled) { _, newValue in
                viewModel.handleBiometricChanged(newValue)
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $showWhatsNewSheet) {
                WhatsNewSheet()
                    .presentationDetents([.fraction(0.42), .large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
            }
            .sheet(isPresented: $showSettingsGuide) {
                SettingsGuideSheet()
                    .presentationDetents([.fraction(0.42), .large])
                    .liquidGlassSheetChrome(cornerRadius: 28)
            }
            .sheet(item: $lightweightSheet) { sheet in
                NavigationStack {
                    Group {
                        switch sheet {
                        case .dataExport:
                            DataExportView()
                        case .privacyPolicy:
                            PrivacyPolicyView()
                        case .helpCenter:
                            HelpCenterView()
                        case .debugSession:
                            DebugSessionView()
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
            }
        }
    }
    
    // MARK: - 用户资料卡片
    
    private var userProfileCard: some View {
        let avatarSize: CGFloat = metrics.isCompactWidth ? 52 : 60
        let iconSize: CGFloat = metrics.isCompactWidth ? 48 : 56
        return NavigationLink(destination: ProfileView()) {
            LiquidGlassCard(style: .elevated, padding: 20) {
                HStack(spacing: 16) {
                    // 头像
                    ZStack {
                        Circle()
                            .fill(LinearGradient.accentFlow)
                            .frame(width: avatarSize, height: avatarSize)
                            .blur(radius: 4)
                            .opacity(0.5)

                        if let avatar = viewModel.profileAvatarURL,
                           let url = URL(string: avatar) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: iconSize))
                                    .foregroundColor(.liquidGlassAccent)
                            }
                            .frame(width: avatarSize - 4, height: avatarSize - 4)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: iconSize))
                                .foregroundColor(.liquidGlassAccent)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.profileDisplayName)
                            .font(.title3.bold())
                            .foregroundColor(.textPrimary)
                        
                        Text(viewModel.profileEmail)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                        
                        StatusPill(text: viewModel.isEmailVerified ? "已登录" : "未登录", color: viewModel.isEmailVerified ? .statusSuccess : .statusWarning)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 健康数据
    
    private var healthDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "穿戴与数据链路", icon: "heart.fill")
            
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 0) {
                    LiquidGlassSettingsRow(
                        icon: "heart.fill",
                        iconColor: .statusError,
                        title: "HealthKit",
                        subtitle: "连接 Apple Watch / HealthKit 并进入模型与 RAG"
                    ) {
                        HealthKitSettingsViewNew()
                    }
                    
                    Divider()
                        .background(Color.textPrimary.opacity(0.1))
                        .padding(.leading, 46)
                    
                    LiquidGlassSettingsRow(
                        icon: "applewatch",
                        iconColor: .liquidGlassPrimary,
                        title: "穿戴设备",
                        subtitle: "查看同步状态与最近上传"
                    ) {
                        WearablesView()
                    }
                }
            }
        }
    }
    
    // MARK: - 通知设置
    
    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "跟进提醒", icon: "bell.fill")
            
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.statusSuccess.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "bell.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.statusSuccess)
                        }
                        
                        Text("跟进提醒")
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Toggle("", isOn: $viewModel.notificationsEnabled)
                            .toggleStyle(LiquidGlassToggleStyle())
                            .labelsHidden()
                    }
                    
                    if viewModel.notificationsEnabled {
                        Divider()
                            .background(Color.textPrimary.opacity(0.1))
                            .padding(.leading, 46)
                        
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.liquidGlassWarm.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.liquidGlassWarm)
                            }
                            
                            Text("每日校准与跟进提醒")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            
                            Spacer()
                            
                            Toggle("", isOn: $viewModel.dailyReminderEnabled)
                                .toggleStyle(LiquidGlassToggleStyle())
                                .labelsHidden()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 隐私与安全
    
    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "安全与隐私", icon: "lock.fill")
            
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.liquidGlassPurple.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "faceid")
                                .font(.system(size: 14))
                                .foregroundColor(.liquidGlassPurple)
                        }
                        
                        Text("生物识别锁")
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                        
                        Toggle("", isOn: $viewModel.biometricEnabled)
                            .toggleStyle(LiquidGlassToggleStyle())
                            .labelsHidden()
                    }
                    
                    Divider()
                        .background(Color.textPrimary.opacity(0.1))
                        .padding(.leading, 46)
                        .padding(.vertical, 12)
                    
                    LightweightActionRow(
                        icon: "square.and.arrow.up",
                        iconColor: .liquidGlassAccent,
                        title: "导出数据"
                    ) {
                        let feedback = UIImpactFeedbackGenerator(style: .soft)
                        feedback.impactOccurred()
                        lightweightSheet = .dataExport
                    }
                    
                    Divider()
                        .background(Color.textPrimary.opacity(0.1))
                        .padding(.leading, 46)
                    
                    LightweightActionRow(
                        icon: "hand.raised.fill",
                        iconColor: .liquidGlassSecondary,
                        title: "隐私政策"
                    ) {
                        let feedback = UIImpactFeedbackGenerator(style: .soft)
                        feedback.impactOccurred()
                        lightweightSheet = .privacyPolicy
                    }
                }
            }
        }
    }
    
    // MARK: - 外观
    
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "外观", icon: "paintpalette.fill")
            
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.liquidGlassPrimary.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "circle.lefthalf.filled")
                                .font(.system(size: 14))
                                .foregroundColor(.liquidGlassPrimary)
                        }
                        
                        Text("外观模式")
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                    }
                    
                    // 外观模式选择器
                    HStack(spacing: 8) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                themeManager.appearanceMode = mode
                            } label: {
                                Text(mode.rawValue)
                                    .font(.caption.bold())
                                    .foregroundColor(themeManager.appearanceMode == mode ? .bgPrimary : .textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                            themeManager.appearanceMode == mode
                                            ? Color.liquidGlassAccent
                                            : Color.textPrimary.opacity(0.1)
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 语言
    
    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "语言", icon: "globe")
            
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 12) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.liquidGlassWarm.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "globe")
                                .font(.system(size: 14))
                                .foregroundColor(.liquidGlassWarm)
                        }
                        
                        Text("应用语言")
                            .font(.subheadline)
                            .foregroundColor(.textPrimary)
                        
                        Spacer()
                    }
                    
                    // 语言选择器
                    HStack(spacing: 8) {
                        ForEach(AppLanguage.allCases) { lang in
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                appSettings.language = lang
                            } label: {
                                Text(lang.displayName)
                                    .font(.caption.bold())
                                    .foregroundColor(appSettings.language == lang ? .bgPrimary : .textSecondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        appSettings.language == lang
                                            ? Color.liquidGlassAccent
                                            : Color.textPrimary.opacity(0.1)
                                    )
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 关于
    
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "支持与信息", icon: "info.circle.fill")
            
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 0) {
                    Button {
                        let feedback = UIImpactFeedbackGenerator(style: .soft)
                        feedback.impactOccurred()
                        showWhatsNewSheet = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.textSecondary.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "app.badge")
                                    .font(.system(size: 14))
                                    .foregroundColor(.textSecondary)
                            }
                            
                            Text("版本")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            
                            Spacer()
                            
                            Text(AppVersion.label)
                                .font(.caption)
                                .foregroundColor(.textTertiary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Divider()
                        .background(Color.textPrimary.opacity(0.1))
                        .padding(.leading, 46)
                        .padding(.vertical, 12)
                    
                    LightweightActionRow(
                        icon: "questionmark.circle",
                        iconColor: .liquidGlassAccent,
                        title: "反馈与帮助"
                    ) {
                        let feedback = UIImpactFeedbackGenerator(style: .soft)
                        feedback.impactOccurred()
                        lightweightSheet = .helpCenter
                    }

                    Divider()
                        .background(Color.textPrimary.opacity(0.1))
                        .padding(.leading, 46)

                    LightweightActionRow(
                        icon: "ladybug.fill",
                        iconColor: .textSecondary,
                        title: "调试会话"
                    ) {
                        let feedback = UIImpactFeedbackGenerator(style: .light)
                        feedback.impactOccurred()
                        lightweightSheet = .debugSession
                    }

                    Divider()
                        .background(Color.textPrimary.opacity(0.1))
                        .padding(.leading, 46)

                    LiquidGlassSettingsRow(
                        icon: "wand.and.stars.inverse",
                        iconColor: .liquidGlassAccent,
                        title: "设计系统容器",
                        subtitle: "规范、组件与复刻样机"
                    ) {
                        DesignSystemContainerView()
                    }
                }
            }
        }
    }

    // MARK: - 会员与授权

    private var membershipSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "关键权限", icon: "crown.fill")

            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 0) {
                    LiquidGlassSettingsRow(
                        icon: "crown.fill",
                        iconColor: .liquidGlassWarm,
                        title: "会员方案",
                        subtitle: "查看当前权益"
                    ) {
                        MembershipView()
                    }

                    Divider()
                        .background(Color.textPrimary.opacity(0.1))
                        .padding(.leading, 46)

                    LiquidGlassSettingsRow(
                        icon: "shield.fill",
                        iconColor: .statusSuccess,
                        title: "数据授权",
                        subtitle: "管理数据同步状态"
                    ) {
                        WearablesView()
                    }
                }
            }
        }
    }
    
    // MARK: - 退出登录
    
    private var logoutButton: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            Task { await supabase.signOut() }
        } label: {
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 14))
                    Text("退出登录")
                        .font(.subheadline.bold())
                }
                .foregroundColor(.statusError)
                
                Spacer()
            }
            .padding(.vertical, 16)
            .background(Color.statusError.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.statusError.opacity(0.3), lineWidth: 1)
            )
        }
        .padding(.top, 8)
    }
}

private struct LightweightActionRow: View {
    let icon: String
    var iconColor: Color = .liquidGlassAccent
    let title: String
    var subtitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.localized(title))
                        .font(GlassTypography.body(14, weight: .medium))
                        .foregroundColor(.textPrimary)

                    if let subtitle = subtitle {
                        Text(L10n.localized(subtitle))
                            .font(GlassTypography.caption(11))
                            .foregroundColor(.textTertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.textTertiary)
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - HealthKit 设置视图 (新版)

struct HealthKitSettingsViewNew: View {
    @StateObject private var healthKit = HealthKitService.shared
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            AuroraBackground()
            
            ScrollView {
                VStack(spacing: 20) {
                    // 状态卡片
                    LiquidGlassCard(style: .elevated, padding: 20) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(healthKit.isAuthorized ? Color.statusSuccess.opacity(0.2) : Color.statusWarning.opacity(0.2))
                                    .frame(width: 56, height: 56)
                                
                                Image(systemName: healthKit.isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(healthKit.isAuthorized ? .statusSuccess : .statusWarning)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(healthKit.isAuthorized ? "已授权" : "未授权")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                
                                Text(healthKit.isAuthorized ? "健康数据同步已开启" : "需要授权以同步健康数据")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            
                            Spacer()
                        }
                    }
                    
                    // 授权按钮
                    if !healthKit.isAuthorized {
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.impactOccurred()
                            Task { try? await healthKit.requestAuthorization() }
                        } label: {
                            Text("请求授权")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                    }
                    
                    // 数据类型
                    VStack(alignment: .leading, spacing: 12) {
                        LiquidGlassSectionHeader(title: "可同步数据", icon: "heart.text.square.fill")
                        
                        LiquidGlassCard(style: .standard, padding: 16) {
                            VStack(spacing: 14) {
                                healthDataRow(icon: "waveform.path.ecg", color: .liquidGlassAccent, title: "心率变异性 (HRV)", status: "核心指标")
                                
                                Divider().background(Color.textPrimary.opacity(0.1))
                                
                                healthDataRow(icon: "heart.fill", color: .statusError, title: "静息心率", status: "焦虑基线")
                                
                                Divider().background(Color.textPrimary.opacity(0.1))
                                
                                healthDataRow(icon: "moon.zzz.fill", color: .liquidGlassPurple, title: "睡眠分析", status: "睡眠质量")
                                
                                Divider().background(Color.textPrimary.opacity(0.1))
                                
                                healthDataRow(icon: "figure.walk", color: .liquidGlassWarm, title: "步数", status: "活动量")
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("HealthKit")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func healthDataRow(icon: String, color: Color, title: String, status: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.subheadline)
                .foregroundColor(.textPrimary)
            
            Spacer()
            
            Text(status)
                .font(.caption)
                .foregroundColor(.textTertiary)
        }
    }
}

// MARK: - ViewModel

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var notificationsEnabled: Bool
    @Published var dailyReminderEnabled: Bool
    @Published var biometricEnabled: Bool
    @Published var alertMessage: String?
    @Published var profileDisplayName: String = "探索者"
    @Published var profileEmail: String = "未登录"
    @Published var profileAvatarURL: String?
    @Published var isEmailVerified = false

    private let notificationCenter = UNUserNotificationCenter.current()
    private let dailyReminderId = "daily-calibration-reminder"
    private let supabase = SupabaseManager.shared
    private var isUpdating = false

    init() {
        let defaults = UserDefaults.standard
        notificationsEnabled = defaults.object(forKey: "settings_notifications_enabled") as? Bool ?? false
        dailyReminderEnabled = defaults.object(forKey: "settings_daily_reminder_enabled") as? Bool ?? false
        biometricEnabled = defaults.object(forKey: "settings_biometric_enabled") as? Bool ?? false
    }

    func load() async {
        isUpdating = true
        defer { isUpdating = false }

        let defaults = UserDefaults.standard
        biometricEnabled = defaults.object(forKey: "settings_biometric_enabled") as? Bool ?? false
        let isLaunchBypass = LaunchOverrides.boolFlag("UI_TEST_BYPASS_GATEKEEPING")

        if let user = supabase.currentUser {
            profileEmail = user.email ?? "未设置邮箱"
            profileDisplayName = user.email?.components(separatedBy: "@").first ?? "探索者"
            isEmailVerified = true
        } else {
            profileEmail = "未登录"
            profileDisplayName = "探索者"
            isEmailVerified = false
        }

        if isLaunchBypass {
            profileEmail = supabase.currentUser?.email ?? "ui-test@example.com"
            profileDisplayName = "ui-test"
            isEmailVerified = true
            profileAvatarURL = nil
            alertMessage = nil
        } else {
            do {
                if let profile = try await supabase.getProfileSettings() {
                    if let fullName = profile.full_name, !fullName.isEmpty {
                        profileDisplayName = fullName
                    }
                    profileAvatarURL = profile.avatar_url
                    dailyReminderEnabled = profile.reminder_preferences?.morning ?? dailyReminderEnabled
                }
            } catch {
                alertMessage = "加载设置失败：\(error.localizedDescription)"
            }
        }

        let systemGranted = await currentNotificationPermissionGranted()
        notificationsEnabled = systemGranted
        defaults.set(systemGranted, forKey: "settings_notifications_enabled")
        defaults.set(dailyReminderEnabled, forKey: "settings_daily_reminder_enabled")
    }

    func handleNotificationsChanged(_ enabled: Bool) {
        guard !isUpdating else { return }
        isUpdating = true
        UserDefaults.standard.set(enabled, forKey: "settings_notifications_enabled")

        Task { @MainActor in
            if enabled {
                let granted = await requestNotificationPermission()
                if !granted {
                    notificationsEnabled = false
                    dailyReminderEnabled = false
                    UserDefaults.standard.set(false, forKey: "settings_notifications_enabled")
                    UserDefaults.standard.set(false, forKey: "settings_daily_reminder_enabled")
                    alertMessage = "通知权限未授权，请在系统设置中开启。"
                    await syncReminderPreference(enabled: false)
                } else if dailyReminderEnabled {
                    await scheduleDailyReminder()
                    await syncReminderPreference(enabled: true)
                }
            } else {
                notificationCenter.removeAllPendingNotificationRequests()
                dailyReminderEnabled = false
                UserDefaults.standard.set(false, forKey: "settings_daily_reminder_enabled")
                await syncReminderPreference(enabled: false)
            }
            isUpdating = false
        }
    }

    func handleDailyReminderChanged(_ enabled: Bool) {
        guard !isUpdating else { return }
        isUpdating = true
        UserDefaults.standard.set(enabled, forKey: "settings_daily_reminder_enabled")

        Task { @MainActor in
            if enabled {
                if !notificationsEnabled {
                    notificationsEnabled = true
                    let granted = await requestNotificationPermission()
                    if !granted {
                        notificationsEnabled = false
                        dailyReminderEnabled = false
                        UserDefaults.standard.set(false, forKey: "settings_notifications_enabled")
                        UserDefaults.standard.set(false, forKey: "settings_daily_reminder_enabled")
                        alertMessage = "通知权限未授权，请在系统设置中开启。"
                        await syncReminderPreference(enabled: false)
                        isUpdating = false
                        return
                    }
                }
                await scheduleDailyReminder()
                await syncReminderPreference(enabled: true)
            } else {
                notificationCenter.removePendingNotificationRequests(withIdentifiers: [dailyReminderId])
                await syncReminderPreference(enabled: false)
            }
            isUpdating = false
        }
    }

    func handleBiometricChanged(_ enabled: Bool) {
        guard !isUpdating else { return }
        isUpdating = true
        UserDefaults.standard.set(enabled, forKey: "settings_biometric_enabled")

        Task { @MainActor in
            if enabled {
                let success = await authenticateBiometric()
                if !success {
                    biometricEnabled = false
                    UserDefaults.standard.set(false, forKey: "settings_biometric_enabled")
                }
            }
            isUpdating = false
        }
    }

    private func requestNotificationPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func currentNotificationPermissionGranted() async -> Bool {
        await withCheckedContinuation { continuation in
            notificationCenter.getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }

    private func scheduleDailyReminder() async {
        let content = UNMutableNotificationContent()
        content.title = "每日校准提醒"
        content.body = "花 2 分钟完成今日校准，Max 会更了解你。"
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: dailyReminderId, content: content, trigger: trigger)
        try? await notificationCenter.add(request)
    }

    private func authenticateBiometric() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            alertMessage = "当前设备不支持生物识别。"
            return false
        }

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "用于开启生物识别锁"
            ) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    private func syncReminderPreference(enabled: Bool) async {
        do {
            let current = try await supabase.getReminderPreferences()
            let updated = ReminderPreferences(
                morning: enabled,
                evening: current.evening ?? false,
                breathing: current.breathing ?? false
            )
            _ = try await supabase.updateReminderPreferences(updated)
        } catch {
            alertMessage = "同步提醒设置失败：\(error.localizedDescription)"
        }
    }
}

private enum AppVersion {
    static var label: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
            .environmentObject(AppSettings())
            .preferredColorScheme(.dark)
    }
}

// MARK: - Settings Subviews

struct MembershipView: View {
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = MembershipViewModel()

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("会员方案")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("当前计划：\(viewModel.currentTier)")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("当前权益")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            ForEach(viewModel.benefits, id: \.self) { benefit in
                                Text("• \(benefit)")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }

                    LiquidGlassCard(style: .concave, padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("升级计划")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Text("高级报告、AI 深度分析与更多 API 配额")
                                .font(.caption)
                                .foregroundColor(.textSecondary)

                            Button {
                                if let url = URL(string: "mailto:support@antianxiety.ai?subject=会员咨询") {
                                    openURL(url)
                                }
                            } label: {
                                Text("发送升级咨询")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                        }
                    }
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
        }
        .navigationTitle("会员方案")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }
}

@MainActor
final class MembershipViewModel: ObservableObject {
    @Published var currentTier = "基础版"
    @Published var benefits: [String] = [
        "每日校准与数字孪生分析",
        "科学期刊精选与反馈",
        "计划引擎与习惯追踪"
    ]

    private let supabase = SupabaseManager.shared

    private struct PlanProbe: Codable {
        let id: String?
        let status: String?
    }

    private struct GoalProbe: Codable {
        let id: String?
        let is_completed: Bool?
    }

    func load() async {
        guard let user = supabase.currentUser else { return }
        let planEndpoint = "user_plans?user_id=eq.\(user.id)&select=id,status"
        let goalEndpoint = "phase_goals?user_id=eq.\(user.id)&select=id,is_completed"
        let plans: [PlanProbe] = (try? await supabase.request(planEndpoint)) ?? []
        let goals: [GoalProbe] = (try? await supabase.request(goalEndpoint)) ?? []

        let activePlans = plans.filter { $0.status == "active" }.count
        let completedGoals = goals.filter { $0.is_completed == true }.count

        benefits = [
            "每日校准与数字孪生分析",
            "活跃计划：\(activePlans) 个",
            "已完成目标：\(completedGoals) 个"
        ]
    }
}

struct WearablesView: View {
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("穿戴设备")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("管理 HealthKit 与设备同步")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    NavigationLink(destination: WearableConnectView(viewModel: WearableConnectViewModel())) {
                        LiquidGlassCard(style: .standard, padding: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: "applewatch")
                                    .foregroundColor(.liquidGlassAccent)
                                Text("设备管理")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    NavigationLink(destination: HealthKitSettingsViewNew()) {
                        LiquidGlassCard(style: .standard, padding: 16) {
                            HStack(spacing: 12) {
                                Image(systemName: "heart.text.square")
                                    .foregroundColor(.statusSuccess)
                                Text("HealthKit 授权")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
        }
        .navigationTitle("穿戴设备")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DataExportView: View {
    @StateObject private var viewModel = DataExportViewModel()
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("数据导出")
                            .font(.headline)
                            .foregroundColor(.textPrimary)
                        Text("生成可导出的 JSON 快照")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        Task { await viewModel.export() }
                    } label: {
                        Text(viewModel.isExporting ? "生成中..." : "生成导出文件")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                    .disabled(viewModel.isExporting)

                    if let exportText = viewModel.exportText {
                        Text(exportText)
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                            .lineLimit(12)
                    }

                    if let error = viewModel.error {
                        Text(error)
                            .font(.caption2)
                            .foregroundColor(.statusError)
                    }
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
        }
        .navigationTitle("数据导出")
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
final class DataExportViewModel: ObservableObject {
    @Published var exportText: String?
    @Published var isExporting = false
    @Published var error: String?

    private let supabase = SupabaseManager.shared

    func export() async {
        isExporting = true
        error = nil
        exportText = nil
        defer { isExporting = false }

        do {
            let profile = try? await supabase.getProfileSettings()
            let logs = (try? await supabase.getWeeklyWellnessLogs()) ?? []
            let digitalTwin = try? await supabase.getDigitalTwinAnalysis()
            let hardware = try? await supabase.getHardwareData()

            let payload = ExportPayload(profile: profile, weeklyLogs: logs, digitalTwin: digitalTwin, hardware: hardware)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            exportText = String(data: data, encoding: .utf8)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ExportPayload: Codable {
    let profile: ProfileSettings?
    let weeklyLogs: [WellnessLog]
    let digitalTwin: DigitalTwinAnalysis?
    let hardware: HardwareData?
}

struct PrivacyPolicyView: View {
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    Text("隐私政策摘要")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("• 数据仅用于生成可解释反焦虑建议")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text("• 仅在你授权时同步穿戴设备数据")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text("• 支持导出与删除个人数据")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HelpCenterView: View {
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    Text("帮助中心")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("如需支持，请联系 support@antianxiety.ai")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                            Text("建议在反馈中附上调试会话截图")
                                .font(.caption)
                                .foregroundColor(.textSecondary)

                            Button {
                                if let url = URL(string: "mailto:support@antianxiety.ai?subject=App支持请求") {
                                    openURL(url)
                                }
                            } label: {
                                Text("发送支持邮件")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                        }
                    }
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
        }
        .navigationTitle("帮助中心")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Design System Container

private enum LabStylePreset: String, CaseIterable, Identifiable {
    case purplePink
    case forestGreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purplePink: return "淡紫流光"
        case .forestGreen: return "森氧深绿"
        }
    }

    var subtitle: String {
        switch self {
        case .purplePink: return "浅色体系 + 情绪疗愈感"
        case .forestGreen: return "稳态感 + 训练恢复风"
        }
    }

    var primary: Color {
        switch self {
        case .purplePink: return Color(hex: "#E3A2FF")
        case .forestGreen: return Color(hex: "#33CB7D")
        }
    }

    var secondary: Color {
        switch self {
        case .purplePink: return Color(hex: "#F6BDE9")
        case .forestGreen: return Color(hex: "#7BDFAB")
        }
    }

    var tertiary: Color {
        switch self {
        case .purplePink: return Color(hex: "#D6C3FF")
        case .forestGreen: return Color(hex: "#9ADDFD")
        }
    }

    var deepBackground: Color {
        switch self {
        case .purplePink: return Color(hex: "#291A36")
        case .forestGreen: return Color(hex: "#08110E")
        }
    }

    var lightBackground: Color {
        switch self {
        case .purplePink: return Color(hex: "#FFF9FE")
        case .forestGreen: return Color(hex: "#F3FAF5")
        }
    }

    var gradient: LinearGradient {
        switch self {
        case .purplePink:
            return LinearGradient(
                colors: [Color(hex: "#E4A5FF"), Color(hex: "#F8C1EA"), Color(hex: "#90E8BC")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .forestGreen:
            return LinearGradient(
                colors: [Color(hex: "#0B4A34"), Color(hex: "#1C9262"), Color(hex: "#0B2D25")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct DesignRoleDecision: Identifiable {
    let id = UUID()
    let role: String
    let decision: String
}

struct DesignSystemContainerView: View {
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("design_lab_style_preset") private var stylePresetRaw = LabStylePreset.purplePink.rawValue

    @State private var email = ""
    @State private var showSheetDemo = false
    @State private var runTypewriterToken = UUID()

    private var preset: LabStylePreset {
        get { LabStylePreset(rawValue: stylePresetRaw) ?? .purplePink }
        nonmutating set { stylePresetRaw = newValue.rawValue }
    }

    private var roleDecisions: [DesignRoleDecision] {
        [
            DesignRoleDecision(role: "角色A · 顶级前端设计师", decision: "建立可维护 token 与组件规范，避免页面硬编码"),
            DesignRoleDecision(role: "角色B · 顶级时尚设计师", decision: "保留品牌情绪锚点：渐变、人格化图标、高识别CTA"),
            DesignRoleDecision(role: "角色C · 前端设计师", decision: "把借鉴点拆到按钮/输入/卡片/图表/动效节奏"),
            DesignRoleDecision(role: "角色D · 前端代码工程师", decision: "保证 SwiftUI 可复刻、可测试、可集成到容器")
        ]
    }

    var body: some View {
        ZStack {
            preset.gradient
                .opacity(colorScheme == .dark ? 0.35 : 0.22)
                .blur(radius: 40)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    containerHeader
                    roleAlignmentSection
                    brandToneSection
                    typographySection
                    buttonInputCardSection
                    typewriterSection
                    outsidersChartSection
                    interactionSection
                }
                .liquidGlassPageWidth()
                .padding(.top, metrics.verticalPadding)
                .padding(.bottom, metrics.bottomContentInset)
            }
        }
        .navigationTitle("设计系统容器")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSheetDemo) {
            DesignBottomSheetDemoView(preset: preset)
                .presentationDetents([.height(280), .height(420), .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var containerHeader: some View {
        LiquidGlassCard(style: .elevated, padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("UI 定型容器")
                    .font(GlassTypography.display(28, weight: .bold))
                    .foregroundColor(.textPrimary)
                Text("规范先行，再做复刻。先把底座稳定，再把视觉拉满。")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                Text("当前容器包含：色调对比、排版标尺、核心组件、Lovi逐字问句、Outsiders图表。")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var roleAlignmentSection: some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                LiquidGlassSectionHeader(title: "四角色协同结论", icon: "person.3.sequence.fill")
                ForEach(roleDecisions) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.role)
                            .font(.caption.bold())
                            .foregroundColor(.textPrimary)
                        Text(item.decision)
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var brandToneSection: some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                LiquidGlassSectionHeader(title: "品牌色调 A/B", icon: "paintpalette.fill")

                HStack(spacing: 8) {
                    ForEach(LabStylePreset.allCases) { style in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            preset = style
                            runTypewriterToken = UUID()
                        } label: {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(style.gradient)
                                    .frame(height: 56)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(style == preset ? Color.white.opacity(0.8) : Color.white.opacity(0.2), lineWidth: style == preset ? 2 : 1)
                                    )
                                Text(style.title)
                                    .font(.caption.bold())
                                    .foregroundColor(.textPrimary)
                                Text(style.subtitle)
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    colorChip("主色", color: preset.primary)
                    colorChip("强调", color: preset.secondary)
                    colorChip("辅助", color: preset.tertiary)
                }
            }
        }
    }

    private var typographySection: some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                LiquidGlassSectionHeader(title: "排版标尺", icon: "textformat.size")
                Text("Lovi 风格中文推荐：PingFang SC（系统内置）")
                    .font(GlassTypography.cnLovi(13, weight: .medium))
                    .foregroundColor(.textTertiary)
                Text("Display 34 · New York/SF Serif")
                    .font(.system(size: 34, weight: .semibold, design: .serif))
                    .foregroundColor(.textPrimary)
                Text("Lovi CN 28 · PingFangSC-Semibold")
                    .font(GlassTypography.cnLovi(28, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Title 22 · Semibold")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Text("Body 17 · Regular。用于主要说明文本。")
                    .font(.system(size: 17))
                    .foregroundColor(.textSecondary)
                Text("Caption 13 · Medium。用于辅助标签和状态。")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private var buttonInputCardSection: some View {
        LiquidGlassCard(style: .elevated, padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                LiquidGlassSectionHeader(title: "核心组件规范样机", icon: "square.grid.2x2.fill")

                HStack(spacing: 10) {
                    Button("Primary CTA") {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    .buttonStyle(LabGlowButtonStyle(preset: preset, kind: .primary))

                    Button("Secondary") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    .buttonStyle(LabGlowButtonStyle(preset: preset, kind: .secondary))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("输入样式（44高 + 16圆角 + 语义边框）")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                    HStack(spacing: 8) {
                        Image(systemName: "envelope")
                            .foregroundColor(.textTertiary)
                        TextField("请输入邮箱", text: $email)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.surfaceGlass(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(email.isEmpty ? Color.white.opacity(0.16) : preset.primary.opacity(0.65), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("卡片样式（16圆角 / 16内边距）")
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Smart Savings")
                                .font(.subheadline.bold())
                                .foregroundColor(.textPrimary)
                            Text("Reliable performance, everyday affordability.")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.textTertiary)
                    }
                    .padding(14)
                    .background(Color.surfaceGlass(for: colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(preset.secondary.opacity(0.45), lineWidth: 1)
                    )
                }
            }
        }
    }

    private var typewriterSection: some View {
        LoviTypewriterQuestionLabView(
            preset: preset,
            replayToken: runTypewriterToken
        )
    }

    private var outsidersChartSection: some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                LiquidGlassSectionHeader(title: "Outsiders 图表形态复刻", icon: "chart.xyaxis.line")
                OutsidersChartLabView(preset: preset)
            }
        }
    }

    private var interactionSection: some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                LiquidGlassSectionHeader(title: "交互容器", icon: "sparkles")
                Text("包含：Tab 点击反馈 + 底部弹窗尺寸规范（280/420/Large）")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                TabMicroInteractionLabView(preset: preset)

                Button("弹出窗口尺寸样机") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showSheetDemo = true
                }
                .buttonStyle(LabGlowButtonStyle(preset: preset, kind: .primary))
            }
        }
    }

    private func colorChip(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 14, height: 14)
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(Capsule())
    }
}

private struct LabGlowButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }

    let preset: LabStylePreset
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        let isPrimary = kind == .primary
        return configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(isPrimary ? .white : .textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isPrimary
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [preset.primary, preset.tertiary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            : AnyShapeStyle(Color.surfaceGlass(for: .dark))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.35) : Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: isPrimary ? preset.primary.opacity(0.45) : .clear, radius: isPrimary ? 10 : 0, y: isPrimary ? 3 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct LoviTypewriterQuestionLabView: View {
    let preset: LabStylePreset
    let replayToken: UUID
    @Environment(\.colorScheme) private var colorScheme

    @State private var renderedQuestion = ""
    @State private var task: Task<Void, Never>?

    private let fullQuestion = "How much do you typically spend on a skincare item like a moisturizer?"

    var body: some View {
        LiquidGlassCard(style: .elevated, padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                LiquidGlassSectionHeader(title: "Lovi 逐字问句复刻", icon: "character.cursor.ibeam")
                Text("每 45-65ms 出现一个字符，每 2-3 个字符给一次轻震反馈。")
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text(renderedQuestion)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.textPrimary)
                        .minimumScaleFactor(0.8)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Choose your budget for everyday skincare products. Note: Prices for advanced treatments may vary.")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
                .padding(14)
                .background(Color.surfaceGlass(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(spacing: 8) {
                    optionRow(title: "Smart Savings ($19 and less)", subtitle: "Reliable performance, everyday affordability.", icon: "lightbulb.max")
                    optionRow(title: "Balanced Value ($20...$49)", subtitle: "Great balance of efficacy and cost.", icon: "scalemass")
                    optionRow(title: "Professional & Innovative ($50...$99)", subtitle: "Advanced technology and ingredients.", icon: "diamond")
                }

                Button("重播逐字动效") {
                    runTypewriter()
                }
                .buttonStyle(LabGlowButtonStyle(preset: preset, kind: .secondary))
            }
        }
        .onAppear { runTypewriter() }
        .onChange(of: replayToken) { _, _ in runTypewriter() }
        .onDisappear { task?.cancel() }
    }

    private func optionRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(preset.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.surfaceGlass(for: colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(preset.secondary.opacity(0.35), lineWidth: 1)
        )
    }

    private func runTypewriter() {
        task?.cancel()
        renderedQuestion = ""

        task = Task {
            for (index, scalar) in fullQuestion.enumerated() {
                if Task.isCancelled { return }
                await MainActor.run {
                    renderedQuestion.append(scalar)
                    if index.isMultiple(of: 3) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
                    }
                }
                try? await Task.sleep(nanoseconds: 55_000_000)
            }
        }
    }
}

private struct OutsidersChartLabView: View {
    let preset: LabStylePreset
    @State private var selectedIndex = 5

    private let values: [Double] = [0.8, 1.2, 1.0, 2.4, 2.1, 3.2, 2.6]
    private let days = ["周一", "周二", "周三", "周四", "周五", "今天", "周日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let chartSize = proxy.size
                let maxValue = max(values.max() ?? 1, 1)
                let stepX = chartSize.width / CGFloat(max(values.count - 1, 1))
                let selectedX = CGFloat(selectedIndex) * stepX
                let selectedY = yPosition(value: values[selectedIndex], maxValue: maxValue, height: chartSize.height)

                ZStack {
                    ForEach(0..<5, id: \.self) { line in
                        let y = CGFloat(line) / 4 * chartSize.height
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: chartSize.width, y: y))
                        }
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    }

                    Path { p in
                        for (idx, value) in values.enumerated() {
                            let x = CGFloat(idx) * stepX
                            let y = yPosition(value: value, maxValue: maxValue, height: chartSize.height)
                            if idx == 0 {
                                p.move(to: CGPoint(x: x, y: y))
                            } else {
                                p.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(preset.tertiary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                    Path { p in
                        p.move(to: CGPoint(x: selectedX, y: selectedY))
                        p.addLine(to: CGPoint(x: selectedX, y: chartSize.height))
                    }
                    .stroke(Color.white.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    Circle()
                        .fill(preset.primary)
                        .frame(width: 9, height: 9)
                        .position(x: selectedX, y: selectedY)
                        .shadow(color: preset.primary.opacity(0.45), radius: 6)
                }
            }
            .frame(height: 180)
            .padding(12)
            .background(preset.deepBackground.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            HStack {
                ForEach(days.indices, id: \.self) { idx in
                    Button(days[idx]) {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedIndex = idx
                        }
                    }
                    .font(.caption2.weight(selectedIndex == idx ? .bold : .medium))
                    .foregroundColor(selectedIndex == idx ? .textPrimary : .textTertiary)
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 10) {
                metricCard(title: "训练负荷", value: String(format: "%.1f", values[selectedIndex]), color: preset.primary)
                metricCard(title: "时长", value: "\(Int(values[selectedIndex] * 15)) 分钟", color: preset.secondary)
            }
        }
    }

    private func yPosition(value: Double, maxValue: Double, height: CGFloat) -> CGFloat {
        guard maxValue > 0 else { return height }
        return height - CGFloat(value / maxValue) * height
    }

    private func metricCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.textTertiary)
            Text(value)
                .font(.headline)
                .foregroundColor(.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceGlass(for: .dark))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct TabMicroInteractionLabView: View {
    let preset: LabStylePreset
    @State private var selected = 0

    private let items: [(String, String)] = [
        ("今日", "calendar"),
        ("进度", "chart.line.uptrend.xyaxis"),
        ("训练", "figure.run"),
        ("洞察", "sparkles")
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { idx in
                let item = items[idx]
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                        selected = idx
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.1)
                            .font(.system(size: 14, weight: .semibold))
                        Text(item.0)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(selected == idx ? .white : .textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(selected == idx ? preset.secondary : Color.clear)
                    )
                    .scaleEffect(selected == idx ? 1.02 : 1.0)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Color.surfaceGlass(for: .dark))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DesignBottomSheetDemoView: View {
    let preset: LabStylePreset
    @State private var intensity = 0.62

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("弹窗尺寸规范")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("推荐 Detents：280 / 420 / Large。用于提醒卡、支付卡、解释卡。")
                .font(.caption)
                .foregroundColor(.textSecondary)

            HStack {
                Circle().fill(preset.primary).frame(width: 12, height: 12)
                Text("主强调色强度")
                    .font(.caption)
                    .foregroundColor(.textTertiary)
            }

            Slider(value: $intensity, in: 0.2...1)
                .tint(preset.primary)

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(preset.gradient.opacity(intensity))
                .frame(height: 120)
                .overlay(
                    Text("Bottom Sheet Surface")
                        .font(.headline)
                        .foregroundColor(.textOnAccent)
                )
        }
        .padding(20)
    }
}

private struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("本次视觉更新")
                        .font(GlassTypography.cnLovi(22, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .liquidGlassCircleBadge(padding: 10)
                    }
                    .buttonStyle(.plain)
                }

                bullet("启动页改为 Lovi 风格的淡紫流体质感。")
                bullet("按钮、输入、开关统一到 Light Lilac Glass 语义。")
                bullet("新增底部弹层：今日洞察、解释方法、版本更新。")

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func bullet(_ text: String) -> some View {
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

private struct SettingsGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("设置页说明")
                        .font(GlassTypography.cnLovi(22, weight: .semibold))
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.textSecondary)
                            .liquidGlassCircleBadge(padding: 10)
                    }
                    .buttonStyle(.plain)
                }

                guideRow("先连 HealthKit，再开提醒。建议质量提升最快。")
                guideRow("外观和语言会即时生效，便于你快速预览新 UI。")
                guideRow("隐私与登录操作都放在同页底部，减少跳转成本。")

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private func guideRow(_ text: String) -> some View {
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
