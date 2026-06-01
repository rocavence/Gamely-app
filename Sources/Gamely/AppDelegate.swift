import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: GameModeMonitor!
    /// Debug-only manual override (GAMELY_DEBUG) to exercise the pause/restore
    /// path without launching a real game.
    private var simulating = false

    private var statusLine: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var restoreItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        monitor = GameModeMonitor { [weak self] active in
            MainActor.assumeIsolated { self?.gameModeChanged(active) }
        }
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the user's Hot Corners paused after we go away.
        HotCornerController.restore()
    }

    // MARK: - Game Mode → Hot Corners

    private func gameModeChanged(_ active: Bool) {
        if active {
            if Defaults.enabled { HotCornerController.pause() }
        } else {
            HotCornerController.restore()
        }
        updateUI()
    }

    // MARK: - Menu bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        menu.delegate = self

        statusLine = NSMenuItem(title: "Game Mode: Off", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        enabledItem = NSMenuItem(title: "Pause Hot Corners in Game Mode",
                                 action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        menu.addItem(.separator())

        restoreItem = NSMenuItem(title: "Restore Hot Corners Now",
                                 action: #selector(restoreNow), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)

        if ProcessInfo.processInfo.environment["GAMELY_DEBUG"] != nil {
            let sim = NSMenuItem(title: "Simulate Game Mode (debug)", action: #selector(toggleSimulate), keyEquivalent: "")
            sim.target = self
            menu.addItem(sim)
        }

        let quit = NSMenuItem(title: "Quit Gamely", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        updateUI()
    }

    private func updateUI() {
        let active = (monitor?.isActive ?? false) || simulating
        let paused = HotCornerController.isPaused
        let symbol = paused ? "gamecontroller.fill" : "gamecontroller"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Gamely")

        statusLine.title = active
            ? (paused ? "Game Mode: On — Hot Corners paused" : "Game Mode: On")
            : "Game Mode: Off"
        enabledItem.state = Defaults.enabled ? .on : .off
        loginItem.state = LoginItem.isEnabled ? .on : .off
        restoreItem.isHidden = !paused
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        Defaults.enabled.toggle()
        // If the user turns Gamely off mid-game, give their corners back now.
        if !Defaults.enabled {
            HotCornerController.restore()
        } else if monitor.isActive {
            HotCornerController.pause()
        }
        updateUI()
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        updateUI()
    }

    @objc private func restoreNow() {
        HotCornerController.restore()
        updateUI()
    }

    @objc private func toggleSimulate() {
        simulating.toggle()
        gameModeChanged(simulating)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { updateUI() }
}
