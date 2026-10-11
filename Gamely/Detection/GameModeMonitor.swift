import Foundation

/// Detects macOS Game Mode by watching the unified log for gamepolicyd /
/// GamePolicyAgent's transition messages — the only reliable signal (there is
/// no public API and the notify(3) state isn't populated).
///
/// We tail `log stream` event-driven rather than polling `log show`. `log`
/// block-buffers when its stdout is a plain pipe, so small bursts never flush;
/// but when stdout is a tty it line-buffers and delivers each line immediately.
/// So we hand `log stream` the slave end of a pseudo-terminal (PTY) and read
/// its master end as an async line sequence — near-zero idle CPU, no per-poll
/// process spawn, and each transition lands the moment it's logged.
///
/// If the stream ends on its own it is restarted; after three quick failures in
/// a row detection is marked as stopped until `retry()`. All state lives on the
/// main actor.
@MainActor
final class GameModeMonitor {
    enum Health: Equatable, Sendable {
        case starting, running, stopped
    }

    struct Command: Sendable {
        var path: String
        var arguments: [String]

        static let logStream = Command(path: "/usr/bin/log",
                                       arguments: ["stream", "--style", "compact", "--predicate", GameModeLog.predicate])
    }

    private let command: Command
    private let seedsFromLog: Bool
    private let restartDelay: Duration
    private let onChange: @MainActor (Bool) -> Void
    private let onHealthChange: @MainActor (Health) -> Void

    private var process: Process?
    private var reader: Task<Void, Never>?
    private var startedAt: ContinuousClock.Instant?
    private var quickFailures = 0
    private var stopping = false
    private var seenLiveTransition = false
    private(set) var isActive = false
    private(set) var health: Health = .starting {
        didSet { if health != oldValue { onHealthChange(health) } }
    }
    /// How many times the stream has been (re)started; for the self-test.
    private(set) var launches = 0

    init(command: Command = .logStream,
         seedsFromLog: Bool = true,
         restartDelay: Duration = .seconds(1),
         onChange: @escaping @MainActor (Bool) -> Void,
         onHealthChange: @escaping @MainActor (Health) -> Void = { _ in }) {
        self.command = command
        self.seedsFromLog = seedsFromLog
        self.restartDelay = restartDelay
        self.onChange = onChange
        self.onHealthChange = onHealthChange
    }

    func start() {
        Task {
            // Clean up any `log stream` orphaned by a prior crash/kill first, so
            // the reap can't hit the stream we're about to start.
            if seedsFromLog {
                _ = await Shell.run("/usr/bin/pkill", ["-f", "log stream.*gamepolicyd.*GamePolicyAgent"])
            }
            startStream()
            guard seedsFromLog else { return }
            // `log show` over a wide window can take several seconds; skip its
            // answer if the live stream has already reported a transition. With
            // no transition in the log, a full-screen game in front still counts.
            let logged = await Self.currentStateFromLog()
            guard !seenLiveTransition else { return }
            seed(logged ?? FrontmostGame.isFullScreenGame())
        }
    }

    func stop() {
        stopping = true
        // The child's exit closes the PTY's slave end, which ends the reader's
        // line sequence; the reader then releases (and closes) the master end.
        // Closing it here instead would race a read still in flight.
        process?.terminate()
        process = nil
        reader?.cancel()
        reader = nil
    }

    /// Starts the stream again after detection stopped.
    func retry() {
        guard health == .stopped else { return }
        quickFailures = 0
        health = .starting
        startStream()
    }

    /// Reports the initial state even when it matches the default, so a pause
    /// left over from before (a crash, a forced quit) is settled right away.
    func seed(_ active: Bool) {
        isActive = active
        onChange(active)
    }

    /// Spawns the stream with stdout wired to a PTY so it line-buffers, and
    /// reads the master end line by line.
    private func startStream() {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let namePtr = ptsname(master) else {
            if master >= 0 { close(master) }
            streamEnded()
            return
        }
        let slave = open(String(cString: namePtr), O_RDWR | O_NOCTTY)
        guard slave >= 0 else { close(master); streamEnded(); return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: command.path)
        task.arguments = command.arguments
        task.standardOutput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        task.standardError = Pipe()
        task.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.streamEnded() }
        }
        do {
            try task.run()
        } catch {
            log.error("`log stream` failed to start: \(error)")
            close(slave)
            close(master)
            streamEnded()
            return
        }
        close(slave)   // child holds its own dup; parent doesn't need it
        process = task
        startedAt = .now
        launches += 1
        health = .running

        let lines = FileHandle(fileDescriptor: master, closeOnDealloc: true).bytes.lines
        reader = Task { [weak self] in
            do {
                for try await line in lines {
                    guard let active = GameModeLog.transition(in: line) else { continue }
                    self?.seenLiveTransition = true
                    self?.update(active)
                }
            } catch {
                // EIO once the child exits — the stream is over.
            }
        }
    }

    /// The stream ended without being asked to: start it again, unless it keeps
    /// dying within moments of starting.
    private func streamEnded() {
        guard !stopping else { return }
        process = nil
        if let startedAt, startedAt.duration(to: .now) > .seconds(30) { quickFailures = 0 }
        quickFailures += 1
        guard quickFailures < 3 else {
            log.error("`log stream` keeps exiting; detection stopped")
            health = .stopped
            return
        }
        log.notice("`log stream` exited; restarting")
        Task {
            try? await Task.sleep(for: restartDelay)
            guard !stopping, health != .stopped else { return }
            startStream()
        }
    }

    private func update(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }

    private static func currentStateFromLog() async -> Bool? {
        let args = ["show", "--last", "12h", "--style", "compact", "--predicate", GameModeLog.predicate]
        guard let data = await Shell.run("/usr/bin/log", args),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return GameModeLog.lastState(in: text)
    }
}
