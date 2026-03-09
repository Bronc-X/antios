// OnboardingView.swift
// 新手引导视图 - Liquid Glass 风格

import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @Binding var isComplete: Bool
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appSettings: AppSettings
    @State private var showStepGuide = false
    
    var body: some View {
        ZStack {
            AuroraBackground()
            
            VStack(spacing: 0) {
                // 进度指示器
                progressIndicator
                    .padding(.top, metrics.safeAreaInsets.top + (metrics.isCompactHeight ? 8 : 20))
                
                // 步骤内容
                TabView(selection: $viewModel.currentStep) {
                    welcomeStep.tag(1)
                    basicInfoStep.tag(2)
                    goalsStep.tag(3)
                    lifestyleStep.tag(4)
                    preferencesStep.tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: viewModel.currentStep)
            }
            
            // 加载指示器
            if viewModel.isLoading || viewModel.isSaving {
                loadingOverlay
            }
        }
        .task {
            await viewModel.loadProgress()
        }
        .onChange(of: viewModel.isComplete) { _, newValue in
            if newValue {
                isComplete = true
            }
        }
        .onChange(of: viewModel.currentStep) { _, _ in
            let feedback = UISelectionFeedbackGenerator()
            feedback.selectionChanged()
        }
        .sheet(isPresented: $showStepGuide) {
            OnboardingStepGuideSheet(step: viewModel.currentStep)
                .presentationDetents([.fraction(0.42), .large])
                .liquidGlassSheetChrome(cornerRadius: 28)
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        LiquidGlassCard(style: .standard, padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Onboarding")
                        .font(GlassTypography.caption(12, weight: .semibold))
                        .foregroundColor(.liquidGlassAccent)
                    Spacer()
                    Text("0\(viewModel.currentStep) / 05")
                        .font(GlassTypography.caption(12, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { step in
                        Capsule()
                            .fill(
                                step <= viewModel.currentStep
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: [Color(hex: "#7C93FF"), Color(hex: "#C8AAFF")],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    : AnyShapeStyle(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24))
                            )
                            .frame(height: step == viewModel.currentStep ? 6 : 4)
                            .animation(.spring(response: 0.3), value: viewModel.currentStep)
                    }
                }
            }
        }
        .liquidGlassPageWidth()
    }
    
    // MARK: - Step 1: Welcome
    
    private var welcomeStep: some View {
        let ringSize: CGFloat = metrics.isCompactHeight ? 150 : 180
        let iconSize: CGFloat = metrics.isCompactWidth ? 60 : 70
        return VStack(spacing: 32) {
            Spacer()
            
            LiquidGlassCard(style: .elevated, padding: 24) {
                VStack(spacing: 20) {
                    ZStack {
                        PulsingRingsView(color: .liquidGlassAccent)
                            .frame(width: ringSize, height: ringSize)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: iconSize))
                            .foregroundColor(.liquidGlassAccent)
                    }
                    
                    VStack(spacing: 16) {
                        Text("欢迎来到 AntiAnxiety")
                            .font(GlassTypography.cnLovi(30, weight: .semibold))
                            .foregroundColor(.bioTextPrimary(for: colorScheme))
                        
                        Text("你的反焦虑跟进助手\n主动问询、每日校准、科学解释、行动跟进")
                            .font(GlassTypography.cnLovi(16, weight: .regular))
                            .foregroundColor(.bioTextSecondary(for: colorScheme))
                            .multilineTextAlignment(.center)
                    }

                    HStack(spacing: 10) {
                        OnboardingSignalPill(text: "问询", tint: .liquidGlassAccent)
                        OnboardingSignalPill(text: "校准", tint: .liquidGlassWarm)
                        OnboardingSignalPill(text: "行动", tint: .statusSuccess)
                    }
                }
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    viewModel.nextStep()
                } label: {
                    Text("开始设置")
                }
                .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                
                Button {
                    Task {
                        if await viewModel.skip() {
                            isComplete = true
                        }
                    }
                } label: {
                    Text("跳过")
                        .font(GlassTypography.cnLovi(15, weight: .regular))
                        .foregroundColor(.bioTextSecondary(for: colorScheme))
                }
            }
            .padding(.bottom, metrics.isCompactHeight ? 24 : 40)
        }
        .liquidGlassPageWidth(alignment: .center)
    }
    
    // MARK: - Step 2: Basic Info
    
    private var basicInfoStep: some View {
        VStack(spacing: 24) {
            stepHeader(
                title: "基本信息",
                subtitle: "用于初始化你的反焦虑画像"
            )
            
            ScrollView {
                VStack(spacing: 20) {
                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(spacing: 16) {
                            LiquidGlassTextField(
                                placeholder: "你的名字",
                                text: Binding(
                                    get: { viewModel.onboardingData.name ?? "" },
                                    set: { viewModel.onboardingData.name = $0 }
                                ),
                                icon: "person.fill"
                            )
                            
                            // 年龄选择
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.liquidGlassAccent.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "calendar")
                                        .font(.system(size: 14))
                                        .foregroundColor(.liquidGlassAccent)
                                }
                                
                                Text("年龄")
                                    .font(GlassTypography.cnLovi(16, weight: .medium))
                                    .foregroundColor(.bioTextPrimary(for: colorScheme))
                                
                                Spacer()
                                
                                Picker("年龄", selection: Binding(
                                    get: { viewModel.onboardingData.age ?? 25 },
                                    set: { viewModel.onboardingData.age = $0 }
                                )) {
                                    ForEach(18...80, id: \.self) { age in
                                        Text("\(age) 岁").tag(age)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(.liquidGlassAccent)
                            }
                        }
                    }
                    
                    // 性别选择
                    VStack(alignment: .leading, spacing: 12) {
                        LiquidGlassSectionHeader(title: "性别", icon: "person.2.fill")
                        
                        LiquidGlassCard(style: .standard, padding: 16) {
                            HStack(spacing: 12) {
                                genderButton("male", label: "男", icon: "figure.stand")
                                genderButton("female", label: "女", icon: "figure.stand.dress")
                                genderButton("other", label: "其他", icon: "figure.wave")
                            }
                        }
                    }
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
            
            navigationButtons()
        }
    }
    
    private func genderButton(_ value: String, label: String, icon: String) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            viewModel.onboardingData.gender = value
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(GlassTypography.cnLovi(13, weight: .medium))
            }
            .foregroundColor(viewModel.onboardingData.gender == value ? .bgPrimary : .bioTextSecondary(for: colorScheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
                .background(
                    viewModel.onboardingData.gender == value
                        ? Color.liquidGlassAccent
                        : Color.surfaceGlass(for: colorScheme)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
    
    // MARK: - Step 3: Goals
    
    private var goalsStep: some View {
        VStack(spacing: 24) {
            stepHeader(
                title: "反焦虑优先目标",
                subtitle: "这一项会决定 Max 的问询与行动方向"
            )
            
            ScrollView {
                VStack(spacing: 16) {
                    goalOption("anxiety", label: "缓解焦虑", icon: "brain.head.profile", color: .liquidGlassPurple)
                    goalOption("sleep", label: "改善睡眠", icon: "moon.zzz.fill", color: .liquidGlassAccent)
                    goalOption("stress", label: "压力管理", icon: "waveform.path.ecg", color: .statusWarning)
                    goalOption("mood", label: "情绪调节", icon: "heart.fill", color: .statusError)
                    goalOption("focus", label: "提升专注", icon: "scope", color: .statusSuccess)
                    goalOption("general", label: "降低过度担忧", icon: "figure.mind.and.body", color: .liquidGlassWarm)
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
            
            navigationButtons()
        }
    }
    
    private func goalOption(_ value: String, label: String, icon: String, color: Color) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            viewModel.onboardingData.primaryGoal = value
        } label: {
            LiquidGlassCard(style: viewModel.onboardingData.primaryGoal == value ? .elevated : .standard, padding: 16) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .foregroundColor(color)
                    }
                    
                    Text(label)
                        .font(GlassTypography.cnLovi(18, weight: .semibold))
                        .foregroundColor(.bioTextPrimary(for: colorScheme))
                    
                    Spacer()
                    
                    if viewModel.onboardingData.primaryGoal == value {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.statusSuccess)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Step 4: Lifestyle
    
    private var lifestyleStep: some View {
        VStack(spacing: 24) {
            stepHeader(
                title: "日常与触发因素",
                subtitle: "用于每日校准与机制解释"
            )
            
            ScrollView {
                VStack(spacing: 20) {
                    // 睡眠时间
                    VStack(alignment: .leading, spacing: 12) {
                        LiquidGlassSectionHeader(title: "最近平均睡眠时长", icon: "moon.zzz.fill")
                        
                        LiquidGlassCard(style: .standard, padding: 16) {
                            VStack(spacing: 12) {
                                Text(String(format: "%.1f 小时", viewModel.onboardingData.sleepHours ?? 7))
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(.liquidGlassAccent)
                                
                                Slider(
                                    value: Binding(
                                        get: { viewModel.onboardingData.sleepHours ?? 7 },
                                        set: { viewModel.onboardingData.sleepHours = $0 }
                                    ),
                                    in: 4...12,
                                    step: 0.5
                                )
                                .tint(.liquidGlassAccent)
                            }
                        }
                    }
                    
                    // 运动频率
                    VStack(alignment: .leading, spacing: 12) {
                        LiquidGlassSectionHeader(title: "身体激活频率", icon: "figure.run")
                        
                        LiquidGlassCard(style: .standard, padding: 16) {
                            HStack(spacing: 8) {
                                exerciseButton("rarely", label: "很少")
                                exerciseButton("sometimes", label: "偶尔")
                                exerciseButton("regular", label: "经常")
                            }
                        }
                    }
                    
                    // 压力水平
                    VStack(alignment: .leading, spacing: 12) {
                        LiquidGlassSectionHeader(title: "当前焦虑紧张度", icon: "gauge.high")
                        
                        LiquidGlassCard(style: .standard, padding: 16) {
                            VStack(spacing: 12) {
                                Text("\(viewModel.onboardingData.stressLevel ?? 5)")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(stressColor)
                                
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.onboardingData.stressLevel ?? 5) },
                                        set: { viewModel.onboardingData.stressLevel = Int($0) }
                                    ),
                                    in: 1...10,
                                    step: 1
                                )
                                .tint(stressColor)
                                
                                HStack {
                                    Text("较平稳")
                                        .font(.caption2)
                                        .foregroundColor(.bioTextSecondary(for: colorScheme).opacity(0.6))
                                    Spacer()
                                    Text("高度紧张")
                                        .font(.caption2)
                                        .foregroundColor(.bioTextSecondary(for: colorScheme).opacity(0.6))
                                }
                            }
                        }
                    }
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
            
            navigationButtons()
        }
    }
    
    private var stressColor: Color {
        let level = viewModel.onboardingData.stressLevel ?? 5
        if level <= 3 { return .statusSuccess }
        if level <= 6 { return .statusWarning }
        return .statusError
    }
    
    private func exerciseButton(_ value: String, label: String) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            viewModel.onboardingData.exerciseFrequency = value
        } label: {
            Text(label)
                .font(GlassTypography.cnLovi(16, weight: .semibold))
                .foregroundColor(viewModel.onboardingData.exerciseFrequency == value ? .bgPrimary : .bioTextSecondary(for: colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    viewModel.onboardingData.exerciseFrequency == value
                        ? Color.liquidGlassAccent
                        : Color.surfaceGlass(for: colorScheme)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    // MARK: - Step 5: Preferences
    
    private var preferencesStep: some View {
        VStack(spacing: 24) {
            stepHeader(
                title: "偏好设置",
                subtitle: "最后一步，设定你的提醒节奏"
            )
            
            ScrollView {
                VStack(spacing: 20) {
                    // 通知设置
                    LiquidGlassCard(style: .standard, padding: 16) {
                        Toggle(isOn: Binding(
                            get: { viewModel.onboardingData.notificationEnabled ?? true },
                            set: { viewModel.onboardingData.notificationEnabled = $0 }
                        )) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.statusSuccess.opacity(0.15))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.statusSuccess)
                                }
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("启用跟进提醒")
                                        .font(GlassTypography.cnLovi(16, weight: .medium))
                                        .foregroundColor(.bioTextPrimary(for: colorScheme))
                                    Text("接收每日校准与跟进提醒")
                                        .font(GlassTypography.cnLovi(13, weight: .regular))
                                        .foregroundColor(.bioTextSecondary(for: colorScheme))
                                }
                            }
                        }
                        .toggleStyle(LiquidGlassToggleStyle())
                    }
                    
                    // 语言选择
                    VStack(alignment: .leading, spacing: 12) {
                        LiquidGlassSectionHeader(title: "语言", icon: "globe")
                        
                        LiquidGlassCard(style: .standard, padding: 16) {
                            HStack(spacing: 12) {
                                languageButton(AppLanguage.zhHans.rawValue, label: AppLanguage.zhHans.displayName)
                                languageButton(AppLanguage.zhHant.rawValue, label: AppLanguage.zhHant.displayName)
                                languageButton(AppLanguage.en.rawValue, label: AppLanguage.en.displayName)
                            }
                        }
                    }
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
            
            // 完成按钮
            VStack(spacing: 16) {
                Button {
                    print("[Onboarding] 开始使用按钮被点击")
                    
                    // 触觉反馈
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    
                    // 保存数据到本地
                    let selectedLanguage = AppLanguage.fromStored(viewModel.onboardingData.language)
                    appSettings.language = selectedLanguage

                    let data: [String: String] = [
                        "notification_enabled": String(viewModel.onboardingData.notificationEnabled ?? true),
                        "language": selectedLanguage.apiCode
                    ]
                    
                    // 直接标记 Onboarding 完成
                    UserDefaults.standard.set(true, forKey: "isOnboardingComplete")
                    // isOnboardingComplete = true // Removed invalid line
                    isComplete = true
                    
                    print("[Onboarding] 已完成 Onboarding")
                    
                    // 后台异步同步到服务器
                    Task {
                        _ = await viewModel.saveStep(data)
                    }
                } label: {
                    Text("开始使用")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                
                Button {
                    viewModel.prevStep()
                } label: {
                    Text("上一步")
                        .font(GlassTypography.cnLovi(15, weight: .regular))
                        .foregroundColor(.bioTextSecondary(for: colorScheme))
                }
            }
            .liquidGlassPageWidth(alignment: .center)
            .padding(.bottom, metrics.isCompactHeight ? 24 : 40)
        }
    }
    
    private func languageButton(_ value: String, label: String) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            viewModel.onboardingData.language = value
            appSettings.language = AppLanguage.fromStored(value)
        } label: {
            Text(label)
                .font(GlassTypography.cnLovi(16, weight: .semibold))
                .foregroundColor(viewModel.onboardingData.language == value ? .bgPrimary : .bioTextSecondary(for: colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    viewModel.onboardingData.language == value
                        ? Color.liquidGlassAccent
                        : Color.surfaceGlass(for: colorScheme)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    // MARK: - Helpers
    
    private func stepHeader(title: String, subtitle: String) -> some View {
        LiquidGlassCard(style: .standard, padding: 16) {
            VStack(spacing: 10) {
                HStack(alignment: .top) {
                    TypewriterHeadlineText(
                        text: title,
                        trigger: viewModel.currentStep,
                        font: GlassTypography.cnLovi(28, weight: .semibold),
                        color: .bioTextPrimary(for: colorScheme)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .soft)
                        impact.impactOccurred()
                        showStepGuide = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.liquidGlassAccent)
                            .liquidGlassCircleBadge(padding: 8)
                    }
                    .buttonStyle(.plain)
                }

                Text(subtitle)
                    .font(GlassTypography.cnLovi(15, weight: .regular))
                    .foregroundColor(.bioTextSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, metrics.isCompactHeight ? 16 : 32)
        .liquidGlassPageWidth()
    }
    
    private func navigationButtons() -> some View {
        HStack(spacing: 16) {
            if viewModel.currentStep > 1 {
                Button {
                    viewModel.prevStep()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(.bioTextSecondary(for: colorScheme))
                        .frame(width: 50, height: 50)
                        .background(Color.surfaceGlass(for: colorScheme))
                        .clipShape(Circle())
                }
            }
            
            Spacer()
            
            Button {
                print("[Onboarding] 继续按钮被点击，当前步骤: \(viewModel.currentStep)")
                
                // 触觉反馈
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                
                // 同步保存数据到本地
                let data = collectStepData()
                saveDataLocally(data)
                
                // 直接前进到下一步
                withAnimation(.easeInOut(duration: 0.3)) {
                    viewModel.nextStep()
                }
                
                print("[Onboarding] 已前进到步骤: \(viewModel.currentStep)")
                
                // 后台异步同步到服务器
                Task {
                    _ = await viewModel.saveStep(data)
                }
            } label: {
                HStack(spacing: 8) {
                    Text("继续")
                    Image(systemName: "chevron.right")
                }
            }
            .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
        }
        .liquidGlassPageWidth()
        .padding(.bottom, metrics.isCompactHeight ? 24 : 40)
    }
    
    private func collectStepData() -> [String: String] {
        var data: [String: String] = [:]
        
        switch viewModel.currentStep {
        case 2:
            if let name = viewModel.onboardingData.name { data["name"] = name }
            if let age = viewModel.onboardingData.age { data["age"] = String(age) }
            if let gender = viewModel.onboardingData.gender { data["gender"] = gender }
        case 3:
            if let goal = viewModel.onboardingData.primaryGoal { data["primary_goal"] = goal }
        case 4:
            if let sleep = viewModel.onboardingData.sleepHours { data["sleep_hours"] = String(sleep) }
            if let exercise = viewModel.onboardingData.exerciseFrequency { data["exercise_frequency"] = exercise }
            if let stress = viewModel.onboardingData.stressLevel { data["stress_level"] = String(stress) }
        default:
            break
        }
        
        return data
    }
    
    private func saveDataLocally(_ data: [String: String]) {
        // 将数据保存到 viewModel 的 onboardingData
        switch viewModel.currentStep {
        case 2:
            if let name = data["name"] { viewModel.onboardingData.name = name }
            if let ageStr = data["age"], let age = Int(ageStr) { viewModel.onboardingData.age = age }
            if let gender = data["gender"] { viewModel.onboardingData.gender = gender }
        case 3:
            if let goal = data["primary_goal"] { viewModel.onboardingData.primaryGoal = goal }
        case 4:
            if let sleepStr = data["sleep_hours"], let sleep = Double(sleepStr) { viewModel.onboardingData.sleepHours = sleep }
            if let exercise = data["exercise_frequency"] { viewModel.onboardingData.exerciseFrequency = exercise }
            if let stressStr = data["stress_level"], let stress = Int(stressStr) { viewModel.onboardingData.stressLevel = stress }
        default:
            break
        }
        
        // 持久化到 UserDefaults
        if let encoded = try? JSONEncoder().encode(viewModel.onboardingData) {
            UserDefaults.standard.set(encoded, forKey: "onboarding_data")
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            LiquidGlassCard(style: .elevated, padding: 24) {
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.liquidGlassAccent)
                    Text("正在保存你的恢复偏好…")
                        .font(GlassTypography.cnLovi(14, weight: .medium))
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(.horizontal, 28)
        }
    }
}

private struct OnboardingSignalPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(GlassTypography.caption(11, weight: .semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .overlay(
                Capsule()
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}

private struct TypewriterHeadlineText: View {
    let text: String
    let trigger: Int
    let font: Font
    let color: Color

    @State private var renderedText = ""

    var body: some View {
        Text(renderedText.isEmpty ? " " : renderedText)
            .font(font)
            .foregroundColor(color)
            .multilineTextAlignment(.center)
            .task(id: "\(trigger)-\(text)") {
                await animateText()
            }
    }

    @MainActor
    private func animateText() async {
        renderedText = ""
        let haptic = UISelectionFeedbackGenerator()
        haptic.prepare()
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            renderedText.append(character)
            if index % 2 == 0 {
                haptic.selectionChanged()
                haptic.prepare()
            }
            try? await Task.sleep(nanoseconds: 22_000_000)
        }
    }
}

private struct OnboardingStepGuideSheet: View {
    let step: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var title: String {
        switch step {
        case 1: return "欢迎页说明"
        case 2: return "基本信息说明"
        case 3: return "目标说明"
        case 4: return "生活节律说明"
        case 5: return "偏好设置说明"
        default: return "步骤说明"
        }
    }

    private var bullets: [String] {
        switch step {
        case 1:
            return [
                "你可以先快速进入，后续随时在设置里补全信息。",
                "引导流程默认走低负担路径，不会要求一次填完。"
            ]
        case 2:
            return [
                "名字、年龄、性别用于初始化你的个体画像。",
                "这些信息会影响后续问询文案与建议颗粒度。"
            ]
        case 3:
            return [
                "优先目标决定 Max 今天更关注什么。",
                "目标后续可改，先选你最在意的一项即可。"
            ]
        case 4:
            return [
                "睡眠、激活频率、紧张度决定每日校准节奏。",
                "系统会根据你的输入动态调整建议强度。"
            ]
        case 5:
            return [
                "提醒决定触达频率，建议先开启再微调。",
                "语言切换会实时生效，不影响历史数据。"
            ]
        default:
            return ["继续完成当前步骤即可。"]
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
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

                ForEach(bullets, id: \.self) { text in
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

                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }
}

// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isComplete: .constant(false))
            .preferredColorScheme(.dark)
    }
}
