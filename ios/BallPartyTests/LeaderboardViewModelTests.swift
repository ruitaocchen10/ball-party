import Foundation
@testable import BallParty
import XCTest

/// `LeaderboardViewModel` against a stub `LeaderboardClient`.
@MainActor
final class LeaderboardViewModelTests: XCTestCase {
    private struct Offline: Error {}

    private final class StubClient: LeaderboardClient, @unchecked Sendable {
        var rows: [LeaderboardWindow: [LeaderboardRow]] = [:]
        var standings: [LeaderboardWindow: LeaderboardStanding] = [:]
        var failing = false
        private(set) var requested: [LeaderboardWindow] = []

        func leaderboard(window: LeaderboardWindow) async throws -> [LeaderboardRow] {
            requested.append(window)
            if failing { throw Offline() }
            return rows[window] ?? []
        }

        func standing(window: LeaderboardWindow) async throws -> LeaderboardStanding {
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
}
