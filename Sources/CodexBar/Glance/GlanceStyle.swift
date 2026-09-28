import AppKit
import CodexBarCore
import CoreText
import SwiftUI

enum GlanceStyle {
    static let ink = Color.black
    static let primary = Color.white.opacity(0.94)
    static let secondary = Color.white.opacity(0.48)
    static let faint = Color.white.opacity(0.26)
    static let track = Color.white.opacity(0.12)
    static let hairline = Color.white.opacity(0.08)
    static let amber = Color(red: 0.96, green: 0.72, blue: 0.29)
    static let ember = Color(red: 1.0, green: 0.36, blue: 0.31)

    static let expand = Animation.spring(response: 0.38, dampingFraction: 0.84)
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.9)

    static func tint(_ severity: GlanceSeverity) -> Color {
        switch severity {
        case .calm: primary
        case .watch: amber
        case .low: ember
        }
    }

    static func numerals(_ size: CGFloat) -> Font {
        .custom(GlanceFonts.monoName, fixedSize: size)
    }

    static func label(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).monospacedDigit()
    }
}

enum GlanceFonts {
    static let monoName = "DepartureMono-Regular"
    @MainActor private static var registered = false

    @MainActor
    static func registerIfNeeded() {
        guard !self.registered else { return }
        self.registered = true
        let candidates = [
            Bundle.main.url(forResource: "DepartureMono-Regular", withExtension: "otf", subdirectory: "Fonts"),
            Bundle.main.url(forResource: "DepartureMono-Regular", withExtension: "otf"),
        ]
        guard let url = candidates.compactMap(\.self).first else {
            CodexBarLog.logger(LogCategories.app).error("Glance font missing from bundle; falling back to system")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let message = error?.takeRetainedValue().localizedDescription ?? "unknown"
            CodexBarLog.logger(LogCategories.app).error(
                "Glance font registration failed",
                metadata: ["error": message])
        }
    }
}
