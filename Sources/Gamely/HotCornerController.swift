import Foundation

/// Pauses and restores macOS Hot Corners by editing the Dock's `wvous-*`
/// preferences and restarting the Dock. The user's real settings are saved to
/// Gamely's own defaults before we touch them, so they survive a crash.
enum HotCornerController {
    private static var dock: UserDefaults? { UserDefaults(suiteName: "com.apple.dock") }
    private static let corners = ["wvous-tl-corner", "wvous-tr-corner", "wvous-bl-corner", "wvous-br-corner"]
    private static let modifiers = ["wvous-tl-modifier", "wvous-tr-modifier", "wvous-bl-modifier", "wvous-br-modifier"]
    private static var keys: [String] { corners + modifiers }

    /// True while we currently hold the user's corners paused.
    static var isPaused: Bool { Defaults.savedCorners != nil }

    /// Save the current Hot Corners and set every corner to "no action".
    /// No-op if already paused (so we never overwrite the saved real settings).
    static func pause() {
        guard let dock, Defaults.savedCorners == nil else { return }

        var saved: [String: Int] = [:]
        for key in keys where dock.object(forKey: key) != nil {
            saved[key] = dock.integer(forKey: key)
        }
        Defaults.savedCorners = saved

        // 0 = "no action" for a corner (and clear its modifier).
        var expected: [String: Int?] = [:]
        for key in keys {
            dock.set(0, forKey: key)
            expected[key] = 0
        }
        applyDockChanges(expected: expected)
    }

    /// Put the user's saved Hot Corners back. No-op if we aren't paused.
    static func restore() {
        guard let dock, let saved = Defaults.savedCorners else { return }

        var expected: [String: Int?] = [:]
        for key in keys {
            if let value = saved[key] {
                dock.set(value, forKey: key)
                expected[key] = value
            } else {
                dock.removeObject(forKey: key)   // wasn't set originally
                expected[key] = Int?.none        // expect read-back to be absent
            }
        }
        Defaults.savedCorners = nil
        applyDockChanges(expected: expected)
    }

    /// The Dock only re-reads `wvous-*` on relaunch. During Game Mode the game
    /// is full-screen so the relaunch is invisible; on restore it's a brief blip.
    ///
    /// `expected` maps each key to the value we just wrote (or `nil` if we
    /// removed it). cfprefsd caches writes and may not flush them to the
    /// on-disk plist before the relaunched Dock re-reads it — a race that
    /// occasionally drops our change. So we force-flush, then read the values
    /// back from a fresh (cfprefsd-backed) handle and confirm they match before
    /// we restart the Dock.
    private static func applyDockChanges(expected: [String: Int?]) {
        dock?.synchronize()
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)

        // Read back until cfprefsd reports our values, or attempts run out.
        for _ in 0..<8 {
            let store = UserDefaults(suiteName: "com.apple.dock")
            let settled = expected.allSatisfy { key, value in
                if let value {
                    return store?.object(forKey: key) != nil && store?.integer(forKey: key) == value
                } else {
                    return store?.object(forKey: key) == nil
                }
            }
            if settled { break }
            usleep(40_000)   // ~40ms
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }
}
