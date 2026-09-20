import Foundation
import SwiftUI
@testable import BallParty
import XCTest

/// What a matchup cover is built from: the franchise tables (verbatim from the
/// web's `team-logos.ts`), the shared schedule row, and the rule for which
/// slots are drawn as a game at all.
final class MatchupTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Teams

    /// Every code the web's tables know. A code with a logo and no colour (or
    /// the reverse) would draw half a cover, so both tables are held to the
    /// same list.
    private let webTeamCodes = [
        "ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET", "GB",
        "HOU", "IND", "JAX", "KC", "LA", "LAR", "LAC", "LV", "MIA", "MIN", "NE", "NO",
        "NYG", "NYJ", "OAK", "PHI", "PIT", "SEA", "SF", "SD", "STL", "TB", "TEN", "WAS",
    ]

    func test_everyTeamTheWebKnowsHasALogoAndAColour() {
        for code in webTeamCodes {
            XCTAssertNotNil(NFLTeams.logoCode(for: code), "\(code) has no logo code")
            XCTAssertNotNil(NFLTeams.primaryColor(for: code), "\(code) has no colour")
        }
    }

    func test_logoCodesAreTheProFootballReferenceOnesTheBucketIsKeyedOn() {
        XCTAssertEqual(NFLTeams.logoCode(for: "KC"), "kan")
        XCTAssertEqual(NFLTeams.logoCode(for: "GB"), "gnb")
        XCTAssertEqual(NFLTeams.logoCode(for: "IND"), "clt")
        XCTAssertEqual(NFLTeams.logoCode(for: "TEN"), "oti")
    }

    func test_aHistoricCodeResolvesToItsCurrentFranchise() {
        XCTAssertEqual(NFLTeams.logoCode(for: "OAK"), NFLTeams.logoCode(for: "LV"))
        XCTAssertEqual(NFLTeams.logoCode(for: "STL"), NFLTeams.logoCode(for: "LA"))
        XCTAssertEqual(NFLTeams.logoCode(for: "SD"), NFLTeams.logoCode(for: "LAC"))
    }

    func test_teamLookupIgnoresCaseAndRefusesAnUnknownCode() {
        XCTAssertEqual(NFLTeams.logoCode(for: "kc"), "kan")
        XCTAssertNil(NFLTeams.logoCode(for: "XYZ"))
        XCTAssertNil(NFLTeams.primaryColor(for: "XYZ"))
    }

    func test_primaryColourIsTheFranchisesHex() {
        XCTAssertEqual(NFLTeams.primaryColor(for: "KC"), Color(hex: 0xE31837))
        XCTAssertEqual(NFLTeams.primaryColor(for: "BUF"), Color(hex: 0x00338D))
    }

    func test_logoURLIsThePublicBucketPathTheWebBuilds() {
        let base = URL(string: "http://127.0.0.1:55321")!

        XCTAssertEqual(
            NFLTeams.logoURL(for: "KC", storageBase: base)?.absoluteString,
            "http://127.0.0.1:55321/storage/v1/object/public/team-logos/kan.png"
        )
    }

    func test_noLogoURLWithoutAProjectURLOrForAnUnknownTeam() {
        XCTAssertNil(NFLTeams.logoURL(for: "KC", storageBase: nil))
        XCTAssertNil(NFLTeams.logoURL(for: "XYZ", storageBase: URL(string: "http://127.0.0.1:55321")))
    }

    // MARK: - Wording

    func test_kickoffReadsInEasternTimeWhateverTheDeviceZoneIs() {
        // 2026-09-11 00:20 UTC is Thursday 8:20 PM in New York (EDT, UTC-4).
        let thursdayNight = Date(timeIntervalSince1970: 1_789_086_000)

        XCTAssertEqual(MatchupText.kickoff(thursdayNight), "Thu 8:20 PM EDT")
    }

    func test_kickoffNamesStandardTimeAfterTheClocksChange() {
        // 2026-12-07 01:20 UTC is Sunday 8:20 PM in New York (EST, UTC-5).
        let sundayNight = Date(timeIntervalSince1970: 1_796_606_400)

        XCTAssertEqual(MatchupText.kickoff(sundayNight), "Sun 8:20 PM EST")
    }

    func test_aMissingKickoffAndVenueSayTheyAreToBeDetermined() {
        XCTAssertEqual(MatchupText.kickoff(nil), "Game time TBD")
        XCTAssertEqual(MatchupText.venue(nil), "Venue TBD")
        XCTAssertEqual(MatchupText.venue(NFLGame(id: "g", stadium: "", kickoff: Date())), "Venue TBD")
        XCTAssertEqual(MatchupText.venue(NFLGame(id: "g", stadium: "Highmark Stadium", kickoff: Date())), "Highmark Stadium")
    }

    // MARK: - The schedule row

    func test_gameDecodesARowAsPostgRESTPrintsIt() throws {
        let game = try decode(NFLGame.self, """
        {"id": "2026_01_SF_LA", "stadium": "Melbourne Cricket Ground",
         "kickoff": "2026-09-11T00:35:00+00:00", "primetime": true}
        """)

        XCTAssertEqual(game.id, "2026_01_SF_LA")
        XCTAssertEqual(game.stadium, "Melbourne Cricket Ground")
        XCTAssertTrue(game.primetime)
        XCTAssertEqual(game.kickoff.timeIntervalSince1970, 1_789_086_900, accuracy: 0.001)
    }

    func test_slotRowKeepsItsGameIdAndToleratesNone() throws {
        let game = try decode(PromptSlotRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Chiefs @ Bills", "shape": "pick", "pick_count": null, "points": 10, "sort_order": 0,
         "correct_option_ids": null, "source_game_id": "2026_02_KC_BUF"}
        """)
        let other = try decode(PromptSlotRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Top three", "shape": "rank", "pick_count": 3, "points": 10, "sort_order": 0,
         "correct_option_ids": null, "source_game_id": null}
        """)

        XCTAssertEqual(game.sourceGameId, "2026_02_KC_BUF")
        XCTAssertNil(other.sourceGameId)
    }

    // MARK: - Feed assembly

    private let viewer = UUID()

    /// One post with one slot of two team options, optionally pointing at a game.
    private func rows(sourceGameId: String?, games: [NFLGame]) -> PromptFeedRows {
        let post = UUID(), slot = UUID()
        var rows = PromptFeedRows()
        rows.posts = [PromptPostRow(
            id: post, authorId: viewer, promptText: "Who wins?",
            lockAt: Date(timeIntervalSince1970: 1_789_000_000), createdAt: Date(timeIntervalSince1970: 1_788_000_000)
        )]
        rows.slots = [PromptSlotRow(id: slot, postId: post, label: "Chiefs @ Bills", sourceGameId: sourceGameId)]
        rows.options = [
            PromptOptionRow(id: UUID(), slotId: slot, label: "Chiefs", teamCode: "KC", sortOrder: 0),
            PromptOptionRow(id: UUID(), slotId: slot, label: "Bills", teamCode: "BUF", sortOrder: 1),
        ]
        rows.games = games
        return rows
    }

    func test_aSlotIsGivenTheGameItsSourceIdNames() {
        let game = NFLGame(id: "2026_02_KC_BUF", stadium: "Highmark Stadium", kickoff: Date(timeIntervalSince1970: 1_789_100_000), primetime: true)
        let other = NFLGame(id: "2026_02_DET_BUF", kickoff: Date(timeIntervalSince1970: 1_789_200_000))

        let posts = PromptFeed.assemble(rows: rows(sourceGameId: "2026_02_KC_BUF", games: [other, game]), viewerId: viewer)

        XCTAssertEqual(posts.first?.slots.first?.game, game)
    }

    func test_aSlotWhoseGameTheScheduleLacksStillShowsWithoutOne() {
        let elsewhere = NFLGame(id: "2026_02_DET_BUF", kickoff: Date())

        let unknown = PromptFeed.assemble(rows: rows(sourceGameId: "2026_02_KC_BUF", games: [elsewhere]), viewerId: viewer)
        let unlinked = PromptFeed.assemble(rows: rows(sourceGameId: nil, games: [elsewhere]), viewerId: viewer)
        let outage = PromptFeed.assemble(rows: rows(sourceGameId: "2026_02_KC_BUF", games: []), viewerId: viewer)

        for posts in [unknown, unlinked, outage] {
            XCTAssertEqual(posts.count, 1, "the post stays on the feed")
            XCTAssertNil(posts.first?.slots.first?.game)
            XCTAssertNotNil(posts.first?.slots.first?.matchup, "and is still drawn as a game")
        }
    }

    // MARK: - Which slots are a game

    private func slot(shape: SlotShape, options: [PromptOption]) -> PromptSlot {
        PromptSlot(
            id: UUID(), label: "Slot", shape: shape, pickCount: nil, points: 10,
            correctOptionIds: nil, options: options
        )
    }

    private func team(_ label: String, _ code: String?, headshot: URL? = nil) -> PromptOption {
        PromptOption(id: UUID(), label: label, sublabel: nil, teamCode: code, headshotURL: headshot)
    }

    func test_aPickBetweenTwoTeamsIsAMatchupAwayFirst() {
        let chiefs = team("Chiefs", "KC"), bills = team("Bills", "BUF")

        let matchup = slot(shape: .pick, options: [chiefs, bills]).matchup

        XCTAssertEqual(matchup?.away, chiefs)
        XCTAssertEqual(matchup?.home, bills)
    }

    func test_nothingElseIsDrawnAsAMatchup() {
        let chiefs = team("Chiefs", "KC"), bills = team("Bills", "BUF"), jets = team("Jets", "NYJ")
        let player = URL(string: "https://example.test/mahomes.png")!

        XCTAssertNil(slot(shape: .rank, options: [chiefs, bills]).matchup, "a ranking")
        XCTAssertNil(slot(shape: .pickSet, options: [chiefs, bills]).matchup, "a pick of several")
        XCTAssertNil(slot(shape: .pick, options: [chiefs, bills, jets]).matchup, "three candidates")
        XCTAssertNil(slot(shape: .pick, options: [chiefs]).matchup, "one candidate")
        XCTAssertNil(slot(shape: .pick, options: [chiefs, team("Mahomes", "KC", headshot: player)]).matchup, "a player")
        XCTAssertNil(slot(shape: .pick, options: [chiefs, team("Draw", nil)]).matchup, "an option that isn't a team")
    }

    func test_aPostIsAMatchupPostOnlyWhenEverySlotIs() {
        let game = slot(shape: .pick, options: [team("Chiefs", "KC"), team("Bills", "BUF")])
        let ranking = slot(shape: .rank, options: [team("Chiefs", "KC"), team("Bills", "BUF")])

        func post(_ slots: [PromptSlot]) -> PromptPost {
            PromptPost(
                id: UUID(), templateKind: "picks", templateName: "Picks", author: "A", caption: "",
                createdAt: Date(), promptText: "Q", resolutionCriteria: "", lockAt: Date(), status: .open,
                voidReason: nil, isOpinion: false, slots: slots, comments: [], responseCount: 0,
                viewerResponse: nil, viewerPointsAwarded: nil, aggregate: nil
            )
        }

        XCTAssertTrue(post([game, game]).isMatchupPost)
        XCTAssertFalse(post([game, ranking]).isMatchupPost)
        XCTAssertFalse(post([]).isMatchupPost, "a post with no slots has nothing to draw")
    }

    func test_theWinnerIsTheFirstCorrectOptionOnceGradedAndNilBefore() {
        let chiefs = team("Chiefs", "KC"), bills = team("Bills", "BUF")
        let open = slot(shape: .pick, options: [chiefs, bills])
        let graded = PromptSlot(
            id: UUID(), label: "Slot", shape: .pick, pickCount: nil, points: 10,
            correctOptionIds: [bills.id], options: [chiefs, bills]
        )

        XCTAssertNil(open.winnerId)
        XCTAssertEqual(graded.winnerId, bills.id)
    }
}
