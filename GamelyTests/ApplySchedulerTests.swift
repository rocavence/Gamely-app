import Testing
@testable import Gamely

@MainActor
struct ApplySchedulerTests {
    @Test func burstCoalescesIntoOneApply() async throws {
        var applies = 0
        let scheduler = ApplyScheduler(debounce: .milliseconds(100), minInterval: .zero) { applies += 1 }

        for _ in 0..<5 {
            scheduler.schedule()
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(applies == 0)   // still inside the debounce window
        try await Task.sleep(for: .milliseconds(250))
        #expect(applies == 1)
    }

    @Test func appliesAreSpacedByMinInterval() async throws {
        var times: [ContinuousClock.Instant] = []
        let scheduler = ApplyScheduler(debounce: .milliseconds(20), minInterval: .milliseconds(300)) {
            times.append(.now)
        }

        scheduler.schedule()
        try await Task.sleep(for: .milliseconds(80))
        scheduler.schedule()   // debounce alone would apply ~20ms from now
        try await Task.sleep(for: .milliseconds(500))

        #expect(times.count == 2)
        if times.count == 2 {
            #expect(times[0].duration(to: times[1]) >= .milliseconds(300))
        }
    }
}

struct PauseTriggersTests {
    @Test func disabledNeverPauses() {
        let t = PauseTriggers(gameMode: true, forcedApp: true, manual: true, simulated: true)
        #expect(!t.shouldPause(enabled: false))
    }

    @Test func anyTriggerPausesWhenEnabled() {
        #expect(!PauseTriggers().shouldPause(enabled: true))
        #expect(PauseTriggers(gameMode: true).shouldPause(enabled: true))
        #expect(PauseTriggers(forcedApp: true).shouldPause(enabled: true))
        #expect(PauseTriggers(manual: true).shouldPause(enabled: true))
    }

    @Test func manualPauseIsNotDetection() {
        #expect(!PauseTriggers(manual: true).detected)
    }
}
