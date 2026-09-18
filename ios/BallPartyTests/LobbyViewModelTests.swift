import Foundation
@testable import BallParty
import XCTest

/// `LobbyViewModel` against `FakeLobbyClient` and `FakeHigherOrLowerClient` —
/// the two network seams a room screen touches. Every assertion is on what a
/// screen would show or what the app asked the server for.
@MainActor
final class LobbyViewModelTests: XCTestCase {
    private var viewerId = UUID()
    private var client: FakeLobbyClient!
    private var game: FakeHigherOrLowerClient!
    private var viewModel: LobbyViewModel!

    override func setUp() async throws {
        viewerId = UUID()
        client = FakeLobbyClient(viewerId: viewerId)
        game = FakeHigherOrLowerClient(viewerId: viewerId)
        viewModel = LobbyViewModel(client: client, game: game, viewerId: viewerId)
    }

    override func tearDown() async throws {
        viewModel.stopObserving()
    }

    // MARK: - Helpers

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
    }

    private var memberNames: [String] { viewModel.members.map(\.displayName) }

    // MARK: - Getting into a room

    func test_hosting_showsTheCodeToShareAndSeatsTheHost() async {
        await viewModel.createRoom()

        XCTAssertEqual(viewModel.stage, .room)
        XCTAssertEqual(viewModel.roomCode, "BRZWK")
        XCTAssertTrue(viewModel.isHost)
        XCTAssertEqual(memberNames, ["You"])
    }

    func test_joining_byCodeShowsTheRosterAlreadyInTheRoom() async {
        client.roomHostedBySomebodyElse(code: "QRTZW", hostName: "Dana")

        viewModel.code = "qrtzw"
        await viewModel.joinRoom()

        XCTAssertEqual(viewModel.stage, .room)
        XCTAssertFalse(viewModel.isHost)
        XCTAssertEqual(memberNames, ["Dana", "You"])
        // Codes are read aloud across a table, so the room takes them the way
        // the server stores them rather than the way they were typed.
        XCTAssertEqual(client.joinedCodes, ["QRTZW"])
    }

    func test_joining_aFullRoomSaysSoAndStaysOnTheEntryScreen() async {
        client.failures["join_lobby"] = LobbyServerError(message: "lobby_full")

        viewModel.code = "QRTZW"
        await viewModel.joinRoom()

        XCTAssertEqual(viewModel.stage, .entry)
        XCTAssertEqual(viewModel.errorMessage, "That room is already full.")
    }

    func test_joining_anUnknownRefusalSurfacesRawRatherThanAsAFriendlyLie() async {
        client.failures["join_lobby"] = LobbyServerError(message: "some_new_rule")

        viewModel.code = "QRTZW"
        await viewModel.joinRoom()

        XCTAssertEqual(viewModel.errorMessage, "some_new_rule")
    }

    func test_joining_needsACode() async {
        viewModel.code = "  "
        await viewModel.joinRoom()

        XCTAssertEqual(viewModel.stage, .entry)
        XCTAssertEqual(viewModel.errorMessage, "Enter a room code.")
        XCTAssertTrue(client.joinedCodes.isEmpty)
    }

    // MARK: - Staying in step with the room

    func test_room_aPlayerArrivingShowsUpWithoutBeingAskedFor() async {
        await viewModel.createRoom()

        client.anotherPlayerJoins(named: "Sam")

        await eventually { self.memberNames == ["You", "Sam"] }
    }

    func test_room_aPlayerLeavingIsTakenOffTheRoster() async {
        await viewModel.createRoom()
        let sam = client.anotherPlayerJoins(named: "Sam")
        await eventually { self.memberNames.count == 2 }

        client.playerLeaves(sam)

        await eventually { self.memberNames == ["You"] }
    }

    func test_room_reconnectingReReadsTheWholeRoom() async {
        await viewModel.createRoom()
        await eventually { self.client.isObserved }
        let reads = client.snapshotCount

        // The channel dropping and coming back is invisible to the app: the
        // SDK resubscribes and reports success again, which is the whole of
        // the reconnect contract (`realtime.md`).
        client.channelSubscribes()

        await eventually { self.client.snapshotCount > reads }
    }

    func test_room_theRoomClosingUnderYouEndsTheScreen() async {
        client.roomHostedBySomebodyElse()
        viewModel.code = "QRTZW"
        await viewModel.joinRoom()

        client.roomCloses()

        await eventually { self.viewModel.stage == .closed }
    }

    func test_room_renewsItsPresenceLeaseWhileTheScreenIsOpen() async {
        viewModel = LobbyViewModel(
            client: client, game: game, viewerId: viewerId, heartbeatInterval: .milliseconds(1)
        )
        await viewModel.createRoom()

        // The stamp nothing in the app reads back: it keeps the server's
        // host-recovery and janitor sweeps working for a mobile-hosted lobby.
        await eventually { self.client.heartbeatCount >= 3 }
    }

    func test_room_aBackgroundedScreenLetsItsLeaseLapseAndRenewsOnReturn() async {
        viewModel = LobbyViewModel(
            client: client, game: game, viewerId: viewerId, heartbeatInterval: .milliseconds(1)
        )
        await viewModel.createRoom()
        await eventually { self.client.heartbeatCount >= 1 }

        viewModel.appEnteredBackground()
        // Let anything already in flight land before taking the reading.
        for _ in 0..<50 { await Task.yield() }
        let whileAway = client.heartbeatCount
        for _ in 0..<50 { await Task.yield() }
        XCTAssertEqual(client.heartbeatCount, whileAway, "a backgrounded screen kept renewing")

        viewModel.appBecameActive()

        await eventually { self.client.heartbeatCount > whileAway }
    }

    func test_room_returningToTheForegroundReReadsTheRoom() async {
        await viewModel.createRoom()
        await eventually { self.client.isObserved }
        let reads = client.snapshotCount

        viewModel.appBecameActive()

        await eventually { self.client.snapshotCount > reads }
    }

    func test_room_leavingGoesBackToTheEntryScreen() async {
        await viewModel.createRoom()

        await viewModel.leaveRoom()

        XCTAssertEqual(viewModel.stage, .entry)
        XCTAssertEqual(client.leaveCount, 1)
        XCTAssertFalse(client.isObserved, "the room's channel outlived the room")
    }

    func test_room_onlyTheHostIsOfferedTheRoomsControls() async {
        client.roomHostedBySomebodyElse()
        viewModel.code = "QRTZW"
        await viewModel.joinRoom()

        XCTAssertFalse(viewModel.isHost)
        XCTAssertFalse(viewModel.canClose)
    }

    func test_room_theHostClosingTheRoomEndsItAndLeaves() async {
        await viewModel.createRoom()
        XCTAssertTrue(viewModel.canClose)

        await viewModel.closeRoom()

        XCTAssertEqual(client.closeCount, 1)
        XCTAssertEqual(viewModel.stage, .entry)
    }

    // MARK: - Starting a game

    func test_startingAGame_theHostsChoiceIsVisibleToTheWholeRoom() async {
        await viewModel.createRoom()

        await viewModel.selectGame(.higherOrLower)

        XCTAssertEqual(client.selectedGames, [.higherOrLower])
        await eventually { self.viewModel.selectedGame == .higherOrLower }
    }

    func test_startingAGame_takesTwoPlayers() async {
        await viewModel.createRoom()
        await viewModel.selectGame(.higherOrLower)
        await eventually { self.viewModel.selectedGame == .higherOrLower }

        XCTAssertFalse(viewModel.canStart, "a host could start a game alone")
        XCTAssertEqual(viewModel.startBlockedReason, "Waiting for one more player")

        client.anotherPlayerJoins(named: "Sam")

        await eventually { self.viewModel.canStart }
        XCTAssertNil(viewModel.startBlockedReason)
    }

    func test_startingAGame_needsAGameChosenFirst() async {
        await viewModel.createRoom()
        client.anotherPlayerJoins(named: "Sam")
        await eventually { self.viewModel.members.count == 2 }

        XCTAssertFalse(viewModel.canStart)
        XCTAssertEqual(viewModel.startBlockedReason, "Pick a game first")
    }

    func test_startingAGame_freezesTheRosterThenDealsTheLadderAndGoesIn() async {
        await viewModel.createRoom()
        await viewModel.selectGame(.higherOrLower)
        client.anotherPlayerJoins(named: "Sam")
        await eventually { self.viewModel.canStart }

        await viewModel.startGame()

        // Two calls, in order: the platform freezes the roster and opens a
        // `'setup'` match, then the game deals into it.
        XCTAssertEqual(client.startedRuns, [.higherOrLower])
        XCTAssertEqual(game.startCalls.count, 1)
        XCTAssertEqual(viewModel.matchToEnter, game.matchId)
    }

    func test_startingAGame_sendsTheHostsScoringAndEra() async {
        await viewModel.createRoom()
        await viewModel.loadFormat()
        await viewModel.selectGame(.higherOrLower)
        client.anotherPlayerJoins(named: "Sam")
        await eventually { self.viewModel.canStart }

        viewModel.scoringMode = .weekly
        viewModel.seasonFrom = 2018
        viewModel.seasonTo = 2022
        await viewModel.startGame()

        XCTAssertEqual(game.startCalls.first?.scoringMode, .weekly)
        XCTAssertEqual(game.startCalls.first?.era, SeasonRange(from: 2018, to: 2022))
    }

    func test_startingAGame_movingTheFirstSeasonPastTheLastDragsTheLastAlong() async {
        await viewModel.createRoom()
        await viewModel.loadFormat()

        viewModel.seasonTo = 2015
        viewModel.seasonFrom = 2020

        XCTAssertEqual(viewModel.seasonTo, 2020)
    }

    func test_startingAGame_aRefusalLeavesTheRoomUpWithItsReason() async {
        await viewModel.createRoom()
        await viewModel.selectGame(.higherOrLower)
        client.anotherPlayerJoins(named: "Sam")
        await eventually { self.viewModel.canStart }
        client.failures["start_run"] = LobbyServerError(message: "bad_player_count")

        await viewModel.startGame()

        XCTAssertEqual(viewModel.stage, .room)
        XCTAssertEqual(viewModel.errorMessage, "You need between two and four players.")
        XCTAssertNil(viewModel.matchToEnter)
    }

    func test_startingAGame_carriesEverySeatedPlayerIn() async {
        client.roomHostedBySomebodyElse()
        viewModel.code = "QRTZW"
        await viewModel.joinRoom()

        // Somebody else's tap on Start. This player finds out only because the
        // room changed under them.
        let matchId = client.hostStartsARun()

        await eventually { self.viewModel.matchToEnter == matchId }
    }

    func test_startingAGame_aPlayerWhoArrivedAfterTheFreezeWaitsForTheNextOne() async {
        client.roomHostedBySomebodyElse()
        let seated = client.anotherPlayerJoins(named: "Sam")
        viewModel.code = "QRTZW"
        await viewModel.joinRoom()

        client.hostStartsARun(seating: [seated])

        await eventually { self.viewModel.waitingForNextRun }
        XCTAssertNil(viewModel.matchToEnter, "a player who wasn't seated was sent to the board anyway")
    }

    func test_startingAGame_aFinishedMatchStopsPullingAnybodyIn() async {
        client.roomHostedBySomebodyElse()
        viewModel.code = "QRTZW"
        await viewModel.joinRoom()
        client.hostStartsARun()
        await eventually { self.viewModel.matchToEnter != nil }

        client.runFinishes()

        await eventually { self.viewModel.matchToEnter == nil }
        XCTAssertFalse(viewModel.waitingForNextRun)
    }

    func test_startingAGame_comingBackToTheRoomDoesNotYankYouIntoTheSameMatch() async {
        client.roomHostedBySomebodyElse()
        viewModel.code = "QRTZW"
        await viewModel.joinRoom()
        let first = client.hostStartsARun()
        await eventually { self.viewModel.matchToEnter != nil }

        viewModel.matchDismissed(first)

        XCTAssertNil(viewModel.matchToEnter)

        // A *different* match — the replay the host just started — still does.
        let replay = client.hostStartsARun()
        await eventually { self.viewModel.matchToEnter == replay }
    }

    func test_startingAGame_aPlayerWhoSteppedOutOfTheirGameIsOfferedTheWayBack() async {
        client.roomHostedBySomebodyElse()
        viewModel.code = "QRTZW"
        await viewModel.joinRoom()
        let matchId = client.hostStartsARun()
        await eventually { self.viewModel.matchToEnter == matchId }

        viewModel.matchDismissed(matchId)

        // Their seat is still theirs — the server never took it away, this
        // screen only stopped pushing them at it.
        XCTAssertEqual(viewModel.rejoinableMatch, matchId)

        viewModel.rejoinMatch()

        XCTAssertEqual(viewModel.matchToEnter, matchId)
        XCTAssertNil(viewModel.rejoinableMatch)
    }
}
