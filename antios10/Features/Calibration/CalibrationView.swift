// CalibrationView.swift
// 校准视图 - 对齐 Web 端

import SwiftUI

struct CalibrationView: View {
  @StateObject private var viewModel = CalibrationViewModel()
  @Environment(\.dismiss) private var dismiss
  @Environment(\.screenMetrics) private var metrics
  let autoStart: Bool
  @State private var hasAutoStarted = false

  init(autoStart: Bool = false) {
    self.autoStart = autoStart
  }

  var body: some View {
    ZStack {
      AuroraBackground()

      VStack(spacing: 0) {
        header

        Group {
          switch viewModel.step {
          case .welcome:
            if viewModel.shouldShowToday || viewModel.hasCompletedToday {
              WelcomeStep(
                hasCompletedToday: viewModel.hasCompletedToday,
                onStart: { await viewModel.start() }
              )
            } else {
              RestDayStep()
            }
          case .questions:
            if let question = viewModel.currentQuestion {
              QuestionStep(
                question: question,
                progress: viewModel.progressPercent / 100,
                onAnswer: { value in
                  viewModel.answerQuestion(questionId: question.id, value: value)
                }
              )
            }
          case .analyzing:
            AnalyzingStep()
          case .result:
            if let result = viewModel.result {
              ResultStep(
                summary: result,
                onDismiss: {
                  viewModel.reset()
                  dismiss()
                }
              )
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, metrics.horizontalPadding)
      }
    }
    .navigationBarHidden(true)
    .animation(.spring(response: 0.4), value: viewModel.step)
    .task {
      await viewModel.checkFrequency()
    }
    .task {
      guard autoStart, !hasAutoStarted else { return }
      hasAutoStarted = true
      await viewModel.start()
    }
  }

  private var header: some View {
    LiquidGlassCard(style: .elevated, padding: 18) {
      VStack(alignment: .leading, spacing: metrics.isCompactHeight ? 10 : 14) {
        Button {
          dismiss()
        } label: {
          Image(systemName: "chevron.left")
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.textPrimary)
            .frame(width: 42, height: 42)
            .background(Color.textPrimary.opacity(0.12))
            .clipShape(Circle())
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 6) {
          Text("每日状态")
            .font(.caption.weight(.semibold))
            .foregroundColor(.liquidGlassAccent)
          Text("状态记录")
            .font(.system(size: metrics.isCompactWidth ? 48 : 56, weight: .bold, design: .rounded))
            .foregroundColor(.textPrimary)
          Text("每天花一分钟，记下现在的状态。")
            .font(.caption)
            .foregroundColor(.textSecondary)
        }
      }
    }
    .padding(.leading, metrics.horizontalPadding)
    .padding(.trailing, metrics.horizontalPadding)
    .padding(.top, metrics.safeAreaInsets.top + (metrics.isCompactHeight ? 4 : 8))
    .padding(.bottom, metrics.isCompactHeight ? 8 : 12)
  }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
  let hasCompletedToday: Bool
  let onStart: @MainActor () async -> Void
  @Environment(\.screenMetrics) private var metrics
  @State private var isStarting = false

  var body: some View {
    VStack(spacing: 32) {
      Spacer()

      LiquidGlassCard(style: .elevated, padding: 24) {
        VStack(spacing: 20) {
          ZStack {
            PulsingRingsView(color: .liquidGlassAccent)
              .frame(width: metrics.ringLarge, height: metrics.ringLarge)
            Image(systemName: "brain.head.profile")
              .font(.system(size: metrics.isCompactWidth ? 48 : 60))
              .foregroundColor(.liquidGlassAccent)
          }
          .offset(x: -2)

          VStack(spacing: 12) {
            if hasCompletedToday {
              Text("今日已完成")
                .font(.title.bold())
              Text("你今天已经记录过状态")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            } else {
              Text("准备好了吗？")
                .font(.title.bold())
              Text("记录一下状态，Max 才能更贴近你")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            }
          }
        }
      }
      .padding(.horizontal, metrics.horizontalPadding)

      Spacer()

      let buttonWidth = min(metrics.maxContentWidth, metrics.isCompactWidth ? 240 : 280)
      if hasCompletedToday {
        Button("再次记录") {
          guard !isStarting else { return }
          isStarting = true
          Task { @MainActor in
            await onStart()
            isStarting = false
          }
        }
          .buttonStyle(LiquidGlassButtonStyle(isProminent: false))
          .disabled(isStarting)
          .frame(maxWidth: buttonWidth)
          .frame(maxWidth: .infinity, alignment: .center)
      } else {
        Button("开始记录") {
          guard !isStarting else { return }
          isStarting = true
          Task { @MainActor in
            await onStart()
            isStarting = false
          }
        }
          .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
          .disabled(isStarting)
          .frame(maxWidth: buttonWidth)
          .frame(maxWidth: .infinity, alignment: .center)
      }

      Spacer()
    }
    .padding(.vertical, metrics.verticalPadding)
  }
}

struct RestDayStep: View {
  @Environment(\.screenMetrics) private var metrics

  var body: some View {
    VStack(spacing: 24) {
      Spacer()

      LiquidGlassCard(style: .standard, padding: 24) {
        VStack(spacing: 14) {
          Image(systemName: "sparkles")
            .font(.system(size: metrics.isCompactWidth ? 40 : 48))
            .foregroundColor(.liquidGlassAccent)

          VStack(spacing: 8) {
            Text("今天先不用记录")
              .font(.title.bold())
            Text("根据当前频率安排，明天再来吧。")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }
      }
      .padding(.horizontal, metrics.horizontalPadding)

      Spacer()
    }
    .padding(.vertical, metrics.verticalPadding)
  }
}

// MARK: - Question Step

struct QuestionStep: View {
  let question: CalibrationQuestion
  let progress: Double
  let onAnswer: @MainActor (Int) -> Void
  @Environment(\.screenMetrics) private var metrics

  var body: some View {
    VStack(spacing: 24) {
      ProgressView(value: progress)
        .tint(.liquidGlassAccent)
        .padding(.horizontal, metrics.horizontalPadding)

      Spacer()

      LiquidGlassCard {
        VStack(spacing: 20) {
          Text(question.text)
            .font(.title3)
            .multilineTextAlignment(.center)

          if question.type == .slider {
            SliderView(question: question, onAnswer: onAnswer)
          } else if let options = question.options {
            VStack(spacing: 12) {
              ForEach(options) { option in
                Button {
                  onAnswer(option.value)
                } label: {
                  Text(option.label)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(LiquidGlassButtonStyle())
              }
            }
          }
        }
      }
      .padding(.horizontal)

      Spacer()
    }
  }
}

struct SliderView: View {
  let question: CalibrationQuestion
  let onAnswer: @MainActor (Int) -> Void
  @State private var value: Double = 5

  var body: some View {
    VStack(spacing: 24) {
      // 滑块值显示
      VStack(spacing: 4) {
        Text(String(format: "%.0f", value))
          .font(.system(size: 48, weight: .bold, design: .rounded))
          .foregroundColor(.liquidGlassAccent)
        
        Text(sliderDescription)
          .font(.caption)
          .foregroundColor(.textSecondary)
      }
      
      // 滑块
      GeometryReader { geo in
        let width = geo.size.width
        let minVal = Double(question.min ?? 0)
        let maxVal = Double(question.max ?? 10)
        let progress = (value - minVal) / (maxVal - minVal)
        
        ZStack(alignment: .leading) {
          // 背景轨道
          Capsule()
            .fill(Color.white.opacity(0.1))
            .frame(height: 10)
          
          // 进度轨道
          Capsule()
            .fill(
              LinearGradient(colors: [.liquidGlassAccent.opacity(0.6), .liquidGlassAccent], startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: max(0, width * progress), height: 10)
            .shadow(color: .liquidGlassAccent.opacity(0.4), radius: 8)
          
          // 滑块
          Circle()
            .fill(Color.liquidGlassAccent)
            .frame(width: 28, height: 28)
            .shadow(color: .liquidGlassAccent.opacity(0.6), radius: 10)
            .overlay(
              Circle()
                .stroke(Color.white.opacity(0.4), lineWidth: 2)
            )
            .offset(x: max(0, min(width - 28, width * progress - 14)))
            .gesture(
              DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                  let newProgress = gesture.location.x / width
                  let newValue = minVal + (maxVal - minVal) * min(max(newProgress, 0), 1)
                  value = newValue.rounded()
                }
                .onEnded { _ in
                  let impact = UIImpactFeedbackGenerator(style: .light)
                  impact.impactOccurred()
                }
            )
        }
      }
      .frame(height: 32)
      
      // 刻度标签
      HStack {
        Text(String(format: "%.0f", Double(question.min ?? 0)))
          .font(.caption2)
          .foregroundColor(.textTertiary)
        Spacer()
        Text(String(format: "%.0f", Double(question.max ?? 10)))
          .font(.caption2)
          .foregroundColor(.textTertiary)
      }

      Button("继续") {
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        onAnswer(Int(value))
      }
      .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
    }
    .onAppear {
      value = Double(question.min ?? 0) + Double((question.max ?? 10) - (question.min ?? 0)) / 2
    }
  }
  
  private var sliderDescription: String {
    let intValue = Int(value)
    if intValue <= 3 {
      return "较低"
    } else if intValue <= 6 {
      return "中等"
    } else {
      return "较高"
    }
  }
}

// MARK: - Analyzing Step

struct AnalyzingStep: View {
  @Environment(\.screenMetrics) private var metrics

  var body: some View {
    VStack(spacing: 32) {
      LiquidGlassCard(style: .elevated, padding: 24) {
        VStack(spacing: 20) {
          ZStack {
            PulsingRingsView(color: .liquidGlassPrimary)
              .frame(width: metrics.isCompactHeight ? 160 : 200, height: metrics.isCompactHeight ? 160 : 200)
            Image(systemName: "brain")
              .font(.system(size: metrics.isCompactWidth ? 40 : 50))
              .foregroundColor(.liquidGlassPrimary)
          }

          VStack(spacing: 8) {
            Text("分析中...")
              .font(.title2.bold())
            Text("Max 正在理解你的状态")
              .font(.subheadline)
              .foregroundColor(.secondary)
          }
        }
      }
      .padding(.horizontal, metrics.horizontalPadding)
    }
  }
}

// MARK: - Result Step

struct ResultStep: View {
  let summary: DailyCalibrationResult
  let onDismiss: @MainActor () -> Void
  @Environment(\.screenMetrics) private var metrics

  var statusText: String {
    switch summary.dailyIndex {
    case 0...3: return "优秀"
    case 4...7: return "良好"
    case 8...10: return "一般"
    default: return "需关注"
    }
  }

  var statusColor: Color {
    switch summary.dailyIndex {
    case 0...3: return .statusSuccess
    case 4...7: return .liquidGlassAccent
    case 8...10: return .statusWarning
    default: return .statusError
    }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        ZStack {
          ProgressRingView(progress: Double(summary.dailyIndex) / 12.0, lineWidth: 12, color: statusColor)
            .frame(width: metrics.isCompactHeight ? 120 : 140, height: metrics.isCompactHeight ? 120 : 140)
          VStack(spacing: 4) {
            Text("\(summary.dailyIndex)")
              .font(.system(size: 44, weight: .bold))
            Text("/ 12")
              .font(.caption)
              .foregroundColor(.secondary)
          }
        }

        StatusPill(text: statusText, color: statusColor)

        if summary.savedToCloud {
          HStack {
            Image(systemName: "checkmark.icloud.fill")
              .foregroundColor(.statusSuccess)
            Text("已同步到云端")
              .font(.caption)
              .foregroundColor(.textSecondary)
          }
        }

        if let trigger = summary.triggerFullScale {
          HStack {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.statusWarning)
            Text("建议完成 \(trigger) 量表")
              .font(.caption)
              .foregroundColor(.textSecondary)
          }
        }

        if summary.safetyTriggered {
          LiquidGlassCard(style: .concave, padding: 16) {
            HStack(alignment: .top, spacing: 12) {
              Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.statusWarning)
              VStack(alignment: .leading, spacing: 6) {
                Text("安全提醒")
                  .font(.headline)
                Text("检测到需要关注的回答，建议尽快寻求支持或使用危机资源。")
                  .font(.caption)
                  .foregroundColor(.textSecondary)
              }
            }
          }
        }

        if let stability = summary.stability {
          LiquidGlassCard {
            VStack(alignment: .leading, spacing: 12) {
              Text("稳定性评估")
                .font(.headline)
              Text("完成率：\(Int(stability.completionRate * 100))%  · 平均得分：\(String(format: "%.1f", stability.averageScore))")
                .font(.caption)
                .foregroundColor(.textSecondary)
              Text("建议频率：\(frequencyLabel(stability.recommendation))")
                .font(.caption)
                .foregroundColor(.textSecondary)
              if stability.hasRedFlag {
                Text("风险提示：\(stability.redFlagReasons.joined(separator: "、"))")
                  .font(.caption2)
                  .foregroundColor(.statusWarning)
              }
            }
          }
        }

        Button("完成") { onDismiss() }
          .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
          .padding(.top)
      }
      .padding()
    }
  }

  private func frequencyLabel(_ value: String) -> String {
    switch value {
    case "every_other_day": return "隔日"
    case "increase_to_daily": return "每日"
    default: return "每日"
    }
  }
}

// MARK: - Preview

struct CalibrationView_Previews: PreviewProvider {
  static var previews: some View {
    CalibrationView()
      .preferredColorScheme(.dark)
  }
}
