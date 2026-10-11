import AppKit

/// The menu-bar icon and its menu. Reads state from `AppController` and
/// forwards every action to it.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private unowned let controller: AppController
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    /// Opens Settings, on a page.
    var openSettings: (SettingsPage) -> Void = { _ in }

    private var statusLine: NSMenuItem!
    private var detectionItem: NSMenuItem!
    private var updateItem: NSMenuItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var loginApprovalItem: NSMenuItem!
    private var whitelistItem: NSMenuItem!
    private var pauseItem: NSMenuItem!
    private var restoreItem: NSMenuItem!
    private var flashing: Task<Void, Never>?

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

        updateItem = item("", #selector(openUpdate))
        menu.addItem(updateItem)
        menu.addItem(.separator())

        statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statusLine.isEnabled = false
        menu.addItem(statusLine)

        detectionItem = item(String(localized: "Detection stopped. Click to retry", comment: "Menu item shown when Game Mode detection has stopped"), #selector(retryDetection))
        detectionItem.image = Icon.nsImage(.warning, size: 14)
        menu.addItem(detectionItem)
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
        loginApprovalItem = item(String(localized: "Allow Gamely in Login Items…", comment: "Shown when macOS needs the user to approve launch at login"), #selector(openLoginItems))
        loginApprovalItem.image = Icon.nsImage(.warning, size: 14)
        menu.addItem(loginApprovalItem)

        #if DEBUG
        menu.addItem(item(String(localized: "Simulate Game Mode (debug)", comment: "Debug-only action to simulate Game Mode"), #selector(toggleSimulate)))
        #endif

        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…", comment: "Action: open the Settings window"), #selector(showSettings), key: ","))
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
        let paused = controller.isPaused
        if flashing == nil { setIcon(filled: paused) }
        // VoiceOver reads the icon with what Gamely is doing.
        statusItem.button?.setAccessibilityLabel("Gamely, \(controller.statusText)")

        statusLine.title = controller.statusText
        detectionItem.isHidden = controller.detection != .stopped
        if let release = controller.updates.available {
            updateItem.title = String(localized: "Gamely \(release.version) is available. Download…", comment: "Menu item when a newer version is out")
            updateItem.isHidden = false
        } else {
            updateItem.isHidden = true
        }
        enabledItem.state = controller.enabled ? .on : .off
        loginItem.state = controller.loginItemEnabled ? .on : .off
        loginApprovalItem.isHidden = !controller.loginItemNeedsApproval && controller.loginItemError == nil
        pauseItem.isHidden = paused
        restoreItem.isHidden = !paused
    }

    private func setIcon(filled: Bool) {
        statusItem.button?.image = Self.menuBarIcon(filled: filled)
    }

    /// The bold gamepad at 95% size, its top 1.5pt below the image's top so it
    /// sits on the menu bar's optical centre (the glyph's cable leaves its box top-heavy).
    private static func menuBarIcon(filled: Bool) -> NSImage {
        let glyph = Icon.nsImage(.gamepad3Bold, weight: filled ? .filled : .outline, size: 18)
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let side = rect.width * 0.95
            glyph.draw(in: NSRect(x: (rect.width - side) / 2, y: rect.maxY - 1.5 - side, width: side, height: side))
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A short blink between the two icons when Hot Corners are paused or
    /// restored, so the change is noticed. Skipped with Reduce Motion.
    func flash(paused: Bool) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return update() }
        flashing?.cancel()
        flashing = Task {
            for filled in [paused, !paused, paused, !paused, paused] {
                setIcon(filled: filled)
                try? await Task.sleep(for: .milliseconds(140))
            }
            flashing = nil
            update()
        }
    }

    /// (Re)build the "Force Game Mode for Apps" submenu from the current whitelist.
    private func rebuildWhitelistMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        for bundleID in controller.whitelist {
            let item = item(AppInfo.name(for: bundleID), #selector(removeWhitelistApp(_:)))
            item.representedObject = bundleID
            item.state = .on
            menu.addItem(item)
        }

        if !controller.whitelist.isEmpty {
            menu.addItem(.separator())
        }

        // "Add App ▸" — pick from currently running apps not already whitelisted.
        let addItem = NSMenuItem(title: String(localized: "Add App", comment: "Submenu: pick a running app to add to the whitelist"), action: nil, keyEquivalent: "")
        let addMenu = NSMenu()
        addMenu.autoenablesItems = false

        var seen = Set(controller.whitelist)
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
        addMenu.addItem(.separator())
        addMenu.addItem(item(String(localized: "Choose from Applications…", comment: "Opens Settings to pick any installed app"), #selector(showForcedApps)))
        addItem.submenu = addMenu
        menu.addItem(addItem)
    }

    // MARK: - Actions

    @objc private func toggleEnabled() { controller.enabled.toggle() }
    @objc private func toggleLogin() { controller.setLoginItem(!controller.loginItemEnabled) }
    @objc private func openLoginItems() { LoginItem.openSystemSettings() }
    @objc private func pauseNow() { Task { await controller.pauseNow() } }
    @objc private func restoreNow() { Task { await controller.restoreNow() } }
    @objc private func toggleSimulate() { controller.setSimulated(!controller.triggers.simulated) }
    @objc private func retryDetection() { controller.retryDetection() }
    @objc private func showSettings() { openSettings(.general) }
    @objc private func showForcedApps() { openSettings(.forcedApps) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openUpdate() {
        NSWorkspace.shared.open(controller.updates.available?.page ?? UpdateChecker.releases)
    }

    @objc private func removeWhitelistApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        controller.whitelist.removeAll { $0 == bundleID }
    }

    @objc private func addWhitelistApp(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String,
              bundleID != Bundle.main.bundleIdentifier,
              !controller.whitelist.contains(bundleID) else { return }
        controller.whitelist.append(bundleID)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu == whitelistItem.submenu {
            rebuildWhitelistMenu(menu)
        } else {
            controller.refreshLoginItem()
            update()
        }
    }
}
