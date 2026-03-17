import SwiftUI

enum A10SpatialPalette {
    static let mistTop = Color(hex: "#E6F4E1")
    static let mistBottom = Color(hex: "#F4F6F0")
    static let mistWarm = Color(hex: "#EEE8DE")

    static let panelFill = Color.white.opacity(0.16)
    static let panelSheen = Color.white.opacity(0.48)
    static let panelEdge = Color.white.opacity(0.24)
    static let fogText = Color.white.opacity(0.9)
    static let fogSubtext = Color.white.opacity(0.58)
    static let fogHint = Color.white.opacity(0.34)

    static let graphite = Color(hex: "#1E222A")
    static let graphiteSoft = Color(hex: "#2B323A")
    static let stageLight = Color(hex: "#ECECEC")
    static let floatingShadow = Color.black.opacity(0.14)

    static let pillWhite = Color.white.opacity(0.9)
    static let pillEdge = Color.white.opacity(0.62)
    static let signalRed = Color(hex: "#E83A30")
    static let signalRedGlow = Color(hex: "#FF7B70")

    static let wheelCanvas = Color(hex: "#121111")
    static let wheelText = Color.white.opacity(0.82)
    static let wheelMuted = Color.white.opacity(0.36)
    static let wheelRing = Color.white.opacity(0.1)
    static let wheelTrack = Color(hex: "#4A4650")
    static let wheelTrackDeep = Color(hex: "#302D34")
    static let wheelTrackStroke = Color.white.opacity(0.06)
    static let wheelPetalStroke = Color.white.opacity(0.1)
    static let wheelDock = Color(hex: "#1C1A1D")
    static let wheelCard = Color(hex: "#E2D9F2")
    static let wheelPetals: [Color] = [
        Color(hex: "#B7A9D3"),
        Color(hex: "#C5B5C7"),
        Color(hex: "#D8D0E0"),
        Color(hex: "#9F99AE"),
        Color(hex: "#7D7A84"),
        Color(hex: "#8F8597"),
        Color(hex: "#DFD6E9"),
        Color(hex: "#B8B0C4")
    ]

    static func heroPanelFill(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return panelFill
        }
        return Color.white.opacity(0.54)
    }

    static func heroPanelSheen(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return panelSheen
        }
        return Color.white.opacity(0.76)
    }

    static func heroPanelEdge(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return panelEdge
        }
        return Color(hex: "#CCD5C9").opacity(0.88)
    }

    static func heroPrimaryText(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return fogText
        }
        return Color.textPrimary(for: scheme).opacity(0.96)
    }

    static func heroSecondaryText(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return fogSubtext
        }
        return Color.textSecondary(for: scheme).opacity(0.94)
    }

    static func heroTertiaryText(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return fogHint
        }
        return Color(hex: "#7A8577").opacity(0.96)
    }

    static func heroChartLine(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.84)
        }
        return Color(hex: "#536254").opacity(0.94)
    }

    static func heroChartGlow(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.white
        }
        return Color(hex: "#A7B9A3")
    }

    static func heroPointFill(for scheme: ColorScheme, highlighted: Bool) -> Color {
        if scheme == .dark {
            return Color.white.opacity(highlighted ? 0.85 : 0.45)
        }
        return highlighted
            ? Color(hex: "#4E5F51").opacity(0.96)
            : Color(hex: "#738171").opacity(0.8)
    }

    static func heroTagFill(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.12)
        }
        return Color.white.opacity(0.5)
    }

    static func heroTagBorder(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.16)
        }
        return Color(hex: "#C9D3C6").opacity(0.94)
    }

    static func heroTagText(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.86)
        }
        return Color(hex: "#4A554B").opacity(0.96)
    }

    static func heroProductionBar(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.36)
        }
        return Color(hex: "#81907E").opacity(0.42)
    }

    static func heroShadow(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.black.opacity(0.05)
        }
        return Color(hex: "#AAB5A4").opacity(0.18)
    }

    static func heroTopSheen(for scheme: ColorScheme) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.16)
        }
        return Color.white.opacity(0.58)
    }
}

enum A10SpatialSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum A10SpatialRadius {
    static let pill: CGFloat = 999
    static let card: CGFloat = 34
    static let panel: CGFloat = 42
    static let wheelCard: CGFloat = 26
}

enum A10SpatialMotion {
    static let snap = Animation.interpolatingSpring(
        mass: 0.8,
        stiffness: 400,
        damping: 30,
        initialVelocity: 0
    )
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.74)
    static let aura = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
}

enum A10SpatialTypography {
    static func heroNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .ultraLight, design: .default)
    }

    static func title(_ size: CGFloat = 18, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func body(_ size: CGFloat = 15, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func label(_ size: CGFloat = 12, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func wheelLabel(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func wheelValue(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

struct A10MistCanvas: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [
                        A10SpatialPalette.mistTop,
                        A10SpatialPalette.mistBottom
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: max(proxy.size.width, proxy.size.height) * 1.1
                )

                LinearGradient(
                    colors: [
                        A10SpatialPalette.mistWarm.opacity(0.32),
                        Color.white.opacity(0)
                    ],
                    startPoint: .bottomTrailing,
                    endPoint: .topLeading
                )

                Circle()
                    .fill(Color.white.opacity(0.34))
                    .frame(width: proxy.size.width * 0.46, height: proxy.size.width * 0.46)
                    .blur(radius: 56)
                    .offset(x: proxy.size.width * 0.22, y: proxy.size.height * 0.22)

                Circle()
                    .fill(Color(hex: "#D9E6D1").opacity(0.28))
                    .frame(width: proxy.size.width * 0.54, height: proxy.size.width * 0.54)
                    .blur(radius: 72)
                    .offset(x: -proxy.size.width * 0.2, y: -proxy.size.height * 0.12)
            }
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

enum A10SpatialStageMode {
    case lightCanvas
    case darkBackdrop
}

struct A10SpatialBackdrop: View {
    let mode: A10SpatialStageMode

    var body: some View {
        ZStack {
            switch mode {
            case .lightCanvas:
                LinearGradient(
                    colors: [
                        Color(hex: "#F5F5F3"),
                        A10SpatialPalette.stageLight
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RoundedRectangle(cornerRadius: 44, style: .continuous)
                    .fill(Color.white.opacity(0.48))
                    .padding(18)

            case .darkBackdrop:
                LinearGradient(
                    colors: [
                        Color(hex: "#271F1B"),
                        Color(hex: "#121112")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 250, height: 156)
                    .blur(radius: 0.6)
                    .offset(x: 62, y: -60)

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                    .frame(width: 150, height: 162)
                    .offset(x: -86, y: 34)
                    .blur(radius: 2)

                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 132, height: 12)
                    .blur(radius: 8)
                    .offset(y: -72)

                Circle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .blur(radius: 90)
                    .offset(x: -130, y: 80)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }
}
