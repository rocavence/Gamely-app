import Foundation

/// Pauses and restores macOS Hot Corners by editing the Dock's `wvous-*`
/// preferences and restarting the Dock. The user's real settings are saved to
/// Gamely's own defaults before we touch them, so they survive a crash.
///
/// Both preference domains and the Dock restart are injectable so tests and the
/// self-test never touch the user's real Dock.
struct HotCornerController: Sendable {
    /// Preference domain holding the `wvous-*` keys.
    let dockDomain: String
    /// Preference domain where the user's real corners are kept while paused;
    /// nil means Gamely's own defaults.
    let stateDomain: String?
    /// Makes the Dock re-read its preferences.
    let restartDock: @Sendable () -> Void

    static let live = HotCornerController(dockDomain: "com.apple.dock", stateDomain: nil) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }

    static let corners = ["wvous-tl-corner", "wvous-tr-corner", "wvous-bl-corner", "wvous-br-corner"]
    static let modifiers = ["wvous-tl-modifier", "wvous-tr-modifier", "wvous-bl-modifier", "wvous-br-modifier"]
    static var keys: [String] { corners + modifiers }

    private static let savedKey = "Gamely.savedCorners"

    private var state: UserDefaults {
        stateDomain.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }

    /// The user's real Hot Corner settings, saved while we have them disabled.
    /// Non-nil means "we currently have Hot Corners paused" — used to restore
    /// after Game Mode ends, and to recover if Gamely crashed mid-game.
    var savedCorners: [String: Int]? {
        state.dictionary(forKey: Self.savedKey) as? [String: Int]
    }

    /// True while we currently hold the user's corners paused.
    var isPaused: Bool { savedCorners != nil }

    /// Save the current Hot Corners and set every corner to "no action".
    /// No-op if already paused (so we never overwrite the saved real settings).
    @concurrent
    func pause() async { pauseBlocking() }

    /// Put the user's saved Hot Corners back. No-op if we aren't paused.
    @concurrent
    @discardableResult
    func restore() async -> Bool { restoreBlocking() }

    func pauseBlocking() {
        guard let dock = UserDefaults(suiteName: dockDomain), savedCorners == nil else { return }

        var saved: [String: Int] = [:]
        for key in Self.keys where dock.object(forKey: key) != nil {
            saved[key] = dock.integer(forKey: key)
        }
        state.set(saved, forKey: Self.savedKey)

        // 0 = "no action" for a corner (and clear its modifier).
        var expected: [String: Int?] = [:]
        for key in Self.keys {
            dock.set(0, forKey: key)
            expected[key] = 0
        }
        applyDockChanges(expected: expected)
    }

    /// Synchronous so it can run from `applicationWillTerminate` and before a
    /// power-off. The saved copy is cleared only once the Dock's preferences
    /// read back as restored, so a failed write is retried next time.
    @discardableResult
    func restoreBlocking() -> Bool {
        guard let dock = UserDefaults(suiteName: dockDomain), let saved = savedCorners else { return true }

        var expected: [String: Int?] = [:]
        for (corner, modifier) in zip(Self.corners, Self.modifiers) {
            // While paused, both keys of every corner read 0. Anything else means
            // the user set this corner themselves meanwhile: their choice wins.
            let changed = [corner, modifier].contains { (dock.object(forKey: $0) as? Int) != 0 }
            for key in [corner, modifier] {
                if changed {
                    expected[key] = dock.object(forKey: key) as? Int
                } else if let value = saved[key] {
                    dock.set(value, forKey: key)
                    expected[key] = value
                } else {
                    dock.removeObject(forKey: key)   // wasn't set originally
                    expected[key] = Int?.none        // expect read-back to be absent
                }
            }
        }
        let settled = applyDockChanges(expected: expected)
        if settled {
            state.removeObject(forKey: Self.savedKey)
        } else {
            log.error("Hot Corners didn't read back as restored; keeping the saved copy")
        }
        return settled
    }

    /// The user's real Hot Corners: the saved copy while paused, otherwise the
    /// Dock's current settings. Absent keys read as 0.
    func realCorners() -> [String: Int] {
        if let savedCorners { return savedCorners }
        guard let dock = UserDefaults(suiteName: dockDomain) else { return [:] }
        var corners: [String: Int] = [:]
        for key in Self.keys where dock.object(forKey: key) != nil {
            corners[key] = dock.integer(forKey: key)
        }
        return corners
    }

    /// The Dock only re-reads `wvous-*` on relaunch. During Game Mode the game
    /// is full-screen so the relaunch is invisible; on restore it's a brief blip.
    ///
    /// `expected` maps each key to the value we just wrote (or `nil` if we
    /// removed it). cfprefsd caches writes and may not flush them to the
    /// on-disk plist before the relaunched Dock re-reads it — a race that
    /// occasionally drops our change. So we force-flush, then read the values
    /// back from a fresh (cfprefsd-backed) handle and confirm they match before
    /// we restart the Dock. Runs off the main thread (see `pause()`/`restore()`).
    @discardableResult
    private func applyDockChanges(expected: [String: Int?]) -> Bool {
        CFPreferencesAppSynchronize(dockDomain as CFString)

        // Read back until cfprefsd reports our values, or attempts run out.
        var settled = false
        for _ in 0..<8 {
            let store = UserDefaults(suiteName: dockDomain)
            settled = expected.allSatisfy { key, value in
                if let value {
                    return store?.object(forKey: key) != nil && store?.integer(forKey: key) == value
                } else {
                    return store?.object(forKey: key) == nil
                }
            }
            if settled { break }
            usleep(40_000)   // ~40ms
        }
        restartDock()
        return settled
    }
}
