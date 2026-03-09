// CalibrationExtras.swift
// 周/月校准视图

import SwiftUI

struct DailyQuestionnaireView: View {
    let log: WellnessLog?

    init(log: WellnessLog? = nil) {
        self.log = log
    }

    var body: some View {
        if let log {
            DailyLogDetailView(log: log)
        } else {
            CalibrationView()
        }
    }
}

private struct DailyLogDetailView: View {
    let log: WellnessLog
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss
    @State private var summaryItems: [CalibrationSummaryItem] = []
    @State private var isLoadingSummary = false

    private struct CalibrationSummaryItem: Identifiable, Hashable {
        let id: String
        let label: String
        let value: String
    }

    private struct DailyResponseRow: Codable {
        let question_id: String?
        let answer_value: Int?
        let created_at: String?
    }

    var body: some View {
        ZStack {
            AbyssBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    header

                    LiquidGlassCard(style: .elevated, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("今日校准概览")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Spacer()
                                Text(formattedDate(log.log_date))
                                    .font(.caption)
                                    .foregroundColor(.textTertiary)
                            }
                            HStack {
                                Text("已记录 \(summaryItems.count) 项")
                                    .font(.caption)
                                    .foregroundColor(.liquidGlassAccent)
                                Spacer()
                                Text("仅展示本次实际提交内容")
                                    .font(.caption2)
                                    .foregroundColor(.textTertiary)
                            }

                            if isLoadingSummary && summaryItems.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .tint(.liquidGlassAccent)
                                    Text("正在读取今日校准明细...")
                                        .font(.caption)
                                        .foregroundColor(.textSecondary)
                                }
                            } else if summaryItems.isEmpty {
                                Text("暂未读取到今日明细数据")
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(summaryItems) { item in
                                        MetricRow(label: item.label, value: item.value)
                                    }
                                }
                            }
                        }
                    }

                    if let recommendation = log.ai_recommendation, !recommendation.isEmpty {
                        LiquidGlassCard(style: .standard, padding: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AI 建议")
                                    .font(.headline)
                                    .foregroundColor(.textPrimary)
                                Text(recommendation)
                                    .font(.subheadline)
                                    .foregroundColor(.textSecondary)
                            }
                        }
                    }

                    Button {
                        dismiss()
                    } label: {
                        Text("返回首页")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }
        }
        .navigationTitle("每日校准")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: log.log_date) {
            await loadSummaryItems()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今日已完成")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("汇总页仅显示你今天实际填写的校准项")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, metrics.isCompactHeight ? 8 : 16)
    }

    @MainActor
    private func loadSummaryItems() async {
        isLoadingSummary = true
        defer { isLoadingSummary = false }

        let fallback = fallbackSummaryItems()
        guard let userId = SupabaseManager.shared.currentUser?.id else {
            summaryItems = fallback
            return
        }

        do {
            let endpoint = "user_scale_responses?user_id=eq.\(userId)&source=eq.daily&response_date=eq.\(formattedDate(log.log_date))&select=question_id,answer_value,created_at"
            let rows: [DailyResponseRow] = try await SupabaseManager.shared.request(endpoint)
            let mapped = mapRowsToSummary(rows)
            summaryItems = mapped.isEmpty ? fallback : mapped
        } catch {
            summaryItems = fallback
        }
    }

    private func fallbackSummaryItems() -> [CalibrationSummaryItem] {
        var items: [CalibrationSummaryItem] = []

        if let minutes = log.sleep_duration_minutes {
            let hours = Double(minutes) / 60.0
            items.append(CalibrationSummaryItem(id: "daily_sleep_duration", label: "昨晚睡了多少小时？", value: String(format: "%.1f 小时", hours)))
        }
        if let quality = formatSleepQuality(log.sleep_quality) {
            items.append(CalibrationSummaryItem(id: "daily_sleep_quality", label: "入睡容易吗？", value: quality))
        }
        if let stress = log.stress_level {
            items.append(CalibrationSummaryItem(id: "daily_stress_level", label: "当前压力水平？", value: formatStressLevel(stress)))
        }

        return items
    }

    private func mapRowsToSummary(_ rows: [DailyResponseRow]) -> [CalibrationSummaryItem] {
        var byQuestion: [String: Int] = [:]
        for row in rows {
            guard let questionId = row.question_id, let value = row.answer_value else { continue }
            byQuestion[questionId] = value
        }

        let order = [
            "gad7_q1",
            "gad7_q2",
            "daily_sleep_duration",
            "daily_sleep_quality",
            "daily_stress_level"
        ]

        let sortedQuestionIds = byQuestion.keys.sorted { lhs, rhs in
            let leftOrder = order.firstIndex(of: lhs) ?? Int.max
            let rightOrder = order.firstIndex(of: rhs) ?? Int.max
            if leftOrder == rightOrder { return lhs < rhs }
            return leftOrder < rightOrder
        }

        return sortedQuestionIds.compactMap { questionId in
            guard let value = byQuestion[questionId] else { return nil }
            let label = questionLabel(questionId)
            let displayValue = questionValueLabel(questionId: questionId, value: value)
            return CalibrationSummaryItem(id: questionId, label: label, value: displayValue)
        }
    }

    private func questionLabel(_ questionId: String) -> String {
        switch questionId {
        case "gad7_q1": return "感到紧张、焦虑或急切"
        case "gad7_q2": return "不能停止或控制担忧"
        case "daily_sleep_duration": return "昨晚睡了多少小时？"
        case "daily_sleep_quality": return "入睡容易吗？"
        case "daily_stress_level": return "当前压力水平？"
        default: return questionId
        }
    }

    private func questionValueLabel(questionId: String, value: Int) -> String {
        switch questionId {
        case "gad7_q1", "gad7_q2":
            switch value {
            case 0: return "完全没有"
            case 1: return "偶尔"
            case 2: return "经常"
            case 3: return "完全符合"
            default: return "\(value)"
            }
        case "daily_sleep_duration":
            switch value {
            case 0: return "7-8小时"
            case 1: return "8-9小时"
            case 2: return "6-7小时"
            case 3: return "5-6小时"
            case 4: return "超过9小时"
            case 5: return "少于5小时"
            default: return "\(value)"
            }
        case "daily_sleep_quality":
            switch value {
            case 0: return "很容易"
            case 1: return "有点困难"
            case 2: return "很困难"
            default: return "\(value)"
            }
        case "daily_stress_level":
            switch value {
            case 0: return "低压"
            case 1: return "中压"
            case 2: return "高压"
            default: return "\(value)"
            }
        default:
            return "\(value)"
        }
    }

    private func formatSleepQuality(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        switch raw.lowercased() {
        case "good": return "很容易"
        case "average": return "有点困难"
        case "poor": return "很困难"
        default: return raw
        }
    }

    private func formatStressLevel(_ value: Int) -> String {
        if value <= 3 { return "低压" }
        if value <= 7 { return "中压" }
        return "高压"
    }

    private func formattedDate(_ dateString: String) -> String {
        let components = dateString.split(separator: "T").first.map(String.init) ?? dateString
        return components
    }
}

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.textSecondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.textPrimary)
        }
    }
}

struct WeeklyCalibrationView: View {
    @StateObject private var viewModel = WeeklyCalibrationViewModel()
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AbyssBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    header

                    LiquidGlassCard(style: .elevated, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("本周概览")
                                .font(.headline)
                                .foregroundColor(.textPrimary)

                            HStack(spacing: 12) {
                                ReportMetricView(title: "睡眠", value: viewModel.averageSleep)
                                ReportMetricView(title: "压力", value: viewModel.averageStress)
                                ReportMetricView(title: "能量", value: viewModel.averageEnergy)
                            }

                            Text("记录次数：\(viewModel.logs.count) / 7")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("最近记录")
                                .font(.headline)
                                .foregroundColor(.textPrimary)

                            if viewModel.logs.isEmpty {
                                Text("暂无记录")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            } else {
                                ForEach(viewModel.logs.prefix(7)) { log in
                                    HStack {
                                        Text(log.log_date)
                                            .font(.caption2)
                                            .foregroundColor(.textTertiary)
                                        Spacer()
                                        Text("睡眠 \(log.sleep_duration_minutes ?? 0)min")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    NavigationLink(destination: CalibrationView()) {
                        Text("补充本周校准")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }

            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .liquidGlassAccent))
            }
        }
        .navigationTitle("周校准")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("每周校准复盘")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("总结一周趋势并更新计划")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MonthlyCalibrationView: View {
    @StateObject private var viewModel = MonthlyCalibrationViewModel()
    @Environment(\.screenMetrics) private var metrics

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: metrics.sectionSpacing) {
                    header

                    LiquidGlassCard(style: .elevated, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("本月概览")
                                .font(.headline)
                                .foregroundColor(.textPrimary)

                            HStack(spacing: 12) {
                                ReportMetricView(title: "睡眠", value: viewModel.averageSleep)
                                ReportMetricView(title: "压力", value: viewModel.averageStress)
                                ReportMetricView(title: "能量", value: viewModel.averageEnergy)
                            }

                            Text("记录次数：\(viewModel.logs.count) / 30")
                                .font(.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }

                    LiquidGlassCard(style: .standard, padding: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("月度趋势")
                                .font(.headline)
                                .foregroundColor(.textPrimary)

                            if viewModel.logs.isEmpty {
                                Text("暂无记录")
                                    .font(.caption)
                                    .foregroundColor(.textSecondary)
                            } else {
                                ForEach(viewModel.logs.prefix(10)) { log in
                                    HStack {
                                        Text(log.log_date)
                                            .font(.caption2)
                                            .foregroundColor(.textTertiary)
                                        Spacer()
                                        Text("压力 \(log.stress_level ?? 0)")
                                            .font(.caption)
                                            .foregroundColor(.textSecondary)
                                    }
                                }
                            }
                        }
                    }

                    NavigationLink(destination: CalibrationView()) {
                        Text("补充月度校准")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))
                }
                .liquidGlassPageWidth()
                .padding(.vertical, metrics.verticalPadding)
            }

            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .liquidGlassAccent))
            }
        }
        .navigationTitle("月校准")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("月度复盘与趋势")
                .font(.headline)
                .foregroundColor(.textPrimary)
            Text("用于长期趋势追踪")
                .font(.caption)
                .foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
final class WeeklyCalibrationViewModel: ObservableObject {
    @Published var logs: [WellnessLog] = []
    @Published var isLoading = false

    private let supabase = SupabaseManager.shared

    var averageSleep: String {
        let values = logs.compactMap { $0.sleep_duration_minutes }
        return formatAverage(values, suffix: "min")
    }

    var averageStress: String {
        let values = logs.compactMap { $0.stress_level }
        return formatAverage(values, suffix: "")
    }

    var averageEnergy: String {
        let values = logs.compactMap { $0.energy_level }
        return formatAverage(values, suffix: "")
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            logs = try await supabase.getWeeklyWellnessLogs()
        } catch {
            logs = []
        }
    }

    private func formatAverage(_ values: [Int], suffix: String) -> String {
        guard !values.isEmpty else { return "—" }
        let avg = Double(values.reduce(0, +)) / Double(values.count)
        return String(format: "%.1f%@", avg, suffix)
    }
}

@MainActor
final class MonthlyCalibrationViewModel: ObservableObject {
    @Published var logs: [WellnessLog] = []
    @Published var isLoading = false

    private let supabase = SupabaseManager.shared

    var averageSleep: String {
        let values = logs.compactMap { $0.sleep_duration_minutes }
        return formatAverage(values, suffix: "min")
    }

    var averageStress: String {
        let values = logs.compactMap { $0.stress_level }
        return formatAverage(values, suffix: "")
    }

    var averageEnergy: String {
        let values = logs.compactMap { $0.energy_level }
        return formatAverage(values, suffix: "")
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            logs = try await supabase.getMonthlyWellnessLogs()
        } catch {
            logs = []
        }
    }

    private func formatAverage(_ values: [Int], suffix: String) -> String {
        guard !values.isEmpty else { return "—" }
        let avg = Double(values.reduce(0, +)) / Double(values.count)
        return String(format: "%.1f%@", avg, suffix)
    }
}
