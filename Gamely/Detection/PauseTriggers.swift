/// Everything that can ask Gamely to pause Hot Corners, combined into one decision.
struct PauseTriggers: Equatable, Sendable {
    /// macOS reports Game Mode on.
    var gameMode = false
    /// A whitelisted ("Force Game Mode") app is frontmost.
    var forcedApp = false
    /// The user chose "Pause Hot Corners Now".
    var manual = false
    /// Debug-only simulation of Game Mode.
    var simulated = false

    /// A game is detected — what the status line reports as "Game Mode: On".
    var detected: Bool { gameMode || forcedApp || simulated }

    func shouldPause(enabled: Bool) -> Bool {
        enabled && (detected || manual)
    }
}
