import AppKit

/// Watches which app is frontmost and reports it when it's in the user's
/// whitelist (`Defaults.whitelist`). Used to force "Game Mode" for apps that
/// don't trigger real macOS Game Mode — e.g. Steam or CrossOver games.
@MainActor
final class ActiveAppMonitor {
    /// Fired with the whitelisted frontmost app's name, or nil, whenever it changes.
    private let onChange: @MainActor (String?) -> Void

    /// The name of the frontmost app when it's whitelisted.
    private(set) var activeApp: String?

    private var observer: NSObjectProtocol?

    init(onChange: @escaping @MainActor (String?) -> Void) {
        self.onChange = onChange
    }

    func start() {
        // The notification arrives on the main queue, so AppKit access is safe.
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
        // Seed the initial state from whatever is frontmost right now.
        recheck()
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    /// Recompute from the current frontmost app and fire `onChange` if it changed.
    /// Call after editing the whitelist so changes take effect immediately.
    func recheck() {
        let front = NSWorkspace.shared.frontmostApplication
        let id = front?.bundleIdentifier
        let active = id.flatMap { Defaults.whitelist.contains($0) ? (front?.localizedName ?? $0) : nil }
        if active != activeApp {
            activeApp = active
            onChange(active)
        }
    }
}
