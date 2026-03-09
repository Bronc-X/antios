import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en

    static var allCases: [AppLanguage] { [.zhHans, .zhHant, .en] }
    var id: String { rawValue }
}

struct L10n {
    static func text(_ zh: String, _ en: String, language: AppLanguage) -> String {
        switch language {
        case .en:
            return en
        case .zhHant:
            return toTraditional(zh)
        case .zh, .zhHans:
            return zh
        }
    }

    static func toTraditional(_ text: String) -> String {
        let mutable = NSMutableString(string: text) as CFMutableString
        CFStringTransform(mutable, nil, "Hans-Hant" as CFString, false)
        return mutable as String
    }
}

extension Color {
    init(hex: String) {
        let sanitized = hex
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")

        let scanner = Scanner(string: sanitized)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)

        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double

        switch sanitized.count {
        case 8:
            red = Double((value & 0xFF00_0000) >> 24) / 255
            green = Double((value & 0x00FF_0000) >> 16) / 255
            blue = Double((value & 0x0000_FF00) >> 8) / 255
            alpha = Double(value & 0x0000_00FF) / 255
        default:
            red = Double((value & 0xFF00_00) >> 16) / 255
            green = Double((value & 0x00FF_00) >> 8) / 255
            blue = Double(value & 0x0000_FF) / 255
            alpha = 1
        }

        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
