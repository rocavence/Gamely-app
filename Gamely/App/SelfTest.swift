#if DEBUG
import AppKit
import os

/// End-to-end self-test driven by `scripts/selftest.sh [item]`. Operates the
/// real controller, menu and windows against throwaway preference domains with
/// a fake Dock restart, so the user's Dock is never touched (and the debug
/// build has its own bundle ID, so Gamely's own settings aren't either).
/// Prints PASS/FAIL lines and "SELFTEST OK" when everything passed, then quits.
/// Screenshots of Settings and the guide go to $GAMELY_SHOTS when set.
@MainActor
enum SelfTest {
    private static let dockDomain = "com.gamely.selftest.dock"
    private static let stateDomain = "com.gamely.selftest.state"
    private static var failures = 0

    static func run(_ only: String) {
        Task {
            let items: [(String, () async -> Void)] = [
                ("hotcorners", hotCorners),
                ("usersetting", userSetting),
                ("recovery", recovery),
                ("restart", restart),
                ("debounce", debounce),
                ("menu", menuStatus),
                ("windows", windows),
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
        let dock = seedDock()

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

    /// A corner the user changes while paused keeps their new setting.
    private static func userSetting() async {
        let hc = controller(Counter())
        let dock = seedDock()
        await hc.pause()
        dock.set(4, forKey: "wvous-bl-corner")   // the user picks Desktop meanwhile

        await hc.restore()
        check("the user's new corner wins", dock.integer(forKey: "wvous-bl-corner") == 4)
        check("its untouched modifier stays as the user left it", dock.integer(forKey: "wvous-bl-modifier") == 0)
        check("other corners are restored", dock.integer(forKey: "wvous-tl-corner") == 2 && dock.integer(forKey: "wvous-br-corner") == 5)
    }

    /// Killed while paused, then relaunched: restore if no game is on, stay
    /// paused if one is — without waiting for a Game Mode change.
    private static func recovery() async {
        let restarts = Counter()
        let dock = seedDock()
        await controller(Counter()).pause()   // the run that was killed

        let idle = AppController(hotCorners: controller(restarts), debounce: .milliseconds(50), minInterval: .zero)
        check("relaunch starts out paused", idle.isPaused)
        GameModeMonitor(seedsFromLog: false, onChange: { idle.setGameMode($0) }).seed(false)
        try? await Task.sleep(for: .milliseconds(400))
        check("no game: Hot Corners restored on launch", !idle.isPaused && dock.integer(forKey: "wvous-tl-corner") == 2)

        await controller(Counter()).pause()
        let playing = AppController(hotCorners: controller(restarts), debounce: .milliseconds(50), minInterval: .zero)
        GameModeMonitor(seedsFromLog: false, onChange: { playing.setGameMode($0) }).seed(true)
        try? await Task.sleep(for: .milliseconds(400))
        check("game still on: stays paused", playing.isPaused && dock.integer(forKey: "wvous-tl-corner") == 0)
        check("status says why", playing.statusText == String(localized: "Hot Corners paused: \(String(localized: "Game Mode"))"))
    }

    /// A stream that keeps exiting is restarted, then given up on after three
    /// quick failures; Retry starts it again. A healthy one reports running.
    private static func restart() async {
        var health: [GameModeMonitor.Health] = []
        let dying = GameModeMonitor(command: .init(path: "/bin/sh", arguments: ["-c", "sleep 0.2"]), seedsFromLog: false,
                                    restartDelay: .milliseconds(100), onChange: { _ in }, onHealthChange: { health.append($0) })
        dying.start()
        try? await Task.sleep(for: .seconds(2))
        check("restarted after exiting", dying.launches == 3)
        check("stops after three quick failures", dying.health == .stopped && health.last == .stopped)
        dying.retry()
        try? await Task.sleep(for: .milliseconds(100))
        check("retry starts it again", dying.launches == 4)
        dying.stop()

        let healthy = GameModeMonitor(command: .init(path: "/bin/sleep", arguments: ["30"]), seedsFromLog: false, onChange: { _ in })
        healthy.start()
        try? await Task.sleep(for: .milliseconds(300))
        check("a live stream reports running", healthy.health == .running && healthy.launches == 1)
        healthy.stop()
        try? await Task.sleep(for: .milliseconds(300))
        check("stop doesn't restart it", healthy.launches == 1)
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

    /// The status line names the reason, including a manual pause.
    private static func menuStatus() async {
        let app = AppController(hotCorners: controller(Counter()), debounce: .milliseconds(50), minInterval: .zero)
        let menu = StatusMenu(controller: app)
        app.onChange = { menu.update() }
        let gameMode = String(localized: "Game Mode")

        check("idle reads Hot Corners on", menu.statusTitle == String(localized: "Hot Corners on"))
        app.setGameMode(true)
        check("detected before apply reads pausing", menu.statusTitle == String(localized: "\(gameMode): pausing Hot Corners…"))
        try? await Task.sleep(for: .milliseconds(300))
        check("paused names Game Mode", menu.statusTitle == String(localized: "Hot Corners paused: \(gameMode)"))
        app.setGameMode(false)
        try? await Task.sleep(for: .milliseconds(300))
        check("restored reads Hot Corners on", menu.statusTitle == String(localized: "Hot Corners on") && !app.isPaused)

        await app.pauseNow()
        check("manual pause says so", menu.statusTitle == String(localized: "Hot Corners paused: \(String(localized: "paused by you"))"))
        await app.restoreNow()
        check("restore now clears it", menu.statusTitle == String(localized: "Hot Corners on"))
    }

    /// Every Settings page and the guide render at their designed size.
    private static func windows() async {
        let app = AppController(hotCorners: controller(Counter()), debounce: .milliseconds(50), minInterval: .zero)
        seedDock()
        let settings = SettingsWindow(controller: app) {}
        let shots = ProcessInfo.processInfo.environment["GAMELY_SHOTS"].map { URL(fileURLWithPath: $0) }
        for page in SettingsPage.allCases {
            settings.show(page, activate: false)
            try? await Task.sleep(for: .milliseconds(400))
            let image = settings.snapshot()
            check("Settings › \(page.rawValue) renders 900×600", image.map { $0.size == NSSize(width: 900, height: 600) } ?? false)
            save(image, shots, "settings-\(page.rawValue)")
        }
        settings.close()

        let welcome = WelcomeWindow()
        welcome.show(corners: app.hotCorners.realCorners(), openForcedApps: {}, activate: false)
        try? await Task.sleep(for: .milliseconds(400))
        let image = welcome.snapshot()
        check("the guide renders", image.map { $0.size.width == 560 } ?? false)
        save(image, shots, "welcome")
        welcome.close()
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

    /// ⌘ Mission Control top left, Start Screen Saver bottom right.
    @discardableResult
    private static func seedDock() -> UserDefaults {
        let dock = UserDefaults(suiteName: dockDomain)!
        dock.set(2, forKey: "wvous-tl-corner")
        dock.set(1_048_576, forKey: "wvous-tl-modifier")
        dock.set(5, forKey: "wvous-br-corner")
        return dock
    }

    private static func save(_ image: NSBitmapImageRep?, _ folder: URL?, _ name: String) {
        guard let folder, let data = image?.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: folder.appendingPathComponent("\(name).png"))
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
