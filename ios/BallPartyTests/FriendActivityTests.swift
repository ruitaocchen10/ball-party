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
    "post_id":null,"post_caption":null,"points":null,"match_id":null,"game":null,"placement":null,"raw_score":null,"run_mode":null
    """

    func testPickMadeDecodesAndNeverCarriesAnOption() throws {
        let json = "[" + row("pick_made", "2026-10-01T12:00:00.123456+00:00",
            "\"post_id\":\"00000000-0000-0000-0000-0000000000B1\",\"post_caption\":\"Week 5 lock\",\"points\":null,\"match_id\":null,\"game\":null,\"placement\":null,\"raw_score\":null,\"run_mode\":null") + "]"
        let events = try decodePage(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].actor.username, "sam_k")
        XCTAssertEqual(events[0].summary, "made a pick on “Week 5 lock”")
        XCTAssertEqual(events[0].occurredAtRaw, "2026-10-01T12:00:00.123456+00:00")
    }

    func testPickResultReadsPoints() throws {
        let events = try decodePage("[" + row("pick_result", "2026-10-01T12:00:00+00:00",
            "\"post_id\":\"00000000-0000-0000-0000-0000000000B1\",\"post_caption\":\"Week 5 lock\",\"points\":3,\"match_id\":null,\"game\":null,\"placement\":null,\"raw_score\":null,\"run_mode\":null") + "]")
        XCTAssertEqual(events[0].summary, "scored +3 points on “Week 5 lock”")
        XCTAssertEqual(
            FriendActivityEvent(kind: .pickResult(postId: UUID(), caption: nil, points: 1), occurredAt: Date(), actor: .fixture()).summary,
            "scored +1 point"
        )
    }

    func testMatchResultReadsGamePlacementAndScore() throws {
        let events = try decodePage("[" + row("match_result", "2026-10-01T12:00:00+00:00",
            "\"post_id\":null,\"post_caption\":null,\"points\":null,\"match_id\":\"00000000-0000-0000-0000-0000000000C1\",\"game\":\"higher_or_lower\",\"placement\":2,\"raw_score\":\"1450.5\",\"run_mode\":\"party\"") + "]")
        XCTAssertEqual(events[0].summary, "finished 2nd in Higher or Lower · 1,450.5")
    }

    func testASoloMatchHasNoPlacementLine() throws {
        let events = try decodePage("[" + row("match_result", "2026-10-01T12:00:00+00:00",
            "\"post_id\":null,\"post_caption\":null,\"points\":null,\"match_id\":\"00000000-0000-0000-0000-0000000000C1\",\"game\":\"higher_or_lower\",\"placement\":1,\"raw_score\":12,\"run_mode\":\"solo\"") + "]")
        XCTAssertEqual(events[0].summary, "played Higher or Lower solo · 12")
    }

    func testAnUnknownGameIsHumanizedNotDropped() throws {
        let events = try decodePage("[" + row("match_result", "2026-10-01T12:00:00+00:00",
            "\"post_id\":null,\"post_caption\":null,\"points\":null,\"match_id\":\"00000000-0000-0000-0000-0000000000C1\",\"game\":\"qb_season_builder\",\"placement\":null,\"raw_score\":null,\"run_mode\":\"arcade\"") + "]")
        XCTAssertEqual(events[0].summary, "played Qb season builder")
    }

    func testAnUnknownEventTypeIsSkippedNotFatal() throws {
        let json = "[" + row("brand_new", "2026-10-01T12:00:00+00:00", blanks) + ","
            + row("pick_made", "2026-10-01T11:00:00+00:00",
                "\"post_id\":\"00000000-0000-0000-0000-0000000000B1\",\"post_caption\":null,\"points\":null,\"match_id\":null,\"game\":null,\"placement\":null,\"raw_score\":null,\"run_mode\":null") + "]"
        let events = try decodePage(json)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].summary, "made a pick")
    }

    // MARK: Paging

    private final class StubClient: FriendActivityClient, @unchecked Sendable {
        var pages: [[FriendActivityEvent]] = []
        var failing = false
        private(set) var befores: [String?] = []
        private(set) var limits: [Int] = []

        func activity(limit: Int, before: String?) async throws -> [FriendActivityEvent] {
            befores.append(before)
            limits.append(limit)
            if failing { throw Offline() }
            return pages.isEmpty ? [] : pages.removeFirst()
        }
    }

    private let samIdentity = PlayerIdentity.fixture()

    private func event(_ n: Int) -> FriendActivityEvent {
        FriendActivityEvent(
            kind: .pickMade(postId: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!, caption: "P\(n)"),
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

    func testHomeTabsAreHuddleThenFriends() {
        XCTAssertEqual(HomeTab.allCases, [.huddle, .friends])
        XCTAssertEqual(HomeTab.allCases.map(\.title), ["Huddle", "Friends"])
    }
}
