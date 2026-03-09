// LiquidGlassTheme.swift
// antios10 共享玻璃视觉基础（Mist / Spatial / Minimal）

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

    /// TabBar 宽度（基于 fixedScreenWidth，确保布局稳定）
    var tabBarWidth: CGFloat {
        let baseWidth = fixedScreenWidth - tabBarHorizontalPadding * 2
        return alignToPixel(min(max(0, baseWidth), 560))
    }

    var bottomContentInset: CGFloat {
        tabBarHeight + tabBarBottomPadding + 20
    }

    var maxContentWidth: CGFloat {
        // iOS 26 下左右 safe-area 可能出现轻微不对称，使用 fixedScreenWidth 作为列宽基准可避免整页横向漂移。
        max(0, min(fixedScreenWidth - horizontalPadding * 2, 560))
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
        .system(size: size, weight: weight, design: .rounded)
    }

    static func loviBody(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func cnLovi(_ size: CGFloat = 16, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
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
    static let deepGreen = Color(hex: "#55625A")
    static let deepGreenDarker = Color(hex: "#1E222A")
    static let paperWhite = Color(hex: "#F4F6F0")
    static let sageGreen = Color(hex: "#C4D0BE")
    static let lightGrey = Color(hex: "#F7F8F4")
    static let softBlack = Color(hex: "#202520")
    
    // 语义色 (Semantic - Dynamic)
    static let bgPrimary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#121111") : UIColor(hex: "#F4F6F0")
    })

    static let bgSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#181716") : UIColor(hex: "#EDF1E9")
    })

    static let bgTertiary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#211F20") : UIColor(hex: "#E5EADF")
    })

    // Logo & Brand Colors
    static let brandDeepGreen = Color.deepGreen
    static let brandPaper = Color.paperWhite
    static let brandMoss = Color.sageGreen
    static let brandSage = Color(hex: "#E7EEE2")
    
    // Liquid Glass Specifics
    static let liquidGlassPrimary = Color.bgPrimary
    static let liquidGlassAccent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#DCE5D9") : UIColor(hex: "#55625A")
    })
    static let liquidGlassPurple = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#B7B1C0") : UIColor(hex: "#D6DDD4")
    })
    static let liquidGlassSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#A7B1A8") : UIColor(hex: "#C7D0C5")
    })
    static let liquidGlassWarm = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#B59983") : UIColor(hex: "#D0BFB0")
    })
    static let liquidGlassFreshGreen = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#89A28B") : UIColor(hex: "#B5C7B3")
    })

    // Status Colors
    static let statusSuccess = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#87B08E") : UIColor(hex: "#527861")
    })
    static let statusWarning = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#D0AF73") : UIColor(hex: "#B79153")
    })
    static let statusError = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#E36B61") : UIColor(hex: "#D45E55")
    })

    // Text Colors (Dynamic)
    static let textPrimary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#F2F1EC") : UIColor(hex: "#1F2320")
    })

    static let textSecondary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#C7CCC2") : UIColor(hex: "#667065")
    })

    static let textTertiary = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: "#9DA398") : UIColor(hex: "#8A9287")
    })

    static func textPrimary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#F2F1EC") : Color(hex: "#1F2320")
    }

    static func textSecondary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#C7CCC2") : Color(hex: "#667065")
    }

    static func textTertiary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#9DA398") : Color(hex: "#8A9287")
    }

    static func surfaceGlass(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color(hex: "#202224").opacity(0.62)
        }
        return Color.white.opacity(0.72)
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
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(hex: "#171513"),
                        Color(hex: "#1E1A17"),
                        Color(hex: "#121111")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color(hex: "#E6F4E1"),
                        Color(hex: "#F4F6F0")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color(hex: "#EEE8DE").opacity(0.36),
                        Color.white.opacity(0.02)
                    ],
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )
                .ignoresSafeArea()
            }

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.34))
                .frame(width: 320, height: 320)
                .blur(radius: colorScheme == .dark ? 94 : 78)
                .offset(x: animate ? -120 : -160, y: -180)

            Circle()
                .fill(Color.bioGlow(for: colorScheme).opacity(colorScheme == .dark ? 0.16 : 0.1))
                .frame(width: 420, height: 420)
                .blur(radius: colorScheme == .dark ? 100 : 88)
                .offset(x: animate ? 100 : 140, y: 260)

            Circle()
                .fill(Color.liquidGlassFreshGreen.opacity(colorScheme == .dark ? 0.14 : 0.12))
                .frame(width: colorScheme == .dark ? 230 : 180, height: colorScheme == .dark ? 230 : 180)
                .blur(radius: colorScheme == .dark ? 68 : 54)
                .offset(x: animate ? 112 : 72, y: animate ? -92 : -126)

            if colorScheme == .light {
                Circle()
                    .fill(Color.liquidGlassSecondary.opacity(0.22))
                    .frame(width: 260, height: 260)
                    .blur(radius: 64)
                    .offset(x: animate ? 60 : 20, y: 40)
            }
            
            if colorScheme == .dark {
                Circle()
                    .fill(Color.bioluminPink(for: colorScheme).opacity(0.08))
                    .frame(width: 200, height: 200)
                    .blur(radius: 74)
                    .offset(x: 0, y: 0)
                    .scaleEffect(animate ? 1.05 : 0.95)
            }

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
                    : [Color.white.opacity(0.28), Color(hex: "#DCE5D8").opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .concave:
            return LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.black.opacity(0.2), Color.black.opacity(0.08)]
                    : [Color.white.opacity(0.2), Color(hex: "#E3EADF").opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .elevated:
            return LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.08), Color(hex: "#C6D2C2").opacity(0.02)]
                    : [Color.white.opacity(0.44), Color(hex: "#E8EEE2").opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .standard:
            return LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.05), Color.white.opacity(0.01)]
                    : [Color.white.opacity(0.34), Color(hex: "#E4EBDD").opacity(0.18)],
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
            return style == .elevated ? 0.22 : 0.12
        }
        return style == .elevated ? 0.09 : 0.05
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
