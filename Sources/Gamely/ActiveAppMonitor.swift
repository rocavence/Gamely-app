import AppKit

/// Watches which app is frontmost and reports whether it's in the user's
/// whitelist (`Defaults.whitelist`). Used to force "Game Mode" for apps that
/// don't trigger real macOS Game Mode — e.g. Steam or CrossOver games.
///
/// Marked `@MainActor` because it only ever touches AppKit, and the workspace
/// notification is delivered on the main queue.
@MainActor
final class ActiveAppMonitor {
    /// Fired (on the main thread) whenever the whitelisted-frontmost state flips.
    private let onChange: (Bool) -> Void

    /// Whether the current frontmost app's bundle ID is in the whitelist.
    private(set) var isActive = false

    private var observer: NSObjectProtocol?

    init(onChange: @escaping (Bool) -> Void) {
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

    /// Recompute from the current frontmost app and fire `onChange` if it flipped.
    /// Call after editing the whitelist so changes take effect immediately.
    func recheck() {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let active = bundleID.map { Defaults.whitelist.contains($0) } ?? false
        if active != isActive {
            isActive = active
            onChange(active)
        }
    }
}
