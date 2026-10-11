/// What a Hot Corner does, as stored in the Dock's `wvous-*-corner` value, and
/// the keys held with it (`wvous-*-modifier`).
enum HotCornerAction {
    static func name(_ value: Int) -> String {
        switch value {
        case 2: String(localized: "Mission Control")
        case 3: String(localized: "Application Windows")
        case 4: String(localized: "Desktop")
        case 5: String(localized: "Start Screen Saver")
        case 6: String(localized: "Disable Screen Saver")
        case 7: String(localized: "Dashboard")
        case 10: String(localized: "Put Display to Sleep")
        case 11: String(localized: "Launchpad")
        case 12: String(localized: "Notification Center")
        case 13: String(localized: "Lock Screen")
        case 14: String(localized: "Quick Note")
        default: "—"
        }
    }

    /// ⇧⌃⌥⌘ for the modifier bits, in the order macOS shows them.
    static func symbols(_ modifier: Int) -> String {
        [(131_072, "⇧"), (262_144, "⌃"), (524_288, "⌥"), (1_048_576, "⌘")]
            .filter { modifier & $0.0 != 0 }
            .map(\.1)
            .joined()
    }

    /// "⌘ Mission Control", or "—" when the corner does nothing.
    static func describe(corner: Int, modifier: Int) -> String {
        let action = name(corner)
        guard action != "—" else { return action }
        let keys = symbols(modifier)
        return keys.isEmpty ? action : "\(keys) \(action)"
    }

    /// The four corners in reading order, as (corner key, modifier key).
    static let positions: [(corner: String, modifier: String)] =
        Array(zip(HotCornerController.corners, HotCornerController.modifiers))
}
