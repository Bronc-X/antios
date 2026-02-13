// ProfileView.swift
// 个人资料视图 - Liquid Glass 风格

import SwiftUI

struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showEditSheet = false
    @State private var showAvatarPicker = false
    @State private var showAIPersonalityEditor = false
    @State private var showAIPersonaContextEditor = false
    @Environment(\.screenMetrics) private var metrics
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 深渊背景
                AbyssBackground()
                
                ScrollView {
                    VStack(spacing: metrics.sectionSpacing) {
                        // ==========================================
                        // 用户头像和基本信息
                        // ==========================================
                        profileHeaderCard
                        
                        // ==========================================
                        // 统计数据
                        // ==========================================
                        statsSection
                        
                        // ==========================================
                        // AI 个性化设置
                        // ==========================================
                        aiPersonalizationSection
                        
                        // ==========================================
                        // 偏好设置
                        // ==========================================
                        preferencesSection
                    }
                    .liquidGlassPageWidth()
                    .padding(.vertical, metrics.verticalPadding)
                }
                
                if viewModel.isLoading && viewModel.profile == nil {
                    ProgressView()
                        .scaleEffect(1.2)
                        .progressViewStyle(CircularProgressViewStyle(tint: .liquidGlassAccent))
                }
            }
            .navigationTitle("个人资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showEditSheet = true
                    } label: {
                        Text("编辑")
                            .font(.subheadline)
                            .foregroundColor(.liquidGlassAccent)
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                EditProfileSheet(
                    profile: viewModel.profile,
                    onSave: { input in
                        Task { await viewModel.update(input) }
                    }
                )
            }
            .sheet(isPresented: $showAvatarPicker) {
                ImagePickerView { image in
                    if let data = image.jpegData(compressionQuality: 0.8) {
                        Task {
                            if let url = await viewModel.uploadAvatar(imageData: data) {
                                _ = await viewModel.update(UpdateProfileInput(avatar_url: url))
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAIPersonalityEditor) {
                AIPersonalitySheet(
                    currentValue: viewModel.profile?.aiPersonality ?? "friendly",
                    onSave: { value in
                        Task { _ = await viewModel.update(UpdateProfileInput(ai_personality: value)) }
                    }
                )
            }
            .sheet(isPresented: $showAIPersonaContextEditor) {
                AIPersonaContextSheet(
                    currentValue: viewModel.profile?.aiPersonaContext ?? "",
                    onSave: { value in
                        Task { _ = await viewModel.update(UpdateProfileInput(ai_persona_context: value)) }
                    }
                )
            }
            .alert(
                "操作失败",
                isPresented: Binding(
                    get: { viewModel.error != nil },
                    set: { _ in viewModel.error = nil }
                )
            ) {
                Button("知道了", role: .cancel) { }
            } message: {
                Text(viewModel.error ?? "")
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .task {
            await viewModel.loadProfile()
        }
    }
    
    // MARK: - 头像和基本信息
    
    private var profileHeaderCard: some View {
        let haloSize = metrics.avatarLarge
        let imageSize = metrics.avatarLarge - (metrics.isCompactWidth ? 16 : 10)
        let fallbackSize: CGFloat = metrics.isCompactWidth ? 64 : 80
        let editOffset: CGFloat = metrics.isCompactWidth ? 28 : 35
        return LiquidGlassCard(style: .elevated, padding: 24) {
            VStack(spacing: 20) {
                // 头像
                ZStack {
                    // 光晕效果
                    Circle()
                        .fill(LinearGradient.accentFlow)
                        .frame(width: haloSize, height: haloSize)
                        .blur(radius: 15)
                        .opacity(0.4)
                    
                    // 头像
                    if let avatarUrl = viewModel.profile?.avatarUrl,
                       let url = URL(string: avatarUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: fallbackSize))
                                .foregroundColor(.liquidGlassAccent)
                        }
                        .frame(width: imageSize, height: imageSize)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(LinearGradient.glassBorder, lineWidth: 2)
                        )
                    } else {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: fallbackSize))
                            .foregroundColor(.liquidGlassAccent)
                    }
                    
                    // 编辑按钮
                    Button {
                        showAvatarPicker = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.bgSecondary)
                                .frame(width: 28, height: 28)
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        }
                    }
                    .offset(x: editOffset, y: editOffset)
                }
                
                // 用户名和邮箱
                VStack(spacing: 6) {
                    Text(viewModel.profile?.fullName ?? "探索者")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text(viewModel.profile?.email ?? "未设置邮箱")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                }
                
                // 状态徽章
                HStack(spacing: 12) {
                    if viewModel.profile?.notificationEnabled == true {
                        StatusPill(text: "通知开启", color: .statusSuccess)
                    }
                    
                    if let language = viewModel.profile?.preferredLanguage {
                        StatusPill(text: language == "zh" ? "中文" : "English", color: .liquidGlassAccent)
                    }
                }

                if viewModel.isUploading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.liquidGlassAccent)
                        Text("头像上传中...")
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }
    
    // MARK: - 统计数据
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "闭环进展", icon: "chart.bar.fill")
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(
                    title: "连续打卡",
                    value: "\(viewModel.usageStats.streakDays)",
                    unit: "天",
                    icon: "flame.fill",
                    color: .liquidGlassWarm
                )
                StatCard(
                    title: "校准次数(30天)",
                    value: "\(viewModel.usageStats.calibrationCount30d)",
                    unit: "次",
                    icon: "brain.head.profile",
                    color: .liquidGlassAccent
                )
                StatCard(
                    title: "完成目标",
                    value: "\(viewModel.usageStats.completedGoals)",
                    unit: "项",
                    icon: "target",
                    color: .statusSuccess
                )
                StatCard(
                    title: "AI 对话",
                    value: "\(viewModel.usageStats.conversationCount)",
                    unit: "次",
                    icon: "bubble.left.and.bubble.right.fill",
                    color: .liquidGlassPurple
                )
            }
        }
    }
    
    // MARK: - AI 个性化
    
    private var aiPersonalizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "Max 个性化", icon: "sparkles")
            
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 16) {
                    // AI 性格
                    Button {
                        showAIPersonalityEditor = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.liquidGlassPurple.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "person.wave.2.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.liquidGlassPurple)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI 风格")
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                Text(viewModel.profile?.aiPersonality ?? "默认")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Divider().background(Color.white.opacity(0.05))
                    
                    // 个人背景
                    Button {
                        showAIPersonaContextEditor = true
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.liquidGlassAccent.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.liquidGlassAccent)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("个人背景")
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                Text((viewModel.profile?.aiPersonaContext?.isEmpty == false) ? "已设置，可点击更新" : "未设置，点击补充")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 偏好设置
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LiquidGlassSectionHeader(title: "偏好设置", icon: "gearshape.fill")

            Text("这些信息会直接影响 Max 的问询重点、动作建议和跟进提醒。")
                .font(.caption2)
                .foregroundColor(.textTertiary)
            
            LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 16) {
                    // 反焦虑重点
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.statusSuccess.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "target")
                                .font(.system(size: 14))
                                .foregroundColor(.statusSuccess)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("反焦虑重点")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Text(viewModel.profile?.primaryGoal ?? "未设置")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        
                        Spacer()
                    }
                    
                    Divider().background(Color.white.opacity(0.05))
                    
                    // 当前关注
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.liquidGlassWarm.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "eye.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.liquidGlassWarm)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("当前关注")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Text(viewModel.profile?.currentFocus ?? "未设置")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        
                        Spacer()
                    }

                    Divider().background(Color.white.opacity(0.05))

                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.liquidGlassSecondary.opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: "clock.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.liquidGlassSecondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("每日提醒时间")
                                .font(.subheadline)
                                .foregroundColor(.textPrimary)
                            Text(viewModel.profile?.dailyCheckinTime ?? "未设置")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }

                        Spacer()
                    }
                }
            }

            NavigationLink(destination: ProfileSetupView()) {
                LiquidGlassCard(style: .standard, padding: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.badge.plus")
                            .foregroundColor(.liquidGlassAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("完善资料")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                            Text("更新重点与偏好设置")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color
    
    var body: some View {
        LiquidGlassCard(style: .concave, padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(color)
                    Spacer()
                }
                
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.textTertiary)
                }
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
        }
    }
}

// MARK: - Edit Profile Sheet

struct EditProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    let profile: UserProfileData?
    let onSave: (UpdateProfileInput) -> Void
    
    @State private var fullName: String = ""
    @State private var aiPersonality: String = "friendly"
    @State private var notificationEnabled: Bool = true
    
    let personalityOptions = [
        ("friendly", "友善温暖", "☀️"),
        ("professional", "专业理性", "📊"),
        ("humorous", "幽默风趣", "😄"),
        ("calm", "沉稳平和", "🧘")
    ]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 基本信息
                        VStack(alignment: .leading, spacing: 12) {
                            LiquidGlassSectionHeader(title: "基本信息", icon: "person.fill")
                            
                            LiquidGlassCard(style: .standard, padding: 16) {
                                LiquidGlassTextField(placeholder: "你的名字", text: $fullName, icon: "person.fill")
                            }
                        }
                        
                        // AI 风格
                        VStack(alignment: .leading, spacing: 12) {
                            LiquidGlassSectionHeader(title: "Max 风格", icon: "sparkles")
                            
                            LiquidGlassCard(style: .standard, padding: 16) {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(personalityOptions, id: \.0) { option in
                                        Button {
                                            let impact = UIImpactFeedbackGenerator(style: .light)
                                            impact.impactOccurred()
                                            aiPersonality = option.0
                                        } label: {
                                            VStack(spacing: 6) {
                                                Text(option.2)
                                                    .font(.title2)
                                                Text(option.1)
                                                    .font(.caption)
                                            }
                                            .foregroundColor(aiPersonality == option.0 ? .bgPrimary : .textSecondary)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(
                                                aiPersonality == option.0
                                                    ? Color.liquidGlassAccent
                                                    : Color.white.opacity(0.05)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 通知
                        VStack(alignment: .leading, spacing: 12) {
                            LiquidGlassSectionHeader(title: "通知", icon: "bell.fill")
                            
                            LiquidGlassCard(style: .standard, padding: 16) {
                                Toggle("启用推送通知", isOn: $notificationEnabled)
                                    .toggleStyle(LiquidGlassToggleStyle())
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundColor(.liquidGlassAccent)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        
                        let input = UpdateProfileInput(
                            full_name: fullName.isEmpty ? nil : fullName,
                            ai_personality: aiPersonality,
                            notification_enabled: notificationEnabled
                        )
                        onSave(input)
                        dismiss()
                    }
                    .font(.headline)
                    .foregroundColor(.liquidGlassAccent)
                }
            }
            .toolbarBackground(Color.bgPrimary, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                fullName = profile?.fullName ?? ""
                aiPersonality = profile?.aiPersonality ?? "friendly"
                notificationEnabled = profile?.notificationEnabled ?? true
            }
        }
    }
}

struct AIPersonalitySheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentValue: String
    let onSave: (String) -> Void

    private let options = [
        ("friendly", "友善温暖", "☀️"),
        ("professional", "专业理性", "📊"),
        ("humorous", "幽默风趣", "😄"),
        ("calm", "沉稳平和", "🧘")
    ]

    @State private var selected = "friendly"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("选择 Max 的交流风格")
                        .font(.subheadline)
                        .foregroundColor(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(spacing: 10) {
                            ForEach(options, id: \.0) { option in
                                Button {
                                    selected = option.0
                                } label: {
                                    HStack(spacing: 10) {
                                        Text(option.2)
                                        Text(option.1)
                                            .font(.subheadline)
                                        Spacer()
                                        if selected == option.0 {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.liquidGlassAccent)
                                        }
                                    }
                                    .foregroundColor(.textPrimary)
                                    .padding(.vertical, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("AI 风格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(selected)
                        dismiss()
                    }
                }
            }
            .onAppear {
                selected = currentValue
            }
        }
    }
}

struct AIPersonaContextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentValue: String
    let onSave: (String?) -> Void
    @State private var text = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgPrimary.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    Text("补充你的背景、偏好和限制，Max 会据此优化建议。")
                        .font(.caption)
                        .foregroundColor(.textSecondary)

                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(Color.surfaceGlass(for: .dark))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .foregroundColor(.textPrimary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("个人背景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                }
            }
            .onAppear {
                text = currentValue
            }
        }
    }
}

// MARK: - Profile Setup

struct ProfileSetupView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @Environment(\.screenMetrics) private var metrics
    @EnvironmentObject private var appSettings: AppSettings
    @State private var fullName = ""
    @State private var primaryGoal: ProfileGoal = .sleep
    @State private var currentFocus: ProfileFocus = .stress
    @State private var dailyTime = "08:30"
    @State private var statusMessage: String?

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    header

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("姓名/称呼", text: $fullName)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.surfaceGlass(for: .dark))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .foregroundColor(.textPrimary)

                            Picker("反焦虑重点", selection: $primaryGoal) {
                                ForEach(ProfileGoal.allCases) { goal in
                                    Text(goal.title).tag(goal)
                                }
                            }
                            .pickerStyle(.segmented)

                            Picker("当前关注", selection: $currentFocus) {
                                ForEach(ProfileFocus.allCases) { focus in
                                    Text(focus.title).tag(focus)
                                }
                            }
                            .pickerStyle(.segmented)

                            TextField("每日校准提醒时间", text: $dailyTime)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.surfaceGlass(for: .dark))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .foregroundColor(.textPrimary)
                        }
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Text("保存资料")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption2)
                            .foregroundColor(.statusSuccess)
                    }
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
        }
        .navigationTitle("资料设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadProfile()
            fullName = viewModel.profile?.fullName ?? ""
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("完善你的个人资料")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("此信息用于生成更准确的建议")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() async {
        let input = UpdateProfileInput(
            full_name: fullName.isEmpty ? nil : fullName,
            preferred_language: appSettings.language.apiCode,
            daily_checkin_time: dailyTime,
            primary_goal: primaryGoal.rawValue,
            current_focus: currentFocus.rawValue
        )
        _ = await viewModel.update(input)
        statusMessage = "资料已保存"
    }
}

struct ProfileEditView: View {
    @StateObject private var viewModel = ProfileViewModel()

    var body: some View {
        EditProfileSheet(profile: viewModel.profile) { input in
            Task { _ = await viewModel.update(input) }
        }
        .task {
            await viewModel.loadProfile()
        }
    }
}

enum ProfileGoal: String, CaseIterable, Identifiable {
    case sleep
    case stress
    case metabolism
    case resilience

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return "睡眠"
        case .stress: return "压力"
        case .metabolism: return "代谢"
        case .resilience: return "恢复力"
        }
    }
}

enum ProfileFocus: String, CaseIterable, Identifiable {
    case stress
    case energy
    case mood

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stress: return "压力"
        case .energy: return "精力"
        case .mood: return "情绪"
        }
    }
}

// MARK: - Preview

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .preferredColorScheme(.dark)
    }
}
