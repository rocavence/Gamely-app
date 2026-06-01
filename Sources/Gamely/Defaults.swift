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

    /// The user's real Hot Corner settings, saved while we have them disabled.
    /// Non-nil means "we currently have Hot Corners paused" — used to restore
    /// after Game Mode ends, and to recover if Gamely crashed mid-game.
    static var savedCorners: [String: Int]? {
        get { UserDefaults.standard.dictionary(forKey: "Gamely.savedCorners") as? [String: Int] }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: "Gamely.savedCorners")
            } else {
                UserDefaults.standard.removeObject(forKey: "Gamely.savedCorners")
            }
        }
    }
}
