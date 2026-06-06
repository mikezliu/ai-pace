import AppKit
import SwiftUI

struct AppTheme: Identifiable {
    let id: String
    let name: String
    let claudeAccent: Color
    let codexAccent: Color
    /// When true, the menu bar pill color is derived from live usage instead of
    /// the fixed accents above (which are then only a neutral popover fallback).
    var isDynamic: Bool = false

    static let dynamic = AppTheme(
        id: "dynamic", name: "Dynamic",
        claudeAccent: Color(red: 0.55, green: 0.50, blue: 0.45),
        codexAccent: Color(red: 0.40, green: 0.48, blue: 0.55),
        isDynamic: true
    )

    static let sunset = AppTheme(
        id: "sunset", name: "Sunset",
        claudeAccent: Color(red: 0.95, green: 0.45, blue: 0.10),
        codexAccent: Color(red: 0.10, green: 0.50, blue: 0.95)
    )

    static let neon = AppTheme(
        id: "neon", name: "Neon",
        claudeAccent: Color(red: 0.95, green: 0.15, blue: 0.45),
        codexAccent: Color(red: 0.05, green: 0.80, blue: 0.35)
    )

    static let ocean = AppTheme(
        id: "ocean", name: "Ocean",
        claudeAccent: Color(red: 0.92, green: 0.30, blue: 0.25),
        codexAccent: Color(red: 0.0, green: 0.65, blue: 0.75)
    )

    static let forest = AppTheme(
        id: "forest", name: "Forest",
        claudeAccent: Color(red: 0.85, green: 0.55, blue: 0.05),
        codexAccent: Color(red: 0.05, green: 0.65, blue: 0.35)
    )

    static let berry = AppTheme(
        id: "berry", name: "Berry",
        claudeAccent: Color(red: 0.78, green: 0.15, blue: 0.55),
        codexAccent: Color(red: 0.30, green: 0.25, blue: 0.85)
    )

    static let citrus = AppTheme(
        id: "citrus", name: "Citrus",
        claudeAccent: Color(red: 0.92, green: 0.42, blue: 0.0),
        codexAccent: Color(red: 0.35, green: 0.75, blue: 0.05)
    )

    static let arctic = AppTheme(
        id: "arctic", name: "Arctic",
        claudeAccent: Color(red: 0.88, green: 0.28, blue: 0.38),
        codexAccent: Color(red: 0.15, green: 0.55, blue: 0.82)
    )

    static let volcano = AppTheme(
        id: "volcano", name: "Volcano",
        claudeAccent: Color(red: 0.88, green: 0.18, blue: 0.12),
        codexAccent: Color(red: 0.85, green: 0.65, blue: 0.0)
    )

    static let aurora = AppTheme(
        id: "aurora", name: "Aurora",
        claudeAccent: Color(red: 0.55, green: 0.25, blue: 0.90),
        codexAccent: Color(red: 0.05, green: 0.72, blue: 0.48)
    )

    static let mono = AppTheme(
        id: "mono", name: "Mono",
        claudeAccent: Color(red: 0.55, green: 0.50, blue: 0.45),
        codexAccent: Color(red: 0.40, green: 0.48, blue: 0.55)
    )

    static let all: [AppTheme] = [
        .dynamic,
        .sunset, .neon, .ocean, .forest, .berry,
        .citrus, .arctic, .volcano, .aurora, .mono,
    ]

    static let defaultTheme = dynamic
    static let customClaudeAccentDefaultsKey = "customClaudeAccentHex"
    static let customCodexAccentDefaultsKey = "customCodexAccentHex"

    static func find(_ id: String) -> AppTheme {
        all.first { $0.id == id } ?? defaultTheme
    }

    func overriding(claudeAccent: Color? = nil, codexAccent: Color? = nil) -> AppTheme {
        AppTheme(
            id: id,
            name: name,
            claudeAccent: claudeAccent ?? self.claudeAccent,
            codexAccent: codexAccent ?? self.codexAccent,
            isDynamic: isDynamic
        )
    }

    static func resolvedTheme(themeID: String, userDefaults: UserDefaults = .standard) -> AppTheme {
        resolvedTheme(
            themeID: themeID,
            customClaudeAccentHex: userDefaults.string(forKey: customClaudeAccentDefaultsKey),
            customCodexAccentHex: userDefaults.string(forKey: customCodexAccentDefaultsKey)
        )
    }

    static func resolvedTheme(
        themeID: String,
        customClaudeAccentHex: String?,
        customCodexAccentHex: String?
    ) -> AppTheme {
        find(themeID).overriding(
            claudeAccent: AppColorHex.color(from: customClaudeAccentHex),
            codexAccent: AppColorHex.color(from: customCodexAccentHex)
        )
    }
}

/// Background + foreground colors for a single menu bar pill.
struct StatusPillStyle: Equatable {
    let background: Color
    let foreground: Color
}

/// Severity buckets for the Dynamic theme, based on how much usage remains.
enum DynamicThemeLevel: Equatable {
    case normal    // >= 30% remaining
    case caution   // < 30%
    case warning   // < 20%
    case critical  // < 10%

    static func level(forRemaining remaining: Double?) -> DynamicThemeLevel {
        guard let remaining else {
            return .normal
        }
        if remaining < 10 {
            return .critical
        }
        if remaining < 20 {
            return .warning
        }
        if remaining < 30 {
            return .caution
        }
        return .normal
    }
}

/// Computes the menu bar pill style for the Dynamic theme. Warning levels use
/// vivid backgrounds with high-contrast text; the healthy state uses the system
/// window/label colors so it blends into the menu bar like ordinary text.
enum DynamicTheme {
    static let cautionBackground = Color(red: 0.98, green: 0.78, blue: 0.10)  // yellow
    static let warningBackground = Color(red: 0.95, green: 0.50, blue: 0.05)  // orange
    static let criticalBackground = Color(red: 0.82, green: 0.10, blue: 0.10) // red

    static func pillStyle(forRemaining remaining: Double?, isDark: Bool) -> StatusPillStyle {
        switch DynamicThemeLevel.level(forRemaining: remaining) {
        case .critical:
            return StatusPillStyle(background: criticalBackground, foreground: .white)
        case .warning:
            return StatusPillStyle(background: warningBackground, foreground: .black)
        case .caution:
            return StatusPillStyle(background: cautionBackground, foreground: .black)
        case .normal:
            return StatusPillStyle(
                background: systemColor(.windowBackgroundColor, isDark: isDark),
                foreground: systemColor(.labelColor, isDark: isDark)
            )
        }
    }

    /// Resolves a dynamic system color to a concrete sRGB color for the given
    /// appearance, so it renders correctly in the status item image (which is
    /// drawn outside the normal appearance context).
    private static func systemColor(_ nsColor: NSColor, isDark: Bool) -> Color {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        var resolved = nsColor
        appearance?.performAsCurrentDrawingAppearance {
            resolved = nsColor.usingColorSpace(.sRGB) ?? nsColor
        }
        return Color(nsColor: resolved)
    }
}

enum AppColorHex {
    static func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()

        let expanded: String
        switch trimmed.count {
        case 3:
            expanded = trimmed.map { "\($0)\($0)" }.joined()
        case 6:
            expanded = trimmed
        default:
            return nil
        }

        guard expanded.allSatisfy(\.isHexDigit) else {
            return nil
        }

        return "#\(expanded)"
    }

    static func color(from value: String?) -> Color? {
        guard let normalized = normalized(value) else {
            return nil
        }

        let hex = String(normalized.dropFirst())
        guard let int = UInt32(hex, radix: 16) else {
            return nil
        }

        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }

    static func string(from color: Color) -> String? {
        let nsColor = NSColor(color)
        guard let srgb = nsColor.usingColorSpace(.sRGB) else {
            return nil
        }

        let red = Int((srgb.redComponent * 255).rounded())
        let green = Int((srgb.greenComponent * 255).rounded())
        let blue = Int((srgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}
