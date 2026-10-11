import Foundation
@testable import BallParty
import XCTest

/// The pure dial rules and the row decoding — the iOS counterpart of
/// `webapp/lib/games/wavelength/board.test.ts`.
final class WavelengthModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - Clues

    func test_validateClue_acceptsAShortWordClue() {
        XCTAssertNil(WavelengthRules.validateClue("A tailgate in January"))
    }

    func test_validateClue_refusesEmptyDigitsAndLengths() {
        XCTAssertEqual(WavelengthRules.validateClue("   "), "Write a clue before locking it in.")
        XCTAssertEqual(WavelengthRules.validateClue("Gronk 87"), "Clues cannot contain digits.")
        XCTAssertEqual(
            WavelengthRules.validateClue("one two three four five six seven eight nine"),
            "Keep your clue to 8 words or fewer."
        )
        XCTAssertEqual(
            WavelengthRules.validateClue(String(repeating: "a", count: 101)),
            "Keep your clue to 100 characters or fewer."
        )
    }

    func test_validateClue_eightWordsIsTheLimitNotNine() {
        XCTAssertNil(WavelengthRules.validateClue("one two three four five six seven eight"))
    }

    // MARK: - Scoring

    func test_scoringWedges_arePointsTwoThreeFourThreeTwoAroundTheTarget() {
        let wedges = WavelengthRules.scoringWedges(target: 500)
        XCTAssertEqual(wedges.map(\.points), [2, 3, 4, 3, 2])
        XCTAssertEqual(wedges[2].from, 480)
        XCTAssertEqual(wedges[2].to, 520)
        XCTAssertEqual(wedges[0].from, 400)
        XCTAssertEqual(wedges[4].to, 600)
    }

    func test_scoringWedges_areClippedToTheDial() {
        let wedges = WavelengthRules.scoringWedges(target: 10)
        XCTAssertEqual(wedges[0].from, 0)
        XCTAssertGreaterThanOrEqual(wedges[0].to, wedges[0].from)
        let high = WavelengthRules.scoringWedges(target: 995)
        XCTAssertEqual(high[4].to, 1000)
    }

    func test_score_bandsByDistance() {
        XCTAssertEqual(WavelengthRules.score(position: 500, target: 500), 4)
        XCTAssertEqual(WavelengthRules.score(position: 520, target: 500), 4)
        XCTAssertEqual(WavelengthRules.score(position: 521, target: 500), 3)
        XCTAssertEqual(WavelengthRules.score(position: 560, target: 500), 3)
        XCTAssertEqual(WavelengthRules.score(position: 561, target: 500), 2)
        XCTAssertEqual(WavelengthRules.score(position: 600, target: 500), 2)
        XCTAssertEqual(WavelengthRules.score(position: 601, target: 500), 0)
    }

    // MARK: - The dial

    func test_position_mapsTheArcLeftToRight() {
        XCTAssertEqual(WavelengthRules.position(dx: -100, dy: 0), 0)
        XCTAssertEqual(WavelengthRules.position(dx: 100, dy: 0), 1000)
        XCTAssertEqual(WavelengthRules.position(dx: 0, dy: -100), 500)
    }

    func test_position_belowTheBaselineSnapsToTheNearerEnd() {
        XCTAssertEqual(WavelengthRules.position(dx: -50, dy: 80), 0)
        XCTAssertEqual(WavelengthRules.position(dx: 50, dy: 80), 1000)
    }

    func test_angle_isTheInverseOfPosition() {
        for position in [0, 250, 500, 750, 1000] {
            let angle = WavelengthRules.angle(for: position)
            let back = WavelengthRules.position(dx: cos(angle), dy: -sin(angle))
            XCTAssertLessThanOrEqual(abs(back - position), 1)
        }
    }

    // MARK: - Decoding

    func test_board_decodesTheStateProjection() throws {
        let board = try decode(WavelengthBoard.self, """
        {"match_id": "1B2F1C0E-0000-4000-8000-000000000001", "mode": "versus", "preset": null,
         "round_count": 8, "current_round": 3, "phase": "guess",
         "phase_deadline": "2026-10-09T12:01:00Z", "server_now": "2026-10-09T12:00:00Z",
         "team_scores": [6, 4]}
        """)
        XCTAssertEqual(board.mode, .versus)
        XCTAssertNil(board.preset)
        XCTAssertEqual(board.phase, .guess)
        XCTAssertEqual(board.teamScores, [6, 4])
        XCTAssertEqual(board.phaseDeadline?.timeIntervalSince(board.serverNow), 60)
    }

    func test_board_aMissingScoreArrayReadsAsNoScores() throws {
        let board = try decode(WavelengthBoard.self, """
        {"match_id": "1B2F1C0E-0000-4000-8000-000000000001", "mode": "coop", "preset": "short",
         "round_count": 4, "current_round": 1, "phase": "fill",
         "phase_deadline": null, "server_now": "2026-10-09T12:00:00Z"}
        """)
        XCTAssertEqual(board.teamScores, [])
        XCTAssertEqual(board.preset, .short)
    }

    func test_player_takesItsNameFromTheEmbeddedProfile() throws {
        let player = try decode(WavelengthPlayer.self, """
        {"user_id": "1B2F1C0E-0000-4000-8000-000000000001", "seat": 0, "team": 1, "absent": false,
         "profiles": {"display_name": "Dana", "avatar_url": "https://example.com/a.png"}}
        """)
        XCTAssertEqual(player.name, "Dana")
        XCTAssertEqual(player.team, 1)
        XCTAssertEqual(player.avatarURL?.absoluteString, "https://example.com/a.png")
    }

    func test_round_aLockedRoundCarriesTheRevealedTargetAndGuess() throws {
        let round = try decode(WavelengthRound.self, """
        {"round": 2, "psychic_id": "1B2F1C0E-0000-4000-8000-000000000001",
         "guesser_id": "1B2F1C0E-0000-4000-8000-000000000002", "status": "locked",
         "points": 3, "revealed_target": 410, "guess_position": 450}
        """)
        XCTAssertEqual(round.status, .locked)
        XCTAssertEqual(round.revealedTarget, 410)
        XCTAssertEqual(round.guessPosition, 450)
    }

    func test_round_aPendingRoundHasNoTargetOrGuess() throws {
        let round = try decode(WavelengthRound.self, """
        {"round": 2, "psychic_id": "1B2F1C0E-0000-4000-8000-000000000001",
         "guesser_id": "1B2F1C0E-0000-4000-8000-000000000002", "status": "pending",
         "points": null, "revealed_target": null, "guess_position": null}
        """)
        XCTAssertNil(round.revealedTarget)
        XCTAssertNil(round.guessPosition)
    }
}
