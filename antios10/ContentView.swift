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
    case max
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

enum A10MaxRole: String, Codable {
    case user
    case assistant
}

enum A10PlanSource: String, Codable {
    case local
    case habit
    case recommendation
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
    var remoteID: String?
    var sourceRaw: String
    var sortOrder: Int
    var updatedAt: Date

    init(
        title: String,
        detail: String,
        effortLabel: String,
        estimatedMinutes: Int,
        isCompleted: Bool = false,
        remoteID: String? = nil,
        sourceRaw: String = A10PlanSource.local.rawValue,
        sortOrder: Int = 0,
        updatedAt: Date = .now
    ) {
        self.title = title
        self.detail = detail
        self.effortLabel = effortLabel
        self.estimatedMinutes = estimatedMinutes
        self.isCompleted = isCompleted
        self.remoteID = remoteID
        self.sourceRaw = sourceRaw
        self.sortOrder = sortOrder
        self.updatedAt = updatedAt
    }

    var source: A10PlanSource {
        get { A10PlanSource(rawValue: sourceRaw) ?? .local }
        set { sourceRaw = newValue.rawValue }
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

// Keep the persisted SwiftData entity names stable while migrating runtime code to Max naming.
typealias A10MaxSession = A10CoachSession

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

    var role: A10MaxRole {
        A10MaxRole(rawValue: roleRaw) ?? .assistant
    }
}

// Keep the persisted SwiftData entity names stable while migrating runtime code to Max naming.
typealias A10MaxMessage = A10CoachMessage

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
    @StateObject private var syncCoordinator = A10ShellSyncCoordinator()
    @State private var selectedTab: A10Tab = .home

    let language: AppLanguage

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                A10HomeView(
                    language: language,
                    onOpenMax: { selectedTab = .max }
                )
            }
            .tabItem {
                Label(
                    A10Tab.home.title(language: language),
                    systemImage: A10Tab.home.icon
                )
            }
            .tag(A10Tab.home)

            MaxChatView()
            .tabItem {
                Label(
                    A10Tab.max.title(language: language),
                    systemImage: A10Tab.max.icon
                )
            }
            .tag(A10Tab.max)

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
            await syncCoordinator.sync(context: modelContext, language: language, force: false, trigger: "shell")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMaxChat)) { _ in
            selectedTab = .max
        }
        .onReceive(NotificationCenter.default.publisher(for: .openDashboard)) { _ in
            selectedTab = .home
        }
        .environmentObject(syncCoordinator)
        .tint(A10Palette.brand)
        .background {
            AuroraBackground()
        }
    }
}

private struct A10HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var syncCoordinator: A10ShellSyncCoordinator
    @Query(sort: \A10LoopSnapshot.updatedAt, order: .reverse) private var loopSnapshots: [A10LoopSnapshot]
    @Query(sort: \A10ActionPlan.sortOrder) private var plans: [A10ActionPlan]

    let language: AppLanguage
    let onOpenMax: () -> Void

    private var currentSnapshot: A10LoopSnapshot? { loopSnapshots.first }
    private var activePlansCount: Int { plans.filter { !$0.isCompleted }.count }
    private var completedPlansCount: Int { plans.filter(\.isCompleted).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let currentSnapshot {
                    A10HomeOverviewCard(
                        snapshot: currentSnapshot,
                        activePlansCount: activePlansCount,
                        completedPlansCount: completedPlansCount,
                        language: language
                    )
                    A10FocusHeroCard(snapshot: currentSnapshot, language: language)
                } else {
                    A10EmptyStateCard(
                        title: L10n.text("正在建立今日闭环", "Creating today's loop", language: language),
                        message: L10n.text("SwiftData 已接入，正在和远端数据对齐。", "SwiftData is active and aligning with remote data.", language: language)
                    )
                }

                A10RemoteStatusCard(language: language)

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
                        onOpenMax()
                    } label: {
                        A10ActionButtonLabel(
                            title: L10n.text("打开 Max", "Open Max", language: language),
                            subtitle: L10n.text("进入对话与行动收口", "Enter chat and action handoff", language: language),
                            systemImage: "bubble.left.and.bubble.right.fill"
                        )
                    }
                    .buttonStyle(A10SecondaryButtonStyle())
                }
            }
            .padding(20)
        }
        .background {
            AuroraBackground()
        }
        .navigationTitle(A10Tab.home.title(language: language))
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "home_refresh")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if syncCoordinator.isSyncing {
                    ProgressView()
                        .tint(A10Palette.brand)
                } else {
                    Button {
                        Task {
                            await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "home_toolbar_refresh")
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .tint(A10Palette.brand)
                }
            }
        }
    }

    private func advanceLoop() {
        guard let snapshot = currentSnapshot else { return }

        UISelectionFeedbackGenerator().selectionChanged()
        snapshot.stage = snapshot.stage.next
        snapshot.updatedAt = .now

        if snapshot.stage == .evidence {
            snapshot.evidenceNote = L10n.text(
                "本地闭环会先推进，下一次同步会补齐远端证据与推荐。",
                "The local loop advances first, and the next sync will pull remote evidence and guidance.",
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
        Task {
            await syncCoordinator.sync(context: modelContext, language: language, force: false, trigger: "loop_advance")
        }
    }

    private func toggle(plan: A10ActionPlan) {
        UISelectionFeedbackGenerator().selectionChanged()
        plan.isCompleted.toggle()
        plan.updatedAt = .now
        try? modelContext.save()
        Task {
            await syncCoordinator.syncPlanToggle(plan, context: modelContext, language: language)
        }
    }
}

private struct A10MeView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var supabase: SupabaseManager
    @EnvironmentObject private var syncCoordinator: A10ShellSyncCoordinator
    @Query(sort: \A10PreferenceRecord.updatedAt, order: .reverse) private var preferenceRecords: [A10PreferenceRecord]
    @Query(sort: \A10LoopSnapshot.updatedAt, order: .reverse) private var loopSnapshots: [A10LoopSnapshot]
    @Query(sort: \A10ActionPlan.sortOrder) private var plans: [A10ActionPlan]

    let language: AppLanguage

    private var preferences: A10PreferenceRecord? { preferenceRecords.first }
    private var currentSnapshot: A10LoopSnapshot? { loopSnapshots.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                A10MeOverviewCard(
                    snapshot: currentSnapshot,
                    preferences: preferences,
                    planCount: plans.count,
                    language: language,
                    isSyncing: syncCoordinator.isSyncing
                )

                A10SectionHeader(
                    title: L10n.text("系统与偏好", "System and preferences", language: language),
                    subtitle: L10n.text("把设置和远端同步状态都收口到一个运维面板。", "Keep settings and remote sync status in one operating panel.", language: language)
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
                    subtitle: L10n.text("确认新壳层已由 SwiftData 驱动，并正在桥接后端。", "Confirm that the rebuild shell is driven by SwiftData and bridged to the backend.", language: language)
                )

                A10RemoteStatusCard(language: language)

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
                            title: "Max",
                            value: L10n.text("已作为统一 agent 入口", "Now acts as the unified agent entry", language: language)
                        )
                        A10MetricRow(
                            title: "Remote",
                            value: L10n.text("Dashboard / Habits / Max 已桥接", "Dashboard / Habits / Max are bridged", language: language)
                        )
                    }
                }

                Button {
                    Task {
                        await syncCoordinator.sync(context: modelContext, language: language, force: true, trigger: "me_manual_sync")
                    }
                } label: {
                    A10ActionButtonLabel(
                        title: L10n.text("立即同步", "Sync now", language: language),
                        subtitle: L10n.text("刷新闭环、计划与远端建议", "Refresh loop, plans, and remote guidance", language: language),
                        systemImage: "arrow.triangle.2.circlepath.circle.fill"
                    )
                }
                .buttonStyle(A10PrimaryButtonStyle())

                A10SectionHeader(
                    title: L10n.text("账户", "Account", language: language),
                    subtitle: L10n.text("当前先保留 Supabase Auth，不在本轮迁移提供商。", "Supabase Auth remains in place for this rebuild pass.", language: language)
                )

                A10Card {
                    VStack(alignment: .leading, spacing: 14) {
                        A10MetricRow(
                            title: "Supabase",
                            value: supabase.isAuthenticated
                            ? L10n.text("已连接当前账户", "Connected to the current account", language: language)
                            : L10n.text("当前未登录", "Not signed in", language: language)
                        )
                        A10MetricRow(
                            title: L10n.text("通知", "Notifications", language: language),
                            value: preferences?.notificationsEnabled == true
                            ? L10n.text("已开启低噪提醒", "Low-noise reminders enabled", language: language)
                            : L10n.text("暂未开启", "Currently off", language: language)
                        )

                        Button {
                            Task { await supabase.signOut() }
                        } label: {
                            A10ActionButtonLabel(
                                title: L10n.text("退出登录", "Sign out", language: language),
                                subtitle: L10n.text("保留本地状态，断开当前远端账户", "Keep local state and disconnect the current remote account", language: language),
                                systemImage: "rectangle.portrait.and.arrow.right"
                            )
                        }
                        .buttonStyle(A10SecondaryButtonStyle())
                    }
                }
            }
            .padding(20)
        }
        .background {
            AuroraBackground()
        }
        .navigationTitle(A10Tab.me.title(language: language))
        .navigationBarTitleDisplayMode(.large)
    }

    private func updatePreferences(_ mutate: (A10PreferenceRecord) -> Void) {
        let record = preferences ?? A10SeedData.createPreferences(context: modelContext, language: language)
        mutate(record)
        record.languageCode = language.rawValue
        record.updatedAt = .now
        try? modelContext.save()
        Task {
            await syncCoordinator.syncPreferences(record, language: language)
        }
    }
}

private struct A10LaunchView: View {
    let language: AppLanguage

    var body: some View {
        ZStack {
            AuroraBackground()

            LiquidGlassCard(style: .elevated, padding: 32) {
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
                    .multilineTextAlignment(.center)

                    ProgressView()
                        .tint(A10Palette.brand)
                        .padding(.top, 8)
                }
            }
            .padding(28)
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
                .background(A10Palette.inset)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(A10Palette.line.opacity(0.85), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private struct A10HomeOverviewCard: View {
    let snapshot: A10LoopSnapshot
    let activePlansCount: Int
    let completedPlansCount: Int
    let language: AppLanguage

    var body: some View {
        A10Card {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("恢复总览", "Recovery overview", language: language))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                        Text(snapshot.stage.title(language: language))
                            .font(.system(size: 32, weight: .light, design: .rounded))
                            .foregroundStyle(A10Palette.ink)
                        Text(snapshot.evidenceNote)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Text(L10n.text("压力读数", "Stress reading", language: language))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                        Text("\(snapshot.stressScore)/10")
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .foregroundStyle(A10Palette.ink)
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    A10OverviewMetricCard(
                        title: L10n.text("当前阶段", "Current stage", language: language),
                        value: snapshot.stage.title(language: language),
                        detail: L10n.text("以闭环推进为主", "Drive the loop first", language: language),
                        tint: A10Palette.brand
                    )
                    A10OverviewMetricCard(
                        title: L10n.text("进行中动作", "Active plans", language: language),
                        value: "\(activePlansCount)",
                        detail: L10n.text("待执行或待确认", "Awaiting execution", language: language),
                        tint: A10Palette.info
                    )
                    A10OverviewMetricCard(
                        title: L10n.text("已完成动作", "Completed plans", language: language),
                        value: "\(completedPlansCount)",
                        detail: L10n.text("形成正反馈", "Closing the loop", language: language),
                        tint: A10Palette.success
                    )
                    A10OverviewMetricCard(
                        title: L10n.text("下一步", "Next move", language: language),
                        value: snapshot.nextActionTitle,
                        detail: L10n.text("保持最低阻力", "Keep resistance low", language: language),
                        tint: A10Palette.brandSecondary
                    )
                }
            }
        }
    }
}

private struct A10MeOverviewCard: View {
    let snapshot: A10LoopSnapshot?
    let preferences: A10PreferenceRecord?
    let planCount: Int
    let language: AppLanguage
    let isSyncing: Bool

    var body: some View {
        A10Card(highlighted: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text("系统面板", "System panel", language: language))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                        Text(L10n.text("antios10", "antios10", language: language))
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .foregroundStyle(A10Palette.ink)
                        Text(
                            isSyncing
                            ? L10n.text("远端数据正在回流", "Remote data is flowing in", language: language)
                            : L10n.text("偏好、状态与远端桥接保持一致", "Preferences, state, and remote bridge are aligned", language: language)
                        )
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(A10Palette.inkSecondary)
                    }

                    Spacer()

                    A10Badge(
                        title: isSyncing
                        ? L10n.text("同步中", "Syncing", language: language)
                        : L10n.text("已就绪", "Ready", language: language),
                        tint: isSyncing ? A10Palette.info : A10Palette.success
                    )
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    A10OverviewMetricCard(
                        title: L10n.text("闭环阶段", "Loop stage", language: language),
                        value: snapshot?.stage.title(language: language) ?? "A10",
                        detail: L10n.text("当前体验重心", "Current experience focus", language: language),
                        tint: A10Palette.brand
                    )
                    A10OverviewMetricCard(
                        title: L10n.text("语言", "Language", language: language),
                        value: preferences?.languageCode.uppercased() ?? language.rawValue.uppercased(),
                        detail: L10n.text("界面与文案偏好", "Interface preference", language: language),
                        tint: A10Palette.brandSecondary
                    )
                    A10OverviewMetricCard(
                        title: L10n.text("提醒", "Reminders", language: language),
                        value: preferences?.notificationsEnabled == true
                        ? L10n.text("开启", "On", language: language)
                        : L10n.text("关闭", "Off", language: language),
                        detail: L10n.text("只保留高价值触达", "High-value only", language: language),
                        tint: A10Palette.warning
                    )
                    A10OverviewMetricCard(
                        title: L10n.text("行动池", "Plan pool", language: language),
                        value: "\(planCount)",
                        detail: L10n.text("本地与远端统一编排", "Local and remote orchestration", language: language),
                        tint: A10Palette.info
                    )
                }
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

private struct A10RemoteStatusCard: View {
    @EnvironmentObject private var syncCoordinator: A10ShellSyncCoordinator

    let language: AppLanguage

    var body: some View {
        A10Card {
            VStack(alignment: .leading, spacing: 12) {
                A10MetricRow(
                    title: "Remote",
                    value: remoteStatusText
                )

                if let lastSyncAt = syncCoordinator.lastSyncAt {
                    A10MetricRow(
                        title: L10n.text("最近同步", "Last sync", language: language),
                        value: lastSyncAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }

                if let source = syncCoordinator.lastRemoteSource {
                    A10MetricRow(
                        title: L10n.text("最近来源", "Latest source", language: language),
                        value: sourceLabel(for: source)
                    )
                }

                if let error = syncCoordinator.lastErrorMessage, !error.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.text("最近一次远端同步失败", "The last remote sync attempt failed", language: language))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(A10Palette.warning)
                        Text(error)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(A10Palette.inkSecondary)
                    }
                }
            }
        }
    }

    private var remoteStatusText: String {
        if syncCoordinator.isSyncing {
            return L10n.text("正在同步 Dashboard / Habits / Recommendations", "Syncing Dashboard / Habits / Recommendations", language: language)
        }
        if syncCoordinator.lastSyncAt != nil {
            return L10n.text("远端数据已接入当前壳层", "Remote data is connected to the current shell", language: language)
        }
        return L10n.text("等待首次远端同步", "Waiting for the first remote sync", language: language)
    }

    private func sourceLabel(for source: String) -> String {
        switch source {
        case "dashboard":
            return L10n.text("Dashboard 与计划数据", "Dashboard and plan data", language: language)
        case "plans":
            return L10n.text("今日行动回写", "Today plan writeback", language: language)
        case "coach", "max":
            return "Max"
        case "profile":
            return L10n.text("Profile 偏好", "Profile preferences", language: language)
        default:
            return source
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
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .opacity(0.8)
            }
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .opacity(0.65)
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
        LiquidGlassCard(style: highlighted ? .elevated : .standard, padding: 18) {
            content
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(highlighted ? A10Palette.brand.opacity(0.16) : A10Palette.line.opacity(0.72), lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(highlighted ? 0.12 : 0.06),
            radius: highlighted ? 24 : 16,
            y: highlighted ? 14 : 10
        )
    }
}

private struct A10OverviewMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(tint.opacity(0.16))
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(A10Palette.inkSecondary)
            }

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(A10Palette.ink)
                .lineLimit(2)

            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(A10Palette.inkSecondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(14)
        .background(A10Palette.inset.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            .background(tint.opacity(0.12))
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
            )
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
        GlassButtonStyle(kind: .primary).makeBody(configuration: configuration)
    }
}

private struct A10SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonStyle(kind: .secondary).makeBody(configuration: configuration)
    }
}

private enum A10Palette {
    static let canvas = Color.bgPrimary
    static let surface = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#222426") : UIColor(hex: "#FFFFFF")
    })
    static let surfaceStrong = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#27292C") : UIColor(hex: "#F7F9F3")
    })
    static let inset = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#1A1B1D") : UIColor(hex: "#E8EEE2")
    })
    static let line = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#414547") : UIColor(hex: "#D7DDD2")
    })
    static let ink = Color.textPrimary
    static let inkSecondary = Color.textSecondary
    static let inkTertiary = Color.textTertiary
    static let brand = Color.liquidGlassAccent
    static let brandSecondary = Color.liquidGlassWarm
    static let success = Color.statusSuccess
    static let warning = Color.statusWarning
    static let info = Color.liquidGlassSecondary
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
                        evidenceNote: L10n.text("壳层启动后会用远端证据替换这条占位摘要。", "Shell startup will replace this placeholder summary with remote evidence.", language: language),
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

@MainActor
private final class A10ShellSyncCoordinator: ObservableObject {
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastRemoteSource: String?

    private let supabase = SupabaseManager.shared

    func sync(
        context: ModelContext,
        language: AppLanguage,
        force: Bool,
        trigger: String
    ) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        if force || lastSyncAt == nil {
            await supabase.triggerDailyRecommendations(force: force, language: language.apiCode)
        }

        async let dashboardTask: DashboardData? = loadOptional { [self] in
            try await self.supabase.getDashboardData()
        }
        async let recommendationsTask: [DailyAIRecommendationItem] = loadDefault([]) { [self] in
            try await self.supabase.getDailyRecommendations()
        }
        async let habitsTask: [SupabaseManager.HabitStatus] = loadDefault([]) { [self] in
            try await self.supabase.getHabitsForToday()
        }
        async let profileTask: ProfileSettings? = loadProfileSettings()

        let dashboard = await dashboardTask
        let recommendations = await recommendationsTask
        let habits = await habitsTask
        let profile = await profileTask

        guard dashboard != nil || profile != nil || !recommendations.isEmpty || !habits.isEmpty else {
            lastErrorMessage = "No usable remote data returned."
            return
        }

        do {
            try applyRemoteData(
                dashboard: dashboard,
                recommendations: recommendations,
                habits: habits,
                profile: profile,
                context: context,
                language: language
            )
            lastSyncAt = .now
            lastErrorMessage = nil
            lastRemoteSource = "dashboard"

            await supabase.captureUserSignal(
                domain: "a10_shell",
                action: "remote_hydrated",
                summary: "\(trigger): habits=\(habits.count), recommendations=\(recommendations.count)",
                metadata: [
                    "trigger": trigger,
                    "habits_count": habits.count,
                    "recommendations_count": recommendations.count,
                    "has_dashboard": dashboard != nil,
                    "has_profile": profile != nil
                ]
            )
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func syncPlanToggle(_ plan: A10ActionPlan, context: ModelContext, language: AppLanguage) async {
        guard plan.source == .habit, let remoteID = nonEmpty(plan.remoteID) else { return }

        do {
            try await supabase.setHabitCompletion(habitId: remoteID, isCompleted: plan.isCompleted)
            lastSyncAt = .now
            lastErrorMessage = nil
            lastRemoteSource = "plans"
            await sync(context: context, language: language, force: false, trigger: "habit_toggle")
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func syncPreferences(_ record: A10PreferenceRecord, language: AppLanguage) async {
        let reminders = ReminderPreferences(
            morning: record.notificationsEnabled,
            evening: record.notificationsEnabled,
            breathing: record.notificationsEnabled
        )

        do {
            _ = try await supabase.updateProfileSettings(
                ProfileSettingsUpdate(
                    preferred_language: language.apiCode,
                    reminder_preferences: reminders
                )
            )
            await supabase.captureUserSignal(
                domain: "a10_shell",
                action: "preferences_synced",
                summary: "notifications=\(record.notificationsEnabled), health_sync=\(record.healthSyncEnabled)",
                metadata: [
                    "language": language.rawValue,
                    "notifications_enabled": record.notificationsEnabled,
                    "health_sync_enabled": record.healthSyncEnabled,
                    "daily_check_in_hour": record.dailyCheckInHour
                ]
            )
            lastSyncAt = .now
            lastErrorMessage = nil
            lastRemoteSource = "profile"
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func applyRemoteData(
        dashboard: DashboardData?,
        recommendations: [DailyAIRecommendationItem],
        habits: [SupabaseManager.HabitStatus],
        profile: ProfileSettings?,
        context: ModelContext,
        language: AppLanguage
    ) throws {
        let snapshot = latestSnapshot(in: context) ?? createSnapshot(context: context, language: language)
        let preferences = latestPreferences(in: context) ?? A10SeedData.createPreferences(context: context, language: language)
        let planDrafts = buildPlanDrafts(habits: habits, recommendations: recommendations, language: language)

        if !planDrafts.isEmpty {
            replacePlans(planDrafts, in: context)
        }

        let inferredStage = inferStage(dashboard: dashboard, recommendations: recommendations, habits: habits)
        if Calendar.current.isDate(snapshot.updatedAt, inSameDayAs: .now) {
            snapshot.stage = snapshot.stage.rank >= inferredStage.rank ? snapshot.stage : inferredStage
        } else {
            snapshot.stage = inferredStage
        }

        snapshot.headline = buildHeadline(
            dashboard: dashboard,
            recommendations: recommendations,
            habits: habits,
            profile: profile,
            language: language
        )
        snapshot.summary = buildSummary(
            dashboard: dashboard,
            profile: profile,
            language: language
        )
        snapshot.evidenceNote = buildEvidenceNote(
            dashboard: dashboard,
            language: language
        )

        if let primaryPlan = planDrafts.first(where: { !$0.isCompleted }) ?? planDrafts.first {
            snapshot.nextActionTitle = primaryPlan.title
            snapshot.nextActionDetail = primaryPlan.detail
        }
        snapshot.stressScore = buildStressScore(dashboard: dashboard, habits: habits)
        snapshot.updatedAt = .now

        preferences.languageCode = language.rawValue
        if let reminders = profile?.reminder_preferences {
            preferences.notificationsEnabled = [reminders.morning, reminders.evening, reminders.breathing].contains(true)
        }
        if dashboard?.hardwareData != nil {
            preferences.healthSyncEnabled = true
        }
        preferences.updatedAt = .now

        try context.save()
    }

    private func replacePlans(_ drafts: [A10RemotePlanDraft], in context: ModelContext) {
        let descriptor = FetchDescriptor<A10ActionPlan>(sortBy: [SortDescriptor(\.sortOrder)])
        let existingPlans = (try? context.fetch(descriptor)) ?? []
        for plan in existingPlans {
            context.delete(plan)
        }

        for (index, draft) in drafts.enumerated() {
            context.insert(
                A10ActionPlan(
                    title: draft.title,
                    detail: draft.detail,
                    effortLabel: draft.effortLabel,
                    estimatedMinutes: draft.estimatedMinutes,
                    isCompleted: draft.isCompleted,
                    remoteID: draft.remoteID,
                    sourceRaw: draft.source.rawValue,
                    sortOrder: index,
                    updatedAt: .now
                )
            )
        }
    }

    private func buildPlanDrafts(
        habits: [SupabaseManager.HabitStatus],
        recommendations: [DailyAIRecommendationItem],
        language: AppLanguage
    ) -> [A10RemotePlanDraft] {
        var drafts = habits.map { habit in
            A10RemotePlanDraft(
                title: habit.title,
                detail: nonEmpty(habit.description) ?? defaultHabitDetail(language: language),
                effortLabel: effortLabel(for: habit.minResistanceLevel, language: language),
                estimatedMinutes: estimatedMinutes(forHabitResistance: habit.minResistanceLevel),
                isCompleted: habit.isCompleted,
                remoteID: habit.id,
                source: .habit
            )
        }

        let recommendationDrafts = recommendations.compactMap { item -> A10RemotePlanDraft? in
            let title = nonEmpty(item.action) ?? nonEmpty(item.title) ?? nonEmpty(item.summary)
            guard let title else { return nil }

            let detailParts = [nonEmpty(item.summary), nonEmpty(item.reason)].compactMap { $0 }
            return A10RemotePlanDraft(
                title: title,
                detail: detailParts.isEmpty ? defaultRecommendationDetail(language: language) : detailParts.joined(separator: " "),
                effortLabel: L10n.text("AI 建议", "AI recommendation", language: language),
                estimatedMinutes: estimateMinutes(from: [item.action, item.title, item.summary, item.reason]),
                isCompleted: false,
                remoteID: item.id,
                source: .recommendation
            )
        }

        if drafts.count < 3 {
            let existingTitles = Set(drafts.map(\.title))
            drafts.append(contentsOf: recommendationDrafts.filter { !existingTitles.contains($0.title) })
        }

        return Array(drafts.prefix(6))
    }

    private func buildHeadline(
        dashboard: DashboardData?,
        recommendations: [DailyAIRecommendationItem],
        habits: [SupabaseManager.HabitStatus],
        profile: ProfileSettings?,
        language: AppLanguage
    ) -> String {
        if let focus = nonEmpty(profile?.current_focus ?? profile?.primary_goal) {
            return language == .en
                ? "Start by collapsing today's state around \(focus)."
                : "今天先围绕「\(focus)」收口状态。"
        }

        if let title = nonEmpty(recommendations.first?.title) {
            return title
        }

        if let aiRecommendation = nonEmpty(dashboard?.todayLog?.ai_recommendation) {
            return aiRecommendation
        }

        if let habit = habits.first(where: { !$0.isCompleted }) ?? habits.first {
            return language == .en
                ? "The smallest useful action now is \(habit.title)."
                : "当前最小可执行动作是：\(habit.title)"
        }

        return L10n.text(
            "先让系统知道你今天最难的点。",
            "Let the system understand your hardest point today first.",
            language: language
        )
    }

    private func buildSummary(
        dashboard: DashboardData?,
        profile: ProfileSettings?,
        language: AppLanguage
    ) -> String {
        var parts: [String] = []

        if let focus = nonEmpty(profile?.current_focus) {
            parts.append(language == .en ? "Current focus: \(focus)" : "当前焦点：\(focus)")
        }

        if let stress = dashboard?.todayLog?.anxiety_level ?? dashboard?.todayLog?.stress_level {
            parts.append(language == .en ? "stress \(stress)/10" : "压力 \(stress)/10")
        }

        if let sleepMinutes = dashboard?.todayLog?.sleep_duration_minutes, sleepMinutes > 0 {
            let sleepHours = Double(sleepMinutes) / 60
            let value = String(format: "%.1f", sleepHours)
            parts.append(language == .en ? "sleep \(value)h" : "睡眠 \(value) 小时")
        }

        if let hrv = dashboard?.hardwareData?.hrv?.value {
            parts.append("HRV \(Int(hrv.rounded()))")
        }

        if let readiness = dashboard?.todayLog?.overall_readiness {
            parts.append(language == .en ? "readiness \(readiness)/100" : "就绪度 \(readiness)/100")
        }

        if parts.isEmpty {
            return L10n.text(
                "远端数据尚未补齐时，壳层会继续使用本地闭环状态。",
                "When remote data is still sparse, the shell keeps working from the local loop state.",
                language: language
            )
        }

        return parts.joined(separator: language == .en ? " | " : "｜")
    }

    private func buildEvidenceNote(
        dashboard: DashboardData?,
        language: AppLanguage
    ) -> String {
        var parts: [String] = []

        if let bodyTension = dashboard?.todayLog?.body_tension {
            parts.append(language == .en ? "body tension \(bodyTension)/10" : "身体紧绷 \(bodyTension)/10")
        }

        if let clarity = dashboard?.todayLog?.mental_clarity {
            parts.append(language == .en ? "clarity \(clarity)/10" : "清晰度 \(clarity)/10")
        }

        if let sleepQuality = nonEmpty(dashboard?.todayLog?.sleep_quality) {
            parts.append(language == .en ? "sleep quality \(sleepQuality)" : "睡眠质量 \(sleepQuality)")
        }

        if let scores = dashboard?.clinicalScaleScores, !scores.isEmpty {
            let scoreText = scores
                .sorted { $0.key < $1.key }
                .prefix(2)
                .map { "\($0.key.uppercased()) \($0.value)" }
                .joined(separator: language == .en ? ", " : "，")
            if !scoreText.isEmpty {
                parts.append(scoreText)
            }
        }

        if parts.isEmpty {
            return L10n.text(
                "已接入 Dashboard、Habits 和 Recommendations，等待更多证据样本。",
                "Dashboard, Habits, and Recommendations are connected; waiting for more evidence samples.",
                language: language
            )
        }

        return parts.joined(separator: language == .en ? " | " : "｜")
    }

    private func inferStage(
        dashboard: DashboardData?,
        recommendations: [DailyAIRecommendationItem],
        habits: [SupabaseManager.HabitStatus]
    ) -> A10LoopStage {
        if habits.contains(where: \.isCompleted) {
            return .action
        }
        if !recommendations.isEmpty || nonEmpty(dashboard?.todayLog?.ai_recommendation) != nil {
            return .evidence
        }
        if dashboard?.todayLog != nil || dashboard?.hardwareData != nil || !(dashboard?.clinicalScaleScores?.isEmpty ?? true) {
            return .calibration
        }
        return .inquiry
    }

    private func buildStressScore(
        dashboard: DashboardData?,
        habits: [SupabaseManager.HabitStatus]
    ) -> Int {
        if let value = dashboard?.todayLog?.anxiety_level ?? dashboard?.todayLog?.stress_level ?? dashboard?.todayLog?.body_tension {
            return min(max(value, 1), 10)
        }

        if let scores = dashboard?.clinicalScaleScores?.values, !scores.isEmpty {
            let average = Double(scores.reduce(0, +)) / Double(scores.count)
            let normalized = Int((average / 2.1).rounded())
            return min(max(normalized, 1), 10)
        }

        if habits.contains(where: \.isCompleted) {
            return 4
        }

        return 6
    }

    private func latestSnapshot(in context: ModelContext) -> A10LoopSnapshot? {
        var descriptor = FetchDescriptor<A10LoopSnapshot>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func latestPreferences(in context: ModelContext) -> A10PreferenceRecord? {
        var descriptor = FetchDescriptor<A10PreferenceRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func createSnapshot(context: ModelContext, language: AppLanguage) -> A10LoopSnapshot {
        let snapshot = A10LoopSnapshot(
            headline: L10n.text("先让系统知道你今天最难的点。", "Let the system understand your hardest point today first.", language: language),
            summary: L10n.text("正在把本地壳层和远端数据桥接到一起。", "Bridging the local shell with remote data.", language: language),
            nextActionTitle: L10n.text("等待远端建议", "Waiting for remote guidance", language: language),
            nextActionDetail: L10n.text("如果远端暂时没有返回，系统会继续使用本地闭环。", "If remote data is still unavailable, the shell keeps using the local loop.", language: language),
            evidenceNote: L10n.text("等待第一批远端证据。", "Waiting for the first remote evidence batch.", language: language),
            currentStageRaw: A10LoopStage.inquiry.rawValue,
            stressScore: 6
        )
        context.insert(snapshot)
        return snapshot
    }

    private func effortLabel(for level: Int?, language: AppLanguage) -> String {
        switch level ?? 2 {
        case ...2:
            return L10n.text("低负担", "Low load", language: language)
        case 3:
            return L10n.text("中负担", "Medium load", language: language)
        default:
            return L10n.text("高价值", "High value", language: language)
        }
    }

    private func estimatedMinutes(forHabitResistance level: Int?) -> Int {
        switch level ?? 2 {
        case ...2:
            return 3
        case 3:
            return 5
        default:
            return 8
        }
    }

    private func estimateMinutes(from texts: [String?]) -> Int {
        let pool = texts.compactMap { $0?.lowercased() }.joined(separator: " ")
        if let match = pool.range(of: #"(\d+)\s*(min|mins|minute|minutes|分钟)"#, options: .regularExpression) {
            let fragment = String(pool[match])
            if let value = Int(fragment.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                return value
            }
        }
        return 5
    }

    private func defaultHabitDetail(language: AppLanguage) -> String {
        L10n.text(
            "把这个动作作为今天的低阻力锚点，先完成再决定是否加码。",
            "Use this as today's low-friction anchor before deciding whether to do more.",
            language: language
        )
    }

    private func defaultRecommendationDetail(language: AppLanguage) -> String {
        L10n.text(
            "这是后端根据今日状态整理出来的优先动作。",
            "This is the backend-prioritized action for today's state.",
            language: language
        )
    }

    private func loadProfileSettings() async -> ProfileSettings? {
        do {
            return try await supabase.getProfileSettings()
        } catch {
            return nil
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func loadOptional<T>(_ operation: @escaping () async throws -> T) async -> T? {
        do {
            return try await operation()
        } catch {
            return nil
        }
    }

    private func loadDefault<T>(_ fallback: T, operation: @escaping () async throws -> T) async -> T {
        do {
            return try await operation()
        } catch {
            return fallback
        }
    }
}

private struct A10RemotePlanDraft {
    let title: String
    let detail: String
    let effortLabel: String
    let estimatedMinutes: Int
    let isCompleted: Bool
    let remoteID: String?
    let source: A10PlanSource
}

private extension A10LoopStage {
    var rank: Int {
        switch self {
        case .inquiry:
            return 0
        case .calibration:
            return 1
        case .evidence:
            return 2
        case .action:
            return 3
        }
    }
}

private extension A10Tab {
    var icon: String {
        switch self {
        case .home: return "house"
        case .max: return "bubble.left.and.bubble.right"
        case .me: return "person.crop.circle"
        }
    }

    func title(language: AppLanguage) -> String {
        switch self {
        case .home:
            return L10n.text("Home", "Home", language: language)
        case .max:
            return "Max"
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
                A10MaxSession.self,
                A10MaxMessage.self,
                A10PreferenceRecord.self
            ],
            inMemory: true
        )
}
