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

    /// Show a banner when Hot Corners are paused or restored. Default off.
    static var notifies: Bool {
        get { UserDefaults.standard.bool(forKey: "Gamely.notifies") }
        set { UserDefaults.standard.set(newValue, forKey: "Gamely.notifies") }
    }

    /// The first-run guide has been seen.
    static var onboarded: Bool {
        get { UserDefaults.standard.bool(forKey: "Gamely.onboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "Gamely.onboarded") }
    }

    static var lastPausedAt: Date? {
        get { UserDefaults.standard.object(forKey: "Gamely.lastPausedAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "Gamely.lastPausedAt") }
    }

    static var lastRestoredAt: Date? {
        get { UserDefaults.standard.object(forKey: "Gamely.lastRestoredAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "Gamely.lastRestoredAt") }
    }
}
