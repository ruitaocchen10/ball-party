import Foundation
@testable import BallParty
import XCTest

/// The wire shapes in `docs/games/qb_season_builder.md`, decoded the way the
/// Supabase client would hand them over.
final class QbSeasonBuilderModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private let matchId = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"

    func test_aVisibleBoard_carriesEveryGradeOnTheSpin() throws {
        let board = try decode(QbBoard.self, """
        {"match_id":"\(matchId)","mode":"visible","phase":"picking","round_count":6,"current_round":2,
         "respin_used":false,"franchise_code":"kan","season":2018,
         "options":{"quarterbacks":[{"player_id":"MahoPa00","display_name":"Patrick Mahomes",
                    "headshot_url":"https://example.com/m.png",
                    "grades":{"accuracy":"A","arm_talent":"A+","mobility":"B+","iq":"A","build":"B"}}],
                    "supporting_cast":{"grade":"A-"}},
         "picks":[{"round":1,"slot":"iq","franchise_code":"nwe","season":2010,"player_id":"BradTo00",
                   "display_name":"Tom Brady","grade":"A+"}],
         "shown":null}
        """)

        XCTAssertEqual(board.phase, .picking)
        XCTAssertEqual(board.currentRound, 2)
        XCTAssertEqual(board.deal?.franchiseCode, "kan")
        XCTAssertEqual(board.deal?.season, 2018)
        XCTAssertEqual(board.deal?.spin.supportingCastGrade, .aMinus)
        let quarterback = try XCTUnwrap(board.deal?.spin.quarterbacks.first)
        XCTAssertEqual(quarterback.displayName, "Patrick Mahomes")
        XCTAssertEqual(quarterback.headshotURL, URL(string: "https://example.com/m.png"))
        XCTAssertEqual(quarterback.grades?[.armTalent], .aPlus)
        XCTAssertEqual(board.pick(for: .iq)?.grade, .aPlus)
        XCTAssertTrue(board.isTaken(.iq))
        XCTAssertFalse(board.isTaken(.accuracy))
        XCTAssertNil(board.shown)
    }

    func test_aHiddenBoard_hasNoGradesAnywhere() throws {
        let board = try decode(QbBoard.self, """
        {"match_id":"\(matchId)","mode":"hidden","phase":"picking","round_count":6,"current_round":1,
         "respin_used":false,"franchise_code":"crd","season":2015,
         "options":{"quarterbacks":[{"player_id":"PalmCa00","display_name":"Carson Palmer","grades":null}],
                    "supporting_cast":{"grade":null}},
         "picks":[],"shown":null}
        """)

        let spin = try XCTUnwrap(board.deal?.spin)
        XCTAssertNil(spin.quarterbacks[0].grades)
        XCTAssertNil(spin.quarterbacks[0].headshotURL)
        XCTAssertNil(spin.supportingCastGrade)
    }

    func test_aBoardWithNoOpenRound_hasNoSpin() throws {
        let board = try decode(QbBoard.self, """
        {"match_id":"\(matchId)","mode":"visible","phase":"ready_to_finish","round_count":6,"current_round":6,
         "respin_used":true,"franchise_code":null,"season":null,"options":null,"picks":[],"shown":null}
        """)

        XCTAssertEqual(board.phase, .readyToFinish)
        XCTAssertNil(board.deal)
    }

    func test_aFinishedBoard_carriesEverySpinThePlayerSaw() throws {
        let board = try decode(QbBoard.self, """
        {"match_id":"\(matchId)","mode":"hidden","phase":"complete","round_count":6,"current_round":6,
         "respin_used":true,"franchise_code":null,"season":null,"options":null,"picks":[],
         "shown":[{"round":1,"attempt":1,"franchise_code":"oti","season":2011,
                   "options":{"quarterbacks":[{"player_id":"HassMa00","display_name":"Matt Hasselbeck",
                              "grades":{"accuracy":"B","arm_talent":"B","mobility":"C-","iq":"B+","build":"C+"}}],
                              "supporting_cast":{"grade":"C"}}}]}
        """)

        let shown = try XCTUnwrap(board.shown?.first)
        XCTAssertEqual(shown.round, 1)
        XCTAssertEqual(shown.attempt, 1)
        XCTAssertEqual(shown.spin.quarterbacks.first?.grades?[.iq], .bPlus)
        XCTAssertEqual(shown.spin.supportingCastGrade, .c)
    }

    func test_aSavedSeason_decodesEverySection() throws {
        let result = try decode(QbSeasonResult.self, """
        {"match_id":"\(matchId)","mode":"hidden",
         "stat_line":{"attempts":580,"completions":390,"pass_yards":4321,"pass_tds":33,"interceptions":9,
                      "rating":101.2,"rush_yards":210,"rush_tds":2},
         "record":{"wins":13,"losses":4},
         "playoffs":{"depth":3,"result":"lost_conference"},
         "awards":{"mvp":false,"opoy":false,"all_pro":true,"pro_bowl":true,"sb_mvp":false},
         "score":78.4,
         "breakdown":[{"component":"stat_line","weight":55,"percentile":0.82,"points":41.3},
                      {"component":"team_success","weight":30,"percentile":0.75,"points":22.1},
                      {"component":"awards","weight":15,"percentile":0.7,"points":15}],
         "picks":[]}
        """)

        XCTAssertEqual(result.statLine.passYards, 4321)
        XCTAssertEqual(result.statLine.rating, 101.2)
        XCTAssertEqual(result.record.wins, 13)
        XCTAssertEqual(result.playoffs.result, .lostConference)
        XCTAssertEqual(result.awards, [.allPro, .proBowl], "in the order the web lists them")
        XCTAssertEqual(result.score, 78.4)
        XCTAssertEqual(result.breakdown.map(\.label), ["Stat line", "Team success", "Awards"])
        XCTAssertEqual(result.weightPercent(of: result.breakdown[0]), 55)
    }

    func test_pointsShowAsWholeNumbersWhenTheyAreOne() {
        XCTAssertEqual(QbPoints.format(88), "88")
        XCTAssertEqual(QbPoints.format(87.5), "87.5")
    }

    func test_anUnknownGrade_decodesAsAbsentRatherThanFailingTheBoard() throws {
        let spin = try decode(QbSpin.self, """
        {"quarterbacks":[{"player_id":"MahoPa00","display_name":"Patrick Mahomes",
                          "grades":{"accuracy":"A","arm_talent":"A+","mobility":"B+","iq":"A","build":"Z"}}],
         "supporting_cast":{"grade":"Q"}}
        """)

        XCTAssertNil(spin.quarterbacks[0].grades, "all five or none: a run never shows half a quarterback")
        XCTAssertNil(spin.supportingCastGrade)
    }

    func test_gradesReadAloudWithPlusAndMinusSpelledOut() {
        XCTAssertEqual(QbGrade.aMinus.spoken, "A minus")
        XCTAssertEqual(QbGrade.bPlus.spoken, "B plus")
        XCTAssertEqual(QbGrade.c.spoken, "C")
    }

    func test_franchiseNamesReadAsTheTeamAndFallBackToTheCode() {
        XCTAssertEqual(QbFranchises.name(for: "oti"), "Tennessee Titans")
        XCTAssertEqual(QbFranchises.name(for: "zzz"), "zzz")
    }
}
