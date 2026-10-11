import Foundation
@testable import BallParty
import XCTest

final class SabotageModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }

    // MARK: - Modes and slots

    func test_modes_haveTheRoundCountsTheServerDeals() {
        XCTAssertEqual(SabotageMode.full.slots.count, 14)
        XCTAssertEqual(SabotageMode.standard.slots.count, 10)
        XCTAssertEqual(SabotageMode.quick.slots.count, 7)
        for mode in SabotageMode.allCases {
            XCTAssertEqual(mode.slots.last, SabotageRules.xFactor, "\(mode) must end on the X-Factor")
        }
    }

    func test_modeIsRecoveredFromTheRoundCount() {
        XCTAssertEqual(SabotageMode.forRoundCount(14), .full)
        XCTAssertEqual(SabotageMode.forRoundCount(10), .standard)
        XCTAssertEqual(SabotageMode.forRoundCount(7), .quick)
        XCTAssertEqual(SabotageMode.forRoundCount(3), .full, "an unrecognised count reads as the original game")
    }

    func test_slotForRound_followsTheModeAndFallsToTheXFactor() {
        XCTAssertEqual(SabotageRules.slot(forRound: 1, roundCount: 14), "QB")
        XCTAssertEqual(SabotageRules.slot(forRound: 7, roundCount: 14), "TE")
        XCTAssertEqual(SabotageRules.slot(forRound: 7, roundCount: 10), "FLEX")
        XCTAssertEqual(SabotageRules.slot(forRound: 6, roundCount: 7), "DEF")
        XCTAssertEqual(SabotageRules.slot(forRound: 7, roundCount: 7), "X_FACTOR")
        XCTAssertEqual(SabotageRules.slot(forRound: 99, roundCount: 7), "X_FACTOR")
    }

    func test_rosterSlots_dropTheXFactor() {
        XCTAssertEqual(SabotageRules.rosterSlots(roundCount: 7), ["QB", "RB1", "WR1", "TE", "FLEX", "DEF"])
    }

    func test_chooseLabel_saysWhatASlotMayTake() {
        XCTAssertEqual(SabotageRules.chooseLabel("WR2"), "a WR")
        XCTAssertEqual(SabotageRules.chooseLabel("FLEX"), "an RB, WR or TE")
        XCTAssertEqual(SabotageRules.chooseLabel("DEF"), "a defensive player")
        XCTAssertEqual(SabotageRules.chooseLabel("X_FACTOR"), "any offensive skill player")
    }

    func test_xFactorTargets_matchThePicksPositionAndTheMode() {
        XCTAssertEqual(SabotageRules.xFactorTargets(category: "WR", roundCount: 14), ["WR1", "WR2", "WR3"])
        XCTAssertEqual(SabotageRules.xFactorTargets(category: "RB", roundCount: 14), ["RB1", "RB2"])
        XCTAssertEqual(SabotageRules.xFactorTargets(category: "QB", roundCount: 7), ["QB"])
        // FLEX takes an RB, WR or TE, so it is a target for each.
        XCTAssertEqual(SabotageRules.xFactorTargets(category: "TE", roundCount: 7), ["TE", "FLEX"])
        XCTAssertEqual(SabotageRules.xFactorTargets(category: "RB", roundCount: 7), ["RB1", "FLEX"])
        XCTAssertEqual(SabotageRules.xFactorTargets(category: nil, roundCount: 14), [])
    }

    func test_franchiseName_fallsBackToTheCode() {
        XCTAssertEqual(SabotageRules.franchiseName("oti"), "Tennessee Titans")
        XCTAssertEqual(SabotageRules.franchiseName("zzz"), "zzz")
    }

    // MARK: - Grades

    func test_gradeForPick_isRelativeToThePositionsOwnScale() {
        XCTAssertEqual(SabotageRules.gradeForPick(slot: "QB", av: 20), "A+")
        XCTAssertEqual(SabotageRules.gradeForPick(slot: "QB", av: 2), "F")
        // 8 AV is elite for a special teamer and ordinary for a quarterback.
        XCTAssertEqual(SabotageRules.gradeForPick(slot: "ST", av: 8), "A+")
        XCTAssertEqual(SabotageRules.gradeForPick(slot: "QB", av: 8), "D+")
        // RB1 and RB2 share the RB scale.
        XCTAssertEqual(SabotageRules.gradeForPick(slot: "RB2", av: 18), "A+")
    }

    func test_gradeForPick_flexAndDefReadTheirOwnCategory() {
        XCTAssertEqual(SabotageRules.gradeForPick(slot: "FLEX", av: 12, pickCategory: "TE"), "A+")
        XCTAssertEqual(SabotageRules.gradeForPick(slot: "DEF", av: 5, pickCategory: "S"), "C")
    }

    func test_gradeForTeam_rescalesASmallerModeOntoTheFullScale() {
        // A roster sitting on its own mode's baseline grades like 93 does in full.
        let atBaseline = SabotageRules.gradeForTeam(rosterStrength: 93, mode: .full)
        XCTAssertEqual(SabotageRules.gradeForTeam(rosterStrength: 62, mode: .standard), atBaseline)
        XCTAssertEqual(SabotageRules.gradeForTeam(rosterStrength: 52, mode: .quick), atBaseline)
        XCTAssertEqual(SabotageRules.gradeForTeam(rosterStrength: 10, mode: .full), "F")
        XCTAssertEqual(SabotageRules.gradeForTeam(rosterStrength: 140, mode: .full), "A+")
    }

    // MARK: - Decoding

    func test_board_decodesTheStateProjection() throws {
        let board = try decode(SabotageBoard.self, """
        {"match_id":"11111111-1111-1111-1111-111111111111","round_count":10,"current_round":3,
         "slot":"RB2","turn_deadline":"2026-09-01T12:00:30Z","server_now":"2026-09-01T12:00:00Z",
         "x_factor_open":false,"active_user_id":"22222222-2222-2222-2222-222222222222"}
        """)
        XCTAssertEqual(board.currentRound, 3)
        XCTAssertEqual(board.slot, "RB2")
        XCTAssertEqual(board.mode, .standard)
        XCTAssertNotNil(board.turnDeadline)
        XCTAssertNotNil(board.activeUserId)
    }

    func test_board_toleratesTheNullsBetweenTurns() throws {
        let board = try decode(SabotageBoard.self, """
        {"match_id":"11111111-1111-1111-1111-111111111111","round_count":7,"current_round":7,
         "slot":"X_FACTOR","turn_deadline":null,"server_now":"2026-09-01T12:00:00Z",
         "x_factor_open":true,"active_user_id":null}
        """)
        XCTAssertNil(board.turnDeadline)
        XCTAssertNil(board.activeUserId)
        XCTAssertTrue(board.xFactorOpen)
    }

    func test_player_takesItsIdentityFromTheJoinedProfile() throws {
        let player = try decode(SabotagePlayer.self, """
        {"user_id":"11111111-1111-1111-1111-111111111111","seat":1,"absent":true,
         "profiles":{"display_name":"Maya","avatar_url":"https://example.com/m.png"}}
        """)
        XCTAssertEqual(player.name, "Maya")
        XCTAssertEqual(player.seat, 1)
        XCTAssertTrue(player.absent)
        XCTAssertEqual(player.avatarURL?.absoluteString, "https://example.com/m.png")

        let bare = try decode(SabotagePlayer.self, #"{"user_id":"11111111-1111-1111-1111-111111111111","seat":0}"#)
        XCTAssertEqual(bare.name, "Unknown player")
        XCTAssertFalse(bare.absent)
    }

    func test_pick_decodesWithAndWithoutAPortrait() throws {
        let pick = try decode(SabotagePick.self, """
        {"round_number":2,"user_id":"11111111-1111-1111-1111-111111111111","player_id":"x",
         "display_name":"Some Back","season":2014,"by_timeout":true,"headshot_url":null}
        """)
        XCTAssertEqual(pick.round, 2)
        XCTAssertEqual(pick.season, 2014)
        XCTAssertTrue(pick.byTimeout)
        XCTAssertNil(pick.headshotURL)
    }

    func test_guess_isExactOnlyWhenItNamesAYear() throws {
        let exact = try decode(SabotageGuess.self, """
        {"round_number":1,"user_id":"11111111-1111-1111-1111-111111111111",
         "target_user_id":"22222222-2222-2222-2222-222222222222","season":2019,"result":"sabotaged"}
        """)
        XCTAssertTrue(exact.isExact)
        XCTAssertEqual(exact.result, .sabotaged)

        let pending = try decode(SabotageGuess.self, """
        {"round_number":1,"user_id":"11111111-1111-1111-1111-111111111111",
         "target_user_id":"22222222-2222-2222-2222-222222222222","season":null,"result":null}
        """)
        XCTAssertFalse(pending.isExact)
        XCTAssertNil(pending.result, "a guess is pending until the whole turn is complete")
    }

    func test_tiebreak_decodesAByeAsNoSecondPlayer() throws {
        let game = try decode(SabotageTiebreak.self, """
        {"record_wins":11,"bracket_round":1,"game_number":2,"player_a":"11111111-1111-1111-1111-111111111111",
         "player_b":null,"winner_user_id":"11111111-1111-1111-1111-111111111111",
         "player_a_score":null,"player_b_score":null}
        """)
        XCTAssertNil(game.playerB)
        XCTAssertNil(game.playerAScore)
    }

    func test_option_decodesThePoolRow() throws {
        let option = try decode(SabotageOption.self, """
        {"player_id":"p1","display_name":"Pat Passer","season":2012,"slot_category":"QB","headshot_url":"https://example.com/p.png"}
        """)
        XCTAssertEqual(option.id, "p1-2012")
        XCTAssertEqual(option.category, "QB")
        XCTAssertNotNil(option.headshotURL)
    }

    // MARK: - Pool grouping

    func test_tenured_groupsASeasonsPerPlayerMostTenuredFirst() {
        let options = [
            SabotageOption(playerId: "a", name: "A", season: 2010),
            SabotageOption(playerId: "b", name: "B", season: 2019),
            SabotageOption(playerId: "b", name: "B", season: 2021),
            SabotageOption(playerId: "b", name: "B", season: 2020),
            SabotageOption(playerId: "c", name: "C", season: 2022),
        ]
        let grouped = SabotageTenured.group(options)

        XCTAssertEqual(grouped.map(\.playerId), ["b", "c", "a"], "most seasons first, then most recent")
        XCTAssertEqual(grouped.first?.seasons, [2021, 2020, 2019], "newest first")
        XCTAssertEqual(grouped.first?.span, "2019–2021")
        XCTAssertEqual(grouped.last?.span, "2010")
    }

    func test_tenured_keepsTheFirstRealPortrait() {
        let url = URL(string: "https://example.com/p.png")!
        let grouped = SabotageTenured.group([
            SabotageOption(playerId: "a", name: "A", season: 2020),
            SabotageOption(playerId: "a", name: "A", season: 2019, headshotURL: url),
        ])
        XCTAssertEqual(grouped.first?.headshotURL, url)
    }

    // MARK: - Errors

    func test_errors_mapKnownMessagesAndSurfaceUnknownOnesRaw() {
        XCTAssertEqual(SabotageServerError.describe(SabotageServerError(message: "turn_closed")), "This turn has closed.")
        XCTAssertEqual(SabotageServerError.describe(SabotageServerError(message: "something_new")), "something_new")
        XCTAssertEqual(
            SabotageServerError.describe(URLError(.notConnectedToInternet)),
            "Something went wrong. Check your connection and try again."
        )
    }
}
