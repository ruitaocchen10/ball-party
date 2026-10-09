import Foundation
@testable import BallParty
import XCTest

/// The Gamer and solo leaderboards' wire types and the copy built from them.
final class GamerLeaderboardModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testDecodesAGamerRow() throws {
        let row = try decode(GamerRow.self, """
        {"rank":1,"profile_id":"11111111-1111-1111-1111-111111111111","display_name":"Ava","avatar_url":null,
         "wins":12,"games_played":30,"is_me":false,"ranked_count":4,"username":"ava"}
        """)
        XCTAssertEqual(row.rank, 1)
        XCTAssertEqual(row.wins, 12)
        XCTAssertEqual(row.gamesPlayed, 30)
        XCTAssertEqual(row.username, "ava")
    }

    func testDecodesASoloRowWithADecimalScore() throws {
        let row = try decode(SoloRow.self, """
        {"rank":2,"profile_id":"22222222-2222-2222-2222-222222222222","display_name":"Ben","avatar_url":null,
         "best_score":80.5,"is_me":true,"ranked_count":2,"username":null}
        """)
        XCTAssertEqual(row.bestScore, 80.5)
        XCTAssertNil(row.username)
    }

    func testDecodesStandingsAndReadsAnUnknownStatusAsUnranked() throws {
        let gamer = try decode(GamerStanding.self, """
        {"status":"hidden","rank":null,"wins":0,"games_played":0,"ranked_count":3,"min_wins":1}
        """)
        XCTAssertEqual(gamer.status, .unranked)
        XCTAssertNil(gamer.rank)

        let solo = try decode(SoloStanding.self, """
        {"status":"ranked","rank":2,"best_score":null,"ranked_count":5}
        """)
        XCTAssertEqual(solo.status, .ranked)
        XCTAssertNil(solo.bestScore)
    }

    func testOnlySoloBoardsNameAGame() {
        XCTAssertEqual(LeaderboardBoard.higherOrLower.soloGame, .higherOrLower)
        XCTAssertEqual(LeaderboardBoard.qbSeasonBuilder.soloGame, .qbSeasonBuilder)
        XCTAssertNil(LeaderboardBoard.gamer.soloGame)
        XCTAssertNil(LeaderboardBoard.ballKnower.soloGame)
        XCTAssertEqual(SoloGame.qbSeasonBuilder.rawValue, "qb_season_builder")
        XCTAssertEqual(QbMode.hidden.rawValue, "hidden")
    }

    func testOnlyTheWinsBoardHasWindows() {
        XCTAssertEqual(LeaderboardBoard.allCases.filter(\.hasWindows), [.gamer])
    }

    func testScoresFormatByBoard() {
        XCTAssertEqual(BoardEntry.formatScore(1234, board: .higherOrLower), "1,234")
        XCTAssertEqual(BoardEntry.formatScore(91, board: .qbSeasonBuilder), "91.0")
        XCTAssertEqual(BoardEntry.formatScore(80.5, board: .qbSeasonBuilder), "80.5")
    }

    func testAGamerRowBecomesAnEntry() {
        let entry = BoardEntry(GamerRow(rank: 3, displayName: "Cy", wins: 1, gamesPlayed: 1, rankedCount: 3, username: "cy"))
        XCTAssertEqual(entry.value, "1")
        XCTAssertEqual(entry.detail, "1 game")
        XCTAssertEqual(entry.profileUsername, "cy")
        XCTAssertTrue(entry.spoken.contains("1 win"))
    }

    func testYourOwnRowNeverLinksToAProfile() {
        let entry = BoardEntry(SoloRow(rank: 1, displayName: "Me", bestScore: 7, isMe: true, rankedCount: 1, username: "me"), board: .higherOrLower)
        XCTAssertNil(entry.profileUsername)
        XCTAssertNil(entry.detail)
        XCTAssertEqual(entry.value, "7")
    }

    func testStandingCopyBandsOnTheEveryoneBoardAndCountsAmongFriends() {
        let standing = GamerStanding(status: .ranked, rank: 2, wins: 5, gamesPlayed: 9, rankedCount: 10)
        XCTAssertEqual(BoardStanding(standing, scope: .all).detail, "Top 20% of 10 ranked players")
        XCTAssertEqual(BoardStanding(standing, scope: .friends).detail, "Ranked 2 of 10 on your friends board")
        XCTAssertEqual(BoardStanding(standing, scope: .all).headline, "#2")
    }

    func testAnUnrankedCallerGetsTheReasonAndKeepsTheirOwnNumbers() {
        let gamer = BoardStanding(GamerStanding(status: .unranked, wins: 0, gamesPlayed: 2, rankedCount: 4, minWins: 1), scope: .all)
        XCTAssertFalse(gamer.isRanked)
        XCTAssertEqual(gamer.headline, "Not ranked yet")
        XCTAssertEqual(gamer.floor, "1 multiplayer win")

        let solo = BoardStanding(SoloStanding(status: .unranked, rankedCount: 4), board: .qbSeasonBuilder, scope: .all)
        XCTAssertFalse(solo.isRanked)
        XCTAssertNil(solo.value)
    }
}
