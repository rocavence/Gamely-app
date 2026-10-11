import SwiftUI

/// The one colour Gamely chooses: the accent. It marks what's chosen and what's
/// on (the page you're on, a switch, a button) and nothing else. Gamely purple,
/// taken from the app icon, by default; or the system's own accent, or one of
/// the seven vivid colours Wunder offers, each named for the designer or artist
/// it calls to mind.
enum Accent: String, CaseIterable, Sendable {
    case gamely, system, orange, red, pink, purple, blue, glacier, green

    static let key = "Gamely.accent"

    var title: String {
        switch self {
        case .gamely: String(localized: "Gamely Purple")
        case .system: String(localized: "System")
        case .orange: String(localized: "Rams Orange")
        case .red: String(localized: "Matisse Red")
        case .pink: String(localized: "Barragán Pink")
        case .purple: String(localized: "Iris Purple")
        case .blue: String(localized: "Klein Blue")
        case .glacier: String(localized: "Hockney Blue")
        case .green: String(localized: "Monet Green")
        }
    }

    /// The top of the app icon's gradient; then Braun's orange, Matisse's red studio, Barragán's pink walls, Van Gogh's
    /// irises, Klein's blue, Hockney's pools, Monet's bridge at Giverny.
    var color: Color {
        switch self {
        case .gamely: Self.rgb(0x7D4FF7)
        case .system: .accentColor
        case .orange: Self.rgb(0xED3F1C)
        case .red: Self.rgb(0xD21F3C)
        case .pink: Self.rgb(0xE5508F)
        case .purple: Self.rgb(0x7C5CF5)
        case .blue: Self.rgb(0x2147E0)
        case .glacier: Self.rgb(0x23A6DA)
        case .green: Self.rgb(0x2AA572)
        }
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// The accent as text. On a dark background the saturated accents (Gamely
/// purple, Klein blue…) fall below a readable contrast, so text lifts them a
/// third of the way to white; fills keep the accent as is.
struct AccentText: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        let raw = UserDefaults.standard.string(forKey: Accent.key).flatMap(Accent.init) ?? .gamely
        guard environment.colorScheme == .dark,
              let lifted = NSColor(raw.color).usingColorSpace(.sRGB)?.blended(withFraction: 0.35, of: .white) else {
            return raw.color
        }
        return Color(nsColor: lifted)
    }
}

extension ShapeStyle where Self == AccentText {
    static var accentText: AccentText { AccentText() }
}
