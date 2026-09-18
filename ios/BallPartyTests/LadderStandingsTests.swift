import Foundation
@testable import BallParty
import XCTest

/// The rail's ordering and each seat's one-word status — pure derivation over
/// rows the server owns, so these are the ranking rules themselves under test,
/// not a screen.
final class LadderStandingsTests: XCTestCase {
    private func player(
        _ name: String,
        seat: Int,
        correct: Int,
        best: Int = 0,
        streak: Int = 0,
        absent: Bool = false,
        suddenDeath: Bool = false,
        eliminatedAt: Int? = nil
    ) -> LadderPlayer {
        LadderPlayer(
            userId: UUID(), seat: seat, displayName: name, currentStreak: streak,
            bestStreak: best, correctCount: correct, absent: absent,
            suddenDeath: suddenDeath, eliminatedAt: eliminatedAt
        )
    }

    private func ranked(_ standings: [LiveStanding]) -> [(String, Int, Bool)] {
        standings.map { ($0.player.name, $0.rank, $0.tied) }
    }

    // MARK: - The live rail

    func test_liveStandings_rankByTotalCorrectFirst() {
        let standings = liveStandings(
            [player("Ali", seat: 0, correct: 3, best: 3), player("Bo", seat: 1, correct: 5, best: 1)],
            phase: .call
        )

        XCTAssertEqual(ranked(standings).map(\.0), ["Bo", "Ali"])
        XCTAssertEqual(ranked(standings).map(\.1), [1, 2])
    }

    func test_liveStandings_breakATieOnCorrectWithTheBestStreak() {
        let standings = liveStandings(
            [player("Ali", seat: 0, correct: 4, best: 2), player("Bo", seat: 1, correct: 4, best: 4)],
            phase: .call
        )

        XCTAssertEqual(ranked(standings).map(\.0), ["Bo", "Ali"])
    }

    func test_liveStandings_playersLevelOnBothMeasuresShareARank() {
        let standings = liveStandings(
            [
                player("Ali", seat: 0, correct: 4, best: 2),
                player("Bo", seat: 1, correct: 4, best: 2),
                player("Cyd", seat: 2, correct: 1, best: 1),
            ],
            phase: .call
        )

        // Standard competition ranking: the two share first, and third is
        // still third rather than second.
        XCTAssertEqual(ranked(standings).map { "\($0.0) \($0.1)\($0.2 ? "T" : "")" }, ["Ali 1T", "Bo 1T", "Cyd 3"])
    }

    func test_liveStandings_suddenDeathContendersOwnTheTopPositions() {
        let standings = liveStandings(
            [
                // A watcher with more correct answers than nobody: the
                // admitted field is still ahead of them, because the game is
                // now about who outlasts whom.
                player("Cyd", seat: 2, correct: 9, best: 9),
                player("Ali", seat: 0, correct: 4, best: 2, suddenDeath: true),
                player("Bo", seat: 1, correct: 4, best: 2, suddenDeath: true),
            ],
            phase: .suddenDeathCall
        )

        XCTAssertEqual(ranked(standings).map(\.0), ["Ali", "Bo", "Cyd"])
        XCTAssertEqual(ranked(standings).map(\.1), [1, 1, 3])
    }

    func test_liveStandings_aSurvivorLeadsTheContendersWhoWentOut() {
        let standings = liveStandings(
            [
                player("Ali", seat: 0, correct: 4, best: 2, suddenDeath: true, eliminatedAt: 13),
                player("Bo", seat: 1, correct: 4, best: 2, suddenDeath: true),
                // Out later, so ahead of the one who went out first.
                player("Cyd", seat: 2, correct: 4, best: 2, suddenDeath: true, eliminatedAt: 14),
            ],
            phase: .suddenDeathReveal
        )

        XCTAssertEqual(ranked(standings).map(\.0), ["Bo", "Cyd", "Ali"])
        XCTAssertEqual(ranked(standings).map(\.1), [1, 2, 3])
    }

    func test_liveStandings_identicalRowsStillOrderStablyBySeat() {
        let standings = liveStandings(
            [player("Bo", seat: 3, correct: 0), player("Ali", seat: 1, correct: 0)],
            phase: .call
        )

        XCTAssertEqual(ranked(standings).map(\.0), ["Ali", "Bo"])
    }

    // MARK: - What a seat is doing

    func test_seatStatus_readsThroughTheQuestionsLifeCycle() {
        let waiting = player("Ali", seat: 0, correct: 0)

        XCTAssertEqual(seatStatus(waiting, call: nil, lockedIn: false, phase: .call), "THINKING")
        XCTAssertEqual(seatStatus(waiting, call: nil, lockedIn: true, phase: .call), "LOCKED")
    }

    func test_seatStatus_saysWhichWayOnlyOnceTheCallIsVisible() {
        let ali = player("Ali", seat: 0, correct: 0)
        let call = LadderCall(question: 3, userId: ali.userId, direction: .higher, timedOut: false)

        // RLS hands the row over only once this viewer may see it; until then
        // the rail says a seat is locked in without saying which way.
        XCTAssertEqual(seatStatus(ali, call: call, lockedIn: true, phase: .reveal), "HIGHER")
    }

    func test_seatStatus_distinguishesRunningOutOfTimeFromAWrongCall() {
        let ali = player("Ali", seat: 0, correct: 0)
        let missed = LadderCall(question: 3, userId: ali.userId, direction: nil, timedOut: true)

        XCTAssertEqual(seatStatus(ali, call: missed, lockedIn: true, phase: .reveal), "TIMED OUT")
    }

    func test_seatStatus_awayOutranksWhateverTheSeatWasDoing() {
        let away = player("Ali", seat: 0, correct: 0, absent: true)

        XCTAssertEqual(seatStatus(away, call: nil, lockedIn: false, phase: .call), "AWAY")
    }

    func test_seatStatus_saysWhoIsOutAndWhoIsOnlyWatchingInSuddenDeath() {
        let out = player("Ali", seat: 0, correct: 4, suddenDeath: true, eliminatedAt: 13)
        let watcher = player("Cyd", seat: 2, correct: 1)

        XCTAssertEqual(seatStatus(out, call: nil, lockedIn: false, phase: .suddenDeathCall), "ELIMINATED")
        XCTAssertEqual(seatStatus(watcher, call: nil, lockedIn: false, phase: .suddenDeathCall), "WATCHING")
    }

    // MARK: - The finished match

    func test_byPlacement_ordersTheFinalTableAndKeepsASharedWin() {
        let alice = UUID(), bo = UUID(), cyd = UUID()
        let ordered = byPlacement([
            MatchStanding(userId: cyd, placement: 3, rawScore: 1.001),
            MatchStanding(userId: alice, placement: 1, rawScore: 4.002),
            MatchStanding(userId: bo, placement: 1, rawScore: 4.002),
        ])

        XCTAssertEqual(ordered.map(\.placement), [1, 1, 3])
        XCTAssertEqual(Set(ordered.prefix(2).map(\.userId)), [alice, bo])
    }

    func test_suddenDeathRound_countsPastTheMainLadder() {
        // The spare ordinals start where the twelve questions end, so the
        // round number is just the distance past them.
        XCTAssertEqual(suddenDeathRound(question: 13, questionCount: 12), 1)
        XCTAssertEqual(suddenDeathRound(question: 15, questionCount: 12), 3)
    }
}
