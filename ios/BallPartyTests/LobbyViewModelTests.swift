import Foundation
@testable import BallParty
import XCTest

/// `LobbyViewModel` against `FakeLobbyClient`, `FakeHigherOrLowerClient` and
/// `FakeAuctionClient` — the network seams a room screen touches. Every assertion is on what a
/// screen would show or what the app asked the server for.
@MainActor
final class LobbyViewModelTests: XCTestCase {
    private var viewerId = UUID()
    private var client: FakeLobbyClient!
    private var game: FakeHigherOrLowerClient!
    private var auction: FakeAuctionClient!
    private var wavelength: FakeWavelengthClient!
    private var viewModel: LobbyViewModel!

    override func setUp() async throws {
        viewerId = UUID()
        client = FakeLobbyClient(viewerId: viewerId)
        game = FakeHigherOrLowerClient(viewerId: viewerId)
        auction = FakeAuctionClient(viewerId: viewerId)
        wavelength = FakeWavelengthClient(viewerId: viewerId)
        viewModel = LobbyViewModel(client: client, game: game, auction: auction, wavelength: wavelength, viewerId: viewerId, formatSaveDelay: .zero)
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

    func test_lobbyMember_decodesTheProfileAvatarURL() throws {
        let member = try JSONDecoder().decode(LobbyMember.self, from: Data("""
        {"user_id": "1B2F1C0E-0000-4000-8000-000000000001",
         "joined_at": "2026-09-24T12:00:00+00:00",
         "profiles": {"display_name": "Avery", "avatar_url": "https://example.com/avery.png"}}
        """.utf8))

        XCTAssertEqual(member.displayName, "Avery")
        XCTAssertEqual(member.avatarURL, URL(string: "https://example.com/avery.png"))
    }

    // MARK: - Coming back to a room

    /// The same player on a fresh screen: the app was closed or killed, so nothing
    /// is held in memory, while the server still has them in the room.
    private func relaunchedScreen() -> LobbyViewModel {
        LobbyViewModel(client: client, game: game, auction: auction, wavelength: wavelength, viewerId: viewerId, formatSaveDelay: .zero)
    }

    func test_relaunch_stepsBackIntoTheRoomTheServerStillHasYouIn() async {
        await viewModel.createRoom()
        viewModel.stopObserving()

        let relaunched = relaunchedScreen()
        XCTAssertEqual(relaunched.stage, .entry)
        await relaunched.restoreCurrentRoom()

        XCTAssertEqual(relaunched.stage, .room)
        XCTAssertEqual(relaunched.roomCode, "BRZWK")
        XCTAssertEqual(relaunched.members.map(\.displayName), ["You"])
        relaunched.stopObserving()
    }

    func test_relaunch_withNoRoomStaysOnTheEntryScreen() async {
        let relaunched = relaunchedScreen()
        await relaunched.restoreCurrentRoom()

        XCTAssertEqual(relaunched.stage, .entry)
        XCTAssertNil(relaunched.errorMessage)
    }

    func test_relaunch_aRoomThatClosedIsNotRestored() async {
        await viewModel.createRoom()
        viewModel.stopObserving()
        client.roomCloses()

        let relaunched = relaunchedScreen()
        await relaunched.restoreCurrentRoom()

        XCTAssertEqual(relaunched.stage, .entry)
    }

    func test_relaunch_aFailedLookUpJustLeavesTheEntryScreen() async {
        await viewModel.createRoom()
        viewModel.stopObserving()
        client.failures["current_lobby"] = LobbyServerError(message: "boom")

        let relaunched = relaunchedScreen()
        await relaunched.restoreCurrentRoom()

        XCTAssertEqual(relaunched.stage, .entry)
        XCTAssertNil(relaunched.errorMessage, "a best-effort look-up does not nag")
    }

    func test_relaunch_isOnlyTriedOncePerScreen() async {
        let relaunched = relaunchedScreen()
        await relaunched.restoreCurrentRoom()
        await relaunched.restoreCurrentRoom()

        XCTAssertEqual(client.currentLobbyLookups, 1)
    }

    func test_relaunch_neverMovesSomeoneWhoIsAlreadyInARoom() async {
        await viewModel.createRoom()
        let lookupsBefore = client.currentLobbyLookups

        await viewModel.restoreCurrentRoom()

        XCTAssertEqual(client.currentLobbyLookups, lookupsBefore, "a screen already in a room does not ask")
        XCTAssertEqual(viewModel.stage, .room)
    }

    // MARK: - Getting into a room

    func test_hosting_seatsTheHostInTheNewRoom() async {
        await viewModel.createRoom()

        XCTAssertEqual(viewModel.stage, .room)
        XCTAssertEqual(viewModel.roomCode, "BRZWK")
        XCTAssertTrue(viewModel.isHost)
        XCTAssertEqual(memberNames, ["You"])
    }

    func test_joining_byCodeShowsTheRosterAlreadyInTheRoom() async {
        client.roomHostedBySomebodyElse(code: "QRTZW", hostName: "Dana")

        await viewModel.joinRoom(code: "qrtzw")

        XCTAssertEqual(viewModel.stage, .room)
        XCTAssertFalse(viewModel.isHost)
        XCTAssertEqual(memberNames, ["Dana", "You"])
        // Codes are read aloud across a table, so the room takes them the way
        // the server stores them rather than the way they were typed.
        XCTAssertEqual(client.joinedCodes, ["QRTZW"])
    }

    func test_joining_aFullRoomSaysSoAndStaysOnTheEntryScreen() async {
        client.failures["join_lobby"] = LobbyServerError(message: "lobby_full")

        await viewModel.joinRoom(code: "QRTZW")

        XCTAssertEqual(viewModel.stage, .entry)
        XCTAssertEqual(viewModel.errorMessage, "That room is already full.")
    }

    func test_joining_anUnknownRefusalSurfacesRawRatherThanAsAFriendlyLie() async {
        client.failures["join_lobby"] = LobbyServerError(message: "some_new_rule")

        await viewModel.joinRoom(code: "QRTZW")

        XCTAssertEqual(viewModel.errorMessage, "some_new_rule")
    }

    func test_joining_needsALinkToken() async {
        await viewModel.joinRoom(code: "  ")

        XCTAssertEqual(viewModel.stage, .entry)
        XCTAssertEqual(viewModel.errorMessage, "That room link isn't valid.")
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

    func test_scoreboard_ranksTheRoomByWinsAndKeepsJoinOrderForTies() async {
        await viewModel.createRoom()
        let sam = client.anotherPlayerJoins(named: "Sam")
        client.anotherPlayerJoins(named: "Alex")
        await eventually { self.memberNames.count == 3 }
        XCTAssertEqual(viewModel.standings.map(\.wins), [0, 0, 0])
        XCTAssertEqual(viewModel.standings.map(\.rank), [nil, nil, nil])
        XCTAssertEqual(viewModel.standings.map(\.member.displayName), ["You", "Sam", "Alex"])

        client.playerWinsAMatch(sam)

        await eventually { self.viewModel.totalWins == 1 }
        XCTAssertEqual(viewModel.standings.map(\.member.displayName), ["Sam", "You", "Alex"])
        XCTAssertEqual(viewModel.standings.map(\.wins), [1, 0, 0])
        XCTAssertEqual(viewModel.standings.map(\.rank), [1, 2, 2])
    }

    func test_scoreboard_tiedPlayersShareARank() async {
        await viewModel.createRoom()
        let sam = client.anotherPlayerJoins(named: "Sam")
        let alex = client.anotherPlayerJoins(named: "Alex")
        await eventually { self.memberNames.count == 3 }

        client.playerWinsAMatch(sam)
        client.playerWinsAMatch(alex)
        client.playerWinsAMatch(sam)
        client.playerWinsAMatch(alex)

        await eventually { self.viewModel.totalWins == 4 }
        XCTAssertEqual(viewModel.standings.map(\.member.displayName), ["Sam", "Alex", "You"])
        XCTAssertEqual(viewModel.standings.map(\.rank), [1, 1, 3])
    }

    func test_scoreboard_tallyCountsOneWinPerRow() {
        let a = UUID(), b = UUID()
        let rows = [a, b, a].map { LobbySnapshot.WinRow(userId: $0) }
        XCTAssertEqual(LobbySnapshot.tallyWins(rows), [a: 2, b: 1])
    }

    // MARK: - The host's settings, saved on the room

    func test_format_aHostsChangeIsSavedOnTheRoom() async {
        await viewModel.createRoom()

        viewModel.wavelengthMode = .versus

        await eventually { !self.client.formatSaves.isEmpty }
        XCTAssertEqual(client.savedFormat.wavelength?.mode, "versus")
        // The whole blob goes up, so the other games' settings ride along.
        XCTAssertEqual(client.savedFormat.higherOrLower?.scoringMode, "season_total")
    }

    func test_format_loadingTheDefaultsIsNotAChange() async {
        await viewModel.createRoom()

        await viewModel.loadFormat()

        XCTAssertTrue(client.formatSaves.isEmpty)
    }

    func test_format_aReturningHostFindsTheirSettingsAsTheyLeftThem() async {
        client.hostHadSavedFormat(LobbyGameFormat(
            auction: .init(scoringMode: "season_total", rosterPreset: "deep", tokenCount: 3),
            wavelength: .init(mode: "versus", preset: "long")
        ))

        await viewModel.createRoom()

        XCTAssertEqual(viewModel.auctionScoringMode, .seasonTotal)
        XCTAssertEqual(viewModel.rosterPreset, .deep)
        XCTAssertEqual(viewModel.tokenCount, 3)
        XCTAssertEqual(viewModel.wavelengthMode, .versus)
        XCTAssertEqual(viewModel.wavelengthPreset, .long)
        XCTAssertTrue(client.formatSaves.isEmpty, "restoring settings is not a change to save")
    }

    func test_format_aSavedEraWaitsForItsBoundsAndIsClampedIntoThem() async {
        game.bounds = SeasonRange(from: 2000, to: 2020)
        client.hostHadSavedFormat(LobbyGameFormat(
            higherOrLower: .init(scoringMode: "weekly", seasonFrom: 1990, seasonTo: 2010)
        ))

        await viewModel.createRoom()
        await viewModel.loadFormat()

        XCTAssertEqual(viewModel.scoringMode, .weekly)
        XCTAssertEqual(viewModel.seasonFrom, 2000)
        XCTAssertEqual(viewModel.seasonTo, 2010)
    }

    func test_format_aPlayerSeesWhatTheHostSavedAndFollowsChanges() async {
        client.roomHostedBySomebodyElse()
        await viewModel.joinRoom(code: "QRTZW")
        XCTAssertEqual(
            viewModel.displayedFormat.lines(for: .higherOrLower).map(\.value), ["Season total", "All seasons"],
            "an untouched room reads as the defaults"
        )

        client.hostSavesFormat(LobbyGameFormat(higherOrLower: .init(scoringMode: "weekly", seasonFrom: 2010, seasonTo: 2024)))

        await eventually { self.viewModel.displayedFormat.higherOrLower?.scoringMode == "weekly" }
        XCTAssertEqual(
            viewModel.displayedFormat.lines(for: .higherOrLower).map(\.value), ["Weekly", "2010–2024"]
        )
        XCTAssertTrue(client.formatSaves.isEmpty, "a player never writes the room's settings")
    }

    func test_format_aGamesCardSaysWhenTheRoomDoesNotSuitIt() async {
        client.roomHostedBySomebodyElse()
        await viewModel.joinRoom(code: "QRTZW")
        client.anotherPlayerJoins(named: "Sam")
        await eventually { self.memberNames.count == 3 }

        // Three players: fine for the drafts, but Wavelength seats two or four.
        XCTAssertNil(viewModel.roomReadiness(for: .higherOrLower))
        XCTAssertEqual(
            viewModel.roomReadiness(for: .wavelength),
            "Co-op needs exactly 2 players (you have 3)"
        )

        client.hostSavesFormat(LobbyGameFormat(wavelength: .init(mode: "versus", preset: "short")))
        await eventually { self.viewModel.roomReadiness(for: .wavelength) == "2v2 needs exactly 4 players (you have 3)" }
    }

    func test_format_linesNameEachGamesSettings() {
        let format = LobbyGameFormat(
            auction: .init(scoringMode: "season_total", rosterPreset: "full", tokenCount: 0, seasonFrom: 2005, seasonTo: 2005),
            wavelength: .init(mode: "coop", preset: "medium")
        )

        XCTAssertEqual(format.lines(for: .auctionTeamBuilder).map(\.value), ["Season total", "Full · 28 lots", "Off", "2005"])
        XCTAssertEqual(format.lines(for: .wavelength).map(\.value), ["Co-op", "Medium · 6 rounds · target 12"])
        // 2v2 has no length to show.
        XCTAssertEqual(LobbyGameFormat(wavelength: .init(mode: "versus", preset: "short")).lines(for: .wavelength).map(\.label), ["Mode"])
    }

    func test_format_aNewerSettingStillDecodesAndIsShownAsWritten() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","code":"ABCDE","host_id":"00000000-0000-0000-0000-000000000002","game_format":{"wavelength_2v2":{"mode":"mythic","preset":"short"},"cards":{"x":1}}}"#
        let lobby = try JSONDecoder().decode(Lobby.self, from: Data(json.utf8))

        XCTAssertEqual(lobby.gameFormat.lines(for: .wavelength).map(\.value), ["mythic"])
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
        await viewModel.joinRoom(code: "QRTZW")

        client.roomCloses()

        await eventually { self.viewModel.stage == .closed }
    }

    func test_room_renewsItsPresenceLeaseWhileTheScreenIsOpen() async {
        viewModel = LobbyViewModel(
            client: client, game: game, auction: auction, wavelength: wavelength, viewerId: viewerId, heartbeatInterval: .milliseconds(1)
        )
        await viewModel.createRoom()

        // The stamp nothing in the app reads back: it keeps the server's
        // host-recovery and janitor sweeps working for a mobile-hosted lobby.
        await eventually { self.client.heartbeatCount >= 3 }
    }

    func test_room_aBackgroundedScreenLetsItsLeaseLapseAndRenewsOnReturn() async {
        viewModel = LobbyViewModel(
            client: client, game: game, auction: auction, wavelength: wavelength, viewerId: viewerId, heartbeatInterval: .milliseconds(1)
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
        await viewModel.joinRoom(code: "QRTZW")

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

    // MARK: - Starting the auction

    private func hostAnAuctionRoom() async {
        await viewModel.createRoom()
        await viewModel.loadFormat()
        await viewModel.selectGame(.auctionTeamBuilder)
        client.anotherPlayerJoins(named: "Sam")
        await eventually { self.viewModel.selectedGame == .auctionTeamBuilder && self.viewModel.members.count == 2 }
    }

    func test_startingTheAuction_freezesTheRosterThenDealsWithTheHostsFormat() async {
        await hostAnAuctionRoom()
        await eventually { self.viewModel.canStart }

        viewModel.auctionScoringMode = .seasonTotal
        viewModel.rosterPreset = .deep
        viewModel.tokenCount = 3
        viewModel.auctionFrom = 2016
        viewModel.auctionTo = 2024
        await viewModel.startGame()

        XCTAssertEqual(client.startedRuns, [.auctionTeamBuilder])
        XCTAssertEqual(auction.startCalls.count, 1)
        XCTAssertEqual(auction.startCalls.first?.scoringMode, .seasonTotal)
        XCTAssertEqual(auction.startCalls.first?.preset, .deep)
        XCTAssertEqual(auction.startCalls.first?.tokens, 3)
        XCTAssertEqual(auction.startCalls.first?.era, SeasonRange(from: 2016, to: 2024))
        XCTAssertTrue(game.startCalls.isEmpty, "the ladder was dealt for an auction")
        XCTAssertNotNil(viewModel.matchToEnter)
        XCTAssertEqual(viewModel.gameToEnter, .auctionTeamBuilder)
    }

    func test_startingTheAuction_opensOnWeeklyLotsStandardRosterAndOneToken() async {
        await hostAnAuctionRoom()
        await eventually { self.viewModel.canStart }

        await viewModel.startGame()

        XCTAssertEqual(auction.startCalls.first?.scoringMode, .weekly)
        XCTAssertEqual(auction.startCalls.first?.preset, .standard)
        XCTAssertEqual(auction.startCalls.first?.tokens, 1)
        // The whole pool, as offered.
        XCTAssertEqual(auction.startCalls.first?.era, SeasonRange(from: 2010, to: 2025))
    }

    func test_startingTheAuction_aWindowNarrowerThanTheDealersFloorIsExplainedBeforeTheTap() async {
        await hostAnAuctionRoom()
        await eventually { self.viewModel.canStart }

        viewModel.auctionFrom = 2020
        viewModel.auctionTo = 2022

        XCTAssertFalse(viewModel.canStart)
        XCTAssertEqual(viewModel.startBlockedReason, "Pick a span of at least 4 seasons")

        viewModel.auctionTo = 2023
        XCTAssertTrue(viewModel.canStart)
    }

    func test_startingTheAuction_theNarrowFloorDoesNotBlockHigherOrLower() async {
        await viewModel.createRoom()
        await viewModel.loadFormat()
        await viewModel.selectGame(.higherOrLower)
        client.anotherPlayerJoins(named: "Sam")
        await eventually { self.viewModel.canStart }

        viewModel.auctionFrom = 2020
        viewModel.auctionTo = 2020

        XCTAssertTrue(viewModel.canStart)
    }

    func test_startingTheAuction_theEraPickersNeverHoldAnInvertedRange() async {
        await viewModel.createRoom()
        await viewModel.loadFormat()

        viewModel.auctionTo = 2015
        viewModel.auctionFrom = 2020

        XCTAssertEqual(viewModel.auctionTo, 2020)
    }

    func test_startingTheAuction_aDealRefusalLeavesTheRoomUpWithItsReason() async {
        await hostAnAuctionRoom()
        await eventually { self.viewModel.canStart }
        auction.failures["start"] = AuctionServerError(message: "pool_exhausted")

        await viewModel.startGame()

        XCTAssertEqual(viewModel.stage, .room)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func test_enteringAMatch_opensTheScreenForTheGameTheRunIsPlaying() async {
        await viewModel.createRoom()
        client.anotherPlayerJoins(named: "Sam")
        await eventually { self.viewModel.members.count == 2 }

        client.hostStartsARun(game: .auctionTeamBuilder)

        await eventually { self.viewModel.matchToEnter != nil }
        XCTAssertEqual(viewModel.gameToEnter, .auctionTeamBuilder)
    }

    func test_enteringAMatch_aMatchWithNoNamedGameIsHigherOrLowerAsEveryEarlierOneWas() {
        XCTAssertEqual(RunMatch(id: UUID(), status: .playing).matchGame, .higherOrLower)
        XCTAssertEqual(RunMatch(id: UUID(), status: .playing, game: "auction_team_builder").matchGame, .auctionTeamBuilder)
    }

    func test_startingAGame_carriesEverySeatedPlayerIn() async {
        client.roomHostedBySomebodyElse()
        await viewModel.joinRoom(code: "QRTZW")

        // Somebody else's tap on Start. This player finds out only because the
        // room changed under them.
        let matchId = client.hostStartsARun()

        await eventually { self.viewModel.matchToEnter == matchId }
    }

    func test_startingAGame_aPlayerWhoArrivedAfterTheFreezeWaitsForTheNextOne() async {
        client.roomHostedBySomebodyElse()
        let seated = client.anotherPlayerJoins(named: "Sam")
        await viewModel.joinRoom(code: "QRTZW")

        client.hostStartsARun(seating: [seated])

        await eventually { self.viewModel.waitingForNextRun }
        XCTAssertNil(viewModel.matchToEnter, "a player who wasn't seated was sent to the board anyway")
    }

    func test_startingAGame_aFinishedMatchStopsPullingAnybodyIn() async {
        client.roomHostedBySomebodyElse()
        await viewModel.joinRoom(code: "QRTZW")
        client.hostStartsARun()
        await eventually { self.viewModel.matchToEnter != nil }

        client.runFinishes()

        await eventually { self.viewModel.matchToEnter == nil }
        XCTAssertFalse(viewModel.waitingForNextRun)
    }

    func test_startingAGame_comingBackToTheRoomDoesNotYankYouIntoTheSameMatch() async {
        client.roomHostedBySomebodyElse()
        await viewModel.joinRoom(code: "QRTZW")
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
        await viewModel.joinRoom(code: "QRTZW")
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

final class ClockTextAndSeatFormTests: XCTestCase {
    func test_clockText_isMinutesAndSeconds_roundedUp() {
        XCTAssertEqual(ClockText.text(seconds: 3), "00:03")
        XCTAssertEqual(ClockText.text(seconds: 84), "01:24")
        XCTAssertEqual(ClockText.text(ms: 1_800), "00:02")
        XCTAssertEqual(ClockText.text(ms: 0), "00:00")
        XCTAssertEqual(ClockText.text(ms: -50), "00:00")
    }

    func test_memberForm_winRateBestStreakAndRecent() {
        let player = UUID()
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        func row(_ minutes: Double, _ placement: Int) -> LobbyMatchHistoryRow {
            LobbyMatchHistoryRow(userId: player, endedAt: t.addingTimeInterval(minutes * 60), placement: placement)
        }
        // Oldest to newest: win, win, loss, win.
        let form = LobbyMemberForm.summaries(from: [row(3, 1), row(0, 1), row(2, 2), row(1, 1)])[player]
        XCTAssertEqual(form?.gamesPlayed, 4)
        XCTAssertEqual(form?.winRate, 75)
        XCTAssertEqual(form?.bestStreak, 2)
        XCTAssertEqual(form?.recent, [true, false, true])
        XCTAssertNil(LobbyMemberForm.summaries(from: [])[player])
    }
}
