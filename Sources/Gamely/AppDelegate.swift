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
    /// Manual override: pause Hot Corners even when no trigger fired. For the case
    /// where the game was already running before Gamely launched, so detection
    /// never saw the transition. Cleared by "Restore Hot Corners Now".
    private var manualPause = false
    /// Debounces the (Dock-restarting) apply so rapid flicker coalesces.
    private var applyWork: DispatchWorkItem?
    /// When the apply last ran, to hard-cap `killall Dock` to ≤1 per 2s even if
    /// transitions arrive spaced just under the debounce window apart.
    private var lastApplyAt: Date?

    private var statusLine: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var whitelistItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
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
        // Tear down the `log stream` child so it doesn't outlive us as an orphan.
        monitor?.stop()
        activeAppMonitor?.stop()
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
        // Hard floor: never restart the Dock more than once per 2s. If the last
        // apply was too recent, defer this one to just past the floor (replacing
        // any pending work) instead of running it now.
        if let last = lastApplyAt {
            let elapsed = Date().timeIntervalSince(last)
            if elapsed < 2 {
                applyWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.applyPauseState() }
                applyWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (2 - elapsed), execute: work)
                return
            }
        }
        lastApplyAt = Date()

        let shouldPause = Defaults.enabled && (gameModeActive || whitelistActive || simulating || manualPause)
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

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionTitle = String(format: NSLocalizedString("Gamely %@", comment: "Version label in the menu, %@ is the version number"), version)
        let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        statusLine = NSMenuItem(title: NSLocalizedString("Game Mode: Off", comment: "Status line when Game Mode is not active"), action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        // Immediate "now" actions — only one of the pair shows at a time
        // (pause when running, restore when paused).
        pauseItem = NSMenuItem(title: NSLocalizedString("Pause Hot Corners Now", comment: "Action: pause the user's Hot Corners immediately"),
                               action: #selector(pauseNow), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)

        restoreItem = NSMenuItem(title: NSLocalizedString("Restore Hot Corners Now", comment: "Action: restore the user's Hot Corners immediately"),
                                 action: #selector(restoreNow), keyEquivalent: "")
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        // Preferences / toggles, grouped together.
        enabledItem = NSMenuItem(title: NSLocalizedString("Pause Hot Corners in Game Mode", comment: "Toggle: pause Hot Corners while Game Mode is active"),
                                 action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)

        whitelistItem = NSMenuItem(title: NSLocalizedString("Force Game Mode for Apps", comment: "Submenu: apps that force Game Mode behavior"), action: nil, keyEquivalent: "")
        let whitelistMenu = NSMenu()
        whitelistMenu.delegate = self
        // We manage enabled-state ourselves (target/action items + the "Add" guard).
        whitelistMenu.autoenablesItems = false
        whitelistItem.submenu = whitelistMenu
        menu.addItem(whitelistItem)

        loginItem = NSMenuItem(title: NSLocalizedString("Launch at Login", comment: "Toggle: launch Gamely at login"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        if ProcessInfo.processInfo.environment["GAMELY_DEBUG"] != nil {
            let sim = NSMenuItem(title: NSLocalizedString("Simulate Game Mode (debug)", comment: "Debug-only action to simulate Game Mode"), action: #selector(toggleSimulate), keyEquivalent: "")
            sim.target = self
            menu.addItem(sim)
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: NSLocalizedString("Quit Gamely", comment: "Action: quit the app"), action: #selector(quit), keyEquivalent: "q")
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
            ? (paused
                ? NSLocalizedString("Game Mode: On — Hot Corners paused", comment: "Status line: Game Mode active and Hot Corners paused")
                : NSLocalizedString("Game Mode: On", comment: "Status line: Game Mode active"))
            : NSLocalizedString("Game Mode: Off", comment: "Status line when Game Mode is not active")
        enabledItem.state = Defaults.enabled ? .on : .off
        loginItem.state = LoginItem.isEnabled ? .on : .off
        pauseItem.isHidden = paused
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

        // "Add App ▸" — pick from currently running apps not already whitelisted.
        let addItem = NSMenuItem(title: NSLocalizedString("Add App", comment: "Submenu: pick a running app to add to the whitelist"), action: nil, keyEquivalent: "")
        let addMenu = NSMenu()
        addMenu.autoenablesItems = false

        var seen = Set(Defaults.whitelist)
        seen.insert(Bundle.main.bundleIdentifier ?? "")
        let candidates = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (name: String, id: String)? in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (app.localizedName ?? id, id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if candidates.isEmpty {
            let none = NSMenuItem(title: NSLocalizedString("No apps to add", comment: "Placeholder when there are no running apps to add"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            addMenu.addItem(none)
        } else {
            for app in candidates {
                let item = NSMenuItem(title: app.name, action: #selector(addWhitelistApp(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = app.id
                addMenu.addItem(item)
            }
        }
        addItem.submenu = addMenu
        menu.addItem(addItem)
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

    @objc private func pauseNow() {
        manualPause = true
        HotCornerController.pause()
        updateUI()
    }

    @objc private func restoreNow() {
        manualPause = false
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

    @objc private func addWhitelistApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String,
              bundleID != Bundle.main.bundleIdentifier,
              !Defaults.whitelist.contains(bundleID) else { return }
        Defaults.whitelist.append(bundleID)
        activeAppMonitor.recheck()
        updatePauseState()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == whitelistItem.submenu {
            rebuildWhitelistMenu(menu)
        } else {
            updateUI()
        }
    }
}
