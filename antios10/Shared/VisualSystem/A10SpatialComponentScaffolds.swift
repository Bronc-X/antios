import SwiftUI

struct A10SpatialGlassPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let padding: CGFloat
    let content: Content

    init(
        cornerRadius: CGFloat = A10SpatialRadius.panel,
        padding: CGFloat = 24,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return content
            .padding(padding)
            .background {
                shape
                    .fill(A10SpatialPalette.heroPanelFill(for: colorScheme))
                    .background(.ultraThinMaterial, in: shape)
                    .overlay(
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        A10SpatialPalette.heroPanelSheen(for: colorScheme),
                                        A10SpatialPalette.heroPanelEdge(for: colorScheme),
                                        colorScheme == .dark ? Color.white.opacity(0.06) : Color(hex: "#DCE4D6").opacity(0.3)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .overlay(alignment: .top) {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        A10SpatialPalette.heroTopSheen(for: colorScheme),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 100)
                            .mask(shape)
                    }
                    .shadow(color: A10SpatialPalette.heroShadow(for: colorScheme), radius: colorScheme == .dark ? 32 : 24, y: 8)
            }
    }
}

struct A10GraphitePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(A10SpatialPalette.graphite)
                    .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
            )
            .foregroundColor(.white.opacity(0.92))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(A10SpatialMotion.press, value: configuration.isPressed)
    }
}

struct A10RoundGraphiteActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 46, height: 46)
            .background(
                Circle()
                    .fill(A10SpatialPalette.graphite)
                    .shadow(color: Color.black.opacity(0.18), radius: 16, y: 8)
            )
            .foregroundColor(.white.opacity(0.9))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(A10SpatialMotion.press, value: configuration.isPressed)
    }
}

struct A10AuraLineChart: View {
    @Environment(\.colorScheme) private var colorScheme

    let model: A10AuraLineChartModel
    let language: AppLanguage

    @State private var selectedIndex: Int?

    var body: some View {
        GeometryReader { proxy in
            let plotRect = CGRect(
                x: 34,
                y: 18,
                width: max(proxy.size.width - 68, 0),
                height: max(proxy.size.height - 58, 0)
            )
            let points = chartPoints(in: plotRect)
            let activeIndex = resolvedSelectedIndex(for: points)

            TimelineView(.animation) { timeline in
                let phase = timeline.date.timeIntervalSinceReferenceDate
                let pulse = 0.78 + (sin(phase * .pi) + 1) * 0.12

                ZStack(alignment: .topLeading) {
                    chartGrid(in: plotRect)
                    yAxis(in: plotRect)
                    xAxis(in: plotRect)

                    curvePath(points: points)
                        .stroke(
                            A10SpatialPalette.heroChartGlow(for: colorScheme).opacity((colorScheme == .dark ? 0.16 : 0.1) * pulse),
                            style: StrokeStyle(lineWidth: colorScheme == .dark ? 16 : 14, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: colorScheme == .dark ? 12 : 10)

                    curvePath(points: points)
                        .stroke(
                            A10SpatialPalette.heroChartGlow(for: colorScheme).opacity((colorScheme == .dark ? 0.22 : 0.14) * pulse),
                            style: StrokeStyle(lineWidth: colorScheme == .dark ? 10 : 8, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: colorScheme == .dark ? 6 : 5)

                    curvePath(points: points)
                        .stroke(
                            A10SpatialPalette.heroChartGlow(for: colorScheme).opacity((colorScheme == .dark ? 0.3 : 0.18) * pulse),
                            style: StrokeStyle(lineWidth: colorScheme == .dark ? 5 : 4, lineCap: .round, lineJoin: .round)
                        )
                        .blur(radius: 2)

                    curvePath(points: points)
                        .stroke(
                            A10SpatialPalette.heroChartLine(for: colorScheme),
                            style: StrokeStyle(lineWidth: colorScheme == .dark ? 1.8 : 2.3, lineCap: .round, lineJoin: .round)
                        )

                    ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                        Circle()
                            .fill(A10SpatialPalette.heroPointFill(for: colorScheme, highlighted: index >= points.count - 2))
                            .frame(width: index >= points.count - 2 ? 5 : 3, height: index >= points.count - 2 ? 5 : 3)
                            .shadow(
                                color: A10SpatialPalette.heroChartGlow(for: colorScheme).opacity(colorScheme == .dark ? 0.34 : 0.16),
                                radius: colorScheme == .dark ? 8 : 6
                            )
                            .position(point)
                    }

                    if points.indices.contains(activeIndex) {
                        let activePoint = points[activeIndex]
                        Path { path in
                            path.move(to: CGPoint(x: activePoint.x, y: plotRect.minY))
                            path.addLine(to: CGPoint(x: activePoint.x, y: plotRect.maxY))
                        }
                        .stroke(
                            A10SpatialPalette.heroTertiaryText(for: colorScheme).opacity(colorScheme == .dark ? 0.44 : 0.3),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 6])
                        )

                        Circle()
                            .fill(A10SpatialPalette.heroPointFill(for: colorScheme, highlighted: true))
                            .frame(width: 10, height: 10)
                            .shadow(
                                color: A10SpatialPalette.heroChartGlow(for: colorScheme).opacity(colorScheme == .dark ? 0.4 : 0.24),
                                radius: 10
                            )
                            .position(activePoint)

                        if let snapshot = activeSnapshot(activeIndex) {
                            A10GlassTag(
                                title: snapshot.xLabel.resolve(language),
                                value: snapshot.primaryValue,
                                detail: snapshot.secondaryValue
                            )
                            .position(
                                x: min(max(activePoint.x, plotRect.minX + 52), plotRect.maxX - 52),
                                y: max(activePoint.y - 44, plotRect.minY + 24)
                            )
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard !points.isEmpty else { return }
                        selectedIndex = nearestPointIndex(for: value.location.x, in: plotRect, count: points.count)
                    }
                    .onEnded { value in
                        guard !points.isEmpty else { return }
                        selectedIndex = nearestPointIndex(for: value.location.x, in: plotRect, count: points.count)
                    }
            )
        }
    }

    private func resolvedSelectedIndex(for points: [CGPoint]) -> Int {
        guard !points.isEmpty else { return 0 }
        return min(max(selectedIndex ?? (points.count - 1), 0), points.count - 1)
    }

    private func nearestPointIndex(for x: CGFloat, in rect: CGRect, count: Int) -> Int {
        guard count > 1 else { return 0 }
        let clampedX = min(max(x, rect.minX), rect.maxX)
        let step = rect.width / CGFloat(max(count - 1, 1))
        let raw = Int(round((clampedX - rect.minX) / max(step, 1)))
        return min(max(raw, 0), count - 1)
    }

    private func activeSnapshot(_ index: Int) -> A10AuraChartSnapshot? {
        guard model.snapshots.indices.contains(index) else { return nil }
        return model.snapshots[index]
    }

    private func chartPoints(in rect: CGRect) -> [CGPoint] {
        guard !model.values.isEmpty else { return [] }
        let minValue = model.minValue
        let maxValue = max(model.maxValue, minValue + 1)
        let range = max(maxValue - minValue, 1)
        let step = rect.width / CGFloat(max(model.values.count - 1, 1))

        return model.values.enumerated().map { index, value in
            let clamped = min(max(value, minValue), maxValue)
            return CGPoint(
                x: rect.minX + CGFloat(index) * step,
                y: rect.maxY - CGFloat((clamped - minValue) / range) * rect.height
            )
        }
    }

    private func curvePath(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)

        guard points.count > 1 else { return path }

        for index in 0..<(points.count - 1) {
            let p0 = index > 0 ? points[index - 1] : points[index]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = index + 2 < points.count ? points[index + 2] : p2

            let control1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 6,
                y: p1.y + (p2.y - p0.y) / 6
            )
            let control2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 6,
                y: p2.y - (p3.y - p1.y) / 6
            )

            path.addCurve(to: p2, control1: control1, control2: control2)
        }

        return path
    }

    private func chartGrid(in rect: CGRect) -> some View {
        let rowCount = max(model.yLabels.count - 1, 1)
        let columnCount = min(max(model.xLabels.count - 1, 1), 6)
        return Path { path in
            for row in 0...rowCount {
                let y = rect.minY + (rect.height / CGFloat(rowCount)) * CGFloat(row)
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }

            for column in 0...columnCount {
                let x = rect.minX + (rect.width / CGFloat(columnCount)) * CGFloat(column)
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
        }
        .stroke(A10SpatialPalette.heroTertiaryText(for: colorScheme).opacity(colorScheme == .dark ? 1 : 0.58), style: StrokeStyle(lineWidth: 1, dash: [3, 8]))
    }

    private func yAxis(in rect: CGRect) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.yLabels, id: \.self) { value in
                Text(value)
                    .font(A10SpatialTypography.label(9, weight: .regular))
                    .foregroundColor(A10SpatialPalette.heroTertiaryText(for: colorScheme))
                if value != model.yLabels.last {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(width: 24, height: rect.height, alignment: .topLeading)
        .position(x: 12, y: rect.midY)
    }

    private func xAxis(in rect: CGRect) -> some View {
        HStack {
            ForEach(Array(model.xLabels.enumerated()), id: \.offset) { _, label in
                Text(label.resolve(language))
                    .font(A10SpatialTypography.label(10, weight: .regular))
                    .foregroundColor(A10SpatialPalette.heroTertiaryText(for: colorScheme))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: rect.width)
        .position(x: rect.midX, y: rect.maxY + 22)
    }
}

struct A10GlassTag: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(A10SpatialTypography.label(9, weight: .medium))
                .foregroundColor(A10SpatialPalette.heroSecondaryText(for: colorScheme))
            Text(value)
                .font(A10SpatialTypography.body(14, weight: .semibold))
                .foregroundColor(A10SpatialPalette.heroTagText(for: colorScheme))
            Text(detail)
                .font(A10SpatialTypography.label(9, weight: .regular))
                .foregroundColor(A10SpatialPalette.heroSecondaryText(for: colorScheme))
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(A10SpatialPalette.heroTagFill(for: colorScheme))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(A10SpatialPalette.heroTagBorder(for: colorScheme), lineWidth: 1)
                )
        )
    }
}

struct A10DashboardSpatialHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.screenMetrics) private var metrics

    let model: A10DashboardSpatialHeroModel
    let language: AppLanguage
    var onPrimaryAction: (() -> Void)? = nil
    var onSecondaryAction: (() -> Void)? = nil

    private var panelPadding: CGFloat {
        metrics.isCompactHeight ? 14 : 16
    }

    private var verticalSpacing: CGFloat {
        metrics.isCompactHeight ? 11 : 13
    }

    private var chartHeight: CGFloat {
        metrics.isCompactHeight ? 170 : 184
    }

    private var productionHeight: CGFloat {
        metrics.isCompactHeight ? 26 : 30
    }

    var body: some View {
        A10SpatialGlassPanel(cornerRadius: 32, padding: panelPadding) {
            VStack(alignment: .leading, spacing: verticalSpacing) {
                HStack {
                    Text(model.eyebrow.resolve(language))
                        .font(A10SpatialTypography.label(11, weight: .regular))
                        .foregroundColor(A10SpatialPalette.heroTertiaryText(for: colorScheme))

                    Spacer()

                    if let statusBadge = model.statusBadge {
                        Text(statusBadge.resolve(language))
                            .font(A10SpatialTypography.label(10, weight: .semibold))
                            .foregroundColor(model.statusTint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(model.statusTint.opacity(0.12))
                            )
                    }
                }

                Group {
                    if let onPrimaryAction {
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .soft)
                            impact.impactOccurred()
                            onPrimaryAction()
                        } label: {
                            actionBlock
                        }
                        .buttonStyle(.plain)
                    } else {
                        actionBlock
                    }
                }

                HStack(spacing: 18) {
                    ForEach(model.topMetrics) { metric in
                        A10MetricBlock(metric: metric, language: language)
                    }
                }

                A10AuraLineChart(model: model.chart, language: language)
                    .frame(height: chartHeight)

                A10ProductionBarStrip(samples: model.waveSamples)
                    .frame(height: productionHeight)
                    .opacity(0.72)

                Text(model.chart.interactionHint.resolve(language))
                    .font(A10SpatialTypography.label(10, weight: .regular))
                    .foregroundColor(A10SpatialPalette.heroSecondaryText(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var actionBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.actionTitle.resolve(language))
                .font(A10SpatialTypography.body(20, weight: .semibold))
                .foregroundColor(A10SpatialPalette.heroPrimaryText(for: colorScheme))
                .multilineTextAlignment(.leading)
            Text(model.actionDetail.resolve(language))
                .font(A10SpatialTypography.label(12, weight: .regular))
                .foregroundColor(A10SpatialPalette.heroSecondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct A10MetricBlock: View {
    @Environment(\.colorScheme) private var colorScheme

    let metric: A10SpatialMetric
    let language: AppLanguage
    var large: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.value)
                .font(large ? A10SpatialTypography.heroNumber(30) : A10SpatialTypography.heroNumber(22))
                .foregroundColor(A10SpatialPalette.heroPrimaryText(for: colorScheme))

            Text(metric.title.resolve(language))
                .font(A10SpatialTypography.label(11, weight: .regular))
                .foregroundColor(A10SpatialPalette.heroSecondaryText(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct A10ProductionBarStrip: View {
    @Environment(\.colorScheme) private var colorScheme

    let samples: [CGFloat]

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                        let animatedSample = animatedHeight(for: sample, index: index, phase: phase)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        A10SpatialPalette.heroProductionBar(for: colorScheme).opacity(index.isMultiple(of: 3) ? 0.5 : 0.84),
                                        A10SpatialPalette.heroProductionBar(for: colorScheme)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.18), lineWidth: 0.7)
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: max(8, proxy.size.height * animatedSample))
                            .offset(y: sin(CGFloat(index) * 0.52 + phase * 0.8) * -1.8)
                    }
                }
            }
        }
    }

    private func animatedHeight(for sample: CGFloat, index: Int, phase: TimeInterval) -> CGFloat {
        let waveA = sin(phase * 1.37 + Double(index) * 0.71) * 0.06
        let waveB = cos(phase * 0.84 + Double(index) * 1.13) * 0.04
        let waveC = sin(phase * 1.91 + Double(index) * 0.29) * 0.03
        return min(max(sample + CGFloat(waveA + waveB + waveC), 0.12), 0.92)
    }
}

struct A10FloatingMenuScaffold: View {
    let model: A10FloatingMenuModel
    let language: AppLanguage
    var onSelectDay: ((Int) -> Void)? = nil
    var onSelectAction: ((A10FloatingMenuAction) -> Void)? = nil

    @Namespace private var menuNamespace
    @State private var selectedDay: Int
    @State private var isExpanded: Bool

    init(
        model: A10FloatingMenuModel,
        language: AppLanguage,
        onSelectDay: ((Int) -> Void)? = nil,
        onSelectAction: ((A10FloatingMenuAction) -> Void)? = nil
    ) {
        self.model = model
        self.language = language
        self.onSelectDay = onSelectDay
        self.onSelectAction = onSelectAction
        _selectedDay = State(initialValue: model.selectedDay)
        _isExpanded = State(initialValue: model.presentation == .expanded)
    }

    var body: some View {
        ZStack {
            A10SpatialBackdrop(mode: model.stageMode)

            VStack(spacing: 18) {
                HStack {
                    Capsule()
                        .fill(Color.black.opacity(model.stageMode == .darkBackdrop ? 0.24 : 0.1))
                        .frame(width: 88, height: 28)
                        .overlay {
                            Text(model.streamCountLabel.resolve(language))
                                .font(A10SpatialTypography.label(12, weight: .medium))
                                .foregroundColor(model.stageMode == .darkBackdrop ? .white.opacity(0.88) : .black.opacity(0.66))
                        }

                    Spacer()

                    Text(model.progressLabel)
                        .font(A10SpatialTypography.label(12, weight: .semibold))
                        .foregroundColor(model.stageMode == .darkBackdrop ? .white.opacity(0.84) : .black.opacity(0.52))
                }

                Spacer(minLength: 0)

                ZStack {
                    if isExpanded {
                        expandedMenu
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        collapsedRail
                            .transition(.opacity)
                    }
                }
                .animation(A10SpatialMotion.snap, value: isExpanded)

                Spacer(minLength: 0)
            }
            .padding(24)
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onChange(of: model.selectedDay) { _, newValue in
            withAnimation(A10SpatialMotion.snap) {
                selectedDay = newValue
            }
        }
        .onChange(of: model.presentation == .expanded) { _, newValue in
            withAnimation(A10SpatialMotion.snap) {
                isExpanded = newValue
            }
        }
    }

    private var collapsedRail: some View {
        HStack(alignment: .bottom, spacing: 18) {
            ForEach(model.days) { day in
                let isSelected = day.id == selectedDay

                Button {
                    withAnimation(A10SpatialMotion.snap) {
                        selectedDay = day.id
                        if day.id == model.selectedDay {
                            isExpanded.toggle()
                        }
                    }
                    onSelectDay?(day.id)
                } label: {
                    VStack(spacing: 8) {
                        if isSelected {
                            Image(systemName: "triangle.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.black.opacity(0.46))
                                .rotationEffect(.degrees(180))
                        }

                        Capsule()
                            .fill(
                                isSelected
                                ? AnyShapeStyle(
                                    LinearGradient(
                                        colors: [
                                            Color.liquidGlassAccent.opacity(0.94),
                                            Color.liquidGlassWarm.opacity(0.78)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                : AnyShapeStyle(Color.white.opacity(0.6))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(isSelected ? 0.4 : 0.74), lineWidth: 1)
                            )
                            .shadow(
                                color: isSelected
                                ? Color.liquidGlassAccent.opacity(0.22)
                                : A10SpatialPalette.floatingShadow,
                                radius: isSelected ? 20 : 18,
                                y: isSelected ? 12 : 10
                            )
                            .frame(width: railWidth(for: day), height: isSelected ? 84 : 62)
                            .matchedGeometryEffect(id: isSelected ? "menu-shell" : "shell-\(day.id)", in: menuNamespace)
                            .overlay {
                                Text(day.shortLabel)
                                    .font(.system(size: railLabelSize(for: day), weight: isSelected ? .semibold : .medium, design: .rounded))
                                    .foregroundColor(isSelected ? .white.opacity(0.96) : .black.opacity(0.52))
                                    .minimumScaleFactor(0.82)
                                    .lineLimit(1)
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func railWidth(for day: A10FloatingMenuDay) -> CGFloat {
        switch day.shortLabel.count {
        case 0...2:
            return day.id == selectedDay ? 72 : 58
        case 3...4:
            return day.id == selectedDay ? 78 : 64
        default:
            return day.id == selectedDay ? 84 : 70
        }
    }

    private func railLabelSize(for day: A10FloatingMenuDay) -> CGFloat {
        switch day.shortLabel.count {
        case 0...2:
            return day.id == selectedDay ? 19 : 15
        case 3...4:
            return day.id == selectedDay ? 16 : 13
        default:
            return day.id == selectedDay ? 14 : 12
        }
    }

    private var expandedMenu: some View {
        VStack(spacing: 18) {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    withAnimation(A10SpatialMotion.snap) {
                        isExpanded = false
                    }
                    onSelectAction?(action)
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(index == model.actions.count - 1 ? 0.38 : 0.1))
                            .frame(width: index == model.actions.count - 1 ? 72 : 52, height: index == model.actions.count - 1 ? 72 : 52)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )

                        Image(systemName: action.symbol)
                            .font(.system(size: index == model.actions.count - 1 ? 24 : 20, weight: .semibold))
                            .foregroundColor(.white.opacity(0.82))
                    }
                    .opacity(isExpanded ? 1 : 0)
                    .offset(y: isExpanded ? 0 : 12)
                    .animation(A10SpatialMotion.snap.delay(Double(index) * 0.04), value: isExpanded)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 22)
        .frame(width: 106, height: 246)
        .background(
            Capsule()
                .fill(Color.white.opacity(model.stageMode == .darkBackdrop ? 0.22 : 0.7))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.26), radius: 24, y: 14)
                .matchedGeometryEffect(id: "menu-shell", in: menuNamespace)
        )
        .onTapGesture {
            withAnimation(A10SpatialMotion.snap) {
                isExpanded = false
            }
        }
    }
}

struct A10EmotionWheelScaffold: View {
    @Environment(\.screenMetrics) private var metrics

    let model: A10EmotionWheelModel
    let language: AppLanguage
    var selectedShortcutID: String? = nil
    var onSelectShortcut: ((A10EmotionShortcut) -> Void)? = nil
    var onSelectDockAction: ((A10DockAction) -> Void)? = nil

    private var shellPadding: CGFloat {
        metrics.isCompactHeight ? 18 : 20
    }

    private var containerMinHeight: CGFloat {
        metrics.isCompactHeight ? 438 : 472
    }

    private var wheelHeight: CGFloat {
        metrics.isCompactHeight ? 188 : 204
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            A10SpatialPalette.wheelCanvas,
                            Color(hex: "#2D2A2F")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(spacing: 14) {
                header
                shortcutRow
                emotionWheel
                insightCard
                bottomDock
            }
            .padding(shellPadding)
        }
        .frame(maxWidth: .infinity, minHeight: containerMinHeight)
    }

    private var header: some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(A10SpatialPalette.wheelText)

            Spacer()

            Text(model.brandTitle)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)

            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 28, height: 28)
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.86))
            }
        }
    }

    private var shortcutRow: some View {
        HStack(spacing: 10) {
            ForEach(model.shortcuts) { item in
                let isSelected = selectedShortcutID == item.id

                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    onSelectShortcut?(item)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12, weight: .semibold))
                        Text(item.title.resolve(language))
                            .font(A10SpatialTypography.label(9, weight: .regular))
                    }
                    .foregroundColor(isSelected ? Color.white.opacity(0.92) : A10SpatialPalette.wheelMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isSelected ? Color.white.opacity(0.24) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emotionWheel: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let baseRadius = size / 2
            let segment = 2 * CGFloat.pi / CGFloat(model.petals.count)
            let gap = segment * 0.12
            let trackInnerRatio: CGFloat = 0.18
            let trackOuterRatio: CGFloat = 0.78
            let minimumActiveOuterRatio: CGFloat = 0.34
            let scoreMax = max(CGFloat(model.maxScore), 1)

            ZStack {
                Circle()
                    .stroke(A10SpatialPalette.wheelRing, lineWidth: 1)
                    .frame(width: size * 0.92, height: size * 0.92)

                ForEach(Array(model.petals.enumerated()), id: \.element.id) { index, petal in
                    let startAngle = -CGFloat.pi / 2 + CGFloat(index) * segment + gap / 2
                    let endAngle = startAngle + segment - gap
                    let scoreRatio = max(0, min(CGFloat(petal.score) / scoreMax, 1))
                    let activeOuterRatio = minimumActiveOuterRatio + scoreRatio * (trackOuterRatio - minimumActiveOuterRatio)
                    let labelRadius = baseRadius * ((trackInnerRatio + activeOuterRatio) / 2 + 0.03)
                    let labelAngle = (startAngle + endAngle) / 2
                    let labelPoint = CGPoint(
                        x: center.x + cos(labelAngle) * labelRadius,
                        y: center.y + sin(labelAngle) * labelRadius
                    )

                    A10EmotionPetalShape(
                        startAngle: startAngle,
                        endAngle: endAngle,
                        innerRatio: trackInnerRatio,
                        outerRatio: trackOuterRatio
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                A10SpatialPalette.wheelTrack.opacity(0.96),
                                A10SpatialPalette.wheelTrackDeep.opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        A10EmotionPetalShape(
                            startAngle: startAngle,
                            endAngle: endAngle,
                            innerRatio: trackInnerRatio,
                            outerRatio: trackOuterRatio
                        )
                        .stroke(A10SpatialPalette.wheelTrackStroke, lineWidth: 1)
                    )

                    A10EmotionPetalShape(
                        startAngle: startAngle,
                        endAngle: endAngle,
                        innerRatio: trackInnerRatio,
                        outerRatio: activeOuterRatio
                    )
                    .fill(
                        LinearGradient(
                            colors: [
                                petal.tint.opacity(0.98),
                                petal.tint.opacity(0.76 + petal.intensity * 0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        A10EmotionPetalShape(
                            startAngle: startAngle,
                            endAngle: endAngle,
                            innerRatio: trackInnerRatio,
                            outerRatio: activeOuterRatio
                        )
                        .stroke(A10SpatialPalette.wheelPetalStroke, lineWidth: 1)
                    )
                    .shadow(color: petal.tint.opacity(0.08), radius: 10, y: 5)

                    VStack(spacing: 2) {
                        Text("\(petal.score)")
                            .font(A10SpatialTypography.wheelValue(12))
                            .foregroundColor(Color.black.opacity(0.58))

                        Text(petal.title.resolve(language))
                            .font(A10SpatialTypography.wheelLabel(9))
                            .foregroundColor(Color.black.opacity(0.5))
                    }
                    .position(labelPoint)
                }

                Circle()
                    .fill(Color(hex: "#252225"))
                    .frame(width: size * 0.18, height: size * 0.18)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .drawingGroup(opaque: false, colorMode: .linear)
        }
        .frame(height: wheelHeight)
    }

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.insight.eyebrow.resolve(language))
                .font(A10SpatialTypography.label(11, weight: .medium))
                .foregroundColor(A10SpatialPalette.wheelMuted)

            Text(model.insight.body.resolve(language))
                .font(.system(size: 14, weight: .medium, design: .serif))
                .foregroundColor(Color.black.opacity(0.68))
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: A10SpatialRadius.wheelCard, style: .continuous)
                .fill(A10SpatialPalette.wheelCard)
        )
    }

    private var bottomDock: some View {
        HStack(spacing: 12) {
            dockButton(action: model.leadingDockAction)

            Spacer()

            dockButton(action: model.centerDockAction)
                .frame(width: 52, height: 52)

            Spacer()

            HStack(spacing: 10) {
                ForEach(model.trailingDockActions) { action in
                    dockButton(action: action)
                }
            }
        }
    }

    private func dockButton(action: A10DockAction) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: action.isPrimary ? .medium : .light)
            impact.impactOccurred()
            onSelectDockAction?(action)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(action.isPrimary ? Color(hex: "#242025") : A10SpatialPalette.wheelDock)
                    .shadow(color: Color.black.opacity(action.isPrimary ? 0.34 : 0.28), radius: 14, y: 8)

                Image(systemName: action.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.84))
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
    }
}

struct A10EmotionPetalShape: Shape {
    let startAngle: CGFloat
    let endAngle: CGFloat
    let innerRatio: CGFloat
    let outerRatio: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2
        let innerRadius = baseRadius * innerRatio
        let outerRadius = baseRadius * outerRatio
        let midAngle = (startAngle + endAngle) / 2
        let span = endAngle - startAngle

        let innerStart = point(center: center, radius: innerRadius, angle: startAngle)
        let innerEnd = point(center: center, radius: innerRadius, angle: endAngle)
        let outerStart = point(center: center, radius: outerRadius * 0.9, angle: startAngle + span * 0.2)
        let outerPeak = point(center: center, radius: outerRadius, angle: midAngle)
        let outerEnd = point(center: center, radius: outerRadius * 0.9, angle: endAngle - span * 0.2)

        let riseControlA = point(center: center, radius: innerRadius * 1.04, angle: startAngle + span * 0.04)
        let riseControlB = point(center: center, radius: outerRadius * 0.62, angle: startAngle + span * 0.1)
        let crestControlA = point(center: center, radius: outerRadius * 1.03, angle: midAngle - span * 0.14)
        let crestControlB = point(center: center, radius: outerRadius * 1.03, angle: midAngle + span * 0.14)
        let fallControlA = point(center: center, radius: outerRadius * 0.62, angle: endAngle - span * 0.1)
        let fallControlB = point(center: center, radius: innerRadius * 1.04, angle: endAngle - span * 0.04)
        let shoulderLiftA = point(center: center, radius: outerRadius * 0.97, angle: startAngle + span * 0.34)
        let shoulderLiftB = point(center: center, radius: outerRadius * 0.97, angle: endAngle - span * 0.34)

        var path = Path()
        path.move(to: innerStart)
        path.addCurve(to: outerStart, control1: riseControlA, control2: riseControlB)
        path.addCurve(to: outerPeak, control1: shoulderLiftA, control2: crestControlA)
        path.addCurve(to: outerEnd, control1: crestControlB, control2: shoulderLiftB)
        path.addCurve(to: innerEnd, control1: fallControlA, control2: fallControlB)
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: .radians(Double(endAngle)),
            endAngle: .radians(Double(startAngle)),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }

    private func point(center: CGPoint, radius: CGFloat, angle: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }
}
