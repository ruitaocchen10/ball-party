import Foundation
@testable import BallParty
import XCTest

/// `AuctionViewModel` against `FakeAuctionClient` — the single network seam.
/// Every assertion is on what a screen would show or what the app asked the
/// server for, never on how the view model arranges itself internally.
@MainActor
final class AuctionViewModelTests: XCTestCase {
    private var viewerId = UUID()
    private var client: FakeAuctionClient!
    private var viewModel: AuctionViewModel!
    private var localNow = Date(timeIntervalSince1970: 1_786_795_200)

    override func setUp() async throws {
        viewerId = UUID()
        client = FakeAuctionClient(viewerId: viewerId)
        client.serverNow = localNow
    }

    override func tearDown() async throws {
        viewModel?.stopObserving()
    }

    // MARK: - Helpers

    /// A dealt table with this viewer at it, already loaded.
    @discardableResult
    private func joinTable(
        others names: [String] = ["Sam"],
        positions: [String]? = nil,
        isHost: Bool = true,
        tokens: Int = 1
    ) async -> [UUID] {
        client.format = AuctionFormat.standard(tokenCount: tokens)
        let others = client.dealMatch(others: names, positions: positions)
        viewModel = AuctionViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId,
            roomCode: "BRZWK", isHost: isHost, now: { [unowned self] in localNow }
        )
        await viewModel.load()
        return others
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
    }

    // MARK: - The board

    func test_board_showsTheLotOnTheBlockWithItsPointsStillHidden() async {
        await joinTable()

        XCTAssertEqual(viewModel.lot?.displayName, "Player 1")
        XCTAssertNil(viewModel.lot?.points, "a lot's points were on screen before it sold")
        XCTAssertEqual(viewModel.phase, .biddingSelf)
        XCTAssertEqual(viewModel.price, 0)
        XCTAssertEqual(viewModel.seats.map(\.name), ["You", "Sam"])
    }

    func test_board_aTableDealtAfterTheScreenOpensIsPickedUp() async {
        // `start_run` opens the match and the game deals into it a moment
        // later: a screen carried in during the gap has nothing to read yet.
        client.failures["snapshot"] = AuctionServerError(message: "match_not_dealt")
        viewModel = AuctionViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId, roomCode: "BRZWK", isHost: true,
            now: { [unowned self] in localNow }
        )
        await viewModel.load()
        await eventually { self.client.isObserved }
        XCTAssertNil(viewModel.snapshot)

        // The deal landing is the first payload; re-reading on it is what turns
        // a permanently empty screen into a dealt one.
        client.failures["snapshot"] = nil
        client.dealMatch()
        client.setTurn(turnSeat: 0)

        await eventually { self.viewModel.lot != nil }
    }

    func test_board_theStripNeverShowsMoreLotsThanTheServerDealt() async {
        let others = await joinTable()
        // Two players, five slots each, dealt eight lots.
        XCTAssertEqual(viewModel.visibleLotCount, 8)

        client.lotSells(seq: 1, to: others[0], price: 3, slot: "RB", points: 14)
        client.setTurn(currentLot: 2, turnSeat: 0)
        await eventually { self.viewModel.turn?.currentLot == 2 }

        // One slot filled, nine open, lot 2 on the block: 2 + 8 — still over the
        // eight dealt, so the server's cap holds.
        XCTAssertEqual(viewModel.visibleLotCount, 8)
    }

    // MARK: - Whose move it is

    func test_turn_isOnlyActionableOnTheViewersOwnTurn() async {
        await joinTable()
        XCTAssertTrue(viewModel.canAct)

        client.setTurn(turnSeat: 1)
        await eventually { self.viewModel.phase == .biddingOther }

        XCTAssertFalse(viewModel.canAct)
        XCTAssertEqual(viewModel.blocked, .notYourTurn)
        XCTAssertEqual(viewModel.statusLine, "Waiting on another player")
        XCTAssertEqual(viewModel.onClock?.name, "Sam")
    }

    func test_turn_aFullPositionSaysWhyRatherThanJustGreyingOut() async {
        await joinTable(positions: ["QB", "QB", "RB", "WR", "TE", "RB", "WR", "TE"])
        // The viewer already holds the quarterback slot.
        client.lotSells(seq: 1, to: viewerId, price: 3, slot: "QB", points: 22.4)
        client.setTurn(currentLot: 2, turnSeat: 0)
        await eventually { self.viewModel.turn?.currentLot == 2 }

        XCTAssertEqual(viewModel.blocked, .noSlot)
        XCTAssertEqual(viewModel.statusLine, "Your QB slots are full.")
        XCTAssertFalse(viewModel.canAct)
    }

    func test_turn_aFilledNaturalSlotSpillsIntoFlex() async {
        await joinTable(positions: ["RB", "RB", "RB", "WR", "TE", "QB", "WR", "TE"])
        client.lotSells(seq: 1, to: viewerId, price: 2, slot: "RB", points: 12)
        client.setTurn(currentLot: 2, turnSeat: 0)
        await eventually { self.viewModel.turn?.currentLot == 2 }

        // Natural RB is full and FLEX is open. One RB is still undealt after
        // this one and Sam still needs exactly one, so the deck can cover him
        // — a win lands in FLEX.
        XCTAssertEqual(viewModel.targetSlot, .flex)
        XCTAssertEqual(viewModel.statusLine, "A win fills your open FLEX.")
    }

    func test_turn_aPassedLotStaysPassed() async {
        await joinTable()
        await viewModel.pass()
        client.setTurn(turnSeat: 0)
        await eventually { self.viewModel.phase == .biddingSelf }

        XCTAssertTrue(viewModel.passed)
        XCTAssertEqual(viewModel.blocked, .passed)
        XCTAssertFalse(viewModel.canAct)
    }

    func test_turn_anEmptyWalletOnlyClosesTheRaiseButtons() async {
        await joinTable()
        client.setSeat(AuctionSeat(userId: viewerId, seat: 0, budget: 0, name: "You"))
        await viewModel.reconcile()

        XCTAssertEqual(viewModel.blocked, .cannotAfford)
        XCTAssertFalse(viewModel.canRaise(by: 1))
    }

    // MARK: - Bidding

    func test_raising_sendsTheExactAmountAndShowsOnlyWhatTheServerConfirmed() async {
        await joinTable()

        await viewModel.raise(to: 5)

        XCTAssertEqual(client.placedBids, [5])
        await eventually { self.viewModel.price == 5 }
        XCTAssertEqual(viewModel.holder, viewerId)
    }

    func test_raising_aRefusalSaysWhyAndReReadsTheTable() async {
        await joinTable()
        client.failures["place_bid"] = AuctionServerError(message: "bid_not_increasing")
        let reads = client.snapshotCount

        await viewModel.raise(to: 1)

        XCTAssertEqual(viewModel.errorMessage, "Your bid must be higher than the current price.")
        XCTAssertGreaterThan(client.snapshotCount, reads, "the screen stayed on a stale board after a refusal")
        XCTAssertEqual(viewModel.price, 0)
    }

    func test_raising_anUnknownRefusalSurfacesRawRatherThanAsAFriendlyLie() async {
        await joinTable()
        client.failures["place_bid"] = AuctionServerError(message: "some_new_rule")

        await viewModel.raise(to: 1)

        XCTAssertEqual(viewModel.errorMessage, "some_new_rule")
    }

    func test_raising_cannotBeSentWhenItIsNotTheViewersTurn() async {
        await joinTable()
        client.setTurn(turnSeat: 1)
        await eventually { self.viewModel.phase == .biddingOther }

        await viewModel.raise(to: 5)

        XCTAssertTrue(client.placedBids.isEmpty)
    }

    func test_customBid_mustClearTheStandingPriceAndFitTheBudget() async {
        let others = await joinTable()
        client.anotherPlayerRaises(others[0], to: 6)
        await eventually { self.viewModel.price == 6 }

        XCTAssertEqual(viewModel.minimumBid, 7)
        XCTAssertFalse(viewModel.isValidCustomBid(6))
        XCTAssertTrue(viewModel.isValidCustomBid(7))
        XCTAssertTrue(viewModel.isValidCustomBid(25))
        XCTAssertFalse(viewModel.isValidCustomBid(26))
        XCTAssertFalse(viewModel.isValidCustomBid(nil))
    }

    func test_table_anotherPlayersRaiseShowsUpWithoutBeingAskedFor() async {
        let others = await joinTable()

        client.anotherPlayerRaises(others[0], to: 4)

        await eventually { self.viewModel.price == 4 }
        XCTAssertEqual(viewModel.holder, others[0])
        XCTAssertEqual(viewModel.status(of: viewModel.seats[1]), "High bid · $4")
    }

    func test_table_aSaleRevealsThePointsAndFillsTheWinnersRoster() async {
        let others = await joinTable()
        client.lotSells(seq: 1, to: others[0], price: 7, slot: "RB", points: 18.2)
        client.setTurn(turnSeat: nil, phase: .sold)

        await eventually { self.viewModel.phase == .sold }

        XCTAssertEqual(viewModel.lot?.points, 18.2)
        XCTAssertEqual(viewModel.points(of: viewModel.seats[1]), 18.2)
        XCTAssertEqual(viewModel.status(of: viewModel.seats[1]), "1/5 filled")
    }

    // MARK: - Free lots and the Pass token

    func test_stuck_aLotNobodyElseCanBidOnIsOfferedFreeOrDeclinedWithAToken() async {
        await joinTable(tokens: 1)
        client.setTurn(turnSeat: 0, stuckSeat: 0)
        await eventually { self.viewModel.isStuck }

        XCTAssertTrue(viewModel.isClaimable)
        XCTAssertEqual(viewModel.passState, .usable)
        XCTAssertEqual(viewModel.minimumBid, 0)

        await viewModel.spendPassToken()

        XCTAssertEqual(client.passCount, 1)
    }

    func test_stuck_withNoTokenLeftTheLotIsTheViewersForFree() async {
        await joinTable(tokens: 0)
        client.setTurn(turnSeat: 0, stuckSeat: 0)
        await eventually { self.viewModel.isStuck }

        XCTAssertEqual(viewModel.passState, .inactive)
        XCTAssertEqual(
            viewModel.statusLine,
            "Nobody else can bid on this one, and you're out of pass tokens — it's yours for $0."
        )
    }

    func test_stuck_takingTheLotFreeIsABidOfZero() async {
        await joinTable()
        client.setTurn(turnSeat: 0, stuckSeat: 0)
        await eventually { self.viewModel.isStuck }

        await viewModel.raise(to: 0)

        XCTAssertEqual(client.placedBids, [0])
    }

    func test_stuck_aBrokeOpenerMayTakeTheLotFreeOrPassItBack() async {
        await joinTable()
        client.setTurn(turnSeat: 0, freeFallbackSeat: 0)
        await eventually { self.viewModel.isFreeFallback }

        XCTAssertTrue(viewModel.isClaimable)
        XCTAssertEqual(viewModel.statusLine, "Take this lot free, or pass it back to the original opener.")
    }

    // MARK: - Scouting

    func test_scouting_showsTheViewersOwnTierAndSpendsTheToken() async {
        await joinTable()
        XCTAssertEqual(viewModel.scoutState, .usable)
        client.scoutTier = "great"

        await viewModel.scout()

        XCTAssertEqual(client.scoutCount, 1)
        XCTAssertEqual(viewModel.myHint?.tier, "great")
        XCTAssertEqual(viewModel.scoutState, .used)
    }

    func test_scouting_isOffOnceTheLotHasSold() async {
        await joinTable()
        client.setTurn(turnSeat: nil, phase: .sold)
        await eventually { self.viewModel.phase == .sold }

        XCTAssertEqual(viewModel.scoutState, .inactive)
    }

    func test_scouting_aRefusalHasItsOwnErrorAndDoesNotBlockBidding() async {
        await joinTable()
        client.failures["use_scout_token"] = AuctionServerError(message: "no_scout_tokens")

        await viewModel.scout()

        XCTAssertEqual(viewModel.scoutError, "You're out of scouting tokens.")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.canAct)
    }

    func test_tokens_aMatchWithNoneOffersNoAbilities() async {
        await joinTable(tokens: 0)

        XCTAssertEqual(viewModel.tokensLeft, 0)
        XCTAssertEqual(viewModel.scoutState, .inactive)
        XCTAssertEqual(viewModel.sealState, .inactive)
    }

    // MARK: - Sealing

    func test_sealing_isOfferedBeforeAnyBidWithARealContest() async {
        await joinTable()

        XCTAssertEqual(viewModel.sealState, .usable)

        await viewModel.seal()

        XCTAssertEqual(client.sealCount, 1)
        await eventually { self.viewModel.phase == .sealed }
    }

    func test_sealing_isOffOnceSomeoneHasBid() async {
        let others = await joinTable()
        client.anotherPlayerRaises(others[0], to: 2)
        await eventually { self.viewModel.price == 2 }

        XCTAssertEqual(viewModel.sealState, .inactive)
    }

    func test_sealing_isOffWhenNobodyElseCanBidOnTheLot() async {
        // Sam already holds the only RB slot, so the viewer would be sealing
        // against nobody.
        await joinTable(positions: ["QB", "QB", "RB", "WR", "TE", "RB", "WR", "TE"])
        client.lotSells(seq: 1, to: client.seats[1].userId, price: 1, slot: "QB", points: 9)
        client.setTurn(currentLot: 2, turnSeat: 0)
        await eventually { self.viewModel.turn?.currentLot == 2 }

        XCTAssertEqual(viewModel.sealState, .inactive)
    }

    func test_sealed_aBidIsSentOnceAndThenTheViewerWaitsOnNamedPlayers() async {
        await joinTable(others: ["Sam", "Ali"])
        await viewModel.seal()
        await eventually { self.viewModel.phase == .sealed }

        await viewModel.submitSealedBid(6)

        XCTAssertEqual(client.submittedSealedAmounts, [6])
        await eventually { self.viewModel.mySealedBid?.amount == 6 }
        XCTAssertEqual(Set(viewModel.sealedWaitingOn), ["Sam", "Ali"])

        client.anotherPlayerSubmitsASealedBid(client.seats[1].userId)
        await eventually { self.viewModel.sealedWaitingOn == ["Ali"] }

        await viewModel.submitSealedBid(9)
        XCTAssertEqual(client.submittedSealedAmounts, [6], "a second sealed bid was sent")
    }

    func test_sealed_aBidOverTheBudgetIsNeverSent() async {
        await joinTable()
        await viewModel.seal()
        await eventually { self.viewModel.phase == .sealed }

        await viewModel.submitSealedBid(26)

        XCTAssertTrue(client.submittedSealedAmounts.isEmpty)
    }

    // MARK: - Staying in step

    func test_sync_reconnectingReReadsTheWholeTable() async {
        await joinTable()
        await eventually { self.client.isObserved }
        let reads = client.snapshotCount

        client.channelSubscribes()

        await eventually { self.client.snapshotCount > reads }
    }

    func test_sync_returningToTheForegroundReReadsTheTable() async {
        await joinTable()
        let reads = client.snapshotCount

        viewModel.appReturnedToForeground()

        await eventually { self.client.snapshotCount > reads }
    }

    func test_sync_aPausedMatchRefusesMovesWithoutAsking() async {
        await joinTable()
        client.matchPauses()
        await eventually { self.viewModel.isPaused }

        await viewModel.raise(to: 5)

        XCTAssertTrue(client.placedBids.isEmpty)
        XCTAssertEqual(viewModel.statusLine, "The host paused the game.")
    }

    func test_sync_aRedrawnLotAppendsToTheDeck() async {
        await joinTable()
        let redraw = AuctionLot(seq: 9, displayName: "Redrawn", position: "WR", season: 2020, team: "SF")

        client.emit(.lot(redraw))

        await eventually { self.viewModel.lots.contains { $0.seq == 9 } }
    }

    func test_sync_aSeatUpdateKeepsTheNameItAlreadyHad() async {
        await joinTable()
        let sam = client.seats[1]

        // A replicated row carries no profile.
        client.emit(.seat(AuctionSeat(userId: sam.userId, seat: sam.seat, budget: 11)))

        await eventually { self.viewModel.seats[1].budget == 11 }
        XCTAssertEqual(viewModel.seats[1].name, "Sam")
    }

    // MARK: - The ending

    func test_ending_theMatchEndsTheMomentTheStatusSaysSoAndReReadsForTheFinalBoard() async {
        let others = await joinTable()
        client.lotSells(seq: 1, to: others[0], price: 3, slot: "RB", points: 14)
        client.setStandings([
            MatchStanding(userId: others[0], placement: 1, rawScore: 14),
            MatchStanding(userId: viewerId, placement: 2, rawScore: 0),
        ])
        let reads = client.snapshotCount

        client.matchEnds()

        await eventually { self.viewModel.isFinished }
        await eventually { self.viewModel.finalStandings.count == 2 }
        XCTAssertGreaterThan(client.snapshotCount, reads, "the final board was never re-read")
        XCTAssertEqual(viewModel.headline, "Sam wins")
        XCTAssertEqual(viewModel.finalStandings.map(\.rank), [1, 2])
        XCTAssertEqual(viewModel.finalStandings.first?.points, 14)
        XCTAssertEqual(viewModel.finalStandings.last?.isViewer, true)
    }

    func test_ending_theDeckRunningOutEndsItToo() async {
        await joinTable()

        client.setTurn(currentLot: 9, turnSeat: nil, phase: .sold)

        await eventually { self.viewModel.isFinished }
    }

    func test_ending_aTieNamesEveryone() async {
        let others = await joinTable()
        client.setStandings([
            MatchStanding(userId: viewerId, placement: 1, rawScore: 30),
            MatchStanding(userId: others[0], placement: 1, rawScore: 30),
        ])
        client.matchEnds()
        await eventually { self.viewModel.finalStandings.count == 2 }

        // Both names, in whichever order the tie sorted them.
        XCTAssertTrue(viewModel.headline.hasSuffix(" tie"))
        XCTAssertTrue(viewModel.headline.contains("You") && viewModel.headline.contains("Sam"))
    }

    func test_ending_onlyTheHostChoosesWhatIsNextAndOnlyOnce() async {
        await joinTable(isHost: true)
        client.matchEnds()
        await eventually { self.viewModel.canChoosePostGame }

        await viewModel.choosePostGame(.replay)

        XCTAssertEqual(client.postGameChoices, [.replay])
        XCTAssertEqual(viewModel.postGameAction?.choice, .replay)
        XCTAssertFalse(viewModel.canChoosePostGame, "a second choice was offered")
    }

    func test_ending_aGuestOfTheRoomIsNotOfferedTheChoice() async {
        await joinTable(isHost: false)
        client.matchEnds()
        await eventually { self.viewModel.isFinished }

        XCTAssertFalse(viewModel.canChoosePostGame)
        await viewModel.choosePostGame(.lobby)
        XCTAssertTrue(client.postGameChoices.isEmpty)
    }

    func test_ending_theHostsChoiceReachesEverybodyElse() async {
        await joinTable(isHost: false)
        client.matchEnds()
        await eventually { self.viewModel.isFinished }

        client.hostChooses(.lobby)

        await eventually { self.viewModel.postGameAction?.choice == .lobby }
    }
}
