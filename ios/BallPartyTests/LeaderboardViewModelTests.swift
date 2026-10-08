import Foundation
@testable import BallParty
import XCTest

/// `LeaderboardViewModel` against a stub `LeaderboardClient`.
@MainActor
final class LeaderboardViewModelTests: XCTestCase {
    private struct Offline: Error {}

    private final class StubClient: LeaderboardClient, @unchecked Sendable {
        var rows: [LeaderboardWindow: [LeaderboardRow]] = [:]
        var friendRows: [LeaderboardWindow: [LeaderboardRow]] = [:]
        var standings: [LeaderboardWindow: LeaderboardStanding] = [:]
        var failing = false
        private(set) var requested: [LeaderboardWindow] = []
        private(set) var requestedScopes: [LeaderboardScope] = []

        func leaderboard(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> [LeaderboardRow] {
            requested.append(window)
            requestedScopes.append(scope)
            if failing { throw Offline() }
            return (scope == .friends ? friendRows[window] : rows[window]) ?? []
        }

        func standing(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> LeaderboardStanding {
            if failing { throw Offline() }
            return standings[window] ?? LeaderboardStanding(status: .unranked)
        }
    }

    private func row(_ rank: Int, _ name: String, isMe: Bool = false) -> LeaderboardRow {
        LeaderboardRow(rank: rank, displayName: name, totalPoints: 100 - rank, scoredPicks: 5, isMe: isMe, rankedCount: 3)
    }

    func testStartsLoadingOnTheRequestedWindow() {
        let viewModel = LeaderboardViewModel(client: StubClient(), window: .month)
        XCTAssertEqual(viewModel.phase, .loading)
        XCTAssertEqual(viewModel.window, .month)
        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    func testLoadFillsRowsAndStandingForTheWindow() async {
        let client = StubClient()
        client.rows[.week] = [row(1, "Alpha"), row(2, "Bravo")]
        client.standings[.week] = LeaderboardStanding(status: .ranked, rank: 2, totalPoints: 98, scoredPicks: 5, rankedCount: 2)
        let viewModel = LeaderboardViewModel(client: client, window: .week)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.rows.map(\.displayName), ["Alpha", "Bravo"])
        XCTAssertEqual(viewModel.standing?.rank, 2)
    }

    func testSwitchingWindowsReadsTheNewWindow() async {
        let client = StubClient()
        client.rows[.year] = [row(1, "Yearly")]
        let viewModel = LeaderboardViewModel(client: client, window: .week)
        await viewModel.load()

        viewModel.window = .year
        await viewModel.load()

        XCTAssertEqual(client.requested, [.week, .year])
        XCTAssertEqual(viewModel.rows.map(\.displayName), ["Yearly"])
    }

    func testAFailedReadLeavesNothingToShow() async {
        let client = StubClient()
        client.failing = true
        let viewModel = LeaderboardViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .failed)
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertNil(viewModel.standing)
    }

    func testRetryRecoversAfterAFailure() async {
        let client = StubClient()
        client.failing = true
        client.rows[.week] = [row(1, "Alpha")]
        let viewModel = LeaderboardViewModel(client: client)
        await viewModel.load()

        client.failing = false
        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.rows.count, 1)
    }

    func testTheScopeIsPassedToBothReads() async {
        let client = StubClient()
        client.friendRows[.week] = [row(1, "Me", isMe: true), row(2, "Friend")]
        let viewModel = LeaderboardViewModel(client: client, scope: .friends)

        await viewModel.load()

        XCTAssertEqual(client.requestedScopes, [.friends])
        XCTAssertEqual(viewModel.rows.map(\.displayName), ["Me", "Friend"])
        XCTAssertFalse(viewModel.friendsBoardIsEmpty)
    }

    func testSwitchingScopeReloadsTheSameWindow() async {
        let client = StubClient()
        client.rows[.week] = [row(1, "Everyone")]
        client.friendRows[.week] = [row(1, "Pal")]
        let viewModel = LeaderboardViewModel(client: client, window: .week)
        await viewModel.load()

        viewModel.scope = .friends
        await viewModel.load()

        XCTAssertEqual(client.requestedScopes, [.all, .friends])
        XCTAssertEqual(viewModel.rows.map(\.displayName), ["Pal"])
    }

    func testAFriendsBoardWithOnlyMeOrNobodyIsEmpty() async {
        let client = StubClient()
        client.friendRows[.week] = [row(1, "Me", isMe: true)]
        let viewModel = LeaderboardViewModel(client: client, scope: .friends)
        await viewModel.load()
        XCTAssertTrue(viewModel.friendsBoardIsEmpty)

        client.friendRows[.week] = []
        await viewModel.load()
        XCTAssertTrue(viewModel.friendsBoardIsEmpty)
    }

    func testTheEveryoneBoardIsNeverTheEmptyFriendsBoard() async {
        let viewModel = LeaderboardViewModel(client: StubClient(), scope: .all)
        await viewModel.load()
        XCTAssertFalse(viewModel.friendsBoardIsEmpty)
    }
}
