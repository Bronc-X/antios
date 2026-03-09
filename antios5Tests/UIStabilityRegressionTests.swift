import XCTest
import SwiftUI
import UIKit
@testable import antios5

final class UIStabilityRegressionTests: XCTestCase {
    func testMaxContentWidthIgnoresAsymmetricSafeAreas() {
        let asymmetric = ScreenMetrics(
            size: CGSize(width: 390, height: 844),
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 24)
        )
        let symmetric = ScreenMetrics(
            size: CGSize(width: 390, height: 844),
            safeAreaInsets: EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        )

        XCTAssertEqual(asymmetric.maxContentWidth, symmetric.maxContentWidth, accuracy: 0.01)
        XCTAssertEqual(asymmetric.maxContentWidth, 354, accuracy: 0.01)
    }

    func testStableCenteredWidthRespectsMinMaxAndFraction() {
        let regular = ScreenMetrics(
            size: CGSize(width: 430, height: 932),
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        )
        let compact = ScreenMetrics(
            size: CGSize(width: 320, height: 568),
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        )

        XCTAssertEqual(regular.stableCenteredWidth(maxWidth: 320, fraction: 0.78), 320, accuracy: 0.01)
        XCTAssertEqual(
            compact.stableCenteredWidth(maxWidth: 620, minWidth: 300, horizontalInset: 8),
            304,
            accuracy: 0.01
        )
    }

    func testAccentContrastIsReadableInLightAndDark() {
        assertContrast(
            foreground: .textOnAccent,
            background: .liquidGlassAccent,
            style: .light,
            minimum: 4.5
        )
        assertContrast(
            foreground: .textOnAccent,
            background: .liquidGlassAccent,
            style: .dark,
            minimum: 4.5
        )
    }

    func testPrimaryTextContrastStaysReadableAgainstPrimaryBackground() {
        assertContrast(
            foreground: .textPrimary,
            background: .bgPrimary,
            style: .light,
            minimum: 7.0
        )
        assertContrast(
            foreground: .textPrimary,
            background: .bgPrimary,
            style: .dark,
            minimum: 7.0
        )
    }

    func testSplashLogoContrastStaysReadableInLightMode() {
        assertContrast(
            foreground: Color.splashLogoPrimary(for: .light),
            background: Color.splashMarkPlateFill(for: .light),
            style: .light,
            minimum: 4.5
        )
        assertContrast(
            foreground: Color.splashLogoSecondary(for: .light),
            background: Color.splashMarkPlateFill(for: .light),
            style: .light,
            minimum: 3.0
        )
    }

    private func assertContrast(
        foreground: Color,
        background: Color,
        style: UIUserInterfaceStyle,
        minimum: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ratio = contrastRatio(
            resolvedUIColor(foreground, style: style),
            resolvedUIColor(background, style: style)
        )

        XCTAssertGreaterThanOrEqual(
            ratio,
            minimum,
            "Contrast ratio \(ratio) is below \(minimum) in \(style == .dark ? "dark" : "light") mode.",
            file: file,
            line: line
        )
    }

    private func resolvedUIColor(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
        UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
    }

    private func contrastRatio(_ lhs: UIColor, _ rhs: UIColor) -> CGFloat {
        let lhsLuminance = relativeLuminance(lhs)
        let rhsLuminance = relativeLuminance(rhs)
        let lighter = max(lhsLuminance, rhsLuminance)
        let darker = min(lhsLuminance, rhsLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> CGFloat {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        func channel(_ value: CGFloat) -> CGFloat {
            if value <= 0.03928 {
                return value / 12.92
            }
            return pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }
}
