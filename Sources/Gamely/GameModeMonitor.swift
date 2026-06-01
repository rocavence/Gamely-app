import Foundation

/// Detects macOS Game Mode by watching the unified log for gamepolicyd /
/// GamePolicyAgent's transition messages — the only reliable signal (there is
/// no public API and the notify(3) state isn't populated).
///
/// We tail `log stream` event-driven rather than polling `log show`. `log`
/// block-buffers when its stdout is a plain pipe, so small bursts never flush;
/// but when stdout is a tty it line-buffers and delivers each line immediately.
/// So we hand `log stream` the slave end of a pseudo-terminal (PTY) and read
/// its master end via a dispatch source — near-zero idle CPU, no per-poll
/// process spawn, and each transition lands the moment it's logged.
///
/// Active when the log last said "Game mode status is now on" (or "enabled");
/// inactive on "status is now paused/off" (or "disabled") — so tabbing out of
/// the game (which pauses Game Mode) restores Hot Corners too. A one-shot
/// `log show --last 12h` seeds the initial state (and recovers after a crash).
final class GameModeMonitor: @unchecked Sendable {
    private let onChange: (Bool) -> Void
    private var process: Process?
    private var masterFD: Int32 = -1
    private var source: DispatchSourceRead?
    // .utility QoS so this persistent log tail is scheduled on efficiency cores,
    // keeping its idle energy impact low.
    private let ioQueue = DispatchQueue(label: "com.gamely.monitor", qos: .utility)
    private var buffer = Data()
    private var seenLiveTransition = false
    private(set) var isActive = false

    private static let predicate =
        #"(process == "gamepolicyd" OR process == "GamePolicyAgent") AND eventMessage CONTAINS[c] "game mode""#

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        Self.reapStrayStreams()   // clean up any `log stream` orphaned by a prior crash/kill
        startStream()
        // Seed the initial state in the background: `log show` over a wide window
        // can take several seconds and must not block app launch. Skip the result
        // if the live stream has already reported a transition by then.
        ioQueue.async { [weak self] in
            let initial = Self.currentStateFromLog() ?? false
            DispatchQueue.main.async {
                guard let self, !self.seenLiveTransition else { return }
                self.update(initial)
            }
        }
    }

    /// Kill any `log stream` we left running before (e.g. after a crash or a
    /// hard kill that skipped applicationWillTerminate), matched by our distinctive
    /// predicate, so they don't pile up.
    private static func reapStrayStreams() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        task.arguments = ["-f", "log stream.*gamepolicyd.*GamePolicyAgent"]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
    }

    func stop() {
        source?.cancel()
        source = nil
        process?.terminate()
        process = nil
        if masterFD >= 0 { close(masterFD); masterFD = -1 }
    }

    /// Spawns `log stream` with stdout wired to a PTY so it line-buffers, and
    /// reads the master end on `ioQueue` via a dispatch read source.
    private func startStream() {
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0, grantpt(master) == 0, unlockpt(master) == 0,
              let namePtr = ptsname(master) else {
            if master >= 0 { close(master) }
            return
        }
        let slavePath = String(cString: namePtr)
        let slave = open(slavePath, O_RDWR | O_NOCTTY)
        guard slave >= 0 else { close(master); return }
        masterFD = master

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["stream", "--style", "compact", "--predicate", Self.predicate]
        task.standardOutput = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        task.standardError = Pipe()

        let src = DispatchSource.makeReadSource(fileDescriptor: master, queue: ioQueue)
        src.setEventHandler { [weak self] in
            guard let self else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = read(self.masterFD, &buf, buf.count)
            if n > 0 { self.handle(Data(buf[0..<n])) }
        }
        source = src

        do {
            try task.run()
            process = task
            close(slave)            // child holds its own dup; parent doesn't need it
            src.resume()
        } catch {
            NSLog("Gamely: `log stream` failed to start: \(error)")
            close(slave)
        }
    }

    /// "game mode", lowercased ASCII — the substring every transition line
    /// carries. Used to gate String transcoding (see `handle`).
    private static let gameModeBytes: [UInt8] = Array("game mode".utf8)

    /// Accumulates stream bytes and applies any complete line's transition.
    private func handle(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            // Cheap byte-level gate: only the rare line mentioning "game mode" can
            // be a transition, so skip String transcoding for everything else.
            guard Self.containsASCIICaseless(lineData, Self.gameModeBytes),
                  let line = String(data: lineData, encoding: .utf8),
                  let active = Self.transition(in: line) else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.seenLiveTransition = true
                self?.update(active)
            }
        }
    }

    /// Case-insensitive (ASCII) search for `needle`'s bytes in `haystack`.
    /// `needle` must already be lowercase ASCII. Matches the case-folding that
    /// `transition(in:)` does via `lowercased()`, so it never rejects a line the
    /// String path would accept.
    private static func containsASCIICaseless(_ haystack: Data, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, haystack.count >= needle.count else { return false }
        let last = haystack.count - needle.count
        return haystack.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            let bytes = raw.bindMemory(to: UInt8.self)
            for start in 0...last {
                var matched = true
                for i in 0..<needle.count {
                    var c = bytes[start + i]
                    if c >= 65 && c <= 90 { c += 32 }   // ASCII upper -> lower
                    if c != needle[i] { matched = false; break }
                }
                if matched { return true }
            }
            return false
        }
    }

    private func update(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        onChange(active)
    }

    /// Parses a single log line into an on/off transition, or nil if the line
    /// carries no Game Mode state change.
    private static func transition(in line: String) -> Bool? {
        let l = line.lowercased()
        guard l.contains("game mode") else { return nil }
        if l.contains("status is now on") || l.contains("game mode enabled") { return true }
        if l.contains("status is now paused") || l.contains("status is now off")
            || l.contains("game mode disabled") { return false }
        return nil
    }

    /// Seeds the initial state from the last 12h of log, or nil if no transition
    /// is found (state unknown).
    private static func currentStateFromLog() -> Bool? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        task.arguments = ["show", "--last", "1h", "--style", "compact", "--predicate", predicate]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do { try task.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        var state: Bool?
        for line in text.split(whereSeparator: \.isNewline) {
            if let t = transition(in: String(line)) { state = t }
        }
        return state
    }
}
