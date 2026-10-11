/// Everything that can ask Gamely to pause Hot Corners, combined into one decision.
struct PauseTriggers: Equatable, Sendable {
    /// macOS reports Game Mode on.
    var gameMode = false
    /// The name of the whitelisted ("Force Game Mode") app that is frontmost.
    var forcedApp: String?
    /// The user chose "Pause Hot Corners Now".
    var manual = false
    /// Debug-only simulation of Game Mode.
    var simulated = false

    enum Reason: Equatable, Sendable {
        case gameMode, forcedApp(String), simulated, manual
    }

    /// Why Hot Corners are (or would be) paused, the strongest reason first.
    var reason: Reason? {
        if gameMode { return .gameMode }
        if let forcedApp { return .forcedApp(forcedApp) }
        if simulated { return .simulated }
        if manual { return .manual }
        return nil
    }

    /// A game is detected — Game Mode, a forced app, or the simulation.
    var detected: Bool { gameMode || forcedApp != nil || simulated }

    func shouldPause(enabled: Bool) -> Bool {
        enabled && (detected || manual)
    }
}
