import Foundation
@testable import BallParty
import XCTest

/// The activity feed's wire shape, its sentences, and its paging.
@MainActor
final class FriendActivityTests: XCTestCase {
    private struct Offline: Error {}

    private func decodePage(_ json: String) throws -> [FriendActivityEvent] {
        try JSONDecoder().decode(FriendActivityPage.self, from: Data(json.utf8)).events
    }

    private let actor = """
    "actor_id":"00000000-0000-0000-0000-0000000000A1","username":"sam_k","display_name":"Sam","avatar_url":null
    """

    private func row(_ type: String, _ time: String, _ extra: String) -> String {
        "{\"event_type\":\"\(type)\",\"occurred_at\":\"\(time)\",\(actor),\(extra)}"
    }

    private let blanks = """
    "post_id":null,"post_caption":null,"take_body":null,"comment_id":null,"reply_count":0,"response":null,"points":null,"match_id":null,"game":null,"placement":null,"raw_score":null,"run_mode":null,"mode":null
    """

    private func fields(_ overrides: [String: String]) -> String {
        var base: [String: String] = [
            "post_id": "null", "post_caption": "null", "take_body": "null", "comment_id": "null", "reply_count": "0", "response": "null", "opponents": "null", "opponent_you": "false", "opponent_count": "0", "friend_rank": "null", "friend_count": "null", "points": "null",
            "match_id": "null", "game": "null", "placement": "null", "raw_score": "null", "run_mode": "null", "mode": "null",
        ]
        for (key, value) in overrides { base[key] = value }
        return base.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
    }

    func testPromptAnswersAreNoLongerEventsHere() throws {
        // Answers moved onto the prompt's own card (friends_who_answered); an older server's rows are skipped, not fatal.
        let json = "[" + row("take", "2026-10-01T12:00:00+00:00", blanks) + ","
            + row("pick_made", "2026-10-01T11:00:00+00:00", blanks) + ","
            + row("win", "2026-10-01T10:00:00+00:00", fields(["match_id": "\"00000000-0000-0000-0000-0000000000C1\"", "game": "\"higher_or_lower\""])) + "]"
        let events = try decodePage(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].actor.username, "sam_k")
    }

    func testAWinReadsGameAndScore() throws {
        let events = try decodePage("[" + row("win", "2026-10-01T12:00:00+00:00", fields([
            "match_id": "\"00000000-0000-0000-0000-0000000000C1\"", "game": "\"higher_or_lower\"",
            "placement": "1", "raw_score": "\"1450.5\"", "run_mode": "\"party\"",
        ])) + "]")
        XCTAssertEqual(events[0].summary, "won Higher or Lower · score 1,450.5")
    }

    func testAWinCarriesWhoItWasOver() throws {
        let events = try decodePage("[" + row("win", "2026-10-01T12:00:00+00:00", fields([
            "match_id": "\"00000000-0000-0000-0000-0000000000C1\"", "game": "\"higher_or_lower\"",
            "opponents": "[\"Ava\"]", "opponent_you": "true", "opponent_count": "3",
        ])) + "]")
        guard case .win(_, _, _, let opponents, let you, let count) = events[0].kind else { return XCTFail("expected a win") }
        XCTAssertEqual(opponents, ["Ava"])
        XCTAssertTrue(you)
        XCTAssertEqual(count, 3)
        XCTAssertEqual(FriendActivityEvent.beatLine(opponents: opponents, you: you, count: count), "you, Ava and 1 other")
        XCTAssertEqual(FriendActivityEvent.beatLine(opponents: [], you: true, count: 1), "you")
        XCTAssertEqual(FriendActivityEvent.beatLine(opponents: [], you: false, count: 2), "2 players")
        XCTAssertNil(FriendActivityEvent.beatLine(opponents: [], you: false, count: 0))
    }

    func testAHighScoreCarriesItsRankAmongFriends() throws {
        let events = try decodePage("[" + row("high_score", "2026-10-01T12:00:00+00:00", fields([
            "game": "\"higher_or_lower\"", "raw_score": "14", "friend_rank": "2", "friend_count": "5",
        ])) + "]")
        guard case .highScore(_, _, _, let rank, let count) = events[0].kind else { return XCTFail("expected a high score") }
        XCTAssertEqual(rank, 2)
        XCTAssertEqual(count, 5)
    }

    func testBackToBackWinsByOneFriendOnADayFoldTogether() throws {
        func win(_ id: String, _ time: String) throws -> FriendActivityEvent {
            try decodePage("[" + row("win", time, fields(["match_id": "\"00000000-0000-0000-0000-0000000000\(id)\"", "game": "\"higher_or_lower\""])) + "]")[0]
        }
        let items = FriendActivityItem.grouped([
            try win("C1", "2026-10-01T12:00:00+00:00"),
            try win("C2", "2026-10-01T09:00:00+00:00"),
            try win("C3", "2026-09-30T09:00:00+00:00"),
        ])
        XCTAssertEqual(items.map(\.more.count), [1, 0])
    }

    func testAHighScoreReadsTheGameAndBoard() throws {
        let hol = try decodePage("[" + row("high_score", "2026-10-01T12:00:00+00:00", fields(["game": "\"higher_or_lower\"", "raw_score": "14"])) + "]")
        XCTAssertEqual(hol[0].summary, "set a new high score in Higher or Lower: 14 in a row")
        let qb = try decodePage("[" + row("high_score", "2026-10-01T12:00:00+00:00", fields(["game": "\"qb_season_builder\"", "raw_score": "\"88.5\"", "mode": "\"hidden\""])) + "]")
        XCTAssertEqual(qb[0].summary, "set a new high score in QB Season Builder (hidden): 88.5")
    }

    func testAnUnknownEventTypeIsSkippedNotFatal() throws {
        let json = "[" + row("brand_new", "2026-10-01T12:00:00+00:00", blanks) + ","
            + row("win", "2026-10-01T11:00:00+00:00", fields(["match_id": "\"00000000-0000-0000-0000-0000000000C1\"", "game": "\"higher_or_lower\""])) + "]"
        let events = try decodePage(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].summary, "won Higher or Lower")
    }

    // MARK: Paging

    private final class StubClient: FriendActivityClient, @unchecked Sendable {
        var pages: [[FriendActivityEvent]] = []
        var failing = false
        var answerRows: [FriendAnswerer] = []
        private(set) var befores: [String?] = []
        private(set) var limits: [Int] = []

        func activity(limit: Int, before: String?) async throws -> [FriendActivityEvent] {
            befores.append(before)
            limits.append(limit)
            if failing { throw Offline() }
            return pages.isEmpty ? [] : pages.removeFirst()
        }

        func answerers(postIds: [UUID]) async throws -> [FriendAnswerer] {
            if failing { throw Offline() }
            return answerRows.filter { postIds.contains($0.postId) }
        }
    }

    private let samIdentity = PlayerIdentity.fixture()

    private func event(_ n: Int) -> FriendActivityEvent {
        FriendActivityEvent(
            kind: .win(matchId: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, game: "higher_or_lower", score: nil, opponents: [], opponentYou: false, opponentCount: 0),
            occurredAt: Date(timeIntervalSince1970: Double(10_000 - n)),
            occurredAtRaw: "raw-\(n)",
            actor: samIdentity
        )
    }

    func testLoadFillsTheFeedAndKnowsWhetherMoreRemains() async {
        let client = StubClient()
        client.pages = [[event(1), event(2)]]
        let viewModel = FriendActivityViewModel(client: client, pageSize: 2)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.events.count, 2)
        XCTAssertTrue(viewModel.hasMore)
        XCTAssertEqual(client.befores, [nil])
        XCTAssertEqual(client.limits, [2])
    }

    func testAShortFirstPageMeansNoMore() async {
        let client = StubClient()
        client.pages = [[event(1)]]
        let viewModel = FriendActivityViewModel(client: client, pageSize: 2)
        await viewModel.load()
        XCTAssertFalse(viewModel.hasMore)

        await viewModel.loadMore()
        XCTAssertEqual(client.befores.count, 1)
    }

    func testLoadMorePagesFromTheOldestEventsRawTime() async {
        let client = StubClient()
        client.pages = [[event(1), event(2)], [event(3)]]
        let viewModel = FriendActivityViewModel(client: client, pageSize: 2)
        await viewModel.load()

        await viewModel.loadMore()

        XCTAssertEqual(client.befores, [nil, "raw-2"])
        XCTAssertEqual(viewModel.events.map(\.id), [event(1), event(2), event(3)].map(\.id))
        XCTAssertFalse(viewModel.hasMore)
    }

    func testLoadMoreDropsEventsItAlreadyHas() async {
        let client = StubClient()
        client.pages = [[event(1), event(2)], [event(2), event(3)]]
        let viewModel = FriendActivityViewModel(client: client, pageSize: 2)
        await viewModel.load()

        await viewModel.loadMore()

        XCTAssertEqual(viewModel.events.count, 3)
    }

    func testAFailedFirstLoadIsFailedAndAFailedRefreshKeepsEvents() async {
        let client = StubClient()
        client.failing = true
        let viewModel = FriendActivityViewModel(client: client, pageSize: 2)
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .failed)

        client.failing = false
        client.pages = [[event(1)]]
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .loaded)

        client.failing = true
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.events.count, 1)
    }

    func testAFailedLoadMoreKeepsEventsAndFlagsTheFailure() async {
        let client = StubClient()
        client.pages = [[event(1), event(2)]]
        let viewModel = FriendActivityViewModel(client: client, pageSize: 2)
        await viewModel.load()
        client.failing = true

        await viewModel.loadMore()

        XCTAssertTrue(viewModel.loadMoreFailed)
        XCTAssertEqual(viewModel.events.count, 2)
        XCTAssertTrue(viewModel.hasMore)
    }

    func testAnEmptyFeedLoadsAsEmpty() async {
        let viewModel = FriendActivityViewModel(client: StubClient(), pageSize: 2)
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertTrue(viewModel.events.isEmpty)
        XCTAssertFalse(viewModel.hasMore)
    }

    func testAnEmptyFeedForAPlayerWithNoFriendsKnowsItHasNoFriends() async {
        let friends = FakeFriendsClient()
        let viewModel = FriendActivityViewModel(client: StubClient(), friendsClient: friends, pageSize: 2)
        await viewModel.load()
        XCTAssertFalse(viewModel.hasFriends)
    }

    func testAnEmptyFeedForAPlayerWithFriendsIsNoActivity() async {
        let friends = FakeFriendsClient()
        friends.friendRows = [Friend(player: .fixture())]
        let viewModel = FriendActivityViewModel(client: StubClient(), friendsClient: friends, pageSize: 2)
        await viewModel.load()
        XCTAssertTrue(viewModel.hasFriends)
    }

    func testAFailedFriendsReadKeepsTheNoActivityCopy() async {
        let friends = FakeFriendsClient()
        friends.failing = true
        let viewModel = FriendActivityViewModel(client: StubClient(), friendsClient: friends, pageSize: 2)
        await viewModel.load()
        XCTAssertTrue(viewModel.hasFriends)
    }

    func testANonEmptyFeedNeverAsksForFriends() async {
        let client = StubClient()
        client.pages = [[event(1)]]
        let friends = FakeFriendsClient()
        let viewModel = FriendActivityViewModel(client: client, friendsClient: friends, pageSize: 2)
        await viewModel.load()
        XCTAssertTrue(viewModel.hasFriends)
    }

    // MARK: The one feed

    private func post(_ created: TimeInterval) -> PromptPost {
        PromptPost(
            id: UUID(), templateKind: "picks", templateName: "Picks", author: "A", caption: "",
            createdAt: Date(timeIntervalSince1970: created), promptText: "Q", resolutionCriteria: "", lockAt: Date(), status: .open,
            voidReason: nil, isOpinion: false, slots: [], comments: [], responseCount: 0,
            viewerResponse: nil, viewerPointsAwarded: nil, aggregate: nil
        )
    }

    private func answerer(_ post: PromptPost, _ name: String, at: TimeInterval) -> FriendAnswerer {
        FriendAnswerer(postId: post.id, identity: .fixture(name.lowercased(), name: name), answeredAt: Date(timeIntervalSince1970: at))
    }

    private func entryIds(_ entries: [HomeFeedEntry]) -> [String] { entries.map(\.id) }

    func testHomeFiltersAreAllPromptsFriends() {
        XCTAssertEqual(HomeFilter.allCases.map(\.title), ["All", "Prompts", "Friends"])
    }

    func testAllInterleavesPromptsAndMomentsByTime() {
        let newer = post(9_000), older = post(1_000)
        let moment = event(1) // 9_999
        let entries = HomeFeed.build(posts: [newer, older], answerers: [:], moments: [moment], filter: .all, hasMoreMoments: false)
        XCTAssertEqual(entryIds(entries), [HomeFeedEntry.moment(FriendActivityItem(event: moment)).id, "prompt-\(newer.id)", "prompt-\(older.id)"])
    }

    func testPromptsShowsOnlyPrompts() {
        let p = post(1_000)
        let entries = HomeFeed.build(posts: [p], answerers: [:], moments: [event(1)], filter: .prompts, hasMoreMoments: true)
        XCTAssertEqual(entryIds(entries), ["prompt-\(p.id)"])
    }

    func testFriendsKeepsOnlyPromptsAFriendAnsweredDatedByTheNewestAnswer() {
        let answered = post(1_000), untouched = post(2_000)
        let moment = event(5) // 9_995
        let entries = HomeFeed.build(
            posts: [answered, untouched],
            answerers: [answered.id: [answerer(answered, "Ava", at: 9_000), answerer(answered, "Ben", at: 9_990)]],
            moments: [moment], filter: .friends, hasMoreMoments: false
        )
        XCTAssertEqual(entryIds(entries), [HomeFeedEntry.moment(FriendActivityItem(event: moment)).id, "prompt-\(answered.id)"])
    }

    func testAFullPageOfMomentsStopsTheFeedAtItsOldestEvent() {
        let recent = post(9_999), old = post(100)
        let entries = HomeFeed.build(posts: [recent, old], answerers: [:], moments: [event(1), event(2)], filter: .all, hasMoreMoments: true)
        XCTAssertFalse(entryIds(entries).contains("prompt-\(old.id)"))
        XCTAssertTrue(entryIds(entries).contains("prompt-\(recent.id)"))
    }

    func testTheAnsweredLineNamesFriends() {
        let p = post(1)
        XCTAssertNil(FriendAnswerer.line([]))
        XCTAssertEqual(FriendAnswerer.line([answerer(p, "Ava", at: 1)]), "Ava answered")
        XCTAssertEqual(FriendAnswerer.line([answerer(p, "Ava", at: 1), answerer(p, "Ben", at: 1)]), "Ava & Ben answered")
        XCTAssertEqual(FriendAnswerer.line([answerer(p, "Ava", at: 1), answerer(p, "Ben", at: 1), answerer(p, "Cy", at: 1)]), "Ava, Ben & 1 other friend answered")
    }

    func testTheAnsweredLineFoldsInTheHeadcountWhenKnown() {
        let p = post(1)
        let a = answerer(p, "Ava", at: 1), b = answerer(p, "Ben", at: 1)
        XCTAssertEqual(FriendAnswerer.line([a], total: 6), "Ava and 5 others have answered")
        XCTAssertEqual(FriendAnswerer.line([a], total: 2), "Ava and 1 other has answered")
        XCTAssertEqual(FriendAnswerer.line([a], total: 1), "Ava has answered")
        XCTAssertEqual(FriendAnswerer.line([a, b], total: 2), "Ava and Ben have answered")
        XCTAssertEqual(FriendAnswerer.line([a, b], total: 7), "Ava, Ben and 5 others have answered")
    }

    func testAnswerersDecodeAndLoadByPrompt() async throws {
        let p = post(1)
        let json = "[{\"post_id\":\"\(p.id.uuidString)\",\"actor_id\":\"00000000-0000-0000-0000-0000000000A1\",\"username\":\"sam_k\",\"display_name\":\"Sam\",\"avatar_url\":null,\"answered_at\":\"2026-10-01T12:00:00+00:00\"}]"
        let decoded = try JSONDecoder().decode([FriendAnswerer].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.first?.identity.displayName, "Sam")

        let client = StubClient()
        client.answerRows = decoded
        let viewModel = FriendActivityViewModel(client: client, pageSize: 2)
        await viewModel.loadAnswerers(postIds: [p.id])
        XCTAssertEqual(viewModel.answerers[p.id]?.count, 1)

        client.failing = true
        await viewModel.loadAnswerers(postIds: [p.id])
        XCTAssertEqual(viewModel.answerers[p.id]?.count, 1, "a failed read keeps what is on screen")
    }
}
