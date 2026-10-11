import Foundation

enum Defaults {
    /// Whether Gamely should pause Hot Corners during Game Mode. Default on.
    static var enabled: Bool {
        get { (UserDefaults.standard.object(forKey: "Gamely.enabled") as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "Gamely.enabled") }
    }

    /// Bundle IDs of apps that should force "Game Mode" even when macOS doesn't
    /// report real Game Mode (e.g. Steam, CrossOver translation-layer games).
    /// When one of these is frontmost, Hot Corners are paused too.
    static var whitelist: [String] {
        get { (UserDefaults.standard.array(forKey: "Gamely.whitelist") as? [String]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "Gamely.whitelist") }
    }
}
