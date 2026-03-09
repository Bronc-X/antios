// PlansView.swift
// 计划视图 - 对齐 Web 端

import SwiftUI

struct PlansView: View {
  private enum LightweightEntrySheet: String, Identifiable {
    case journal
    case habits
    case reminders
    case goals

    var id: String { rawValue }
  }

  @StateObject private var viewModel = PlansViewModel()
  @State private var showAddPlan = false
  @State private var showPlanGuide = false
  @State private var isPreparingMaxChat = false
  @State private var lightweightEntrySheet: LightweightEntrySheet?
  @Environment(\.screenMetrics) private var metrics
  @Environment(\.colorScheme) private var colorScheme
  @EnvironmentObject private var appSettings: AppSettings

  var body: some View {
    NavigationStack {
      ZStack {
        AuroraBackground()
            .ignoresSafeArea()

        if viewModel.plans.isEmpty && !viewModel.isLoading {
          ScrollView {
            VStack(spacing: metrics.sectionSpacing) {
              pageHeader
              planHero
              EmptyPlansView(onAdd: { showAddPlan = true })
            }
            .liquidGlassPageWidth()
            .padding(.top, 8)
            .padding(.bottom, metrics.bottomContentInset)
          }
        } else {
          ScrollView {
            LazyVStack(spacing: metrics.isCompactHeight ? 12 : 16) {
              pageHeader
              planHero
              ForEach(viewModel.plans) { plan in
                NavigationLink(destination: PlanDetailView(viewModel: viewModel, plan: plan)) {
                  PlanDataCard(
                    plan: plan,
                    onToggleStatus: {
                      Task { await viewModel.togglePlan(planId: plan.id) }
                    },
                    onToggleItem: { item in
                      var updatedItems = plan.items
                      if let index = updatedItems.firstIndex(where: { $0.id == item.id }) {
                        updatedItems[index].completed.toggle()
                      }

                      let completedCount = updatedItems.filter { $0.completed }.count
                      let status: PlanCompletionStatus
                      if completedCount == updatedItems.count {
                        status = .completed
                      } else if completedCount > 0 {
                        status = .partial
                      } else {
                        status = .skipped
                      }

                      Task {
                        await viewModel.updateItems(planId: plan.id, items: updatedItems, status: status)
                      }
                    },
                    onPauseResume: {
                      Task {
                        if plan.status == .paused {
                          await viewModel.resumePlan(planId: plan.id)
                        } else {
                          await viewModel.pausePlan(planId: plan.id)
                        }
                      }
                    },
                    onArchive: {
                      Task { await viewModel.archivePlan(planId: plan.id) }
                    },
                    onDelete: {
                      Task { await viewModel.deletePlan(planId: plan.id) }
                    }
                  )
                }
                .buttonStyle(.plain)
              }
            }
            .liquidGlassPageWidth()
            .padding(.top, 8)
            .padding(.bottom, metrics.bottomContentInset)
          }
        }

        if viewModel.isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .liquidGlassAccent))
        }
      }
      .navigationTitle("行动计划")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            let impact = UIImpactFeedbackGenerator(style: .soft)
            impact.impactOccurred()
            showPlanGuide = true
          } label: {
            Image(systemName: "questionmark.circle")
              .font(.system(size: 16, weight: .semibold))
              .foregroundColor(.liquidGlassAccent)
              .liquidGlassCircleBadge(padding: 6)
          }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            showAddPlan = true
          } label: {
            HStack(spacing: 6) {
              Image(systemName: "plus")
              Text("新增")
                .font(GlassTypography.cnLovi(13, weight: .medium))
            }
            .foregroundColor(.liquidGlassAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.surfaceGlass(for: colorScheme))
            .clipShape(Capsule())
            .overlay(
              Capsule()
                .stroke(Color.white.opacity(0.24), lineWidth: 1)
            )
          }
        }
      }
      .sheet(isPresented: $showPlanGuide) {
        PlanGuideSheet()
          .presentationDetents([.fraction(0.42), .large])
          .liquidGlassSheetChrome(cornerRadius: 28)
      }
      .sheet(isPresented: $showAddPlan) {
        NavigationStack {
          PlanCreatorView(viewModel: viewModel)
        }
      }
      .sheet(item: $lightweightEntrySheet) { sheet in
        NavigationStack {
          Group {
            switch sheet {
            case .journal:
              ScienceFeedView()
            case .habits:
              HabitsView()
            case .reminders:
              AiRemindersView()
            case .goals:
              GoalsView()
            }
          }
        }
        .presentationDetents([.medium, .large])
        .liquidGlassSheetChrome(cornerRadius: 28)
      }
      .refreshable {
        await viewModel.loadPlans()
        await viewModel.checkQuickEntryHealth(language: appSettings.language)
      }
    }
    .task {
      await viewModel.loadPlans()
      await viewModel.checkQuickEntryHealth(language: appSettings.language)
    }
  }

  private var pageHeader: some View {
    let activeCount = viewModel.plans.filter { $0.status == .active }.count
    let completedCount = viewModel.plans.filter { $0.status == .completed }.count

    return LiquidGlassCard(style: .elevated, padding: 18) {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 6) {
            Text("Plan Surface")
              .font(GlassTypography.caption(12, weight: .semibold))
              .foregroundColor(.liquidGlassAccent)
            Text("行动计划")
              .font(GlassTypography.display(30, weight: .bold))
              .foregroundColor(.textPrimary)
            Text("将 Max 的建议转成可执行动作，并持续跟进完成率")
              .font(.caption)
              .foregroundColor(.textSecondary)
          }
          Spacer()
          StatusPill(text: activeCount > 0 ? "进行中 \(activeCount)" : "待编排", color: activeCount > 0 ? .statusSuccess : .statusWarning)
        }

        HStack(spacing: 10) {
          PlansMetricChip(title: "总计划", value: "\(viewModel.plans.count)", tint: .liquidGlassAccent)
          PlansMetricChip(title: "已完成", value: "\(completedCount)", tint: .statusSuccess)
          PlansMetricChip(title: "入口", value: "Max", tint: .liquidGlassWarm)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, metrics.isCompactHeight ? 6 : 12)
  }

  private var journalEntry: some View {
    Button {
      let impact = UIImpactFeedbackGenerator(style: .soft)
      impact.impactOccurred()
      lightweightEntrySheet = .journal
    } label: {
      quickEntryCard(
        icon: "books.vertical.fill",
        iconColor: .liquidGlassAccent,
        title: "定制科学期刊",
        subtitle: "精选研究与证据解读，支持你的计划执行",
        route: .journal
      )
    }
    .buttonStyle(.plain)
  }

  private var habitsEntry: some View {
    Button {
      let impact = UIImpactFeedbackGenerator(style: .light)
      impact.impactOccurred()
      lightweightEntrySheet = .habits
    } label: {
      quickEntryCard(
        icon: "checkmark.circle",
        iconColor: .statusSuccess,
        title: "习惯追踪",
        subtitle: "记录每日关键动作",
        route: .habits
      )
    }
    .buttonStyle(.plain)
  }

  private var remindersEntry: some View {
    Button {
      let impact = UIImpactFeedbackGenerator(style: .light)
      impact.impactOccurred()
      lightweightEntrySheet = .reminders
    } label: {
      quickEntryCard(
        icon: "bell.badge.fill",
        iconColor: .liquidGlassWarm,
        title: "AI 提醒",
        subtitle: "定制化提醒触达",
        route: .reminders
      )
    }
    .buttonStyle(.plain)
  }

  private var planHero: some View {
    let activeCount = viewModel.plans.filter { $0.status == .active }.count

    return LiquidGlassCard(style: .elevated, padding: 16) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 10) {
          Image(systemName: "sparkles")
            .font(.title3)
            .foregroundColor(.liquidGlassAccent)
          Text("行动编排器")
            .font(.headline)
            .foregroundColor(.textPrimary)
          Spacer()
          if activeCount > 0 {
            StatusPill(text: "活跃 \(activeCount)", color: .statusSuccess)
          }
        }

        Text("让 Max 基于问询、校准和科学证据生成下一步行动，并在这里执行与跟进")
          .font(.caption)
          .foregroundColor(.textSecondary)

        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) {
            Button {
              let impact = UIImpactFeedbackGenerator(style: .medium)
              impact.impactOccurred()
              launchMaxCustomization()
            } label: {
              HStack(spacing: 8) {
                if isPreparingMaxChat {
                  ProgressView()
                    .tint(.white)
                }
                Text("让 Max 生成行动")
              }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
            .disabled(isPreparingMaxChat)

            Button {
              let impact = UIImpactFeedbackGenerator(style: .light)
              impact.impactOccurred()
              showAddPlan = true
            } label: {
              Text("手动补充")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(isProminent: false))
          }

          VStack(spacing: 10) {
            Button {
              let impact = UIImpactFeedbackGenerator(style: .medium)
              impact.impactOccurred()
              launchMaxCustomization()
            } label: {
              HStack(spacing: 8) {
                if isPreparingMaxChat {
                  ProgressView()
                    .tint(.white)
                }
                Text("让 Max 生成行动")
              }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
            .disabled(isPreparingMaxChat)

            Button {
              let impact = UIImpactFeedbackGenerator(style: .light)
              impact.impactOccurred()
              showAddPlan = true
            } label: {
              Text("手动补充")
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(LiquidGlassButtonStyle(isProminent: false))
          }
        }
      }
    }
  }

  private var goalsEntry: some View {
    Button {
      let impact = UIImpactFeedbackGenerator(style: .light)
      impact.impactOccurred()
      lightweightEntrySheet = .goals
    } label: {
      quickEntryCard(
        icon: "target",
        iconColor: .liquidGlassAccent,
        title: "目标管理",
        subtitle: "设定阶段性目标，保持进展可追溯",
        route: .goals
      )
    }
    .buttonStyle(.plain)
  }

  private func quickEntryCard(
    icon: String,
    iconColor: Color,
    title: String,
    subtitle: String,
    route: PlanEntryRoute
  ) -> some View {
    let status = healthStatus(for: route)

    return LiquidGlassCard(style: .standard, padding: 16) {
      HStack(spacing: 12) {
        ZStack {
          RoundedRectangle(cornerRadius: 10)
            .fill(iconColor.opacity(0.15))
            .frame(width: 36, height: 36)
          Image(systemName: icon)
            .font(.system(size: metrics.iconSize))
            .foregroundColor(iconColor)
        }

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 8) {
            Text(title)
              .font(.headline)
              .foregroundColor(.textPrimary)
            Text(status.label)
              .font(.caption2.weight(.semibold))
              .foregroundColor(status.color)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Capsule().fill(status.color.opacity(0.14)))
          }

          Text(subtitle)
            .font(.caption)
            .foregroundColor(.textSecondary)
            .lineLimit(2)
        }

        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: metrics.smallIconSize))
          .foregroundColor(.textTertiary)
      }
    }
  }

  private func healthStatus(for route: PlanEntryRoute) -> (label: String, color: Color) {
    if viewModel.isCheckingEntryHealth && viewModel.entryHealth[route] == nil {
      return ("检测中", .statusWarning)
    }
    if let isHealthy = viewModel.entryHealth[route] {
      return isHealthy ? ("已连接", .statusSuccess) : ("异常", .statusError)
    }
    return ("待检测", .textTertiary)
  }

  private func launchMaxCustomization() {
    guard !isPreparingMaxChat else { return }
    isPreparingMaxChat = true

    Task {
      let prompt = await viewModel.buildMaxCustomizationPrompt(language: appSettings.language)
      await MainActor.run {
        NotificationCenter.default.post(name: .openMaxChat, object: nil)
      }

      DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
        NotificationCenter.default.post(
          name: .askMax,
          object: nil,
          userInfo: ["question": prompt]
        )
        isPreparingMaxChat = false
      }
    }
  }
}

private struct PlansMetricChip: View {
  let title: String
  let value: String
  let tint: Color

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(GlassTypography.caption(11, weight: .semibold))
        .foregroundColor(.textSecondary)
      Text(value)
        .font(GlassTypography.body(15, weight: .semibold))
        .foregroundColor(.textPrimary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.white.opacity(0.1))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(tint.opacity(0.16), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

// MARK: - Plan Data Card

struct PlanDataCard: View {
  let plan: PlanData
  let onToggleStatus: () -> Void
  let onToggleItem: (PlanItemData) -> Void
  let onPauseResume: () -> Void
  let onArchive: () -> Void
  let onDelete: () -> Void

  var isCompleted: Bool {
    plan.status == .completed
  }

  var categoryEnum: PlanCategory {
    PlanCategory(rawValue: plan.category) ?? .general
  }

  var body: some View {
    LiquidGlassCard(padding: 16) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(spacing: 16) {
          Button { onToggleStatus() } label: {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
              .font(.title2)
              .foregroundColor(isCompleted ? .statusSuccess : .textTertiary)
          }

          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
              Text(plan.name)
                .font(.headline)
                .strikethrough(isCompleted)
                .foregroundColor(isCompleted ? .textSecondary : .textPrimary)

              if let difficulty = plan.difficulty {
                DifficultyBadge(difficulty: difficulty)
              }
            }

            if let desc = plan.description, !desc.isEmpty {
              Text(desc)
                .font(.caption)
                .foregroundColor(.textSecondary)
                .lineLimit(2)
            }

            HStack(spacing: 8) {
              CategoryBadge(category: categoryEnum)
              Text("\(plan.progress)%")
                .font(.caption2)
                .foregroundColor(.textSecondary)
            }
          }

          Spacer()

          Menu {
            Button { onPauseResume() } label: {
              Label(plan.status == .paused ? "继续" : "暂停", systemImage: "pause")
            }

            Button { onArchive() } label: {
              Label("归档", systemImage: "archivebox")
            }

            Button(role: .destructive) { onDelete() } label: {
              Label("删除", systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis")
              .foregroundColor(.textTertiary)
          }
        }

        if !plan.items.isEmpty {
          Divider().opacity(0.2)

          VStack(alignment: .leading, spacing: 8) {
            ForEach(plan.items.prefix(5)) { item in
              PlanItemRow(item: item, onToggle: { onToggleItem(item) })
            }

            if plan.items.count > 5 {
              Text("还有 \(plan.items.count - 5) 项")
                .font(.caption2)
                .foregroundColor(.textSecondary)
            }
          }
        }
      }
    }
  }
}

struct PlanItemRow: View {
  let item: PlanItemData
  let onToggle: () -> Void

  var body: some View {
    Button { onToggle() } label: {
      HStack(spacing: 8) {
        Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
          .foregroundColor(item.completed ? .statusSuccess : .textTertiary)
        Text(item.text)
          .font(.subheadline)
          .foregroundColor(item.completed ? .textSecondary : .textPrimary)
          .strikethrough(item.completed)
        Spacer()
      }
    }
    .buttonStyle(.plain)
  }
}

// MARK: - Badges

struct DifficultyBadge: View {
  let difficulty: String

  var body: some View {
    Text(label)
      .font(.caption2.bold())
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.2))
      .foregroundColor(color)
      .clipShape(Capsule())
  }

  private var color: Color {
    switch difficulty {
    case "easy": return .statusSuccess
    case "medium": return .liquidGlassWarm
    case "hard": return .statusError
    default: return .textSecondary
    }
  }

  private var label: String {
    switch difficulty {
    case "easy": return "简单"
    case "medium": return "中等"
    case "hard": return "困难"
    default: return difficulty
    }
  }
}

struct CategoryBadge: View {
  let category: PlanCategory

  var body: some View {
    Text(category.name)
      .font(.caption2.bold())
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(category.color.opacity(0.2))
      .foregroundColor(category.color)
      .clipShape(Capsule())
  }
}

// MARK: - Empty State

struct EmptyPlansView: View {
  let onAdd: () -> Void
  @Environment(\.screenMetrics) private var metrics

  var body: some View {
    let iconSize: CGFloat = metrics.isCompactHeight ? 48 : 60
    return VStack(spacing: metrics.sectionSpacing) {
      Image(systemName: "list.bullet.clipboard")
        .font(.system(size: iconSize))
        .foregroundColor(.textTertiary)

      VStack(spacing: 8) {
        Text("还没有行动任务")
          .font(.title2.bold())
          .foregroundColor(.textPrimary)
        Text("让 Max 把你的焦虑拆成今天能完成的动作")
          .font(.subheadline)
          .foregroundColor(.textSecondary)
      }

      Button("添加行动") { onAdd() }
        .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
    }
  }
}

// MARK: - Add Plan Sheet

struct AddPlanSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var title = ""
  @State private var description = ""
  @State private var category: PlanCategory = .general
  @State private var items: [String] = [""]
  @Environment(\.screenMetrics) private var metrics

  let onAdd: (String, String?, PlanCategory, [String]) -> Void

  var body: some View {
    NavigationStack {
      ZStack {
        AuroraBackground()
        
        ScrollView {
          VStack(spacing: 20) {
            // 计划详情
            VStack(alignment: .leading, spacing: 12) {
              LiquidGlassSectionHeader(title: "计划详情", icon: "doc.text.fill")
              
              LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 16) {
                  LiquidGlassTextField(placeholder: "计划标题", text: $title, icon: "pencil")
                  
                  VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                      Image(systemName: "text.alignleft")
                        .font(.system(size: 14))
                        .foregroundColor(.textSecondary)
                      Text("描述（可选）")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                    }
                    
                    TextEditor(text: $description)
                      .frame(minHeight: 80)
                      .padding(12)
                      .background(Color.surfaceGlass(for: colorScheme))
                      .clipShape(RoundedRectangle(cornerRadius: 14))
                      .overlay(
                        RoundedRectangle(cornerRadius: 14)
                          .stroke(Color.white.opacity(0.2), lineWidth: 1)
                      )
                      .foregroundColor(.textPrimary)
                      .scrollContentBackground(.hidden)
                  }
                }
              }
            }
            
            // 步骤
            VStack(alignment: .leading, spacing: 12) {
              LiquidGlassSectionHeader(title: "步骤", icon: "list.number")
              
              LiquidGlassCard(style: .standard, padding: 16) {
                VStack(spacing: 12) {
                  ForEach(items.indices, id: \.self) { index in
                    HStack(spacing: 12) {
                      ZStack {
                        Circle()
                          .fill(Color.liquidGlassAccent.opacity(0.2))
                          .frame(width: 28, height: 28)
                        Text("\(index + 1)")
                          .font(.caption.bold())
                          .foregroundColor(.liquidGlassAccent)
                      }
                      
                      TextField("步骤内容", text: $items[index])
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.surfaceGlass(for: colorScheme))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                          RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .foregroundColor(.textPrimary)
                      
                      if items.count > 1 {
                        Button {
                          let impact = UIImpactFeedbackGenerator(style: .light)
                          impact.impactOccurred()
                          items.remove(at: index)
                        } label: {
                          Image(systemName: "minus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.statusError.opacity(0.7))
                        }
                      }
                    }
                  }
                  
                  Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    items.append("")
                  } label: {
                    HStack(spacing: 8) {
                      Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                      Text("添加步骤")
                        .font(.subheadline)
                    }
                    .foregroundColor(.liquidGlassAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.liquidGlassAccent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                      RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.liquidGlassAccent.opacity(0.3), lineWidth: 1)
                    )
                  }
                }
              }
            }
            
            // 分类
            VStack(alignment: .leading, spacing: 12) {
              LiquidGlassSectionHeader(title: "分类", icon: "tag.fill")
              
              LiquidGlassCard(style: .standard, padding: 16) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                  ForEach(PlanCategory.allCases, id: \.self) { cat in
                    Button {
                      let impact = UIImpactFeedbackGenerator(style: .light)
                      impact.impactOccurred()
                      category = cat
                    } label: {
                      HStack(spacing: 8) {
                        Circle()
                          .fill(cat.color)
                          .frame(width: 8, height: 8)
                        Text(cat.name)
                          .font(.subheadline)
                      }
                      .foregroundColor(category == cat ? .bgPrimary : .textSecondary)
                      .frame(maxWidth: .infinity)
                      .padding(.vertical, 12)
                      .background(
                        category == cat
                          ? cat.color
                          : Color.surfaceGlass(for: colorScheme)
                      )
                      .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                  }
                }
              }
            }
          }
          .liquidGlassPageWidth()
          .padding(.vertical, metrics.verticalPadding)
        }
      }
      .navigationTitle("添加计划")
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") { 
            dismiss() 
          }
          .foregroundColor(.liquidGlassAccent)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("添加") {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            let cleanedItems = items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty }
            onAdd(title, description.isEmpty ? nil : description, category, cleanedItems)
            dismiss()
          }
          .font(.headline)
          .foregroundColor(isFormValid ? .liquidGlassAccent : .textTertiary)
          .disabled(!isFormValid)
        }
      }
    }
  }

  private var isFormValid: Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
      items.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
}

// MARK: - Plan Category

enum PlanCategory: String, CaseIterable {
  case general
  case exercise
  case diet
  case sleep
  case mental

  var name: String {
    switch self {
    case .general: return "通用"
    case .exercise: return "运动"
    case .diet: return "饮食"
    case .sleep: return "睡眠"
    case .mental: return "心理"
    }
  }

  var color: Color {
    switch self {
    case .general: return .gray
    case .exercise: return .liquidGlassPrimary
    case .diet: return .liquidGlassWarm
    case .sleep: return .indigo
    case .mental: return .purple
    }
  }
}

private struct PlanGuideSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ZStack {
      AuroraBackground()
        .ignoresSafeArea()

      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("行动页说明")
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

        planBullet("优先让 Max 生成行动，再根据你实际情况手动微调。")
        planBullet("每个计划保持 3-5 步，执行门槛最低时完成率最高。")
        planBullet("完成后回到对话页复盘，系统会自动更新下一步建议。")

        Spacer(minLength: 0)
      }
      .padding(20)
    }
  }

  private func planBullet(_ text: String) -> some View {
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

// MARK: - Preview

struct PlansView_Previews: PreviewProvider {
  static var previews: some View {
    PlansView()
      .preferredColorScheme(.dark)
      .environmentObject(AppSettings())
  }
}
