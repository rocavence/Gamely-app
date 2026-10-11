#if DEBUG
import AppKit
import os

/// End-to-end self-test driven by `scripts/selftest.sh [item]`. Operates the
/// real controller and menu against throwaway preference domains with a fake
/// Dock restart, so the user's Dock is never touched. Prints PASS/FAIL lines
/// and "SELFTEST OK" when everything passed, then quits.
@MainActor
enum SelfTest {
    private static let dockDomain = "com.gamely.selftest.dock"
    private static let stateDomain = "com.gamely.selftest.state"
    private static var failures = 0

    static func run(_ only: String) {
        Task {
            let items: [(String, () async -> Void)] = [
                ("hotcorners", hotCorners),
                ("debounce", debounce),
                ("menu", menuStatus),
            ]
            for (name, test) in items where only.isEmpty || only == "all" || only == name {
                reset()
                print("SELFTEST \(name)")
                await test()
            }
            reset()
            print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
    }

    // MARK: - Items

    /// Pause zeroes every corner and saves the originals; restore puts them back
    /// (including keys that were absent); repeating either is a no-op.
    private static func hotCorners() async {
        let restarts = Counter()
        let hc = controller(restarts)
        let dock = UserDefaults(suiteName: dockDomain)!
        dock.set(2, forKey: "wvous-tl-corner")
        dock.set(1_048_576, forKey: "wvous-tl-modifier")
        dock.set(5, forKey: "wvous-br-corner")

        await hc.pause()
        check("pause zeroes all corners", HotCornerController.keys.allSatisfy { dock.integer(forKey: $0) == 0 && dock.object(forKey: $0) != nil })
        check("pause saves originals", hc.savedCorners == ["wvous-tl-corner": 2, "wvous-tl-modifier": 1_048_576, "wvous-br-corner": 5])
        await hc.pause()
        check("second pause is a no-op", restarts.value == 1)

        await hc.restore()
        check("restore puts values back", dock.integer(forKey: "wvous-tl-corner") == 2
              && dock.integer(forKey: "wvous-tl-modifier") == 1_048_576
              && dock.integer(forKey: "wvous-br-corner") == 5)
        check("restore removes keys that were absent", dock.object(forKey: "wvous-tr-corner") == nil)
        check("restore clears the saved copy", !hc.isPaused)
        await hc.restore()
        check("second restore is a no-op", restarts.value == 2)
    }

    /// Game Mode flickering on/off/on settles into a single pause and one Dock restart.
    private static func debounce() async {
        let restarts = Counter()
        let app = AppController(hotCorners: controller(restarts), debounce: .milliseconds(300), minInterval: .milliseconds(500))
        for active in [true, false, true, false, true] {
            app.setGameMode(active)
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(800))
        check("flicker restarts the Dock once", restarts.value == 1)
        check("flicker ends paused", app.isPaused)

        app.setGameMode(false)
        try? await Task.sleep(for: .milliseconds(800))
        check("Game Mode off restores", !app.isPaused && restarts.value == 2)
    }

    /// The status line follows detection and the pause state.
    private static func menuStatus() async {
        let app = AppController(hotCorners: controller(Counter()), debounce: .milliseconds(50), minInterval: .zero)
        let menu = StatusMenu(controller: app)
        app.onChange = { menu.update() }

        check("idle reads Game Mode: Off", menu.statusTitle == String(localized: "Game Mode: Off"))
        app.setGameMode(true)
        check("detected before apply reads Game Mode: On", menu.statusTitle == String(localized: "Game Mode: On"))
        try? await Task.sleep(for: .milliseconds(300))
        check("paused reads Hot Corners paused", menu.statusTitle == String(localized: "Game Mode: On — Hot Corners paused"))
        app.setGameMode(false)
        try? await Task.sleep(for: .milliseconds(300))
        check("restored reads Game Mode: Off", menu.statusTitle == String(localized: "Game Mode: Off") && !app.isPaused)
    }

    // MARK: - Helpers

    private final class Counter: Sendable {
        private let count = OSAllocatedUnfairLock(initialState: 0)
        var value: Int { count.withLock { $0 } }
        func increment() { count.withLock { $0 += 1 } }
    }

    private static func controller(_ restarts: Counter) -> HotCornerController {
        HotCornerController(dockDomain: dockDomain, stateDomain: stateDomain) {
            restarts.increment()
        }
    }

    private static func reset() {
        UserDefaults.standard.removePersistentDomain(forName: dockDomain)
        UserDefaults.standard.removePersistentDomain(forName: stateDomain)
    }

    private static func check(_ name: String, _ ok: Bool) {
        print(ok ? "PASS \(name)" : "FAIL \(name)")
        if !ok { failures += 1 }
    }
}
#endif
