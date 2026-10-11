import Testing
@testable import Gamely

struct GameModeLogTests {
    @Test(arguments: [
        ("2026-10-11 21:03:12.1 Df gamepolicyd[512:1a2b] Game mode status is now on", true),
        ("... GamePolicyAgent: Game Mode enabled", true),
        ("... gamepolicyd: Game mode status is now paused", false),
        ("... gamepolicyd: GAME MODE STATUS IS NOW OFF", false),
        ("... GamePolicyAgent: game mode disabled\r", false),
    ])
    func transitions(line: String, expected: Bool) {
        #expect(GameModeLog.transition(in: line) == expected)
    }

    @Test(arguments: [
        "Filtering the log data using \"process == gamepolicyd\"",
        "... gamepolicyd: Game mode is on, with 1 user game processes",
        "... gamepolicyd: status is now on",   // no "game mode" in the line
        "",
    ])
    func linesWithoutTransition(line: String) {
        #expect(GameModeLog.transition(in: line) == nil)
    }

    @Test func lastStateWins() {
        let text = """
        ... Game mode status is now on
        ... Game mode status is now paused
        ... Game mode status is now on
        ... unrelated line
        """
        #expect(GameModeLog.lastState(in: text) == true)
    }

    @Test func noTransitionMeansUnknown() {
        #expect(GameModeLog.lastState(in: "Timestamp  Ty Process[PID:TID]\n") == nil)
    }
}
