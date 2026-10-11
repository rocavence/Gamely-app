import Foundation

/// Owns the detectors and decides when Hot Corners are paused. The menu reads
/// its state and calls its actions; nothing else touches `HotCornerController`.
@MainActor
final class AppController {
    let hotCorners: HotCornerController
    private(set) var triggers = PauseTriggers()
    /// Fired after anything the menu shows may have changed.
    var onChange: () -> Void = {}

    private var gameMode: GameModeMonitor?
    private var frontApp: ActiveAppMonitor?
    private var scheduler: ApplyScheduler!

    /// Entering a full-screen game makes Game Mode flicker on/paused/on within a
    /// second, and each change restarts the Dock — doing that repeatedly *during*
    /// the full-screen transition breaks it. So applies are debounced, and the
    /// Dock is never restarted more than once per `minInterval`.
    init(hotCorners: HotCornerController,
         debounce: Duration = .seconds(1.5),
         minInterval: Duration = .seconds(2)) {
        self.hotCorners = hotCorners
        scheduler = ApplyScheduler(debounce: debounce, minInterval: minInterval) { [weak self] in
            await self?.applyPauseState()
        }
    }

    var isPaused: Bool { hotCorners.isPaused }

    func start() {
        gameMode = GameModeMonitor { [weak self] active in
            self?.triggers.gameMode = active
            self?.triggersChanged()
        }
        gameMode?.start()
        frontApp = ActiveAppMonitor { [weak self] active in
            self?.triggers.forcedApp = active
            self?.triggersChanged()
        }
        frontApp?.start()
    }

    func stop() {
        // Tear down the `log stream` child so it doesn't outlive us as an orphan.
        gameMode?.stop()
        frontApp?.stop()
        // Never leave the user's Hot Corners paused after we go away.
        hotCorners.restoreBlocking()
    }

    // MARK: - Actions

    func setEnabled(_ enabled: Bool) {
        Defaults.enabled = enabled
        triggersChanged()
    }

    /// Manual override: pause Hot Corners even when no trigger fired. For the case
    /// where the game was already running before Gamely launched, so detection
    /// never saw the transition. Cleared by `restoreNow()`.
    func pauseNow() async {
        triggers.manual = true
        await hotCorners.pause()
        onChange()
    }

    func restoreNow() async {
        triggers.manual = false
        await hotCorners.restore()
        onChange()
    }

    func setSimulated(_ simulated: Bool) {
        triggers.simulated = simulated
        triggersChanged()
    }

    func whitelistChanged() {
        frontApp?.recheck()
        triggersChanged()
    }

    /// Feeds a Game Mode transition as if the log had reported it (self-test only).
    func setGameMode(_ active: Bool) {
        triggers.gameMode = active
        triggersChanged()
    }

    // MARK: - Pause state

    private func triggersChanged() {
        onChange()   // reflect intent in the menu immediately
        scheduler.schedule()
    }

    private func applyPauseState() async {
        if triggers.shouldPause(enabled: Defaults.enabled) {
            await hotCorners.pause()
        } else {
            await hotCorners.restore()
        }
        onChange()
    }
}
