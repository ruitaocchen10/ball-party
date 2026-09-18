import Foundation

/// Runs a `MatchClock` for a screen: ticks it every `tickMs`, publishes
/// `remainingMs` for the countdown, and performs the actions it asks for.
///
/// All the behaviour lives in `MatchClock`; this is only the shell that owns
/// the timer task and turns `MatchClockAction`s into calls on the screen's own
/// `expire` / `reconcile` closures. `now` is injected and `tick()` is callable
/// directly so a test can step it with a fake clock instead of sleeping.
@MainActor
final class MatchClockDriver: ObservableObject {
    @Published private(set) var remainingMs: Int?

    private var clock: MatchClock
    private let now: () -> Date
    private let expire: @MainActor () async -> Void
    private let reconcile: @MainActor () async -> Void
    private var ticker: Task<Void, Never>?

    init(
        clock: MatchClock = MatchClock(),
        now: @escaping () -> Date = Date.init,
        expire: @escaping @MainActor () async -> Void,
        reconcile: @escaping @MainActor () async -> Void
    ) {
        self.clock = clock
        self.now = now
        self.expire = expire
        self.reconcile = reconcile
    }

    deinit {
        ticker?.cancel()
    }

    /// Starts ticking. Idempotent.
    func start() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(MatchClockConstants.tickMs))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
    }

    /// Feeds the latest board in: `serverNow` from the RPC response, `deadline`
    /// as the phase's `phase_deadline`, nil when nothing is timed.
    func observe(serverNow: Date, deadline: Date?, config: MatchClockConfig) {
        perform(clock.update(config: config, serverNow: serverNow, deadline: deadline, localNow: now()))
        remainingMs = clock.remainingMs
    }

    func tick() {
        perform(clock.tick(localNow: now()))
        remainingMs = clock.remainingMs
    }

    func appReturnedToForeground() {
        perform(clock.appReturnedToForeground())
    }

    private func perform(_ actions: [MatchClockAction]) {
        for action in actions {
            switch action {
            case .expire: Task { await expire() }
            case .reconcile: Task { await reconcile() }
            }
        }
    }
}
