import Foundation

/// Tuned constants for the timer/reconciliation state machine. Values and the
/// reasons behind them are specified in `docs/architecture/game-runtime.md`
/// ("The timer/reconciliation state machine") — that doc is the spec, and
/// `webapp/lib/runtime/game-runtime/useMatchClock.ts` is the reference
/// implementation of it. They were tuned from a real playtest incident, so
/// change them there first.
enum MatchClockConstants {
    /// How far before the real deadline the visible countdown reaches zero, for
    /// a phase a move can still be sent in.
    static let visibleSlackMs = 500
    /// How often the visible countdown updates.
    static let tickMs = 100
    /// How often a client re-asks the server to expire a deadline that has
    /// already passed. Asking again is free — the server no-ops if it disagrees.
    static let retryMs = 1_000
    /// How often a client that wants a heartbeat asks *before* the deadline.
    static let heartbeatMs = 3_000
    /// How far past a deadline the client has to be before it stops trusting its
    /// own expiry attempts and re-reads full state.
    static let staleMs = 4_000

    /// `300 + random * 500`, re-rolled per deadline, so several idle clients'
    /// retries spread across a window instead of stampeding one instant.
    static func rollJitterMs() -> Int {
        300 + Int(Double.random(in: 0..<1) * 500)
    }
}

/// What the caller wants from the clock right now. Mirrors `MatchClockOptions`
/// in `useMatchClock.ts`, minus the two RPCs — those belong to whoever performs
/// the `MatchClockAction`s this machine asks for.
struct MatchClockConfig: Equatable, Sendable {
    /// Subtracted from the deadline before computing `remainingMs`. 0 for a
    /// phase nobody can act in; `visibleSlackMs` for one a move can be sent in.
    var visibleSlackMs = 0
    /// Skip asking the server to expire from this client entirely.
    var skipExpiry = false
    /// How often to ask while the deadline is still ahead. `nil` for a game
    /// whose expiry endpoint learns nothing from being asked early; Higher or
    /// Lower passes `heartbeatMs`, since its `tick` RPC stamps presence.
    var heartbeatMs: Int?
    /// A paused match freezes `remainingMs` and stops all asking.
    var paused = false
}

/// A side effect the machine wants performed. The machine never performs one
/// itself — it has no network, no timers and no clock of its own, which is what
/// lets a test drive it with fake deadlines and a fake `localNow`.
enum MatchClockAction: Equatable, Sendable {
    /// Call the game's expiry RPC (`higher_or_lower.tick`) and apply its result.
    case expire
    /// Re-read the game's full state (`higher_or_lower.state` and the tables)
    /// and apply it.
    case reconcile
}

/// The four behaviours every timer-driven match screen needs, as a value type
/// with no I/O: a countdown measured against server time, expiry asked for
/// repeatedly with jitter, an optional heartbeat, and watchdog reconciliation.
///
/// Callers feed it *time* (`tick`) and *state* (`update`), and it answers
/// with `remainingMs` and the `MatchClockAction`s to perform. Time is always an
/// argument, never read from a clock, so every branch is testable.
///
/// Integer milliseconds throughout: deadlines and timestamps are compared
/// against thresholds like "at least 1000ms since the last ask", and rounding
/// once at the `Date` boundary keeps those comparisons exact.
struct MatchClock {
    private let rollJitterMs: () -> Int

    private var config = MatchClockConfig()
    /// `serverTime - localTime`, re-measured only when a *fresh* `serverNow`
    /// arrives. Recomputing it against the same stale `serverNow` would snap
    /// the countdown back to whatever that timestamp said "now" was at capture,
    /// discarding the real time elapsed since.
    private var offsetMs = 0
    private var lastServerNowMs: Int?
    /// The server-relative "now" as of the last tick. `nil` until the first one.
    /// Frozen while paused.
    private var nowMs: Int?
    private var deadlineMs: Int?
    private var jitterMs = 0
    private var lastAttemptMs: Int?
    private var lastReconcileMs: Int?

    init(jitterMs: @escaping () -> Int = MatchClockConstants.rollJitterMs) {
        rollJitterMs = jitterMs
        self.jitterMs = jitterMs()
    }

    /// Time left on the visible countdown, or `nil` when nothing is timed (or
    /// nothing has been observed yet).
    var remainingMs: Int? {
        guard let deadlineMs, let nowMs else { return nil }
        return max(0, deadlineMs - config.visibleSlackMs - nowMs)
    }

    /// Feeds the latest config and server state in as one step, evaluated once.
    ///
    /// `serverNow` is `server_now` from an RPC response; `deadline` is
    /// `phase_deadline` (or `nil` when nothing is timed, including once the
    /// match is complete). A `serverNow` different from the last one re-measures
    /// the offset; a different `deadline` is a fresh thing to time — its jitter
    /// is re-rolled and its retry cooldown cleared. Toggling `paused` takes one
    /// tick against the current offset, which is what freezes `remainingMs` at
    /// the value it actually held on pause and resumes it from that same point.
    ///
    /// One step rather than one call per input: evaluating between them would
    /// ask about the *old* deadline on the way to the new one.
    mutating func update(
        config newConfig: MatchClockConfig,
        serverNow: Date,
        deadline: Date?,
        localNow: Date
    ) -> [MatchClockAction] {
        let pauseChanged = newConfig.paused != config.paused
        config = newConfig
        if pauseChanged { nowMs = Self.ms(localNow) + offsetMs }

        let serverNowMs = Self.ms(serverNow)
        if serverNowMs != lastServerNowMs {
            lastServerNowMs = serverNowMs
            offsetMs = serverNowMs - Self.ms(localNow)
            nowMs = Self.ms(localNow) + offsetMs
        }

        let newDeadlineMs = deadline.map(Self.ms)
        if newDeadlineMs != deadlineMs {
            deadlineMs = newDeadlineMs
            jitterMs = rollJitterMs()
            lastAttemptMs = nil
        }
        return evaluate()
    }

    /// One countdown tick (every `MatchClockConstants.tickMs`). While paused
    /// this changes nothing: `remainingMs` stays frozen and nothing is asked.
    mutating func tick(localNow: Date) -> [MatchClockAction] {
        guard !config.paused else { return [] }
        nowMs = Self.ms(localNow) + offsetMs
        return evaluate()
    }

    /// The app came back to the foreground. Unconditional — even with nothing
    /// timed, even while paused: while suspended the ticks above may barely
    /// have run, so a foregrounded screen is always worth re-reading.
    func appReturnedToForeground() -> [MatchClockAction] { [.reconcile] }

    /// The Realtime channel (re)subscribed — a first connect counts too. Only
    /// the channel subscription itself can know this happened.
    func channelSubscribed() -> [MatchClockAction] { [.reconcile] }

    // MARK: - Private

    /// Expiry (with its heartbeat) and the watchdog, evaluated against the
    /// current `nowMs`.
    private mutating func evaluate() -> [MatchClockAction] {
        guard let deadlineMs, let nowMs, !config.paused else { return [] }
        var actions: [MatchClockAction] = []

        // One cadence, chosen by whether the deadline has passed: the retry
        // interval once it has, the caller's heartbeat until then. Sharing
        // `lastAttemptMs` across both keeps a beat and a retry from doubling up
        // at the boundary, and its reset on a new deadline is why a fresh phase
        // is asked about immediately — which a heartbeat caller wants, since
        // that ask is what puts them on the record as present for the question
        // that just opened.
        if !config.skipExpiry {
            let passed = nowMs >= deadlineMs + jitterMs
            if let interval = passed ? MatchClockConstants.retryMs : config.heartbeatMs,
               lastAttemptMs.map({ nowMs - $0 >= interval }) ?? true {
                lastAttemptMs = nowMs
                actions.append(.expire)
            }
        }

        // The watchdog is the admission that expiry might not have worked — a
        // suspended app, a dropped Realtime payload, or every client eligible
        // to ask being exempt. It only runs once a deadline is well past, so a
        // healthy match never reaches it.
        if nowMs >= deadlineMs + MatchClockConstants.staleMs,
           lastReconcileMs.map({ nowMs - $0 >= MatchClockConstants.staleMs }) ?? true {
            lastReconcileMs = nowMs
            actions.append(.reconcile)
        }
        return actions
    }

    private static func ms(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 * 1_000).rounded())
    }
}
