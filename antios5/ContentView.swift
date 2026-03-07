import SwiftData
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var supabase: SupabaseManager
    @EnvironmentObject private var appSettings: AppSettings
    @AppStorage("isOnboardingComplete") private var isOnboardingComplete = false

    var body: some View {
        Group {
            if !supabase.isSessionRestored {
                A10LaunchView(language: appSettings.language)
            } else if !supabase.isAuthenticated {
                AuthView()
            } else if !supabase.isClinicalComplete {
                ClinicalOnboardingView(isComplete: $supabase.isClinicalComplete)
            } else if !isOnboardingComplete {
                OnboardingView(isComplete: $isOnboardingComplete)
            } else {
                A10AppShell(language: appSettings.language)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: supabase.isSessionRestored)
        .animation(.easeInOut(duration: 0.24), value: supabase.isAuthenticated)
        .animation(.easeInOut(duration: 0.24), value: isOnboardingComplete)
    }
}

enum A10Tab: String, CaseIterable, Identifiable {
    case home
    case coach
    case me

    var id: String { rawValue }
}

enum A10LoopStage: String, CaseIterable, Identifiable, Codable {
    case inquiry
    case calibration
    case evidence
    case action

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .inquiry: return "bubble.left.and.bubble.right"
        case .calibration: return "waveform.path.ecg"
        case .evidence: return "doc.text.magnifyingglass"
        case .action: return "checklist"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .inquiry:
            return L10n.text("问询", "Inquiry", language: language)
        case .calibration:
            return L10n.text("校准", "Calibration", language: language)
        case .evidence:
            return L10n.text("解释", "Evidence", language: language)
        case .action:
            return L10n.text("行动", "Action", language: language)
        }
    }

    func summary(language: AppLanguage) -> String {
        switch self {
        case .inquiry:
            return L10n.text("用一句话说出今天最明显的触发点。", "Name today's clearest trigger in one sentence.", language: language)
        case .calibration:
            return L10n.text("补齐今日主观状态与身体信号。", "Capture today's subjective and body signals.", language: language)
        case .evidence:
            return L10n.text("把建议和证据链解释清楚。", "Turn the recommendation into an evidence-backed explanation.", language: language)
        case .action:
            return L10n.text("执行一个最低阻力动作。", "Complete one lowest-friction action.", language: language)
        }
    }

    var next: A10LoopStage {
        switch self {
        case .inquiry: return .calibration
        case .calibration: return .evidence
        case .evidence: return .action
        case .action: return .action
        }
    }
}

enum A10CoachRole: String, Codable {
    case user
    case assistant
}

@Model
final class A10LoopSnapshot {
    var headline: String
    var summary: String
    var nextActionTitle: String
    var nextActionDetail: String
    var evidenceNote: String
    var currentStageRaw: String
    var stressScore: Int
    var updatedAt: Date

    init(
        headline: String,
        summary: String,
        nextActionTitle: String,
        nextActionDetail: String,
        evidenceNote: String,
        currentStageRaw: String,
        stressScore: Int,
        updatedAt: Date = .now
    ) {
        self.headline = headline
        self.summary = summary
        self.nextActionTitle = nextActionTitle
        self.nextActionDetail = nextActionDetail
        self.evidenceNote = evidenceNote
        self.currentStageRaw = currentStageRaw
        self.stressScore = stressScore
        self.updatedAt = updatedAt
    }

    var stage: A10LoopStage {
        get { A10LoopStage(rawValue: currentStageRaw) ?? .inquiry }
        set { currentStageRaw = newValue.rawValue }
    }
}

@Model
final class A10ActionPlan {
    var title: String
    var detail: String
    var effortLabel: String
    var estimatedMinutes: Int
    var isCompleted: Bool
    var sortOrder: Int
    var updatedAt: Date

    init(
        title: String,
        detail: String,
        effortLabel: String,
        estimatedMinutes: Int,
        isCompleted: Bool = false,
        sortOrder: Int = 0,
        updatedAt: Date = .now
    ) {
        self.title = title
        self.detail = detail
        self.effortLabel = effortLabel
        self.estimatedMinutes = estimatedMinutes
        self.isCompleted = isCompleted
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }
}

@Model
final class A10CoachSession {
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \A10CoachMessage.session)
    var messages: [A10CoachMessage] = []

    init(title: String, createdAt: Date = .now, updatedAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class A10CoachMessage {
    var roleRaw: String
    var body: String
    var createdAt: Date
    var session: A10CoachSession?

    init(
        roleRaw: String,
        body: String,
        createdAt: Date = .now,
        session: A10CoachSession? = nil
    ) {
        self.roleRaw = roleRaw
        self.body = body
        self.createdAt = createdAt
        self.session = session
    }

    var role: A10CoachRole {
        A10CoachRole(rawValue: roleRaw) ?? .assistant
    }
}

@Model
final class A10PreferenceRecord {
    var languageCode: String
    var healthSyncEnabled: Bool
    var notificationsEnabled: Bool
    var dailyCheckInHour: Int
    var updatedAt: Date

    init(
        languageCode: String,
        healthSyncEnabled: Bool,
        notificationsEnabled: Bool,
        dailyCheckInHour: Int,
        updatedAt: Date = .now
    ) {
        self.languageCode = languageCode
        self.healthSyncEnabled = healthSyncEnabled
        self.notificationsEnabled = notificationsEnabled
        self.dailyCheckInHour = dailyCheckInHour
        self.updatedAt = updatedAt
    }
}

private struct A10AppShell: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: A10Tab = .home

    let language: AppLanguage

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                A10HomeView(
                    language: language,
                    onOpenCoach: { selectedTab = .coach }
                )
            }
            .tabItem {
                Label(
                    A10Tab.home.title(language: language),
                    systemImage: A10Tab.home.icon
                )
            }
            .tag(A10Tab.home)

            NavigationStack {
                A10CoachView(language: language)
            }
            .tabItem {
                Label(
                    A10Tab.coach.title(language: language),
                    systemImage: A10Tab.coach.icon
                )
            }
            .tag(A10Tab.coach)

            NavigationStack {
                A10MeView(language: language)
            }
            .tabItem {
                Label(
                    A10Tab.me.title(language: language),
                    systemImage: A10Tab.me.icon
                )
            }
            .tag(A10Tab.me)
        }
        .task(id: language.rawValue) {
            A10SeedData.ensureSeedData(context: modelContext, language: language)
        }
        .background(A10Palette.canvas.ignoresSafeArea())
    }
}

private struct A10HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \A10LoopSnapshot.updatedAt, order: .reverse) private var loopSnapshots: [A10LoopSnapshot]
    @Query(sort: \A10ActionPlan.sortOrder) private var plans: [A10ActionPlan]

    let language: AppLanguage
    let onOpenCoach: () -> Void

    private var currentSnapshot: A10LoopSnapshot? { loopSnapshots.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let currentSnapshot {
                    A10FocusHeroCard(snapshot: currentSnapshot, language: language)
                } else {
                    A10EmptyStateCard(
                        title: L10n.text("正在建立今日闭环", "Creating today's loop", language: language),
                        message: L10n.text("SwiftData 容器已接入，正在生成本地快照。", "SwiftData is ready and preparing a local snapshot.", language: language)
                    )
                }

                A10SectionHeader(
                    title: L10n.text("闭环状态", "Loop status", language: language),
                    subtitle: L10n.text("先让用户知道自己在哪一步。", "Show the current recovery step first.", language: language)
                )

                A10Card {
                    VStack(spacing: 14) {
                        ForEach(A10LoopStage.allCases) { stage in
                            A10LoopStepRow(
                                stage: stage,
                                currentStage: currentSnapshot?.stage ?? .inquiry,
                                language: language
                            )
                        }
                    }
                }

                A10SectionHeader(
                    title: L10n.text("今日行动", "Today plan", language: language),
                    subtitle: L10n.text("把建议收敛成最小动作。", "Turn guidance into the smallest useful action.", language: language)
                )

                VStack(spacing: 12) {
                    ForEach(plans.prefix(3), id: \.persistentModelID) { plan in
                        A10ActionCard(
                            plan: plan,
                            language: language,
                            onToggle: { toggle(plan: plan) }
                        )
                    }
                }

                A10SectionHeader(
                    title: L10n.text("快速动作", "Quick actions", language: language),
                    subtitle: L10n.text("先推进闭环，再决定是否深入。", "Progress the loop first, then decide whether to go deeper.", language: language)
                )

                HStack(spacing: 12) {
                    Button {
                        advanceLoop()
                    } label: {
                        A10ActionButtonLabel(
                            title: L10n.text("推进下一步", "Advance next step", language: language),
                            subtitle: L10n.text("更新本地闭环状态", "Update the local loop state", language: language),
                            systemImage: "arrow.right.circle.fill"
                        )
                    }
                    .buttonStyle(A10PrimaryButtonStyle())

                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onOpenCoach()
                    } label: {
                        A10ActionButtonLabel(
                            title: L10n.text("打开 Coach", "Open Coach", language: language),
                            subtitle: L10n.text("进入对话与行动收口", "Enter chat and action handoff", language: language),
                            systemImage: "bubble.left.and.bubble.right.fill"
                        )
                    }
                    .buttonStyle(A10SecondaryButtonStyle())
                }
            }
            .padding(20)
        }
        .background(A10Palette.canvas.ignoresSafeArea())
        .navigationTitle(A10Tab.home.title(language: language))
        .navigationBarTitleDisplayMode(.large)
    }

    private func advanceLoop() {
        guard let snapshot = currentSnapshot else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        snapshot.stage = snapshot.stage.next
        snapshot.updatedAt = .now

        if snapshot.stage == .evidence {
            snapshot.evidenceNote = L10n.text(
                "解释优先来自本地闭环快照，后续再接入远端证据链。",
                "Explanations are currently grounded in the local loop snapshot, with remote evidence to follow.",
                language: language
            )
        }

        if snapshot.stage == .action {
            snapshot.nextActionTitle = L10n.text("完成 3 分钟呼吸", "Complete a 3-minute breathing reset", language: language)
            snapshot.nextActionDetail = L10n.text("只做一个最低阻力动作，先把身体带回安全感。", "Do one lowest-friction action and bring the body back to safety first.", language: language)
            if !plans.contains(where: { $0.title == snapshot.nextActionTitle }) {
                modelContext.insert(
                    A10ActionPlan(
                        title: snapshot.nextActionTitle,
                        detail: snapshot.nextActionDetail,
                        effortLabel: L10n.text("低负担", "Low load", language: language),
                        estimatedMinutes: 3,
                        sortOrder: plans.count
                    )
                )
            }
        }

        try? modelContext.save()
    }

    private func toggle(plan: A10ActionPlan) {
        UISelectionFeedbackGenerator().selectionChanged()
        plan.isCompleted.toggle()
        plan.updatedAt = .now
        try? modelContext.save()
    }
}

private struct A10CoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \A10CoachSession.updatedAt, order: .reverse) private var sessions: [A10CoachSession]
    @Query(sort: \A10LoopSnapshot.updatedAt, order: .reverse) private var loopSnapshots: [A10LoopSnapshot]
    @State private var draft = ""

    let language: AppLanguage

    private var activeSession: A10CoachSession? { sessions.first }

    private var sortedMessages: [A10CoachMessage] {
        guard let activeSession else { return [] }
        return activeSession.messages.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    A10SectionHeader(
                        title: L10n.text("Coach 对话", "Coach thread", language: language),
                        subtitle: L10n.text("现在先用本地优先会话模型承接输入。", "The first rebuild pass uses a local-first thread model.", language: language)
                    )

                    ForEach(sortedMessages, id: \.persistentModelID) { message in
                        A10CoachBubble(message: message, language: language)
                    }

                    if sortedMessages.isEmpty {
                        A10EmptyStateCard(
                            title: L10n.text("还没有对话", "No thread yet", language: language),
                            message: L10n.text("发送第一条消息，系统会写入 SwiftData 会话。", "Send the first message and the shell will write to SwiftData.", language: language)
                        )
                    }

                    A10SectionHeader(
                        title: L10n.text("快捷提示", "Quick prompts", language: language),
                        subtitle: L10n.text("减少高压状态下的输入成本。", "Reduce input effort during high stress moments.", language: language)
                    )

                    A10QuickPromptRow(
                        prompts: A10CoachResponder.quickPrompts(language: language),
                        onSelect: { draft = $0 }
                    )
                }
                .padding(20)
            }

            A10ComposerBar(
                draft: $draft,
                language: language,
                onSend: sendMessage
            )
        }
        .background(A10Palette.canvas.ignoresSafeArea())
        .navigationTitle(A10Tab.coach.title(language: language))
        .navigationBarTitleDisplayMode(.large)
    }

    private func sendMessage() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        let session = activeSession ?? A10SeedData.createSession(context: modelContext, language: language)
        let userMessage = A10CoachMessage(roleRaw: A10CoachRole.user.rawValue, body: trimmed, session: session)
        modelContext.insert(userMessage)

        let currentStage = loopSnapshots.first?.stage ?? .inquiry
        let reply = A10CoachResponder.reply(
            to: trimmed,
            stage: currentStage,
            language: language
        )
        let assistantMessage = A10CoachMessage(roleRaw: A10CoachRole.assistant.rawValue, body: reply, session: session)
        modelContext.insert(assistantMessage)

        session.updatedAt = .now

        if let snapshot = loopSnapshots.first, snapshot.stage != .action {
            snapshot.stage = snapshot.stage.next
            snapshot.updatedAt = .now
        }

        draft = ""
        try? modelContext.save()
    }
}

private struct A10MeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabase: SupabaseManager
    @Query(sort: \A10PreferenceRecord.updatedAt, order: .reverse) private var preferenceRecords: [A10PreferenceRecord]
    @Query(sort: \A10LoopSnapshot.updatedAt, order: .reverse) private var loopSnapshots: [A10LoopSnapshot]
    @Query(sort: \A10ActionPlan.sortOrder) private var plans: [A10ActionPlan]
    @Query(sort: \A10CoachSession.updatedAt, order: .reverse) private var sessions: [A10CoachSession]

    let language: AppLanguage

    private var preferences: A10PreferenceRecord? { preferenceRecords.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                A10SectionHeader(
                    title: L10n.text("系统与偏好", "System and preferences", language: language),
                    subtitle: L10n.text("把设置从展示型页面改成状态清晰的运维面板。", "Turn settings into a clear operating panel rather than a decorative page.", language: language)
                )

                A10Card {
                    VStack(spacing: 16) {
                        A10SettingsToggleRow(
                            title: L10n.text("Health 数据同步", "Health data sync", language: language),
                            subtitle: L10n.text("保持 Apple Health 为首选输入来源。", "Keep Apple Health as the preferred signal source.", language: language),
                            isOn: Binding(
                                get: { preferences?.healthSyncEnabled ?? true },
                                set: { newValue in
                                    updatePreferences { record in
                                        record.healthSyncEnabled = newValue
                                    }
                                }
                            )
                        )

                        A10Divider()

                        A10SettingsToggleRow(
                            title: L10n.text("每日提醒", "Daily reminders", language: language),
                            subtitle: L10n.text("仅保留高价值提醒，不制造噪音。", "Keep reminders high value and low noise.", language: language),
                            isOn: Binding(
                                get: { preferences?.notificationsEnabled ?? true },
                                set: { newValue in
                                    updatePreferences { record in
                                        record.notificationsEnabled = newValue
                                    }
                                }
                            )
                        )
                    }
                }

                A10SectionHeader(
                    title: L10n.text("数据层状态", "Data layer status", language: language),
                    subtitle: L10n.text("确认新壳层已经由 SwiftData 驱动。", "Confirm that the rebuild shell is already driven by SwiftData.", language: language)
                )

                A10Card {
                    VStack(spacing: 14) {
                        A10MetricRow(
                            title: "SwiftData",
                            value: L10n.text("已接管本地状态", "Local state is active", language: language)
                        )
                        A10MetricRow(
                            title: L10n.text("闭环快照", "Loop snapshots", language: language),
                            value: "\(loopSnapshots.count)"
                        )
                        A10MetricRow(
                            title: L10n.text("行动计划", "Plans", language: language),
                            value: "\(plans.count)"
                        )
                        A10MetricRow(
                            title: L10n.text("Coach 会话", "Coach sessions", language: language),
                            value: "\(sessions.count)"
                        )
                        A10MetricRow(
                            title: "Remote",
                            value: L10n.text("Auth 与同步后续桥接", "Auth and sync will stay remote", language: language)
                        )
                    }
                }

                A10SectionHeader(
                    title: L10n.text("账户", "Account", language: language),
                    subtitle: L10n.text("当前先保留 Supabase Auth，不在本轮迁移提供商。", "Supabase Auth remains in place for this rebuild pass.", language: language)
                )

                Button {
                    Task { await supabase.signOut() }
                } label: {
                    Text(L10n.text("退出登录", "Sign out", language: language))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(A10SecondaryButtonStyle())
            }
            .padding(20)
        }
        .background(A10Palette.canvas.ignoresSafeArea())
        .navigationTitle(A10Tab.me.title(language: language))
        .navigationBarTitleDisplayMode(.large)
    }

    private func updatePreferences(_ mutate: (A10PreferenceRecord) -> Void) {
        let record = preferences ?? A10SeedData.createPreferences(context: modelContext, language: language)
        mutate(record)
        record.updatedAt = .now
        try? modelContext.save()
    }
}

private struct A10LaunchView: View {
    let language: AppLanguage

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [A10Palette.canvas, A10Palette.surface, A10Palette.inset],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.brand)

                Text("AntiAnxiety")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)

                Text(
                    L10n.text(
                        "正在切换到更轻、更稳的 antios10 主壳层",
                        "Booting the lighter and steadier antios10 shell",
                        language: language
                    )
                )
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)

                ProgressView()
                    .tint(A10Palette.brand)
                    .padding(.top, 8)
            }
            .padding(32)
        }
    }
}

private struct A10FocusHeroCard: View {
    let snapshot: A10LoopSnapshot
    let language: AppLanguage

    var body: some View {
        A10Card(highlighted: true) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.text("今日重点", "Today's focus", language: language))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)

                Text(snapshot.headline)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)

                Text(snapshot.summary)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)

                HStack(spacing: 12) {
                    A10Badge(
                        title: "\(L10n.text("压力", "Stress", language: language)) \(snapshot.stressScore)/10",
                        tint: A10Palette.warning
                    )
                    A10Badge(
                        title: snapshot.stage.title(language: language),
                        tint: A10Palette.brand
                    )
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(snapshot.nextActionTitle)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)
                    Text(snapshot.nextActionDetail)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(A10Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private struct A10LoopStepRow: View {
    let stage: A10LoopStage
    let currentStage: A10LoopStage
    let language: AppLanguage

    private var isComplete: Bool {
        A10LoopStage.allCases.firstIndex(of: stage).map { index in
            guard let currentIndex = A10LoopStage.allCases.firstIndex(of: currentStage) else { return false }
            return index < currentIndex
        } ?? false
    }

    private var isCurrent: Bool { currentStage == stage }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(indicatorColor.opacity(0.18))
                    .frame(width: 38, height: 38)

                Image(systemName: isComplete ? "checkmark" : stage.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(indicatorColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stage.title(language: language))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)

                Text(stage.summary(language: language))
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }

            Spacer()

            Text(statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(indicatorColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var indicatorColor: Color {
        if isComplete { return A10Palette.success }
        if isCurrent { return A10Palette.brand }
        return A10Palette.line
    }

    private var statusText: String {
        if isComplete {
            return L10n.text("完成", "Done", language: language)
        }
        if isCurrent {
            return L10n.text("当前", "Current", language: language)
        }
        return L10n.text("待处理", "Queued", language: language)
    }
}

private struct A10ActionCard: View {
    let plan: A10ActionPlan
    let language: AppLanguage
    let onToggle: () -> Void

    var body: some View {
        A10Card {
            HStack(alignment: .top, spacing: 14) {
                Button(action: onToggle) {
                    Image(systemName: plan.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(plan.isCompleted ? A10Palette.success : A10Palette.line)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(A10Palette.ink)
                    Text(plan.detail)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                    HStack(spacing: 8) {
                        A10Badge(title: plan.effortLabel, tint: A10Palette.info)
                        A10Badge(
                            title: "\(plan.estimatedMinutes) \(L10n.text("分钟", "min", language: language))",
                            tint: A10Palette.brandSecondary
                        )
                    }
                }

                Spacer()
            }
        }
    }
}

private struct A10CoachBubble: View {
    let message: A10CoachMessage
    let language: AppLanguage

    var body: some View {
        HStack {
            if message.role == .assistant {
                bubble(alignment: .leading, tint: A10Palette.surface, foreground: A10Palette.ink)
                Spacer(minLength: 36)
            } else {
                Spacer(minLength: 36)
                bubble(alignment: .trailing, tint: A10Palette.brand.opacity(0.18), foreground: A10Palette.ink)
            }
        }
    }

    private func bubble(alignment: HorizontalAlignment, tint: Color, foreground: Color) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(message.role == .assistant ? "Coach" : L10n.text("你", "You", language: language))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)

            Text(message.body)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)

            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(A10Palette.inkTertiary)
        }
        .padding(16)
        .background(tint)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct A10ComposerBar: View {
    @Binding var draft: String

    let language: AppLanguage
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            A10Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField(
                    L10n.text("输入今天最真实的感受…", "Write the most real thing you feel today...", language: language),
                    text: $draft,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .padding(14)
                .background(A10Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .buttonStyle(.plain)
                .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? A10Palette.line : A10Palette.brand)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .padding(.top, 6)
            .background(A10Palette.canvas)
        }
    }
}

private struct A10QuickPromptRow: View {
    let prompts: [String]
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(prompts, id: \.self) { prompt in
                    Button(action: { onSelect(prompt) }) {
                        Text(prompt)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(A10Palette.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(A10Palette.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct A10SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(A10Palette.ink)
            Text(subtitle)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)
        }
    }
}

private struct A10EmptyStateCard: View {
    let title: String
    let message: String

    var body: some View {
        A10Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)
                Text(message)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }
        }
    }
}

private struct A10MetricRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(A10Palette.ink)
        }
    }
}

private struct A10SettingsToggleRow: View {
    let title: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(A10Palette.brand)
        }
    }
}

private struct A10ActionButtonLabel: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .opacity(0.8)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity)
    }
}

private struct A10Card<Content: View>: View {
    let highlighted: Bool
    @ViewBuilder let content: Content

    init(highlighted: Bool = false, @ViewBuilder content: () -> Content) {
        self.highlighted = highlighted
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? A10Palette.surfaceStrong : A10Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(highlighted ? A10Palette.brand.opacity(0.18) : A10Palette.line.opacity(0.7), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct A10Badge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct A10Divider: View {
    var body: some View {
        Rectangle()
            .fill(A10Palette.line.opacity(0.7))
            .frame(height: 1)
    }
}

private struct A10PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(A10Palette.brand.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct A10SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(A10Palette.ink)
            .background(A10Palette.surface.opacity(configuration.isPressed ? 0.88 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(A10Palette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum A10Palette {
    static let canvas = Color(a10Hex: "#F5F1EA")
    static let surface = Color(a10Hex: "#FFFDF8")
    static let surfaceStrong = Color(a10Hex: "#F8F3EB")
    static let inset = Color(a10Hex: "#ECE4D7")
    static let line = Color(a10Hex: "#D8CEBF")
    static let ink = Color(a10Hex: "#1F2328")
    static let inkSecondary = Color(a10Hex: "#56606B")
    static let inkTertiary = Color(a10Hex: "#7B8794")
    static let brand = Color(a10Hex: "#2F6E62")
    static let brandSecondary = Color(a10Hex: "#C96F4A")
    static let success = Color(a10Hex: "#2E7D5B")
    static let warning = Color(a10Hex: "#C28A2C")
    static let info = Color(a10Hex: "#5073B8")
}

private enum A10SeedData {
    @MainActor
    static func ensureSeedData(context: ModelContext, language: AppLanguage) {
        do {
            var snapshotDescriptor = FetchDescriptor<A10LoopSnapshot>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            snapshotDescriptor.fetchLimit = 1
            let hasSnapshot = try !context.fetch(snapshotDescriptor).isEmpty

            var planDescriptor = FetchDescriptor<A10ActionPlan>(sortBy: [SortDescriptor(\.sortOrder)])
            planDescriptor.fetchLimit = 1
            let hasPlans = try !context.fetch(planDescriptor).isEmpty

            var sessionDescriptor = FetchDescriptor<A10CoachSession>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            sessionDescriptor.fetchLimit = 1
            let hasSession = try !context.fetch(sessionDescriptor).isEmpty

            var preferenceDescriptor = FetchDescriptor<A10PreferenceRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            preferenceDescriptor.fetchLimit = 1
            let existingPreferences = try context.fetch(preferenceDescriptor).first

            if !hasSnapshot {
                context.insert(
                    A10LoopSnapshot(
                        headline: L10n.text("先让系统知道你今天最难的点。", "Let the system understand your hardest point today first.", language: language),
                        summary: L10n.text("新壳层先围绕一个问题、一条解释、一个动作来组织信息。", "The new shell starts by organizing the experience around one question, one explanation, and one action.", language: language),
                        nextActionTitle: L10n.text("用 20 秒说出触发点", "Name the trigger in 20 seconds", language: language),
                        nextActionDetail: L10n.text("例如：今天开会前胸口发紧，注意力被拉走。", "Example: before today's meeting my chest tightened and my attention drifted away.", language: language),
                        evidenceNote: L10n.text("下一阶段会把本地快照与远端证据桥接。", "The next phase will bridge the local snapshot with remote evidence.", language: language),
                        currentStageRaw: A10LoopStage.inquiry.rawValue,
                        stressScore: 6
                    )
                )
            }

            if !hasPlans {
                context.insert(
                    A10ActionPlan(
                        title: L10n.text("做 3 分钟呼吸", "Do a 3-minute breathing reset", language: language),
                        detail: L10n.text("不用追求完整闭环，先做最低阻力动作。", "Do not chase the full loop yet. Start with the lowest-friction action.", language: language),
                        effortLabel: L10n.text("低负担", "Low load", language: language),
                        estimatedMinutes: 3,
                        sortOrder: 0
                    )
                )
                context.insert(
                    A10ActionPlan(
                        title: L10n.text("记录一句触发语境", "Log one trigger sentence", language: language),
                        detail: L10n.text("保留最真实的上下文，后面给解释和行动用。", "Capture the most real context for later explanation and action.", language: language),
                        effortLabel: L10n.text("1 句话", "1 line", language: language),
                        estimatedMinutes: 1,
                        sortOrder: 1
                    )
                )
            }

            if !hasSession {
                let session = createSession(context: context, language: language)
                context.insert(
                    A10CoachMessage(
                        roleRaw: A10CoachRole.assistant.rawValue,
                        body: L10n.text(
                            "我会先帮你把今天的状态说清楚，再把它收敛成一个动作。",
                            "I will first help you name today's state clearly, then collapse it into one action.",
                            language: language
                        ),
                        session: session
                    )
                )
            }

            if let existingPreferences {
                existingPreferences.languageCode = language.rawValue
                existingPreferences.updatedAt = .now
            } else {
                context.insert(
                    A10PreferenceRecord(
                        languageCode: language.rawValue,
                        healthSyncEnabled: true,
                        notificationsEnabled: true,
                        dailyCheckInHour: 21
                    )
                )
            }

            try context.save()
        } catch {
            print("[A10SeedData] failed: \(error)")
        }
    }

    @MainActor
    static func createSession(context: ModelContext, language: AppLanguage) -> A10CoachSession {
        let session = A10CoachSession(
            title: L10n.text("今日恢复线程", "Today's recovery thread", language: language)
        )
        context.insert(session)
        return session
    }

    @MainActor
    static func createPreferences(context: ModelContext, language: AppLanguage) -> A10PreferenceRecord {
        let record = A10PreferenceRecord(
            languageCode: language.rawValue,
            healthSyncEnabled: true,
            notificationsEnabled: true,
            dailyCheckInHour: 21
        )
        context.insert(record)
        return record
    }
}

private enum A10CoachResponder {
    static func quickPrompts(language: AppLanguage) -> [String] {
        [
            L10n.text("我今天最难的是开会前的紧绷", "The hardest part today was the tension before a meeting", language: language),
            L10n.text("我想先做一个最简单的动作", "I want the simplest useful action first", language: language),
            L10n.text("请把原因和下一步说短一点", "Please keep the why and next step short", language: language)
        ]
    }

    static func reply(to message: String, stage: A10LoopStage, language: AppLanguage) -> String {
        let lowered = message.lowercased()

        if lowered.contains("meeting") || message.contains("开会") || message.contains("工作") {
            return L10n.text(
                "这更像是工作场景下的预期性高唤醒。先别要求自己立刻平静，先把身体负荷降下来，再决定是否深入解释。",
                "This looks like anticipatory arousal in a work context. Do not force calm first. Lower body load first, then decide whether to go deeper.",
                language: language
            )
        }

        switch stage {
        case .inquiry:
            return L10n.text(
                "我先帮你收口成一句状态描述：你不是做不到，而是系统现在处在偏高警觉。下一步补一个主观分数就够了。",
                "Let me collapse this into one state statement: you are not failing, your system is simply running at elevated alertness. The next useful step is a quick calibration score.",
                language: language
            )
        case .calibration:
            return L10n.text(
                "现在信息已经够做一版解释了。先用最少证据说明为什么会这样，再给一个低阻力动作。",
                "The information is now enough for a first-pass explanation. Use the smallest useful evidence, then give one low-friction action.",
                language: language
            )
        case .evidence:
            return L10n.text(
                "解释已经足够，接下来别扩写。请只执行一个动作，比如 3 分钟呼吸或离开刺激场景 2 分钟。",
                "The explanation is already enough. Do not expand it further. Execute just one action, such as three minutes of breathing or stepping away from the trigger for two minutes.",
                language: language
            )
        case .action:
            return L10n.text(
                "现在的重点不是理解更多，而是确认动作是否完成。做完后回来告诉我身体有没有降一点紧。",
                "The priority now is not more understanding, but whether the action was completed. Come back and tell me whether the body settled even a little.",
                language: language
            )
        }
    }
}

private extension A10Tab {
    var icon: String {
        switch self {
        case .home: return "house"
        case .coach: return "bubble.left.and.bubble.right"
        case .me: return "person.crop.circle"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .home:
            return L10n.text("Home", "Home", language: language)
        case .coach:
            return "Coach"
        case .me:
            return L10n.text("Me", "Me", language: language)
        }
    }
}

private extension Color {
    init(a10Hex hex: String) {
        let sanitized = hex.replacingOccurrences(of: "#", with: "")
        var value: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&value)

        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255

        self.init(red: red, green: green, blue: blue)
    }
}

#Preview("A10 Shell") {
    A10AppShell(language: .en)
        .modelContainer(
            for: [
                A10LoopSnapshot.self,
                A10ActionPlan.self,
                A10CoachSession.self,
                A10CoachMessage.self,
                A10PreferenceRecord.self
            ],
            inMemory: true
        )
}
