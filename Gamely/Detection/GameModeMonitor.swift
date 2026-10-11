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
/// A one-shot `log show --last 1h` seeds the initial state (and recovers after
/// a crash). All state lives on the main actor.
@MainActor
final class GameModeMonitor {
    private let onChange: @MainActor (Bool) -> Void
    private var process: Process?
    private var reader: Task<Void, Never>?
    private var seenLiveTransition = false
    private(set) var isActive = false

    init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        Task {
            // Clean up any `log stream` orphaned by a prior crash/kill first, so
            // the reap can't hit the stream we're about to start.
            _ = await Shell.run("/usr/bin/pkill", ["-f", "log stream.*gamepolicyd.*GamePolicyAgent"])
            startStream()
            // `log show` over a wide window can take several seconds; skip its
            // answer if the live stream has already reported a transition.
            let initial = await Self.currentStateFromLog() ?? false
            if !seenLiveTransition { update(initial) }
        }
    }

    func stop() {
        // The child's exit closes the PTY's slave end, which ends the reader's
        // line sequence; the reader then releases (and closes) the master end.
        // Closing it here instead would race a read still in flight.
        process?.terminate()
        process = nil
        reader?.cancel()
        reader = nil
    }

    /// Spawns `log stream` with stdout wired to a PTY so it line-buffers, and
    /// reads the master end line by line.
    private func startStream() {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let namePtr = ptsname(master) else {
            if master >= 0 { close(master) }
            return
        }
        let slave = open(String(cString: namePtr), O_RDWR | O_NOCTTY)
        guard slave >= 0 else { close(master); return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["stream", "--style", "compact", "--predicate", GameModeLog.predicate]
        task.standardOutput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            log.error("`log stream` failed to start: \(error)")
            close(slave)
            close(master)
            return
        }
        close(slave)   // child holds its own dup; parent doesn't need it
        process = task

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

    private func update(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }

    private static func currentStateFromLog() async -> Bool? {
        let args = ["show", "--last", "1h", "--style", "compact", "--predicate", GameModeLog.predicate]
        guard let data = await Shell.run("/usr/bin/log", args),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return GameModeLog.lastState(in: text)
    }
}
