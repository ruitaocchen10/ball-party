import Foundation
@testable import BallParty
import XCTest

/// The shell around `MatchClock`: it must turn the machine's actions into calls
/// on the screen's own closures and publish the countdown. The behaviours
/// themselves are `MatchClockTests`; this only proves the wiring, with a fake
/// `now` and hand-driven ticks instead of real sleeping.
@MainActor
final class MatchClockDriverTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_786_795_200)
    private var expirations = 0
    private var reconciliations = 0

    private func makeDriver() -> MatchClockDriver {
        MatchClockDriver(
            clock: MatchClock(jitterMs: { 300 }),
            now: { [unowned self] in now },
            expire: { [unowned self] in expirations += 1 },
            reconcile: { [unowned self] in reconciliations += 1 }
        )
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    func test_publishesTheCountdownFromTheObservedBoard() {
        let driver = makeDriver()
        driver.observe(serverNow: now, deadline: now.addingTimeInterval(10), config: MatchClockConfig())

        XCTAssertEqual(driver.remainingMs, 10_000)

        now = now.addingTimeInterval(3)
        driver.tick()
        XCTAssertEqual(driver.remainingMs, 7_000)
    }

    func test_publishesNothingWhenNothingIsTimed() {
        let driver = makeDriver()
        driver.observe(serverNow: now, deadline: nil, config: MatchClockConfig())

        XCTAssertNil(driver.remainingMs)
    }

    func test_asksTheScreenToExpireOncePastTheDeadlineAndJitter() async {
        let driver = makeDriver()
        driver.observe(serverNow: now, deadline: now.addingTimeInterval(1), config: MatchClockConfig())

        now = now.addingTimeInterval(1.5)
        driver.tick()
        await settle()

        XCTAssertEqual(expirations, 1)
    }

    func test_asksTheScreenToReconcileWhenTheAppReturnsToTheForeground() async {
        let driver = makeDriver()
        driver.observe(serverNow: now, deadline: nil, config: MatchClockConfig())

        driver.appReturnedToForeground()
        await settle()

        XCTAssertEqual(reconciliations, 1)
    }

    func test_asksTheScreenToReconcileOnceADeadlineIsStale() async {
        let driver = makeDriver()
        driver.observe(serverNow: now, deadline: now.addingTimeInterval(1), config: MatchClockConfig())

        now = now.addingTimeInterval(6)
        driver.tick()
        await settle()

        XCTAssertEqual(reconciliations, 1)
    }

    func test_aPausedConfigFreezesTheCountdownAndSilencesTheScreen() async {
        let driver = makeDriver()
        let start = now
        driver.observe(serverNow: start, deadline: start.addingTimeInterval(10), config: MatchClockConfig())
        now = start.addingTimeInterval(2)
        driver.tick()
        driver.observe(serverNow: start, deadline: start.addingTimeInterval(10), config: MatchClockConfig(paused: true))
        let frozen = driver.remainingMs
        XCTAssertEqual(frozen, 8_000)

        now = now.addingTimeInterval(30)
        driver.tick()
        await settle()

        XCTAssertEqual(driver.remainingMs, frozen)
        XCTAssertEqual(expirations, 0)
    }

    func test_startTicksOnItsOwnAndStopHaltsIt() async throws {
        let driver = makeDriver()
        driver.observe(serverNow: now, deadline: now.addingTimeInterval(60), config: MatchClockConfig())
        driver.start()
        driver.start() // idempotent

        now = now.addingTimeInterval(5)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(driver.remainingMs, 55_000)

        driver.stop()
        now = now.addingTimeInterval(5)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(driver.remainingMs, 55_000)
    }
}
