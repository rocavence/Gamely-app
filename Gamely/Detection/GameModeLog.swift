/// Parses gamepolicyd / GamePolicyAgent unified-log lines into Game Mode state.
///
/// Active when the log last said "Game mode status is now on" (or "enabled");
/// inactive on "status is now paused/off" (or "disabled") — so tabbing out of
/// the game (which pauses Game Mode) restores Hot Corners too.
enum GameModeLog {
    static let predicate =
        #"(process == "gamepolicyd" OR process == "GamePolicyAgent") AND eventMessage CONTAINS[c] "game mode""#

    /// The on/off transition a single log line carries, or nil if it carries none.
    static func transition(in line: some StringProtocol) -> Bool? {
        let l = line.lowercased()
        guard l.contains("game mode") else { return nil }
        if l.contains("status is now on") || l.contains("game mode enabled") { return true }
        if l.contains("status is now paused") || l.contains("status is now off")
            || l.contains("game mode disabled") { return false }
        return nil
    }

    /// The state after the last transition in a block of log output, or nil if
    /// it contains none (state unknown).
    static func lastState(in text: String) -> Bool? {
        var state: Bool?
        for line in text.split(whereSeparator: \.isNewline) {
            if let t = transition(in: line) { state = t }
        }
        return state
    }
}
