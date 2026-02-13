// DigitalTwinView.swift
// 数字孪生曲线主视图

import SwiftUI
import Charts

struct DigitalTwinView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = DigitalTwinViewModel()
    @State private var isClinicalPresented = false
    @State private var selectedTrendMetric: DigitalTwinTrendMetric = .mood
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            FluidBackground()

            VStack(spacing: 0) {
                header
                content
            }

            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(1.1)
                    .progressViewStyle(CircularProgressViewStyle(tint: .liquidGlassAccent))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(x: metrics.centerAxisOffset)
            }
        }
        .navigationBarHidden(true)
        .task {
            if viewModel.curveData == nil {
                await viewModel.generateCurve()
            }
        }
        .navigationDestination(for: DigitalTwinMetricKey.self) { metricKey in
            if let curveData = viewModel.curveData {
                DigitalTwinDetailView(curveData: curveData, metricKey: metricKey)
            }
        }
        .fullScreenCover(isPresented: $isClinicalPresented, onDismiss: {
            Task { await viewModel.generateCurve() }
        }) {
            ClinicalOnboardingView(isComplete: $isClinicalPresented)
        }
    }

    private var header: some View {
        let sideSlotWidth: CGFloat = 44
        return ZStack {
            HStack(spacing: 0) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.textPrimary.opacity(0.1))
                        .clipShape(Circle())
                }
                .frame(width: sideSlotWidth, alignment: .leading)
                Spacer()
                Button {
                    Task { await viewModel.refreshCurve() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(Color.textPrimary.opacity(0.1))
                        .clipShape(Circle())
                }
                .frame(width: sideSlotWidth, alignment: .trailing)
            }

            VStack(spacing: 2) {
                Text("数字孪生")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                if let ruleVersion = viewModel.curveData?.meta.ruleVersion {
                    Text("\(L10n.runtime("规则版本")) \(L10n.runtime(ruleVersion))")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(x: metrics.centerAxisOffset)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.isCompactHeight ? 10 : 14)
        .padding(.top, metrics.safeAreaInsets.top)
        .background(Color.textPrimary.opacity(0.05))
    }

    @ViewBuilder
    private var content: some View {
        if let curveData = viewModel.curveData {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = viewModel.error {
                        errorBanner(message: error)
                    }

                    if !curveData.dataQualityStatus().isGood {
                        dataQualityBanner(curveData)
                    }

                    summaryStats(curveData.metricEndpoints.summaryStats)

                    curveChart(
                        timepoints: curveData.predictedLongitudinalOutcomes.timepoints,
                        selectedMetric: selectedTrendMetric,
                        currentWeek: curveData.meta.currentWeek
                    )

                    metricGrid(curveData: curveData)

                    timelineView(
                        milestones: curveData.timeSinceBaselineVisit.milestones,
                        currentWeek: curveData.meta.currentWeek
                    )

                    baselineScales(curveData.participantBaselineData.scales)
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
                .padding(.bottom, metrics.isCompactHeight ? 16 : 24)
            }
            .refreshable {
                await viewModel.refreshCurve()
            }
        } else if let error = viewModel.error {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.statusWarning)
                Text(L10n.runtime(error))
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                
                // 如果是缺少基线数据，显示评估入口
                if viewModel.needsBaseline {
                    Button {
                        isClinicalPresented = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "list.clipboard.fill")
                            Text("完成基础量表")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.liquidGlassAccent)
                        .cornerRadius(12)
                    }
                } else {
                    Button("重试") {
                        Task { await viewModel.generateCurve() }
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                }
            }
            .padding()
        } else {
            digitalTwinSkeleton
        }
    }

    private var digitalTwinSkeleton: some View {
        ScrollView {
            VStack(spacing: 16) {
                skeletonSummaryRow
                skeletonChart
                skeletonGrid
                skeletonCard(title: "里程碑")
                skeletonCard(title: "基线量表")
            }
            .liquidGlassPageWidth()
            .padding(.vertical, metrics.verticalPadding)
            .padding(.bottom, metrics.isCompactHeight ? 16 : 24)
        }
    }

    private var skeletonSummaryRow: some View {
        HStack(spacing: 12) {
            skeletonStatCard(title: "整体改善")
            skeletonStatCard(title: "首次见效")
            skeletonStatCard(title: "坚持度")
        }
    }

    private func skeletonStatCard(title: String) -> some View {
        LiquidGlassCard(style: .concave, padding: 12) {
            VStack(spacing: 8) {
                Text(L10n.localized(title))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.textPrimary.opacity(0.1))
                    .frame(height: 18)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var skeletonChart: some View {
        LiquidGlassCard(style: .standard, padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("预测曲线")
                    .font(.headline)
                    .foregroundColor(.textPrimary)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.textPrimary.opacity(0.08))
                    .frame(height: 200)
            }
        }
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            skeletonCard(title: "焦虑评分")
            skeletonCard(title: "睡眠质量")
            skeletonCard(title: "情绪稳定")
            skeletonCard(title: "能量水平")
        }
    }

    private func skeletonCard(title: String) -> some View {
        LiquidGlassCard(style: .standard, padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.localized(title))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.textPrimary.opacity(0.1))
                    .frame(height: 20)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.textPrimary.opacity(0.06))
                    .frame(height: 14)
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.statusWarning)
            Text(L10n.runtime(message))
                .font(.caption)
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(12)
        .background(Color.statusWarning.opacity(0.2))
        .cornerRadius(14)
    }

    private func dataQualityBanner(_ curveData: DigitalTwinCurveOutput) -> some View {
        let status = curveData.dataQualityStatus()
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.statusWarning)
            VStack(alignment: .leading, spacing: 4) {
                Text("数据质量提示")
                    .font(.caption)
                    .foregroundColor(.statusWarning)
                ForEach(status.warnings.prefix(2), id: \.self) { warning in
                    Text("• \(L10n.runtime(warning))")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.statusWarning.opacity(0.15))
        .cornerRadius(14)
    }

    private func summaryStats(_ stats: DigitalTwinCurveSummaryStats) -> some View {
        HStack(spacing: 12) {
            summaryStatCard(title: "整体改善", value: stats.overallImprovement.value, suffix: "分", color: .statusSuccess, prefixPlus: true)
            summaryStatCard(title: "首次见效", value: stats.daysToFirstResult.value, suffix: "天", color: .liquidGlassAccent, prefixPlus: false)
            summaryStatCard(title: "坚持度", value: stats.consistencyScore.value, suffix: "%", color: .liquidGlassPurple, prefixPlus: false)
        }
    }

    private func summaryStatCard(title: String, value: Double?, suffix: String, color: Color, prefixPlus: Bool) -> some View {
        LiquidGlassCard(style: .concave, padding: 12) {
            VStack(spacing: 6) {
                Text(L10n.localized(title))
                    .font(.caption2)
                    .foregroundColor(.textSecondary)
                Text(displayValue(value, suffix: suffix, prefixPlus: prefixPlus))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(color)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func curveChart(
        timepoints: [DigitalTwinCurveTimepoint],
        selectedMetric: DigitalTwinTrendMetric,
        currentWeek: Int?
    ) -> some View {
        let sorted = timepoints.sorted { $0.week < $1.week }
        let maxWeek = max(sorted.last?.week ?? 0, 1)
        let current = currentWeek ?? sorted.last?.week ?? 0
        let splitIndex = max(0, sorted.lastIndex(where: { $0.week <= current }) ?? max(sorted.count - 2, 0))
        let historyPoints = Array(sorted.prefix(splitIndex + 1))
        let predictionPoints = Array(sorted.suffix(from: splitIndex))

        let historySeries = historyPoints.map { point in
            DigitalTwinTrendPoint(
                week: point.week,
                day: normalizedDay(for: point.week, maxWeek: maxWeek),
                value: selectedMetric.value(in: point.metrics),
                lowerBound: nil,
                upperBound: nil,
                source: .historical
            )
        }
        let predictionSeries = predictionPoints.enumerated().map { index, point in
            let value = selectedMetric.value(in: point.metrics)
            let interval = selectedMetric.predictionInterval(step: index)
            return DigitalTwinTrendPoint(
                week: point.week,
                day: normalizedDay(for: point.week, maxWeek: maxWeek),
                value: value,
                lowerBound: max(0, value - interval),
                upperBound: min(100, value + interval),
                source: .prediction
            )
        }
        let trendStatus = trendStatus(metric: selectedMetric, history: historySeries, prediction: predictionSeries)

        return LiquidGlassCard(style: .standard, padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("未来 7 天预测")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                    Spacer()
                    Picker("指标", selection: $selectedTrendMetric) {
                        ForEach(DigitalTwinTrendMetric.allCases) { metric in
                            Text(metric.label).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                }

                Chart {
                    ForEach(historySeries) { point in
                        LineMark(
                            x: .value("Day", point.day),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(Color.textPrimary.opacity(0.86))
                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Day", point.day),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(Color.textPrimary.opacity(0.86))
                        .symbolSize(30)
                    }

                    ForEach(predictionSeries) { point in
                        if let lower = point.lowerBound, let upper = point.upperBound {
                            AreaMark(
                                x: .value("Day", point.day),
                                yStart: .value("Lower", lower),
                                yEnd: .value("Upper", upper)
                            )
                            .foregroundStyle(trendStatus.shadeColor.opacity(0.2))
                        }
                    }

                    ForEach(predictionSeries) { point in
                        LineMark(
                            x: .value("Day", point.day),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(trendStatus.shadeColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: Array(0...7)) { value in
                        AxisGridLine().foregroundStyle(Color.textPrimary.opacity(0.1))
                        AxisValueLabel {
                            if let day = value.as(Int.self) {
                                Text("D\(day)")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.textPrimary.opacity(0.1))
                        AxisValueLabel {
                            if let val = value.as(Int.self) {
                                Text("\(val)")
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }
                }
                .frame(height: 210)
                .clipped()

                HStack(spacing: 16) {
                    chartLegendDot(color: Color.textPrimary.opacity(0.86), text: "历史数据")
                    chartLegendDot(color: trendStatus.shadeColor, text: "预测值")
                    Spacer()
                    Text(trendStatus.label)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(trendStatus.shadeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(trendStatus.shadeColor.opacity(0.16))
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func chartLegendDot(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.caption2)
                .foregroundColor(.textSecondary)
        }
    }

    private func normalizedDay(for week: Int, maxWeek: Int) -> Int {
        guard maxWeek > 0 else { return 0 }
        let day = Int(round((Double(week) / Double(maxWeek)) * 7.0))
        return max(0, min(7, day))
    }

    private func trendStatus(
        metric: DigitalTwinTrendMetric,
        history: [DigitalTwinTrendPoint],
        prediction: [DigitalTwinTrendPoint]
    ) -> DigitalTwinTrendStatus {
        let currentValue = history.last?.value ?? prediction.first?.value ?? 0
        let forecastValue = prediction.last?.value ?? currentValue
        let rawDelta = forecastValue - currentValue
        let normalizedDelta = metric.isNegative ? -rawDelta : rawDelta

        if metric.isEmergency(currentValue: currentValue, normalizedDelta: normalizedDelta) {
            return DigitalTwinTrendStatus(
                label: "紧急",
                shadeColor: .red
            )
        }
        if normalizedDelta > 4 {
            return DigitalTwinTrendStatus(
                label: "向好",
                shadeColor: .green
            )
        }
        return DigitalTwinTrendStatus(
            label: "持平",
            shadeColor: .yellow
        )
    }

    private func metricGrid(curveData: DigitalTwinCurveOutput) -> some View {
        let timepoints = curveData.predictedLongitudinalOutcomes.timepoints
        let week0 = timepoints.first
        let currentWeek = curveData.meta.currentWeek ?? 0
        let targetWeek = (currentWeek / 3) * 3
        let current = timepoints.first { $0.week == targetWeek } ?? week0

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach([DigitalTwinMetricKey.anxietyScore, .sleepQuality, .moodStability, .energyLevel]) { metric in
                NavigationLink(value: metric) {
                    digitalTwinMetricCard(
                        metric: metric,
                        current: current?.metrics,
                        week0: week0?.metrics
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func digitalTwinMetricCard(metric: DigitalTwinMetricKey, current: DigitalTwinTimepointMetrics?, week0: DigitalTwinTimepointMetrics?) -> some View {
        let currentValue = current.map { metric.prediction(in: $0).value } ?? 0
        let confidence = current.map { metric.prediction(in: $0).confidence } ?? "±8.0"
        let week0Value = week0.map { metric.prediction(in: $0).value } ?? currentValue

        let trend: String
        if metric.isNegative {
            trend = currentValue < week0Value ? "改善" : currentValue > week0Value ? "需关注" : "稳定"
        } else {
            trend = currentValue > week0Value ? "改善" : currentValue < week0Value ? "需关注" : "稳定"
        }

        let trendColor: Color
        switch trend {
        case "改善": trendColor = .statusSuccess
        case "需关注": trendColor = .statusWarning
        default: trendColor = .textSecondary
        }

        return LiquidGlassCard(style: .concave, padding: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: metric.systemImage)
                        .foregroundColor(metric.color)
                    Spacer()
                    Text(L10n.runtime(trend))
                        .font(.caption2)
                        .foregroundColor(trendColor)
                }

                Text(metric.label)
                    .font(.caption)
                    .foregroundColor(.textSecondary)

                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(String(format: "%.1f", currentValue))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("/ 100")
                        .font(.caption2)
                        .foregroundColor(.textTertiary)
                }

                Text("\(L10n.runtime("置信区间")) \(L10n.runtime(confidenceSuffix(confidence)))")
                    .font(.caption2)
                    .foregroundColor(.textTertiary)
            }
        }
    }

    private func timelineView(milestones: [DigitalTwinTimelineMilestone], currentWeek: Int?) -> some View {
        LiquidGlassCard(style: .standard, padding: 12) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundColor(.textSecondary)
                    Text("进度时间线")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                }

                GeometryReader { geo in
                    let width = geo.size.width
                    let progress = min(max(Double(currentWeek ?? 0) / 15.0, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.textPrimary.opacity(0.1))
                            .frame(height: 4)
                        Capsule()
                            .fill(LinearGradient(colors: [.liquidGlassAccent, .liquidGlassPurple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: width * progress, height: 4)
                    }
                }
                .frame(height: 10)
                .clipped() // 防护：确保进度条不溢出容器

                HStack(spacing: 0) {
                    ForEach(milestones) { milestone in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(milestoneColor(milestone.status))
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .stroke(Color.bgPrimary.opacity(milestone.status == .current ? 0.6 : 0), lineWidth: 4)
                                )
                            Text("W\(milestone.week)")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                if let current = milestones.first(where: { $0.status == .current }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.runtime(current.event))
                            .font(.subheadline)
                            .foregroundColor(.liquidGlassAccent)
                        Text(L10n.runtime(current.detail))
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .padding(10)
                    .background(Color.liquidGlassAccent.opacity(0.1))
                    .cornerRadius(12)
                }
            }
        }
    }

    private func baselineScales(_ scales: [DigitalTwinScaleBaselineItem]) -> some View {
        LiquidGlassCard(style: .standard, padding: 12) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.textSecondary)
                    Text("基线量表")
                        .font(.headline)
                        .foregroundColor(.textPrimary)
                }

                if scales.isEmpty {
                    Text("暂无基线量表数据")
                        .font(.caption)
                        .foregroundColor(.textSecondary)
                } else {
                    ForEach(scales) { scale in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L10n.runtime(scale.name))
                                    .font(.subheadline)
                                    .foregroundColor(.textPrimary)
                                Text(L10n.runtime(scale.interpretation))
                                    .font(.caption2)
                                    .foregroundColor(.textSecondary)
                            }
                            Spacer()
                            Text(scale.value.map { String(format: "%.0f", $0) } ?? "N/A")
                                .font(.headline)
                                .foregroundColor(.textPrimary)
                        }
                        if scale.id != scales.last?.id {
                            Divider().background(Color.textPrimary.opacity(0.1))
                        }
                    }
                }
            }
        }
    }

    private func displayValue(_ value: Double?, suffix: String, prefixPlus: Bool) -> String {
        guard let value = value else { return "N/A" }
        let formatted = String(format: "%.1f", value)
        let prefix = prefixPlus ? "+" : ""
        return L10n.runtime("\(prefix)\(formatted)\(suffix)")
    }

    private func confidenceSuffix(_ confidence: String) -> String {
        let parts = confidence.components(separatedBy: "±")
        if parts.count > 1 {
            return "±\(parts[1].trimmingCharacters(in: .whitespaces))"
        }
        return confidence
    }

    private func milestoneColor(_ status: DigitalTwinMilestoneStatus) -> Color {
        switch status {
        case .completed: return .statusSuccess
        case .current: return .liquidGlassAccent
        case .upcoming: return .textTertiary
        }
    }
}

private enum DigitalTwinTrendSource {
    case historical
    case prediction
}

private struct DigitalTwinTrendPoint: Identifiable {
    let week: Int
    let day: Int
    let value: Double
    let lowerBound: Double?
    let upperBound: Double?
    let source: DigitalTwinTrendSource

    var id: String {
        "\(source == .historical ? "h" : "p")-\(week)"
    }
}

private struct DigitalTwinTrendStatus {
    let label: String
    let shadeColor: Color
}

private enum DigitalTwinTrendMetric: String, CaseIterable, Identifiable {
    case mood
    case stress
    case sleep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mood:
            return "情绪"
        case .stress:
            return "压力"
        case .sleep:
            return "睡眠"
        }
    }

    var isNegative: Bool {
        self == .stress
    }

    func value(in metrics: DigitalTwinTimepointMetrics) -> Double {
        switch self {
        case .mood:
            return metrics.moodStability.value
        case .stress:
            return metrics.anxietyScore.value
        case .sleep:
            return metrics.sleepQuality.value
        }
    }

    func predictionInterval(step: Int) -> Double {
        switch self {
        case .mood:
            return 6 + Double(step) * 1.2
        case .stress:
            return 7 + Double(step) * 1.3
        case .sleep:
            return 5.5 + Double(step) * 1.1
        }
    }

    func isEmergency(currentValue: Double, normalizedDelta: Double) -> Bool {
        switch self {
        case .stress:
            return currentValue >= 75 || normalizedDelta < -10
        case .mood, .sleep:
            return currentValue <= 35 || normalizedDelta < -12
        }
    }
}
