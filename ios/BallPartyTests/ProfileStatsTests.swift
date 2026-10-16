import Foundation
@testable import BallParty
import XCTest

/// The pure summary math (`ProfileStats`) and row-decoding (`ProfileMatchHistoryRow`,
/// `ProfileKnowerHighlightRow`) behind the Profile tab's highlights card — the
/// Swift counterpart of the web's `summary.ts` tests.
final class ProfileStatsTests: XCTestCase {
    private let now = try! PostgresTimestamp.parse("2026-09-23T12:00:00+00:00")

    private func match(daysAgo: Double, placement: Int?, mode: RunMode = .party) -> CompletedMatch {
        CompletedMatch(
            game: .higherOrLower, endedAt: now.addingTimeInterval(-daysAgo * 86400), placement: placement, mode: mode
        )
    }

    // MARK: - Rolling windows

    func test_matches_lifetime_keepsEverything() {
        let matches = [match(daysAgo: 1, placement: 1), match(daysAgo: 400, placement: 2)]

        XCTAssertEqual(ProfileStats.matches(matches, in: .lifetime, now: now).count, 2)
    }

    func test_matches_week_dropsAnythingOlderThanSevenDays() {
        let recent = match(daysAgo: 2, placement: 1)
        let old = match(daysAgo: 8, placement: 1)

        XCTAssertEqual(ProfileStats.matches([recent, old], in: .week, now: now), [recent])
    }

    // MARK: - Gamer highlight

    func test_gamerHighlight_computesWinsAndRoundedWinRate() {
        let matches = [
            match(daysAgo: 1, placement: 1),
            match(daysAgo: 1, placement: 2),
            match(daysAgo: 1, placement: 3),
        ]

        let highlight = ProfileStats.gamerHighlight(matches, in: .lifetime, now: now)

        XCTAssertEqual(highlight, GamerHighlight(gamesPlayed: 3, wins: 1, winRate: 33))
    }

    func test_gamerHighlight_excludesSoloRuns() {
        let matches = [match(daysAgo: 1, placement: 1, mode: .solo), match(daysAgo: 1, placement: 1, mode: .arcade)]

        XCTAssertEqual(
            ProfileStats.gamerHighlight(matches, in: .lifetime, now: now),
            GamerHighlight(gamesPlayed: 1, wins: 1, winRate: 100)
        )
    }

    func test_gamerHighlight_withNoMatches_isZeroNotDivideByZero() {
        XCTAssertEqual(ProfileStats.gamerHighlight([], in: .lifetime, now: now), .empty)
    }

    func test_gamerHighlight_respectsTheGivenRange() {
        let matches = [match(daysAgo: 1, placement: 1), match(daysAgo: 40, placement: 1)]

        XCTAssertEqual(ProfileStats.gamerHighlight(matches, in: .month, now: now).gamesPlayed, 1)
    }

    // MARK: - Row → domain

    func test_matchHistoryRow_resolvesAKnownGameAndMode() {
        let row = ProfileMatchHistoryRow(matchId: UUID(), game: "higher_or_lower", endedAt: now, placement: 1, mode: "party")

        XCTAssertEqual(row.completed, CompletedMatch(game: .higherOrLower, endedAt: now, placement: 1, mode: .party))
    }

    func test_matchHistoryRow_withAnUnknownGame_isLeftOut() {
        let row = ProfileMatchHistoryRow(matchId: UUID(), game: "some_future_game", endedAt: now, placement: 1, mode: "party")

        XCTAssertNil(row.completed)
    }

    func test_matchHistoryRow_withAnUnknownMode_isLeftOut() {
        let row = ProfileMatchHistoryRow(matchId: UUID(), game: "higher_or_lower", endedAt: now, placement: 1, mode: "tournament")

        XCTAssertNil(row.completed)
    }

    func test_matchHistoryRow_missingAnEndedAt_isLeftOut() {
        let row = ProfileMatchHistoryRow(matchId: UUID(), game: "higher_or_lower", endedAt: nil, placement: 1, mode: "party")

        XCTAssertNil(row.completed)
    }

    func test_matchHistoryRow_decodesFromPostgREST() throws {
        let row = try JSONDecoder().decode(ProfileMatchHistoryRow.self, from: Data("""
        {"match_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "game": "higher_or_lower",
         "ended_at": "2026-09-20T17:00:00.123456+00:00", "placement": 1, "raw_score": 12, "mode": "party"}
        """.utf8))

        XCTAssertEqual(row.game, "higher_or_lower")
        XCTAssertEqual(row.placement, 1)
        XCTAssertNotNil(row.endedAt)
    }

    // MARK: - Ordinal formatting

    func test_ordinal_handlesTheTeensException() {
        XCTAssertEqual(11.ordinal, "11th")
        XCTAssertEqual(12.ordinal, "12th")
        XCTAssertEqual(13.ordinal, "13th")
        XCTAssertEqual(111.ordinal, "111th")
    }

    func test_ordinal_handlesOrdinarySuffixes() {
        XCTAssertEqual(1.ordinal, "1st")
        XCTAssertEqual(2.ordinal, "2nd")
        XCTAssertEqual(3.ordinal, "3rd")
        XCTAssertEqual(21.ordinal, "21st")
        XCTAssertEqual(42.ordinal, "42nd")
        XCTAssertEqual(80.ordinal, "80th")
    }
}
