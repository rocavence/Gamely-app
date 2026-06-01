import Foundation
import CNotify

/// Watches macOS Game Mode via libnotify. `gamepolicyd` posts stateful
/// `notify(3)` notifications; we read `game-mode-session`'s state (non-zero =
/// Game Mode active) whenever a relevant notification fires.
final class GameModeMonitor {
    /// Stateful notification whose value reflects whether Game Mode is on.
    private static let stateName = "com.apple.gamepolicy.game-mode-session"
    /// Notifications that mean "re-check the state".
    private static let triggers = [
        "com.apple.gamepolicy.game-mode-session",
        "com.apple.gamepolicy.fullscreenStateChanged",
        "com.apple.gamepolicy.GameExited",
    ]

    private let onChange: (Bool) -> Void
    private var tokens: [Int32] = []
    private(set) var isActive = false

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        isActive = Self.readActive()
        for name in Set(Self.triggers) {
            var token: Int32 = 0
            let status = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                self?.evaluate()
            }
            if status == 0 { tokens.append(token) }
        }
        onChange(isActive)   // report the initial state (also drives crash recovery)
    }

    func stop() {
        for token in tokens { notify_cancel(token) }
        tokens.removeAll()
    }

    private func evaluate() {
        let active = Self.readActive()
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }

    private static func readActive() -> Bool {
        var token: Int32 = 0
        guard notify_register_check(stateName, &token) == 0 else { return false }
        defer { notify_cancel(token) }
        var state: UInt64 = 0
        guard notify_get_state(token, &state) == 0 else { return false }
        return state != 0
    }
}
