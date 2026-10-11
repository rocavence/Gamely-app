import AppKit

/// Owns the detectors and decides when Hot Corners are paused. The menu and
/// Settings read its state and call its actions; nothing else touches
/// `HotCornerController`.
@MainActor
@Observable
final class AppController {
    @ObservationIgnored let hotCorners: HotCornerController
    let updates = UpdateChecker()

    private(set) var triggers = PauseTriggers()
    /// Mirrors `hotCorners.isPaused`, updated after every apply so views follow it.
    private(set) var isPaused: Bool
    private(set) var detection: GameModeMonitor.Health = .starting
    private(set) var lastPausedAt = Defaults.lastPausedAt
    private(set) var lastRestoredAt = Defaults.lastRestoredAt
    /// Why turning on launch at login last failed, if it did.
    private(set) var loginItemError: String?
    private(set) var loginItemEnabled = LoginItem.isEnabled
    private(set) var loginItemNeedsApproval = LoginItem.needsApproval

    var enabled = Defaults.enabled {
        didSet {
            Defaults.enabled = enabled
            triggersChanged()
        }
    }

    var whitelist = Defaults.whitelist {
        didSet {
            Defaults.whitelist = whitelist
            frontApp?.recheck()
            triggersChanged()
        }
    }

    var notifies = Defaults.notifies {
        didSet { Defaults.notifies = notifies }
    }

    /// Fired after anything the menu shows may have changed.
    @ObservationIgnored var onChange: () -> Void = {}
    /// Fired when an apply actually paused (true) or restored (false) Hot Corners.
    @ObservationIgnored var onToggle: (Bool) -> Void = { _ in }

    @ObservationIgnored private var gameMode: GameModeMonitor?
    @ObservationIgnored private var frontApp: ActiveAppMonitor?
    @ObservationIgnored private var scheduler: ApplyScheduler!
    @ObservationIgnored private var powerOff: NSObjectProtocol?

    /// Entering a full-screen game makes Game Mode flicker on/paused/on within a
    /// second, and each change restarts the Dock — doing that repeatedly *during*
    /// the full-screen transition breaks it. So applies are debounced, and the
    /// Dock is never restarted more than once per `minInterval`.
    init(hotCorners: HotCornerController,
         debounce: Duration = .seconds(1.5),
         minInterval: Duration = .seconds(2)) {
        self.hotCorners = hotCorners
        isPaused = hotCorners.isPaused
        scheduler = ApplyScheduler(debounce: debounce, minInterval: minInterval) { [weak self] in
            await self?.applyPauseState()
        }
        updates.onChange = { [weak self] in self?.onChange() }
    }

    func start() {
        gameMode = GameModeMonitor(onChange: { [weak self] active in
            self?.setGameMode(active)
        }, onHealthChange: { [weak self] health in
            self?.detection = health
            self?.onChange()
        })
        gameMode?.start()
        frontApp = ActiveAppMonitor { [weak self] app in
            self?.triggers.forcedApp = app
            self?.triggersChanged()
        }
        frontApp?.start()
        // Logging out or shutting down may not give us a normal quit.
        powerOff = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.hotCorners.restoreBlocking() }
        }
        updates.checkIfDue()
    }

    func stop() {
        // Tear down the `log stream` child so it doesn't outlive us as an orphan.
        gameMode?.stop()
        frontApp?.stop()
        // Never leave the user's Hot Corners paused after we go away.
        hotCorners.restoreBlocking()
    }

    // MARK: - Actions

    /// Manual override: pause Hot Corners even when no trigger fired. For the case
    /// where the game was already running before Gamely launched, so detection
    /// never saw the transition. Cleared by `restoreNow()`.
    func pauseNow() async {
        triggers.manual = true
        await apply(pause: true)
    }

    func restoreNow() async {
        triggers.manual = false
        await apply(pause: false)
    }

    func setSimulated(_ simulated: Bool) {
        triggers.simulated = simulated
        triggersChanged()
    }

    func setLoginItem(_ enabled: Bool) {
        loginItemError = LoginItem.setEnabled(enabled)
        refreshLoginItem()
    }

    func refreshLoginItem() {
        loginItemEnabled = LoginItem.isEnabled
        loginItemNeedsApproval = LoginItem.needsApproval
        onChange()
    }

    func retryDetection() {
        gameMode?.retry()
    }

    /// Feeds a Game Mode state as if the log had reported it.
    func setGameMode(_ active: Bool) {
        triggers.gameMode = active
        triggersChanged()
    }

    // MARK: - Pause state

    /// The status line: what Gamely is doing right now, and why.
    var statusText: String {
        let reason = triggers.reason.map(Self.describe)
        if isPaused {
            return String(localized: "Hot Corners paused: \(reason ?? String(localized: "left over from before"))")
        }
        if let reason, triggers.detected, !enabled {
            return String(localized: "\(reason): pausing is turned off")
        }
        if let reason, triggers.detected {
            return String(localized: "\(reason): pausing Hot Corners…")
        }
        return String(localized: "Hot Corners on")
    }

    static func describe(_ reason: PauseTriggers.Reason) -> String {
        switch reason {
        case .gameMode: String(localized: "Game Mode")
        case .forcedApp(let name): String(localized: "Forced app \(name)")
        case .simulated: String(localized: "Simulated Game Mode")
        case .manual: String(localized: "paused by you")
        }
    }

    private func triggersChanged() {
        onChange()   // reflect intent in the menu immediately
        scheduler.schedule()
    }

    private func applyPauseState() async {
        await apply(pause: triggers.shouldPause(enabled: enabled))
    }

    private func apply(pause: Bool) async {
        let was = isPaused
        if pause {
            await hotCorners.pause()
        } else {
            await hotCorners.restore()
        }
        isPaused = hotCorners.isPaused
        if isPaused != was {
            if isPaused {
                lastPausedAt = .now
                Defaults.lastPausedAt = lastPausedAt
            } else {
                lastRestoredAt = .now
                Defaults.lastRestoredAt = lastRestoredAt
            }
            if notifies { Notifier.post(paused: isPaused, reason: triggers.reason.map(Self.describe)) }
            onToggle(isPaused)
        }
        onChange()
    }
}
