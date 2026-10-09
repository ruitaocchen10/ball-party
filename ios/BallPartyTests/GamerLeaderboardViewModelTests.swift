import Foundation
@testable import BallParty
import XCTest

/// `GamerLeaderboardViewModel` against a stub `GamerLeaderboardClient`.
@MainActor
final class GamerLeaderboardViewModelTests: XCTestCase {
    private struct Offline: Error {}

    private final class StubClient: GamerLeaderboardClient, @unchecked Sendable {
        var gamerRows: [GamerRow] = []
        var soloRows: [SoloRow] = []
        var gamerPlace = GamerStanding(status: .unranked)
        var soloPlace = SoloStanding(status: .unranked)
        var failing = false
        private(set) var gamerWindows: [LeaderboardWindow] = []
        private(set) var soloReads: [(game: SoloGame, mode: QbRatingMode?, scope: LeaderboardScope)] = []

        func gamerBoard(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> [GamerRow] {
            gamerWindows.append(window)
            if failing { throw Offline() }
            return gamerRows
        }

        func gamerStanding(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> GamerStanding {
            if failing { throw Offline() }
            return gamerPlace
        }

        func soloBoard(game: SoloGame, mode: QbRatingMode?, scope: LeaderboardScope) async throws -> [SoloRow] {
            soloReads.append((game, mode, scope))
            if failing { throw Offline() }
            return soloRows
        }

        func soloStanding(game: SoloGame, mode: QbRatingMode?, scope: LeaderboardScope) async throws -> SoloStanding {
            if failing { throw Offline() }
            return soloPlace
        }
    }

    func testStartsLoading() {
        let viewModel = GamerLeaderboardViewModel(source: .wins, client: StubClient())
        XCTAssertEqual(viewModel.phase, .loading)
        XCTAssertTrue(viewModel.rows.isEmpty)
    }

    func testTheWinsBoardReadsTheSelectedWindow() async {
        let client = StubClient()
        client.gamerRows = [GamerRow(rank: 1, displayName: "Ava", wins: 3, gamesPlayed: 5, rankedCount: 1)]
        client.gamerPlace = GamerStanding(status: .ranked, rank: 1, wins: 3, gamesPlayed: 5, rankedCount: 1)
        let viewModel = GamerLeaderboardViewModel(source: .wins, client: client, window: .month)

        await viewModel.load()

        XCTAssertEqual(client.gamerWindows, [.month])
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.rows.map(\.displayName), ["Ava"])
        XCTAssertEqual(viewModel.rows.first?.value, "3")
        XCTAssertEqual(viewModel.standing?.isRanked, true)
    }

    func testQbSeasonBuilderReadsItsModeAndFormatsScores() async {
        let client = StubClient()
        client.soloRows = [SoloRow(rank: 1, displayName: "Ava", bestScore: 91, rankedCount: 1)]
        let viewModel = GamerLeaderboardViewModel(source: .solo(.qbSeasonBuilder), client: client, mode: .hidden)

        await viewModel.load()

        XCTAssertEqual(client.soloReads.map(\.game), [.qbSeasonBuilder])
        XCTAssertEqual(client.soloReads.map(\.mode), [.hidden])
        XCTAssertEqual(viewModel.rows.first?.value, "91.0")
    }

    func testHigherOrLowerSendsNoMode() async {
        let client = StubClient()
        let viewModel = GamerLeaderboardViewModel(source: .solo(.higherOrLower), client: client, mode: .hidden)

        await viewModel.load()

        XCTAssertEqual(client.soloReads.map(\.game), [.higherOrLower])
        XCTAssertEqual(client.soloReads.map(\.mode), [nil])
    }

    func testSwitchingScopeReadsAgain() async {
        let client = StubClient()
        let viewModel = GamerLeaderboardViewModel(source: .solo(.higherOrLower), client: client)
        await viewModel.load()

        viewModel.scope = .friends
        await viewModel.load()

        XCTAssertEqual(client.soloReads.map(\.scope), [.all, .friends])
    }

    func testAFailedReadLeavesNothingToShow() async {
        let client = StubClient()
        client.failing = true
        let viewModel = GamerLeaderboardViewModel(source: .wins, client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .failed)
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertNil(viewModel.standing)
    }

    func testAFriendsBoardWithOnlyYouOnItIsEmpty() async {
        let client = StubClient()
        client.soloRows = [SoloRow(rank: 1, displayName: "Me", bestScore: 5, isMe: true, rankedCount: 1)]
        let viewModel = GamerLeaderboardViewModel(source: .solo(.higherOrLower), client: client, scope: .friends)

        await viewModel.load()

        XCTAssertTrue(viewModel.friendsBoardIsEmpty)
    }
}
