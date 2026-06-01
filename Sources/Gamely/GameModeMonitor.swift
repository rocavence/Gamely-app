import Foundation

/// Detects macOS Game Mode by polling the unified log for gamepolicyd /
/// GamePolicyAgent's transition messages — the only reliable signal (there is
/// no public API and the notify(3) state isn't populated). We poll `log show`
/// on a short window rather than tailing `log stream`, because `log stream`
/// block-buffers when its stdout is a pipe and small bursts never flush.
///
/// Active when the log last said "Game mode status is now on" (or "enabled");
/// inactive on "status is now paused/off" (or "disabled") — so tabbing out of
/// the game (which pauses Game Mode) restores Hot Corners too.
final class GameModeMonitor: @unchecked Sendable {
    private let onChange: (Bool) -> Void
    private let queue = DispatchQueue(label: "com.gamely.monitor")
    private var timer: DispatchSourceTimer?
    private(set) var isActive = false

    private static let pollInterval: TimeInterval = 3
    private static let window = 10           // seconds of log to scan each poll
    private static let predicate =
        #"(process == "gamepolicyd" OR process == "GamePolicyAgent") AND eventMessage CONTAINS[c] "game mode""#

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        isActive = Self.lastTransition(lastSeconds: 12 * 3600) ?? false   // initial + crash recovery
        onChange(isActive)

        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval)
        t.setEventHandler { [weak self] in self?.poll() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func poll() {
        guard let latest = Self.lastTransition(lastSeconds: Self.window) else { return }
        DispatchQueue.main.async { [weak self] in self?.update(latest) }
    }

    private func update(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }

    /// The most recent Game Mode on/off transition within the window, or nil if
    /// the window contains no transition (state unchanged).
    private static func lastTransition(lastSeconds: Int) -> Bool? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["show", "--last", "\(lastSeconds)s", "--style", "compact", "--predicate", predicate]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var state: Bool?
        for line in text.split(whereSeparator: \.isNewline) {
            let l = line.lowercased()
            guard l.contains("game mode") else { continue }
            if l.contains("status is now on") || l.contains("game mode enabled") {
                state = true
            } else if l.contains("status is now paused") || l.contains("status is now off")
                        || l.contains("game mode disabled") {
                state = false
            }
        }
        return state
    }
}
