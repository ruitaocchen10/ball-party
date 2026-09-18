import Foundation
@testable import BallParty
import XCTest

/// The wire shapes in `docs/architecture/game-runtime.md`, decoded the way
/// PostgREST actually prints them. These are the hand-maintained mirrors — the
/// only thing standing between a server column change and a silently wrong
/// screen — so they are pinned against realistic payloads.
final class HigherOrLowerModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Timestamps

    func test_timestamp_parsesMicrosecondPrecisionWithAnOffset() throws {
        let date = try PostgresTimestamp.parse("2026-08-15T12:00:00.123456+00:00")
        XCTAssertEqual(date.timeIntervalSince1970, 1_786_795_200.123, accuracy: 0.0005)
    }

    func test_timestamp_parsesWholeSecondsWithNoFraction() throws {
        let date = try PostgresTimestamp.parse("2026-08-15T12:00:00+00:00")
        XCTAssertEqual(date.timeIntervalSince1970, 1_786_795_200)
    }

    func test_timestamp_parsesZuluTime() throws {
        let date = try PostgresTimestamp.parse("2026-08-15T12:00:00.5Z")
        XCTAssertEqual(date.timeIntervalSince1970, 1_786_795_200.5, accuracy: 0.0005)
    }

    func test_timestamp_parsesANonUTCOffset() throws {
        let date = try PostgresTimestamp.parse("2026-08-15T08:00:00.000000-04:00")
        XCTAssertEqual(date.timeIntervalSince1970, 1_786_795_200)
    }

    func test_timestamp_rejectsGarbage() {
        XCTAssertThrowsError(try PostgresTimestamp.parse("yesterday"))
    }

    // MARK: - Board

    func test_board_decodesAnUntimedSoloBoard() throws {
        let board = try decode(HigherOrLowerBoard.self, """
        {"match_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "question_count": 12, "spare_count": 5,
         "current_question": 3, "scoring_mode": "weekly", "season_from": 2018, "season_to": 2022,
         "phase": "call", "phase_deadline": null, "server_now": "2026-08-15T12:00:00.123456+00:00"}
        """)

        XCTAssertEqual(board.currentQuestion, 3)
        XCTAssertEqual(board.scoringMode, .weekly)
        XCTAssertEqual(board.season, SeasonRange(from: 2018, to: 2022))
        XCTAssertEqual(board.phase, .call)
        XCTAssertNil(board.phaseDeadline)
    }

    func test_board_decodesATimedBoardsDeadline() throws {
        let board = try decode(HigherOrLowerBoard.self, """
        {"match_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "question_count": 12, "spare_count": 5,
         "current_question": 1, "scoring_mode": "season_total", "season_from": 2010, "season_to": 2025,
         "phase": "sudden_death_reveal", "phase_deadline": "2026-08-15T12:00:12.000000+00:00",
         "server_now": "2026-08-15T12:00:00+00:00"}
        """)

        XCTAssertEqual(board.phase, .suddenDeathReveal)
        XCTAssertEqual(board.phaseDeadline?.timeIntervalSince(board.serverNow), 12)
    }

    func test_board_anUnknownPhaseFailsLoudlyRatherThanRenderingGarbage() {
        XCTAssertThrowsError(try decode(HigherOrLowerBoard.self, """
        {"match_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "question_count": 12, "spare_count": 5,
         "current_question": 1, "scoring_mode": "season_total", "season_from": 2010, "season_to": 2025,
         "phase": "someday", "phase_deadline": null, "server_now": "2026-08-15T12:00:00+00:00"}
        """))
    }

    func test_board_samePositionIgnoresTheServerClockButNotTheGame() throws {
        let json = { (question: Int, now: String) in """
            {"match_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "question_count": 12, "spare_count": 5,
             "current_question": \(question), "scoring_mode": "season_total", "season_from": 2010,
             "season_to": 2025, "phase": "call", "phase_deadline": null, "server_now": "\(now)"}
            """ }
        let a = try decode(HigherOrLowerBoard.self, json(1, "2026-08-15T12:00:00+00:00"))
        let sameLater = try decode(HigherOrLowerBoard.self, json(1, "2026-08-15T12:00:09+00:00"))
        let nextQuestion = try decode(HigherOrLowerBoard.self, json(2, "2026-08-15T12:00:00+00:00"))

        XCTAssertTrue(a.samePosition(as: sameLater))
        XCTAssertFalse(a.samePosition(as: nextQuestion))
    }

    // MARK: - Cards

    func test_card_aConcealedChallengerHasNoPoints() throws {
        let card = try decode(LadderCard.self, """
        {"match_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "ordinal": 4, "player_id": "00-0033873",
         "display_name": "Patrick Mahomes", "position": "QB", "season": 2022, "team": "KC",
         "week": null, "opponent": null, "headshot_url": null, "points": null, "revealed_at": null}
        """)

        XCTAssertNil(card.points)
        XCTAssertEqual(card.identityLine, "2022 · KC")
    }

    func test_card_pointsArriveAsANumber() throws {
        let card = try decode(LadderCard.self, """
        {"ordinal": 1, "player_id": "x", "display_name": "A", "position": "RB", "season": 2022,
         "team": "KC", "points": 289.4}
        """)
        XCTAssertEqual(card.points, 289.4)
    }

    func test_card_pointsArriveAsAnIntegerNumber() throws {
        let card = try decode(LadderCard.self, """
        {"ordinal": 1, "player_id": "x", "display_name": "A", "position": "RB", "season": 2022,
         "team": "KC", "points": 300}
        """)
        XCTAssertEqual(card.points, 300)
    }

    func test_card_pointsArriveAsANumericString() throws {
        let card = try decode(LadderCard.self, """
        {"ordinal": 1, "player_id": "x", "display_name": "A", "position": "RB", "season": 2022,
         "team": "KC", "points": "289.40"}
        """)
        XCTAssertEqual(card.points, 289.4)
    }

    func test_card_aWeeklyCardNamesTheGame() throws {
        let card = try decode(LadderCard.self, """
        {"ordinal": 2, "player_id": "x", "display_name": "Saquon Barkley", "position": "RB",
         "season": 2024, "team": "PHI", "week": 7, "opponent": "NYG", "points": 31.2}
        """)
        XCTAssertEqual(card.identityLine, "2024 · Week 7 · PHI vs. NYG")
    }

    func test_card_concealingPointsKeepsEverythingElse() {
        let card = LadderCard(
            ordinal: 3, playerId: "x", displayName: "A", position: "WR", season: 2020, team: "DAL", points: 12.5
        )
        let hidden = card.concealingPoints()
        XCTAssertNil(hidden.points)
        XCTAssertEqual(hidden.displayName, "A")
        XCTAssertEqual(hidden.ordinal, 3)
    }

    // MARK: - Players and calls

    func test_player_decodesTheTalliesAndIgnoresColumnsItDoesNotUse() throws {
        let player = try decode(LadderPlayer.self, """
        {"match_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "user_id": "1B2F1C0E-0000-4000-8000-000000000001",
         "seat": 0, "current_streak": 2, "best_streak": 5, "correct_count": 5, "last_seen_at": "2026-08-15T12:00:00+00:00",
         "absent": false, "sudden_death": false, "eliminated_at": null}
        """)

        XCTAssertEqual(player.currentStreak, 2)
        XCTAssertEqual(player.bestStreak, 5)
        XCTAssertEqual(player.correctCount, 5)
    }

    func test_call_aTimedOutQuestionHasNoDirection() throws {
        let call = try decode(LadderCall.self, """
        {"match_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "question": 4,
         "user_id": "1B2F1C0E-0000-4000-8000-000000000001", "direction": null, "timed_out": true,
         "created_at": "2026-08-15T12:00:00+00:00"}
        """)

        XCTAssertNil(call.direction)
        XCTAssertTrue(call.timedOut)
    }

    func test_call_decodesADirection() throws {
        let call = try decode(LadderCall.self, """
        {"question": 1, "user_id": "1B2F1C0E-0000-4000-8000-000000000001", "direction": "lower",
         "timed_out": false}
        """)
        XCTAssertEqual(call.direction, .lower)
    }

    // MARK: - Payloads captured from the real local stack

    /// Verbatim responses from `higher_or_lower.start` / the tables, captured
    /// against a local `supabase start` — a guard against the hand-written JSON
    /// above drifting from what PostgREST really sends.
    func test_realPayloads_aRevealedWeeklySeedCardWithAHeadshot() throws {
        let card = try decode(LadderCard.self, """
        {"match_id":"734b65a7-d765-4553-85dc-7b8a50c51ebd","ordinal":0,"player_id":"00-0031345",
         "display_name":"Jimmy Garoppolo","position":"QB","season":2021,"team":"SF","week":10,
         "opponent":"LA","headshot_url":"https://static.www.nfl.com/image/upload/f_auto,q_auto/league/ivz3zwvjxvgcu4dzabur",
         "points":15.4,"revealed_at":"2026-09-18T15:46:56.199669+00:00"}
        """)

        XCTAssertEqual(card.points, 15.4)
        XCTAssertEqual(card.identityLine, "2021 · Week 10 · SF vs. LA")
        XCTAssertNotNil(card.headshotUrl.flatMap(URL.init(string:)))
    }

    func test_realPayloads_aHiddenChallengerRow() throws {
        let card = try decode(LadderCard.self, """
        {"match_id":"734b65a7-d765-4553-85dc-7b8a50c51ebd","ordinal":1,"player_id":"00-0032058",
         "display_name":"Tevin Coleman","position":"RB","season":2019,"team":"SF","week":7,"opponent":"WAS",
         "headshot_url":"https://static.www.nfl.com/image/private/f_auto,q_auto/league/wiu4r7bvhcafs9vamqc",
         "points":null,"revealed_at":null}
        """)

        XCTAssertNil(card.points)
    }

    func test_realPayloads_theBoardAfterAStartAndAfterAReveal() throws {
        let dealt = try decode(HigherOrLowerBoard.self, """
        {"match_id":"734b65a7-d765-4553-85dc-7b8a50c51ebd","question_count":12,"spare_count":5,
         "current_question":1,"scoring_mode":"weekly","season_from":2018,"season_to":2022,
         "phase":"call","phase_deadline":null,"server_now":"2026-09-18T15:46:56.199669+00:00"}
        """)
        let revealed = try decode(HigherOrLowerBoard.self, """
        {"match_id":"734b65a7-d765-4553-85dc-7b8a50c51ebd","question_count":12,"spare_count":5,
         "current_question":1,"scoring_mode":"weekly","season_from":2018,"season_to":2022,
         "phase":"reveal","phase_deadline":null,"server_now":"2026-09-18T15:47:07.932522+00:00"}
        """)

        XCTAssertEqual(dealt.phase, .call)
        XCTAssertEqual(revealed.phase, .reveal)
        XCTAssertFalse(dealt.samePosition(as: revealed))
    }

    func test_realPayloads_theCallRowAndThePlayersRow() throws {
        let call = try decode(LadderCall.self, """
        {"match_id":"734b65a7-d765-4553-85dc-7b8a50c51ebd","question":1,
         "user_id":"e2d56756-9cd1-41db-9a62-bd2c0c35dcad","direction":"higher",
         "created_at":"2026-09-18T15:47:07.91156+00:00","timed_out":false}
        """)
        let player = try decode(LadderPlayer.self, """
        {"match_id":"734b65a7-d765-4553-85dc-7b8a50c51ebd","user_id":"e2d56756-9cd1-41db-9a62-bd2c0c35dcad",
         "seat":0,"current_streak":0,"best_streak":0,"correct_count":0,
         "last_seen_at":"2026-09-18T15:46:56.199669+00:00","absent":false,"sudden_death":false,"eliminated_at":null}
        """)

        XCTAssertEqual(call.direction, .higher)
        XCTAssertEqual(player.correctCount, 0)
    }

    // MARK: - Phases and labels

    func test_phase_onlyRevealedPhasesShowTheChallengersPoints() {
        XCTAssertFalse(HigherOrLowerPhase.boardIntro.showsChallengerPoints)
        XCTAssertFalse(HigherOrLowerPhase.call.showsChallengerPoints)
        XCTAssertFalse(HigherOrLowerPhase.suddenDeathCall.showsChallengerPoints)
        XCTAssertTrue(HigherOrLowerPhase.reveal.showsChallengerPoints)
        XCTAssertTrue(HigherOrLowerPhase.suddenDeathReveal.showsChallengerPoints)
        XCTAssertTrue(HigherOrLowerPhase.complete.showsChallengerPoints)
    }

    func test_seasonRange_labelsASingleSeasonWithoutADash() {
        XCTAssertEqual(SeasonRange(from: 2023, to: 2023).label, "2023")
        XCTAssertEqual(SeasonRange(from: 2010, to: 2025).label, "2010–2025")
    }
}
