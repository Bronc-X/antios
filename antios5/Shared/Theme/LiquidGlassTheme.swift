// LiquidGlassTheme.swift
// iOS 端 Liquid Glass 设计系统（高端杂志感 / Calm / Scientific / Minimal）

import SwiftUI

// MARK: - Screen Metrics
struct ScreenMetrics {
    let size: CGSize
    let safeAreaInsets: EdgeInsets

    /// 固定屏幕宽度（使用物理像素对齐，避免亚像素导致的布局漂移）
    var fixedScreenWidth: CGFloat {
        alignToPixel(size.width)
    }

    var safeWidth: CGFloat {
        max(0, size.width - safeAreaInsets.leading - safeAreaInsets.trailing)
    }

    var isCompactWidth: Bool { fixedScreenWidth <= 360 }
    var isCompactHeight: Bool { size.height <= 700 }

    /// 水平边距（基于 fixedScreenWidth 判断，避免 safeWidth 微小波动导致阈值跳变）
    var horizontalPadding: CGFloat {
        if fixedScreenWidth <= 360 { return 14 }
        if fixedScreenWidth < 430 { return 18 }
        return 24
    }

    var verticalPadding: CGFloat {
        isCompactHeight ? 12 : 16
    }

    var sectionSpacing: CGFloat {
        isCompactHeight ? 16 : 24
    }

    /// 居中补偿（已修正：移除历史遗留的负值偏移）
    var centerAxisOffset: CGFloat { 0 }

    var iconSize: CGFloat { isCompactWidth ? 18 : 20 }
    var smallIconSize: CGFloat { isCompactWidth ? 14 : 16 }

    var tabBarHeight: CGFloat { isCompactHeight ? 58 : 70 }
    var tabBarHorizontalPadding: CGFloat { isCompactWidth ? 8 : 12 }

    var tabBarBottomPadding: CGFloat {
        0
    }

    func stableCenteredWidth(
        maxWidth: CGFloat,
        minWidth: CGFloat = 0,
        horizontalInset: CGFloat = 0,
        fraction: CGFloat = 1
    ) -> CGFloat {
        let usableWidth = Swift.max(0, (fixedScreenWidth - horizontalInset * 2) * fraction)
        return alignToPixel(Swift.max(minWidth, Swift.min(usableWidth, maxWidth)))
    }

    /// TabBar 宽度（基于 fixedScreenWidth，确保布局稳定）
    var tabBarWidth: CGFloat {
        stableCenteredWidth(maxWidth: 560, horizontalInset: tabBarHorizontalPadding)
    }

    var bottomContentInset: CGFloat {
        tabBarHeight + tabBarBottomPadding + 20
    }

    var maxContentWidth: CGFloat {
        // iOS 26 下左右 safe-area 可能出现轻微不对称，使用 fixedScreenWidth 作为列宽基准可避免整页横向漂移。
        stableCenteredWidth(maxWidth: 560, horizontalInset: horizontalPadding)
    }

    var ringLarge: CGFloat { isCompactHeight ? 140 : 160 }
    var ringMedium: CGFloat { isCompactHeight ? 120 : 140 }
    var avatarLarge: CGFloat { isCompactWidth ? 84 : 100 }

    private func alignToPixel(_ value: CGFloat) -> CGFloat {
        #if os(iOS)
        let scale = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.scale ?? 2.0
        #else
        let scale: CGFloat = 2.0
        #endif
        return (value * scale).rounded() / scale
    }
}

private struct ScreenMetricsKey: EnvironmentKey {
    static let defaultValue = ScreenMetrics(
        size: (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds.size ?? CGSize(width: 390, height: 844),
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
    )
}

extension EnvironmentValues {
    var screenMetrics: ScreenMetrics {
        get { self[ScreenMetricsKey.self] }
        set { self[ScreenMetricsKey.self] = newValue }
    }
}

// MARK: - Tokens
enum GlassSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum GlassRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum GlassShadow {
    static let softColor = Color.black.opacity(0.28)
    static let softRadius: CGFloat = 18
    static let softY: CGFloat = 10

    static let floatColor = Color.black.opacity(0.42)
    static let floatRadius: CGFloat = 28
    static let floatY: CGFloat = 14
}

enum GlassTypography {
    private static func latinFontName(weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            return "AvenirNext-Regular"
        case .regular:
            return "AvenirNext-Regular"
        case .medium:
            return "AvenirNext-Medium"
        case .semibold:
            return "AvenirNext-DemiBold"
        case .bold, .heavy, .black:
            return "AvenirNext-Bold"
        default:
            return "AvenirNext-Regular"
        }
    }

    private static func cnFontName(weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light:
            return "PingFangSC-Light"
        case .regular:
            return "PingFangSC-Regular"
        case .medium:
            return "PingFangSC-Medium"
        case .semibold:
            return "PingFangSC-Semibold"
        case .bold, .heavy, .black:
            return "PingFangSC-Bold"
        default:
            return "PingFangSC-Regular"
        }
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func title(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func caption(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func loviTitle(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom(latinFontName(weight: weight), size: size)
    }

    static func loviBody(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .custom(latinFontName(weight: weight), size: size)
    }

    static func cnLovi(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .custom(cnFontName(weight: weight), size: size)
    }
}

// MARK: - Legacy Typography Helper
struct NeuroFont: ViewModifier {
    var size: CGFloat
    var weight: Font.Weight = .regular
    var design: Font.Design = .serif

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    func neuroFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(NeuroFont(size: size, weight: weight))
    }
}

// MARK: - Palette
extension Color {
    // 基础色板 (Base Palette - Static)
    static let deepGreen = Color(hex: "#6C4A97")
    static let deepGreenDarker = Color(hex: "#221338")
    static let paperWhite = Color(hex: "#FDFBFF")
    static let sageGreen = Color(hex: "#A5EFC6")
    static let lightGrey = Color(hex: "#FDF3FF")
    static let softBlack = Color(hex: "#34244B")
    
    // 语义色 (Semantic - Dynamic)
    static let bgPrimary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#1A102A") : UIColor(hex: "#FFF9FE")
    })

    static let bgSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#291A3D") : UIColor(hex: "#FDF1FF")
    })

    static let bgTertiary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#33214C") : UIColor(hex: "#F9EEFF")
    })

    // Logo & Brand Colors
    static let brandDeepGreen = Color.deepGreen
    static let brandPaper = Color.paperWhite
    static let brandMoss = Color.sageGreen
    static let brandSage = Color(hex: "#ECFFF4")
    
    // Liquid Glass Specifics
    static let liquidGlassPrimary = Color.bgPrimary
    static let liquidGlassAccent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#F5B8FF") : UIColor(hex: "#E8A4FF")
    })
    static let liquidGlassPurple = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#FFC1E9") : UIColor(hex: "#F8C8EB")
    })
    static let liquidGlassSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#C8D8FF") : UIColor(hex: "#D4DEFF")
    })
    static let liquidGlassWarm = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#FFA5CF") : UIColor(hex: "#FCC2DD")
    })
    static let liquidGlassFreshGreen = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#83EDB8") : UIColor(hex: "#5EDCA2")
    })

    // Status Colors
    static let statusSuccess = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#73E4AE") : UIColor(hex: "#43CF88")
    })
    static let statusWarning = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#D5B578") : UIColor(hex: "#BE9A58")
    })
    static let statusError = Color(hex: "#D27795")

    // Text Colors (Dynamic)
    static let textPrimary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#F8F3FF") : UIColor(hex: "#30254A")
    })

    static let textSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#DDD4EC") : UIColor(hex: "#675A82")
    })

    static let textTertiary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#BDADD8") : UIColor(hex: "#7E719C")
    })

    static let textOnAccent = Color(uiColor: UIColor { _ in
        UIColor(hex: "#281A38")
    })

    static let textOnDanger = Color(uiColor: UIColor { _ in
        UIColor(hex: "#2B1421")
    })

    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#F8F3FF") : Color(hex: "#34264D")
    }

    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#D9D0E8") : Color(hex: "#685B82")
    }

    static func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#B9ABD1") : Color(hex: "#7F719B")
    }

    static func surfaceGlass(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color(hex: "#31244D").opacity(0.62)
        }
        // Light mode: keep translucency but add subtle chroma depth for better surface separation.
        return Color(hex: "#F3ECFF").opacity(0.9)
    }

    static func surfaceStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.08)
    }

    static func mutedSurfaceFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035)
    }

    static func splashMarkOuterStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.36) : Color(hex: "#DDC8FA")
    }

    static func splashMarkPlateFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.1) : Color(hex: "#F4E8FF")
    }

    static func splashMarkPlateStroke(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color(hex: "#E0CDFC")
    }

    static func splashLogoPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.95) : Color(hex: "#634E8B")
    }

    static func splashLogoSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#D7C9FF") : Color(hex: "#8B67B9")
    }
}

// MARK: - UIColor Helper
extension UIColor {
    convenience init(hex: String) {
        let hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&rgb)
        
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Gradients
extension LinearGradient {
    static var magazineWash: LinearGradient {
        LinearGradient(
            colors: [Color.bgPrimary, Color.bgSecondary],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var mossVeil: LinearGradient {
        LinearGradient(
            colors: [
                Color.brandMoss.opacity(0.28),
                Color.brandSage.opacity(0.14),
                Color.brandPaper.opacity(0.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var glassSheen: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.42),
                Color.white.opacity(0.14),
                Color.white.opacity(0.02)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Background
// MARK: - Background
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var animate = false
    
    var body: some View {
        ZStack {
            // Dynamic Background
            if colorScheme == .dark {
                // Dark Mode: Plum-black gradient
                LinearGradient(
                    colors: [Color(hex: "#140A21"), Color(hex: "#2A1341")],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                // Light Mode: Soft lilac silk
                LinearGradient(
                    colors: [Color(hex: "#FFFDFE"), Color(hex: "#FCEFFF")],
                    startPoint: .top,
                    endPoint: .bottom
                ).ignoresSafeArea()
            }

            // Orb 1 (Top Left) - Breathing
            Circle()
                .fill(Color.bioGlow(for: colorScheme).opacity(colorScheme == .dark ? 0.19 : 0.16))
                .frame(width: 320, height: 320)
                .blur(radius: colorScheme == .dark ? 94 : 78)
                .offset(x: animate ? -120 : -160, y: -180)

            // Orb 2 (Bottom Right) - Flowing
            Circle()
                .fill(Color.bioluminPink(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.16))
                .frame(width: 420, height: 420)
                .blur(radius: colorScheme == .dark ? 100 : 88)
                .offset(x: animate ? 100 : 140, y: 260)

            // Orb 2.5 (Green Accent) - Energy signal
            Circle()
                .fill(Color.liquidGlassFreshGreen.opacity(colorScheme == .dark ? 0.14 : 0.12))
                .frame(width: colorScheme == .dark ? 230 : 180, height: colorScheme == .dark ? 230 : 180)
                .blur(radius: colorScheme == .dark ? 68 : 54)
                .offset(x: animate ? 112 : 72, y: animate ? -92 : -126)

            if colorScheme == .light {
                Circle()
                    .fill(Color(hex: "#CBD4FF").opacity(0.18))
                    .frame(width: 260, height: 260)
                    .blur(radius: 64)
                    .offset(x: animate ? 60 : 20, y: 40)
            }
            
            // Orb 3 (Center Accent) - Pulse
            if colorScheme == .dark {
                Circle()
                    .fill(Color(hex: "#6F6AAE").opacity(0.06))
                    .frame(width: 200, height: 200)
                    .blur(radius: 74)
                    .offset(x: 0, y: 0)
                    .scaleEffect(animate ? 1.05 : 0.95)
            }

            // Texture: Only in Light Mode for "Paper/Silk" feel. Pure Black should be clean.
            if colorScheme == .light {
                GrainTexture(opacity: 0.025)
                    .blendMode(.multiply)
                    .ignoresSafeArea()
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                animate.toggle()
            }
        }
    }
}

// MARK: - Glass Surface
enum GlassSurfaceStyle {
    case standard
    case elevated
    case sunk
    case concave
}

struct LiquidGlassCard<Content: View>: View {
    let content: Content
    var padding: CGFloat
    var style: GlassSurfaceStyle
    @Environment(\.colorScheme) private var colorScheme

    init(style: GlassSurfaceStyle = .standard, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.style = style
        self.padding = padding
        self.content = content()
    }

    private var cornerRadius: CGFloat {
        switch style {
        case .concave: return GlassRadius.md
        case .sunk: return GlassRadius.lg
        case .elevated: return GlassRadius.xl
        case .standard: return GlassRadius.xl
        }
    }

    private var materialStyle: Material {
        if colorScheme == .dark {
            return style == .elevated ? .thinMaterial : .ultraThinMaterial
        }

        switch style {
        case .elevated:
            return .regularMaterial
        case .standard, .sunk:
            return .thinMaterial
        case .concave:
            return .ultraThinMaterial
        }
    }

    private var tintStyle: LinearGradient {
        // Material 上方的色调层 (Tint)：
        // light 模式提高 1 级明暗分离，仍保持玻璃通透，不走实色卡片。
        switch style {
        case .sunk:
            return LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.bgSecondary.opacity(0.56), Color.black.opacity(0.22)]
                    : [Color.white.opacity(0.28), Color(hex: "#EDE3FA").opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .concave:
            return LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black.opacity(0.2), Color.black.opacity(0.08)]
                    : [Color.white.opacity(0.2), Color(hex: "#E9DDF8").opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .elevated:
            return LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.08), Color.white.opacity(0.02)]
                    : [Color.white.opacity(0.44), Color(hex: "#F2E8FF").opacity(0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .standard:
            return LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.05), Color.white.opacity(0.01)]
                    : [Color.white.opacity(0.34), Color(hex: "#F0E5FF").opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var borderGradient: LinearGradient {
        // 边缘光感 (Rim Light): 左上亮，右下暗
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.3 : 0.7), // 左上高光
                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2),
                Color.white.opacity(colorScheme == .dark ? 0.02 : 0.0)  // 右下消隐
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var shadowOpacity: Double {
        if colorScheme == .dark {
            return style == .elevated ? 0.18 : 0.1
        }
        return style == .elevated ? 0.12 : 0.07
    }

    private var shadowRadius: CGFloat {
        style == .elevated ? 24 : 14
    }

    private var shadowY: CGFloat {
        style == .elevated ? 10 : 6
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 1. 色调层 (Tint)
            .background {
                shape
                    .fill(tintStyle)
            }
            // 2. 物理材质层 (Physical Material - Blur)
            .background(materialStyle, in: shape)
            // 3. 边缘光与内描边 (Rim Light)
            .overlay(
                shape
                    .stroke(
                        borderGradient,
                        lineWidth: colorScheme == .dark ? 0.8 : 1
                    )
            )
            .overlay(
                shape
                    .stroke(Color.black.opacity(colorScheme == .dark ? 0.26 : 0.06), lineWidth: 0.5)
                    .blendMode(.multiply)
            )
            .clipShape(shape)
            // 4. 投影 (Shadow)
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: shadowRadius,
                y: shadowY
            )
            .shadow(
                color: colorScheme == .light ? Color.white.opacity(0.3) : .clear,
                radius: style == .elevated ? 10 : 6,
                y: -1
            )
    }
}

// MARK: - Legacy Button Style
struct LiquidGlassButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    var isDestructive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let kind: GlassButtonStyle.Kind = isDestructive ? .danger : (isProminent ? .primary : .secondary)
        return GlassButtonStyle(kind: kind).makeBody(configuration: configuration)
    }
}

// MARK: - Accent Orb
struct PulsingOrb: View {
    @State private var breathe = false
    var color: Color = .brandMoss

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 80, height: 80)
                .blur(radius: 8)

            Circle()
                .fill(color.opacity(0.25))
                .frame(width: 120, height: 120)
                .blur(radius: 22)
                .scaleEffect(breathe ? 1.1 : 0.92)
                .opacity(breathe ? 0.5 : 0.3)

            Circle()
                .stroke(color.opacity(0.5), lineWidth: 1)
                .frame(width: 100, height: 100)
                .scaleEffect(breathe ? 1.4 : 1.0)
                .opacity(breathe ? 0.0 : 0.7)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
                breathe = true
            }
        }
    }
}

// MARK: - Grain Texture
struct GrainTexture: View {
    var opacity: Double = 0.03

    var body: some View {
        Canvas { context, size in
            let count = Int(size.width * size.height * 0.04)
            for _ in 0..<count {
                let x = Double.random(in: 0...size.width)
                let y = Double.random(in: 0...size.height)
                context.opacity = Double.random(in: 0.08...0.3)
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black))
            }
        }
        .opacity(opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Legacy Noise Texture
struct NoiseTexture: View {
    var opacity: Double = 0.03

    var body: some View {
        GrainTexture(opacity: opacity)
    }
}

// MARK: - View Extensions
extension View {
    func withAuroraBackground() -> some View {
        background(AuroraBackground())
    }

    func liquidGlassCard(style: GlassSurfaceStyle = .standard, padding: CGFloat = 20) -> some View {
        LiquidGlassCard(style: style, padding: padding) { self }
    }
}

// MARK: - Preview
struct Theme_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 24) {
                Text("AntiAnxiety")
                    .font(GlassTypography.display(34, weight: .semibold))
                    .foregroundColor(.textPrimary)

                LiquidGlassCard(style: .elevated) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("整体状态")
                            .font(GlassTypography.caption())
                            .foregroundColor(.textSecondary)
                        Text("85")
                            .font(GlassTypography.display(40, weight: .bold))
                            .foregroundColor(.textPrimary)
                    }
                }

                Button("开始校准") {}
                    .buttonStyle(LiquidGlassButtonStyle(isProminent: true))

                PulsingOrb()
            }
            .padding()
        }
        .preferredColorScheme(.light)
    }
}
