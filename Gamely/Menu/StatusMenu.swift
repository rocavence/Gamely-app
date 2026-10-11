import AppKit

/// The menu-bar icon and its menu. Reads state from `AppController` and
/// forwards every action to it.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private unowned let controller: AppController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    private var statusLine: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var whitelistItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var restoreItem: NSMenuItem!

    init(controller: AppController) {
        self.controller = controller
        super.init()
        build()
        update()
    }

    private func build() {
        menu.delegate = self

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: String(localized: "Gamely \(version)", comment: "Version label in the menu, %@ is the version number"),
                                     action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())

        // Immediate "now" actions — only one of the pair shows at a time
        // (pause when running, restore when paused).
        pauseItem = item(String(localized: "Pause Hot Corners Now", comment: "Action: pause the user's Hot Corners immediately"), #selector(pauseNow))
        menu.addItem(pauseItem)
        restoreItem = item(String(localized: "Restore Hot Corners Now", comment: "Action: restore the user's Hot Corners immediately"), #selector(restoreNow))
        menu.addItem(restoreItem)

        menu.addItem(.separator())

        // Preferences / toggles, grouped together.
        enabledItem = item(String(localized: "Pause Hot Corners in Game Mode", comment: "Toggle: pause Hot Corners while Game Mode is active"), #selector(toggleEnabled))
        menu.addItem(enabledItem)

        whitelistItem = NSMenuItem(title: String(localized: "Force Game Mode for Apps", comment: "Submenu: apps that force Game Mode behavior"), action: nil, keyEquivalent: "")
        let whitelistMenu = NSMenu()
        whitelistMenu.delegate = self
        // We manage enabled-state ourselves (target/action items + the "Add" guard).
        whitelistMenu.autoenablesItems = false
        whitelistItem.submenu = whitelistMenu
        menu.addItem(whitelistItem)

        loginItem = item(String(localized: "Launch at Login", comment: "Toggle: launch Gamely at login"), #selector(toggleLogin))
        menu.addItem(loginItem)

        #if DEBUG
        menu.addItem(item(String(localized: "Simulate Game Mode (debug)", comment: "Debug-only action to simulate Game Mode"), #selector(toggleSimulate)))
        #endif

        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Gamely", comment: "Action: quit the app"), #selector(quit), key: "q"))

        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// The status line for the current state; exposed for the self-test.
    var statusTitle: String { statusLine.title }

    func update() {
        let detected = controller.triggers.detected
        let paused = controller.isPaused
        let symbol = paused ? "gamecontroller.fill" : "gamecontroller"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Gamely")

        statusLine.title = detected
            ? (paused
                ? String(localized: "Game Mode: On — Hot Corners paused", comment: "Status line: Game Mode active and Hot Corners paused")
                : String(localized: "Game Mode: On", comment: "Status line: Game Mode active"))
            : String(localized: "Game Mode: Off", comment: "Status line when Game Mode is not active")
        enabledItem.state = Defaults.enabled ? .on : .off
        loginItem.state = LoginItem.isEnabled ? .on : .off
        pauseItem.isHidden = paused
        restoreItem.isHidden = !paused
    }

    /// (Re)build the "Force Game Mode for Apps" submenu from the current whitelist.
    private func rebuildWhitelistMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        for bundleID in Defaults.whitelist {
            let item = item(friendlyName(for: bundleID), #selector(removeWhitelistApp(_:)))
            item.representedObject = bundleID
            item.state = .on
            menu.addItem(item)
        }

        if !Defaults.whitelist.isEmpty {
            menu.addItem(.separator())
        }

        // "Add App ▸" — pick from currently running apps not already whitelisted.
        let addItem = NSMenuItem(title: String(localized: "Add App", comment: "Submenu: pick a running app to add to the whitelist"), action: nil, keyEquivalent: "")
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
            let none = NSMenuItem(title: String(localized: "No apps to add", comment: "Placeholder when there are no running apps to add"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            addMenu.addItem(none)
        } else {
            for app in candidates {
                let item = item(app.name, #selector(addWhitelistApp(_:)))
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
        controller.setEnabled(!Defaults.enabled)
    }

    @objc private func toggleLogin() {
        LoginItem.setEnabled(!LoginItem.isEnabled)
        update()
    }

    @objc private func pauseNow() {
        Task { await controller.pauseNow() }
    }

    @objc private func restoreNow() {
        Task { await controller.restoreNow() }
    }

    @objc private func toggleSimulate() {
        controller.setSimulated(!controller.triggers.simulated)
    }

    @objc private func removeWhitelistApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        Defaults.whitelist.removeAll { $0 == bundleID }
        controller.whitelistChanged()
    }

    @objc private func addWhitelistApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String,
              bundleID != Bundle.main.bundleIdentifier,
              !Defaults.whitelist.contains(bundleID) else { return }
        Defaults.whitelist.append(bundleID)
        controller.whitelistChanged()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == whitelistItem.submenu {
            rebuildWhitelistMenu(menu)
        } else {
            update()
        }
    }
}
