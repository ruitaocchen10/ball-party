import Foundation
@testable import BallParty
import XCTest

/// The leaderboard's wire shapes and the copy derived from them — decoded from
/// the JSON PostgREST prints, the way `PromptModelsTests` does for the Huddle.
final class LeaderboardModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testRowDecodesFromTheRpcShape() throws {
        let row = try decode(LeaderboardRow.self, """
        {"rank":2,"profile_id":"00000000-0000-0000-0000-000000000001","display_name":"Bravo",
         "avatar_url":"https://example.com/b.png","total_points":30,"scored_picks":4,"is_me":true,"ranked_count":20}
        """)
        XCTAssertEqual(row.rank, 2)
        XCTAssertEqual(row.displayName, "Bravo")
        XCTAssertEqual(row.avatarURL, URL(string: "https://example.com/b.png"))
        XCTAssertEqual(row.totalPoints, 30)
        XCTAssertEqual(row.scoredPicks, 4)
        XCTAssertTrue(row.isMe)
        XCTAssertEqual(row.rankedCount, 20)
    }

    func testRowWithoutAnAvatarHasNoURL() throws {
        let row = try decode(LeaderboardRow.self, """
        {"rank":1,"profile_id":"00000000-0000-0000-0000-000000000001","display_name":"Alpha",
         "avatar_url":null,"total_points":60,"scored_picks":3,"is_me":false,"ranked_count":1}
        """)
        XCTAssertNil(row.avatarURL)
    }

    func testStandingDecodesAnUnknownStatusAsUnranked() throws {
        let standing = try decode(LeaderboardStanding.self, """
        {"status":"suspended","rank":null,"total_points":0,"scored_picks":0,"ranked_count":9,"min_picks":3}
        """)
        XCTAssertEqual(standing.status, .unranked)
        XCTAssertNil(standing.rank)
    }

    func testTopPercentRoundsUpAndIsNilWithoutARank() {
        XCTAssertEqual(LeaderboardStanding(status: .ranked, rank: 1, rankedCount: 1000).topPercent, 1)
        XCTAssertEqual(LeaderboardStanding(status: .ranked, rank: 211, rankedCount: 1316).topPercent, 17)
        XCTAssertEqual(LeaderboardStanding(status: .ranked, rank: 1316, rankedCount: 1316).topPercent, 100)
        XCTAssertNil(LeaderboardStanding(status: .unranked, rankedCount: 10).topPercent)
        XCTAssertNil(LeaderboardStanding(status: .ranked, rank: 1, rankedCount: 0).topPercent)
    }

    func testRankedCopyNamesTheRankAndBand() {
        let copy = LeaderboardStanding(status: .ranked, rank: 2, totalPoints: 30, scoredPicks: 4, rankedCount: 20).copy
        XCTAssertEqual(copy.headline, "#2")
        XCTAssertEqual(copy.detail, "Top 10% of 20 ranked players")
    }

    func testUnrankedCopySaysHowManyPicksAreMissing() {
        XCTAssertEqual(
            LeaderboardStanding(status: .unranked, scoredPicks: 1).copy.detail,
            "2 more scored picks to join the board"
        )
        XCTAssertEqual(
            LeaderboardStanding(status: .unranked, scoredPicks: 2).copy.detail,
            "1 more scored pick to join the board"
        )
    }

    func testEveryProfileRangeMapsToTheMatchingWindow() {
        XCTAssertEqual(LeaderboardWindow(.week), .week)
        XCTAssertEqual(LeaderboardWindow(.month), .month)
        XCTAssertEqual(LeaderboardWindow(.year), .year)
        XCTAssertEqual(LeaderboardWindow(.lifetime), .lifetime)
    }

    func testWindowRawValuesAreWhatTheRpcAccepts() {
        XCTAssertEqual(LeaderboardWindow.allCases.map(\.rawValue), ["week", "month", "year", "lifetime"])
    }

    func testFriendsCopyNamesTheRankOutOfTheFriendsBoard() {
        let copy = LeaderboardStanding(status: .ranked, rank: 2, totalPoints: 30, scoredPicks: 4, rankedCount: 5)
            .copy(for: .friends)
        XCTAssertEqual(copy.headline, "#2")
        XCTAssertEqual(copy.detail, "Ranked 2 of 5 on your friends board")
    }

    func testUnrankedCopyIsTheSameInEveryScope() {
        let standing = LeaderboardStanding(status: .unranked, scoredPicks: 1)
        XCTAssertEqual(standing.copy(for: .friends).detail, standing.copy(for: .all).detail)
    }

    func testScopeRawValuesAreWhatTheRpcAccepts() {
        XCTAssertEqual(LeaderboardScope.allCases.map(\.rawValue), ["all", "friends"])
    }

    func testRowUsernameIsOptionalAndLinksOnlyOthers() throws {
        let without = try decode(LeaderboardRow.self, """
        {"rank":1,"profile_id":"00000000-0000-0000-0000-000000000001","display_name":"A",
         "avatar_url":null,"total_points":6,"scored_picks":3,"is_me":false,"ranked_count":1}
        """)
        XCTAssertNil(without.username)
        XCTAssertNil(without.profileUsername)

        let nulled = try decode(LeaderboardRow.self, """
        {"rank":1,"profile_id":"00000000-0000-0000-0000-000000000001","display_name":"A","username":null,
         "avatar_url":null,"total_points":6,"scored_picks":3,"is_me":false,"ranked_count":1}
        """)
        XCTAssertNil(nulled.profileUsername)

        let other = try decode(LeaderboardRow.self, """
        {"rank":1,"profile_id":"00000000-0000-0000-0000-000000000001","display_name":"A","username":"a_a",
         "avatar_url":null,"total_points":6,"scored_picks":3,"is_me":false,"ranked_count":1}
        """)
        XCTAssertEqual(other.profileUsername, "a_a")

        let me = LeaderboardRow(rank: 1, displayName: "Me", totalPoints: 1, scoredPicks: 3, isMe: true, rankedCount: 1, username: "me_me")
        XCTAssertNil(me.profileUsername)
    }
}
