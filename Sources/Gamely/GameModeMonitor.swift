import Foundation

/// Detects macOS Game Mode by tailing the unified log for gamepolicyd /
/// GamePolicyAgent's "Game mode is on/off" transitions. There is no public API
/// and the notify(3) state isn't populated, so the log is the only reliable
/// signal. Game Mode only engages for full-screen apps whose
/// LSApplicationCategoryType ends in ".games".
final class GameModeMonitor: @unchecked Sendable {
    private let onChange: (Bool) -> Void
    private var process: Process?
    private(set) var isActive = false

    private static let predicate =
        #"(process == "gamepolicyd" OR process == "GamePolicyAgent") AND eventMessage CONTAINS[c] "game mode""#

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        isActive = Self.currentStateFromLog()
        onChange(isActive)        // initial state (also drives crash recovery)
        startStream()
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    // MARK: - Live log stream

    private func startStream() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["stream", "--style", "compact", "--predicate", Self.predicate]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for active in Self.transitions(in: text) {
                DispatchQueue.main.async { self?.update(active) }
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            NSLog("Gamely: `log stream` failed to start: \(error)")
        }
    }

    private func update(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }

    // MARK: - Parsing

    /// Each Game Mode on/off transition found in a chunk of log text, in order.
    private static func transitions(in text: String) -> [Bool] {
        var result: [Bool] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let lower = line.lowercased()
            guard lower.contains("game mode") else { continue }
            if lower.contains("is on") || lower.contains("enabled") {
                result.append(true)
            } else if lower.contains("is off") || lower.contains("disabled") {
                result.append(false)
            }
        }
        return result
    }

    /// Best-effort current state from the most recent transition in the log.
    private static func currentStateFromLog() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["show", "--last", "12h", "--style", "compact", "--predicate", predicate]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return transitions(in: text).last ?? false
    }
}
