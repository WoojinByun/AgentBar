import SwiftUI

enum ServiceType: String, CaseIterable, Codable, Sendable {
    case claude  = "Claude Code"
    case codex   = "OpenAI Codex"
    case gemini  = "Google Gemini"
    case copilot = "GitHub Copilot"
    case cursor  = "Cursor"
    case opencode = "OpenCode"
    case zai     = "Z.ai Coding Plan"

    /// User-chosen color when set in Settings, otherwise the built-in default.
    var darkColor: Color {
        ServiceColorSettings.customColor(for: self) ?? defaultDarkColor
    }

    /// Lighter shade of a custom color, otherwise the built-in default.
    var lightColor: Color {
        ServiceColorSettings.customLightColor(for: self) ?? defaultLightColor
    }

    var defaultDarkColor: Color {
        switch self {
        case .claude:  Color(red: 0.851, green: 0.467, blue: 0.024) // amber-600
        case .codex:   Color(red: 0.60, green: 0.63, blue: 0.67)     // gray-400
        case .gemini:  Color(red: 0.102, green: 0.431, blue: 0.882) // blue-600
        case .copilot: Color(red: 0.09, green: 0.47, blue: 0.95)    // blue-600
        case .cursor:  Color(red: 0.15, green: 0.68, blue: 0.38)    // green-600
        case .opencode: Color(red: 0.0, green: 0.62, blue: 0.74)    // cyan-600
        case .zai:     Color(red: 0.486, green: 0.227, blue: 0.929) // violet-600
        }
    }

    var defaultLightColor: Color {
        switch self {
        case .claude:  Color(red: 0.988, green: 0.827, blue: 0.302) // amber-300
        case .codex:   Color(red: 0.82, green: 0.84, blue: 0.86)     // gray-200
        case .gemini:  Color(red: 0.576, green: 0.773, blue: 0.992) // blue-300
        case .copilot: Color(red: 0.53, green: 0.75, blue: 0.99)    // blue-300
        case .cursor:  Color(red: 0.49, green: 0.89, blue: 0.64)    // green-300
        case .opencode: Color(red: 0.57, green: 0.89, blue: 0.95)   // cyan-300
        case .zai:     Color(red: 0.769, green: 0.710, blue: 0.992) // violet-300
        }
    }

    var shortName: String {
        switch self {
        case .claude:  "CC"
        case .codex:   "CX"
        case .gemini:  "GM"
        case .copilot: "CP"
        case .cursor:  "CR"
        case .opencode: "OC"
        case .zai:     "Z"
        }
    }

    var fiveHourLabel: String {
        switch self {
        case .gemini: "1d"
        case .copilot, .cursor: "Mo"
        default: "5h"
        }
    }

    var weeklyLabel: String {
        switch self {
        case .zai: "MCP"
        default: "7d"
        }
    }

    /// Whether this service uses the standard 5h / 7d dual-window structure.
    var hasFiveHourSevenDayStructure: Bool {
        fiveHourLabel == "5h" && weeklyLabel == "7d"
    }

    var keychainAccount: String {
        switch self {
        case .claude:  "claude"
        case .codex:   "openai"
        case .gemini:  "gemini"
        case .copilot: "copilot"
        case .cursor:  "cursor"
        case .opencode: "opencode"
        case .zai:     "zai"
        }
    }
}


/// Per-agent color overrides stored in UserDefaults as `#RRGGBB` strings.
enum ServiceColorSettings {
    /// Lightness mix toward white used to derive the weekly (light) shade.
    private static let lightMix: Double = 0.55

    static func defaultsKey(for service: ServiceType) -> String {
        "serviceColor.\(service.keychainAccount)"
    }

    static func customHex(for service: ServiceType, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: defaultsKey(for: service)).flatMap { rgb(fromHex: $0) == nil ? nil : $0 }
    }

    static func customColor(for service: ServiceType, defaults: UserDefaults = .standard) -> Color? {
        customHex(for: service, defaults: defaults)
            .flatMap(rgb(fromHex:))
            .map { Color(red: $0.r, green: $0.g, blue: $0.b) }
    }

    static func customLightColor(for service: ServiceType, defaults: UserDefaults = .standard) -> Color? {
        customHex(for: service, defaults: defaults)
            .flatMap(rgb(fromHex:))
            .map {
                Color(
                    red: $0.r + (1 - $0.r) * lightMix,
                    green: $0.g + (1 - $0.g) * lightMix,
                    blue: $0.b + (1 - $0.b) * lightMix
                )
            }
    }

    /// Stores `color`, or clears the override when `nil`.
    static func setCustomColor(_ color: Color?, for service: ServiceType, defaults: UserDefaults = .standard) {
        if let color, let hex = hex(from: color) {
            defaults.set(hex, forKey: defaultsKey(for: service))
        } else {
            defaults.removeObject(forKey: defaultsKey(for: service))
        }
        NotificationCenter.default.post(name: .serviceColorsChanged, object: nil)
    }

    static func hex(from color: Color) -> String? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let channel = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(
            format: "#%02X%02X%02X",
            channel(srgb.redComponent), channel(srgb.greenComponent), channel(srgb.blueComponent)
        )
    }

    static func rgb(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        let trimmed = hex.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}

extension Notification.Name {
    static let serviceColorsChanged = Notification.Name("AgentBarServiceColorsChanged")
}
