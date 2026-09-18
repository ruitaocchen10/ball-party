import Foundation
@testable import BallParty
import XCTest

/// The four behaviours in isolation — the Swift twin of
/// `webapp/lib/runtime/game-runtime/useMatchClock.test.ts`, at the same seam:
/// pure logic, a fake clock, no timers, network or UI. `Harness` plays the part
/// the web test's fake `Date` + fake interval do — it owns "local time" and
/// feeds it to the machine in steps, so the machine sees every tick.
final class MatchClockTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_786_795_200) // 2026-08-15T12:00:00Z

    /// Local-clock stand-in. Time is an integer count of milliseconds since
    /// `epoch` so boundary comparisons are exact, never off by float drift.
    private final class Harness {
        let epoch: Date
        private(set) var elapsedMs = 0
        var clock: MatchClock
        var expiries: [Int] = []
        var reconciles: [Int] = []

        init(epoch: Date, jitterMs: Int = 300) {
            self.epoch = epoch
            clock = MatchClock(jitterMs: { jitterMs })
        }

        /// A point `offsetMs` from `epoch`, on the server's clock or this one's.
        func at(_ offsetMs: Int) -> Date { epoch.addingTimeInterval(Double(offsetMs) / 1_000) }

        var local: Date { at(elapsedMs) }

        func record(_ actions: [MatchClockAction]) {
            for action in actions {
                switch action {
                case .expire: expiries.append(elapsedMs)
                case .reconcile: reconciles.append(elapsedMs)
                }
            }
        }

        func observe(serverNow: Int = 0, deadline: Int?, config: MatchClockConfig = .init()) {
            record(clock.update(config: config, serverNow: at(serverNow), deadline: deadline.map(at), localNow: local))
        }

        /// Steps rather than one jump, so the machine sees every tick.
        func advance(_ ms: Int, step: Int = 100) {
            var elapsed = 0
            while elapsed < ms {
                let stepMs = min(step, ms - elapsed)
                elapsedMs += stepMs
                record(clock.tick(localNow: local))
                elapsed += stepMs
            }
        }

        /// The app is suspended: real time passes and the machine sees none of it.
        func suspend(_ ms: Int) { elapsedMs += ms }

        func tickNow() { record(clock.tick(localNow: local)) }
    }

    // MARK: - The countdown

    func test_countsDownToTheDeadlineUnmodifiedWhenNoSlackIsRequested() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 10_000)
        XCTAssertEqual(h.clock.remainingMs, 10_000)
    }

    func test_endsSlightlyBeforeTheRealDeadlineWhenTheCallerAsksForSlack() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 10_000, config: .init(visibleSlackMs: MatchClockConstants.visibleSlackMs))
        XCTAssertEqual(h.clock.remainingMs, 10_000 - MatchClockConstants.visibleSlackMs)
    }

    func test_neverGoesNegativeOncetheSlackenedDeadlineHasPassed() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 200, config: .init(visibleSlackMs: MatchClockConstants.visibleSlackMs))
        XCTAssertEqual(h.clock.remainingMs, 0)
    }

    func test_reportsNoRemainingTimeWhileNothingIsTimed() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: nil)
        XCTAssertNil(h.clock.remainingMs)
    }

    func test_reportsNothingBeforeItHasSeenAnyServerTime() {
        XCTAssertNil(MatchClock().remainingMs)
    }

    func test_measuresTheDeadlineAgainstServerTimeNotTheDevicesClock() {
        let h = Harness(epoch: epoch)
        // The server says it's 5s past `epoch` while this device still reads
        // `epoch`: a deadline at 10s server-time is 5s away, not 10s.
        h.observe(serverNow: 5_000, deadline: 10_000)
        XCTAssertEqual(h.clock.remainingMs, 5_000)

        h.advance(1_000)
        XCTAssertEqual(h.clock.remainingMs, 4_000)
    }

    func test_doesNotRemeasureTheOffsetWhenTheSameServerTimeIsObservedAgain() {
        let h = Harness(epoch: epoch)
        h.observe(serverNow: 0, deadline: 10_000)
        h.advance(4_000)
        // Re-feeding the same stale `serverNow` must not snap the countdown
        // back to what that timestamp said "now" was at capture.
        h.observe(serverNow: 0, deadline: 10_000)
        XCTAssertEqual(h.clock.remainingMs, 6_000)
    }

    func test_remeasuresTheOffsetWhenAFreshServerTimeArrives() {
        let h = Harness(epoch: epoch)
        h.observe(serverNow: 0, deadline: 10_000)
        h.advance(4_000)
        // Server says 5s have passed rather than the 4s this device counted.
        h.observe(serverNow: 5_000, deadline: 10_000)
        XCTAssertEqual(h.clock.remainingMs, 5_000)
    }

    // MARK: - Expiry

    func test_waitsOutTheJitterWindowBeforeTheFirstAttempt() {
        let h = Harness(epoch: epoch, jitterMs: 300)
        h.observe(deadline: 0)

        h.advance(200)
        XCTAssertTrue(h.expiries.isEmpty)

        h.advance(700)
        XCTAssertFalse(h.expiries.isEmpty)
    }

    func test_keepsAskingEveryRetryIntervalRatherThanFiringOnceAndLatching() {
        let h = Harness(epoch: epoch)
        // A no-op expiry: the deadline never moves, like a server that
        // disagreed and left the match exactly as it was.
        h.observe(deadline: -200)

        h.advance(4_000)
        XCTAssertGreaterThan(h.expiries.count, 1)
    }

    func test_retriesAtTheRetryCadenceOnceTheDeadlineHasPassed() {
        let h = Harness(epoch: epoch, jitterMs: 300)
        h.observe(deadline: 0)

        h.advance(3_500)
        // Jitter 300 → first ask at 300ms, then every 1000ms.
        XCTAssertEqual(h.expiries, [300, 1_300, 2_300, 3_300])
    }

    func test_rollsJitterInsideTheDocumentedWindow() {
        // The default roller is 300 + random * 500 → [300, 800).
        for _ in 0..<50 {
            let jitter = MatchClockConstants.rollJitterMs()
            XCTAssertGreaterThanOrEqual(jitter, 300)
            XCTAssertLessThan(jitter, 800)
        }
    }

    func test_neverAsksForAClientTheCallerHasExempted() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: -2_000, config: .init(skipExpiry: true))

        h.advance(4_000)
        XCTAssertTrue(h.expiries.isEmpty)
    }

    func test_resetsItsRetryCooldownWhenAFreshDeadlineReplacesTheOldOne() {
        let h = Harness(epoch: epoch, jitterMs: 300)
        h.observe(deadline: 200)

        // Fires once, 300ms of jitter after its own 200ms deadline.
        h.advance(400, step: 50)
        XCTAssertEqual(h.expiries.count, 0)
        h.advance(200, step: 50)
        XCTAssertEqual(h.expiries.count, 1)

        // A later deadline, well past the first cooldown. A carried-over
        // cooldown and a reset one fire at different times — that difference
        // is the thing being tested.
        h.observe(deadline: 900)
        h.advance(500, step: 50)
        XCTAssertEqual(h.expiries.count, 1)
        h.advance(200, step: 50)
        XCTAssertEqual(h.expiries.count, 2)
    }

    // MARK: - Heartbeat

    func test_asksNothingBeforeTheDeadlineWhenNoCallerWantsAHeartbeat() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 30_000)

        h.advance(12_000)
        XCTAssertTrue(h.expiries.isEmpty)
    }

    func test_keepsAskingOnItsOwnCadenceWhileTheDeadlineIsStillAhead() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 30_000, config: .init(heartbeatMs: MatchClockConstants.heartbeatMs))

        // A whole call phase is twelve seconds; several beats must land inside.
        h.advance(12_000)
        XCTAssertGreaterThanOrEqual(h.expiries.count, 3)
    }

    func test_speaksUpAsSoonAsANewPhaseBeginsRatherThanWaitingOutABeat() {
        let h = Harness(epoch: epoch)
        let config = MatchClockConfig(heartbeatMs: MatchClockConstants.heartbeatMs)
        h.observe(deadline: 30_000, config: config)

        h.advance(500)
        let onArrival = h.expiries.count

        h.observe(deadline: 60_000, config: config)
        h.advance(500)
        XCTAssertGreaterThan(h.expiries.count, onArrival)
    }

    func test_stillSwitchesToTheFasterRetryCadenceOnceTheDeadlineHasPassed() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: -200, config: .init(heartbeatMs: MatchClockConstants.heartbeatMs))

        h.advance(4_000)
        // Four seconds at the retry cadence is several attempts; at the
        // heartbeat cadence it would be one.
        XCTAssertGreaterThan(h.expiries.count, 2)
    }

    func test_goesQuietOnceNothingIsTimedSoAFinishedMatchStopsBeingPolled() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: nil, config: .init(heartbeatMs: MatchClockConstants.heartbeatMs))

        h.advance(12_000)
        XCTAssertTrue(h.expiries.isEmpty)
    }

    func test_neverAsksForAnExemptedClientHeartbeatOrNot() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 30_000, config: .init(skipExpiry: true, heartbeatMs: MatchClockConstants.heartbeatMs))

        h.advance(12_000)
        XCTAssertTrue(h.expiries.isEmpty)
    }

    func test_aSingleUpdateAsksAtMostOnceEvenWhenTheDeadlineChangesUnderIt() {
        let h = Harness(epoch: epoch, jitterMs: 300)
        let config = MatchClockConfig(heartbeatMs: MatchClockConstants.heartbeatMs)
        h.observe(deadline: 0, config: config)
        h.advance(2_000)
        h.suspend(5_000) // no ticks: the old deadline is long past and its retry is overdue

        let before = h.expiries.count
        // A fresh deadline arrives. The old one must not be asked about on the
        // way to the new one: one update, one evaluation, one ask.
        h.observe(deadline: 60_000, config: config)

        XCTAssertEqual(h.expiries.count - before, 1)
    }

    // MARK: - Pausing

    func test_freezesRemainingMsInsteadOfLettingItKeepCountingDown() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 10_000, config: .init(paused: true))
        let first = h.clock.remainingMs

        h.advance(4_000)
        XCTAssertEqual(h.clock.remainingMs, first)
    }

    func test_asksNothingWhilePausedEvenWithAPassedDeadline() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: -200, config: .init(paused: true))

        h.advance(4_000)
        XCTAssertTrue(h.expiries.isEmpty)
    }

    func test_doesNotReconcileAStaleDeadlineWhilePaused() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: -100, config: .init(paused: true))

        h.advance(5_000)
        XCTAssertTrue(h.reconciles.isEmpty)
    }

    func test_freezesAtTheValueRemainingMsActuallyHeldNotAtServerNowsOriginalSnapshot() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 10_000)
        h.advance(4_000)
        let beforePause = h.clock.remainingMs
        XCTAssertEqual(beforePause, 6_000)

        // The bug this guards against: recomputing the offset from the
        // (unchanged) serverNow on the pause transition snapped `now` back to
        // that snapshot, jumping the countdown back toward its original 10s.
        h.observe(deadline: 10_000, config: .init(paused: true))
        XCTAssertEqual(h.clock.remainingMs, beforePause)
    }

    func test_picksTheCountdownBackUpOnceUnpaused() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 10_000, config: .init(paused: true))
        let frozen = h.clock.remainingMs
        h.advance(4_000)
        XCTAssertEqual(h.clock.remainingMs, frozen)

        h.observe(deadline: 10_000, config: .init(paused: false))
        h.advance(2_000)
        XCTAssertLessThan(h.clock.remainingMs!, frozen!)
    }

    func test_resumesWithoutASpuriousJumpWhenTheDeadlineWasShiftedByThePauseDuration() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 10_000)
        h.advance(4_000)
        let beforePause = h.clock.remainingMs // 6_000

        h.observe(deadline: 10_000, config: .init(paused: true))
        h.advance(3_000) // 3s of real time passes while paused

        // The server's resume shifts the real deadline forward by the pause.
        h.observe(deadline: 13_000, config: .init(paused: false))
        XCTAssertEqual(h.clock.remainingMs, beforePause)
    }

    // MARK: - Reconciliation

    func test_rereadsStateOnceADeadlineHasStayedPastLongEnoughToDistrustExpiry() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: -100)

        h.advance(3_000)
        XCTAssertTrue(h.reconciles.isEmpty)

        h.advance(2_000)
        XCTAssertFalse(h.reconciles.isEmpty)
    }

    func test_keepsReconcilingAStaleDeadlineOncePerStaleInterval() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 0)

        h.advance(9_000)
        // First at the stale threshold (4s), then no sooner than 4s later.
        XCTAssertEqual(h.reconciles, [4_000, 8_000])
    }

    func test_leavesAHealthyDeadlineAlone() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 20_000)

        h.advance(3_000)
        XCTAssertTrue(h.reconciles.isEmpty)
    }

    func test_rereadsStateWhenTheAppReturnsToTheForegroundEvenWithNothingTimed() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: nil)

        XCTAssertEqual(h.clock.appReturnedToForeground(), [.reconcile])
    }

    func test_rereadsStateOnForegroundEvenWhilePaused() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: 10_000, config: .init(paused: true))

        XCTAssertEqual(h.clock.appReturnedToForeground(), [.reconcile])
    }

    func test_exposesTheSameReconciliationARealtimeSubscriptionCanDriveOnChannelRejoin() {
        let h = Harness(epoch: epoch)
        h.observe(deadline: nil)

        XCTAssertEqual(h.clock.channelSubscribed(), [.reconcile])
    }

    // MARK: - Backgrounded mid-question (issue #64)

    func test_afterALongBackgroundingTheNextTickCatchesUpToTheServerDeadlineInOneStep() {
        // iOS suspends the app: no ticks at all for 30s of real time. The
        // machine must not have counted anything meanwhile — its next tick
        // reads local time and lands exactly where the server clock says.
        let h = Harness(epoch: epoch)
        h.observe(deadline: 12_000)
        h.advance(2_000)
        XCTAssertEqual(h.clock.remainingMs, 10_000)

        h.suspend(30_000)
        XCTAssertEqual(h.clock.appReturnedToForeground(), [.reconcile])
        h.tickNow()

        XCTAssertEqual(h.clock.remainingMs, 0)
    }

    func test_afterBackgroundingPastADeadlineTheFirstTickAsksToExpireAndReconciles() {
        let h = Harness(epoch: epoch, jitterMs: 300)
        h.observe(deadline: 12_000, config: .init(heartbeatMs: MatchClockConstants.heartbeatMs))
        h.advance(2_000)

        h.suspend(30_000) // suspended past the deadline
        let actions = h.clock.tick(localNow: h.local)

        XCTAssertEqual(actions, [.expire, .reconcile])
    }

    func test_aFreshServerTimeFromTheForegroundReconcileCorrectsADriftedLocalClock() {
        let h = Harness(epoch: epoch)
        h.observe(serverNow: 0, deadline: 12_000)
        h.advance(2_000)

        // While backgrounded the local clock was adjusted 3s forward (e.g. the
        // user changed it). Reconcile brings a fresh serverNow; the countdown
        // follows the server again.
        h.suspend(3_000)
        h.observe(serverNow: 2_000, deadline: 12_000)
        XCTAssertEqual(h.clock.remainingMs, 10_000)
    }
}
