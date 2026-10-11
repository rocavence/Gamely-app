/// Coalesces bursts of requests into one apply: each `schedule()` restarts a
/// `debounce` timer, and applies are spaced at least `minInterval` apart even
/// when requests arrive just under the debounce window apart.
@MainActor
final class ApplyScheduler {
    private let debounce: Duration
    private let minInterval: Duration
    private let apply: @MainActor () async -> Void
    private var pending: Task<Void, Never>?
    private var lastApplyAt: ContinuousClock.Instant?

    init(debounce: Duration, minInterval: Duration, apply: @escaping @MainActor () async -> Void) {
        self.debounce = debounce
        self.minInterval = minInterval
        self.apply = apply
    }

    func schedule() {
        pending?.cancel()
        pending = Task {
            do {
                try await Task.sleep(for: debounce)
                if let last = lastApplyAt {
                    let wait = minInterval - last.duration(to: .now)
                    if wait > .zero { try await Task.sleep(for: wait) }
                }
            } catch {
                return   // superseded by a newer request
            }
            lastApplyAt = .now
            await apply()
        }
    }
}
