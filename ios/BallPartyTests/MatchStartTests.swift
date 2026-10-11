import Foundation
@testable import BallParty
import XCTest

/// The start countdown is the server's: the screen counts down to
/// `play_starts_at` against the server's clock, never its own.
final class MatchStartTests: XCTestCase {
    private let serverNow = Date(timeIntervalSince1970: 1_786_795_200)

    func testCountsDownToTheServersStartTime() {
        let start = MatchPlayStart(playStartsAt: serverNow.addingTimeInterval(3), serverNow: serverNow)
        let fetchedAt = Date(timeIntervalSince1970: 5_000)

        XCTAssertEqual(start.secondsUntilPlay(fetchedAt: fetchedAt, now: fetchedAt)!, 3, accuracy: 0.001)
        XCTAssertEqual(start.secondsUntilPlay(fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(1.25))!, 1.75, accuracy: 0.001)
    }

    func testIsOverOnceTheStartTimeHasPassed() {
        let start = MatchPlayStart(playStartsAt: serverNow.addingTimeInterval(3), serverNow: serverNow)
        let fetchedAt = Date(timeIntervalSince1970: 5_000)

        XCTAssertLessThanOrEqual(start.secondsUntilPlay(fetchedAt: fetchedAt, now: fetchedAt.addingTimeInterval(3))!, 0)
    }

    func testAJoinerWhoArrivesLateSeesWhatIsLeft() {
        // The server says play starts in 1.2s: the others have already counted down.
        let start = MatchPlayStart(playStartsAt: serverNow.addingTimeInterval(1.2), serverNow: serverNow)
        let fetchedAt = Date(timeIntervalSince1970: 9_999)

        XCTAssertEqual(start.secondsUntilPlay(fetchedAt: fetchedAt, now: fetchedAt)!, 1.2, accuracy: 0.001)
    }

    func testADeviceClockThatIsWrongDoesNotMatter() {
        // Same answer whatever the device thinks the time is: only the elapsed
        // time since the fetch counts.
        let start = MatchPlayStart(playStartsAt: serverNow.addingTimeInterval(3), serverNow: serverNow)
        let wrongClock = Date(timeIntervalSince1970: 42)

        XCTAssertEqual(start.secondsUntilPlay(fetchedAt: wrongClock, now: wrongClock.addingTimeInterval(1))!, 2, accuracy: 0.001)
    }

    func testThereIsNothingToCountWhenTheMatchHasNoStartTime() {
        let start = MatchPlayStart(playStartsAt: nil, serverNow: serverNow)

        XCTAssertNil(start.secondsUntilPlay(fetchedAt: serverNow, now: serverNow))
    }

    func testDecodesWhatTheServerSends() throws {
        let json = #"{"play_starts_at":"2026-10-11T17:36:16.521461+00:00","server_now":"2026-10-11T17:36:13.521461+00:00"}"#
        let start = try JSONDecoder().decode(MatchPlayStart.self, from: Data(json.utf8))

        XCTAssertEqual(start.playStartsAt!.timeIntervalSince(start.serverNow), 3, accuracy: 0.001)
    }

    func testDecodesASoloRunsNullStartTime() throws {
        let json = #"{"play_starts_at":null,"server_now":"2026-10-11T17:36:13.521461+00:00"}"#
        let start = try JSONDecoder().decode(MatchPlayStart.self, from: Data(json.utf8))

        XCTAssertNil(start.playStartsAt)
    }
}
