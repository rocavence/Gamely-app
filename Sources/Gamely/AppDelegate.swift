import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var monitor: GameModeMonitor!
    private var activeAppMonitor: ActiveAppMonitor!
    /// Debug-only manual override (GAMELY_DEBUG) to exercise the pause/restore
    /// path without launching a real game.
    private var simulating = false

    /// Latest state from each source, fed into `updatePauseState()`.
    private var gameModeActive = false
    private var whitelistActive = false
    /// Debounces the (Dock-restarting) apply so rapid flicker coalesces.
    private var applyWork: DispatchWorkItem?

    /// Frontmost app captured when the menu opens — clicking the status item
    /// makes Gamely frontmost, so we can't read it lazily in the action.
    private var capturedFrontmostApp: NSRunningApplication?

    private var statusLine: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var whitelistItem: NSMenuItem!
    private var restoreItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBar()
        monitor = GameModeMonitor { [weak self] active in
            MainActor.assumeIsolated {
                self?.gameModeActive = active
                self?.updatePauseState()
            }
        }
        monitor.start()
        activeAppMonitor = ActiveAppMonitor { [weak self] active in
            MainActor.assumeIsolated {
                self?.whitelistActive = active
                self?.updatePauseState()
            }
        }
        activeAppMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the user's Hot Corners paused after we go away.
        HotCornerController.restore()
    }

    // MARK: - Pause state

    /// Single source of truth: pause Hot Corners while Gamely is enabled and any
    /// trigger is live (real Game Mode, a whitelisted app frontmost, or the debug
    /// simulation), otherwise restore them.
    ///
    /// The apply is debounced: entering a full-screen game makes Game Mode flicker
    /// on/paused/on within a second, and each change restarts the Dock — doing that
    /// repeatedly *during* the full-screen transition breaks it. Coalescing the
    /// changes means the Dock is restarted once, after things settle.
    private func updatePauseState() {
        updateUI()   // reflect intent in the menu immediately
        applyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.applyPauseState() }
        applyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func applyPauseState() {
        let shouldPause = Defaults.enabled && (gameModeActive || whitelistActive || simulating)
        if shouldPause {
            HotCornerController.pause()
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

        whitelistItem = NSMenuItem(title: "Force Game Mode for Apps", action: nil, keyEquivalent: "")
        let whitelistMenu = NSMenu()
        whitelistMenu.delegate = self
        // We manage enabled-state ourselves (target/action items + the "Add" guard).
        whitelistMenu.autoenablesItems = false
        whitelistItem.submenu = whitelistMenu
        menu.addItem(whitelistItem)

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
        let active = gameModeActive || whitelistActive || simulating
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

    /// (Re)build the "Force Game Mode for Apps" submenu from the current whitelist.
    private func rebuildWhitelistMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        for bundleID in Defaults.whitelist {
            let item = NSMenuItem(title: friendlyName(for: bundleID),
                                  action: #selector(removeWhitelistApp(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = bundleID
            item.state = .on
            menu.addItem(item)
        }

        if !Defaults.whitelist.isEmpty {
            menu.addItem(.separator())
        }

        let add = NSMenuItem(title: "Add Frontmost App",
                             action: #selector(addFrontmostApp), keyEquivalent: "")
        add.target = self
        // Disable if there's nothing valid to add (no frontmost app, or it's us).
        let candidate = capturedFrontmostApp?.bundleIdentifier
        add.isEnabled = candidate != nil
            && candidate != Bundle.main.bundleIdentifier
            && !Defaults.whitelist.contains(candidate!)
        menu.addItem(add)
    }

    /// A human-friendly name for a bundle ID: the app's localized name if we can
    /// find it (running or installed), otherwise the raw bundle ID.
    private func friendlyName(for bundleID: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        Defaults.enabled.toggle()
        updatePauseState()
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
        updatePauseState()
    }

    @objc private func removeWhitelistApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        Defaults.whitelist.removeAll { $0 == bundleID }
        activeAppMonitor.recheck()
        updatePauseState()
    }

    @objc private func addFrontmostApp() {
        guard let bundleID = capturedFrontmostApp?.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              !Defaults.whitelist.contains(bundleID) else { return }
        Defaults.whitelist.append(bundleID)
        activeAppMonitor.recheck()
        updatePauseState()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        // Capture the real frontmost app before clicking the status item steals focus.
        if menu == statusItem.menu {
            capturedFrontmostApp = NSWorkspace.shared.frontmostApplication
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == whitelistItem.submenu {
            rebuildWhitelistMenu(menu)
        } else {
            updateUI()
        }
    }
}
