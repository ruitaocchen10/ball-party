import Foundation
@testable import BallParty
import XCTest

/// `SabotageViewModel` against `FakeSabotageClient` — the single network seam.
/// Every assertion is on what a screen would show or what the app asked the
/// server for.
@MainActor
final class SabotageViewModelTests: XCTestCase {
    private var viewerId = UUID()
    private var client: FakeSabotageClient!
    private var viewModel: SabotageViewModel!
    private var localNow = Date(timeIntervalSince1970: 1_786_795_200)

    override func setUp() async throws {
        viewerId = UUID()
        client = FakeSabotageClient(viewerId: viewerId)
        client.serverNow = localNow
    }

    override func tearDown() async throws {
        viewModel?.stopObserving()
    }

    // MARK: - Helpers

    /// Joins a three-seat quick match with `activeSeat` on the clock (0 is the viewer).
    private func joinTable(activeSeat: Int = 0, isHost: Bool = true) async {
        client.deal(activeSeat: activeSeat)
        viewModel = SabotageViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId,
            roomCode: "BRZWK", isHost: isHost, now: { [unowned self] in localNow }
        )
        await viewModel.load()
        await eventually { !viewModel.pool.isEmpty }
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        // Time-based: a screen's reads cross several async hops that a yield
        // loop can burn through before they land.
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
    }

    private var alpha: SabotageOption { client.pool[0] }

    // MARK: - Loading

    func test_load_readsTheBoardAndWhoIsOnTheClock() async {
        await joinTable(activeSeat: 1)

        XCTAssertEqual(viewModel.board?.currentRound, 1)
        XCTAssertEqual(viewModel.mode, .quick)
        XCTAssertEqual(viewModel.players.map(\.name), ["You", "Maya", "Dana"])
        XCTAssertEqual(viewModel.activePlayer?.name, "Maya")
        XCTAssertFalse(viewModel.isActive)
        XCTAssertTrue(viewModel.turnOpen)
        XCTAssertEqual(viewModel.activeSpin?.franchiseCode, "nwe")
        XCTAssertFalse(viewModel.isFinished)
    }

    func test_pool_isTheViewersOwnWhileDraftingAndTheDrafterWhileGuessing() async {
        await joinTable(activeSeat: 0)
        XCTAssertEqual(client.optionCalls.count, 1)
        XCTAssertNil(client.optionCalls[0], "no target asks for the caller's own spin")

        viewModel.stopObserving()
        client = FakeSabotageClient(viewerId: viewerId)
        client.serverNow = localNow
        await joinTable(activeSeat: 1)
        XCTAssertEqual(client.optionCalls.first, client.maya, "a guess is read against the drafter's spin")
    }

    func test_turnLabel_followsWhoIsDraftingAndWhetherTheTurnIsOpen() async {
        await joinTable(activeSeat: 0)
        XCTAssertEqual(viewModel.turnLabel, "Your pick")

        viewModel.stopObserving()
        client = FakeSabotageClient(viewerId: viewerId)
        client.serverNow = localNow
        await joinTable(activeSeat: 2)
        XCTAssertEqual(viewModel.turnLabel, "Sabotage Dana")
    }

    // MARK: - Picking

    func test_pick_needsAChoiceAndThenLocksIt() async {
        await joinTable(activeSeat: 0)
        XCTAssertFalse(viewModel.canLockPick)

        viewModel.pickChoice = alpha
        XCTAssertTrue(viewModel.canLockPick)
        await viewModel.lockPick()

        XCTAssertEqual(client.submittedPicks.first?.playerId, "a")
        XCTAssertEqual(client.submittedPicks.first?.season, 2021)
        XCTAssertEqual(viewModel.myPick?.name, "Alpha Back")
        XCTAssertEqual(viewModel.myFilledCount, 1)
        XCTAssertFalse(viewModel.canLockPick, "a locked pick cannot be locked again")
    }

    func test_pick_refusedWhenItIsNotTheViewersTurn() async {
        await joinTable(activeSeat: 1)
        viewModel.pickChoice = alpha

        XCTAssertFalse(viewModel.canLockPick)
        await viewModel.lockPick()
        XCTAssertTrue(client.submittedPicks.isEmpty)
    }

    func test_pick_aServerRefusalIsShownAndTheBoardIsReRead() async {
        await joinTable(activeSeat: 0)
        client.failures["submit_pick"] = SabotageServerError(message: "invalid_pick")
        viewModel.pickChoice = alpha
        let before = client.snapshotCount

        await viewModel.lockPick()

        XCTAssertEqual(viewModel.errorMessage, "Choose a player from this round's pool.")
        XCTAssertGreaterThan(client.snapshotCount, before)
        XCTAssertNil(viewModel.myPick)
    }

    // MARK: - Guessing

    func test_guess_aPlayerOnlyGuessSendsNoYear() async {
        await joinTable(activeSeat: 1)
        viewModel.chooseGuessKind(.player)
        XCTAssertFalse(viewModel.canLockGuess, "nothing chosen yet")

        viewModel.chooseGuess(alpha)
        XCTAssertTrue(viewModel.canLockGuess)
        await viewModel.lockGuess()

        XCTAssertEqual(client.submittedGuesses.count, 1)
        XCTAssertEqual(client.submittedGuesses[0].playerId, "a")
        XCTAssertNil(client.submittedGuesses[0].season, "a name-only guess never names a year")
        XCTAssertNil(client.submittedGuesses[0].replacement)
        XCTAssertTrue(viewModel.hasActed)
    }

    func test_guess_anExactGuessNeedsAReplacementAndSendsBoth() async {
        await joinTable(activeSeat: 2)
        viewModel.chooseGuessKind(.exact)
        viewModel.chooseGuess(alpha)
        XCTAssertFalse(viewModel.canLockGuess, "an exact guess also needs the replacement it would assign")

        viewModel.replacementChoice = client.pool[3]
        XCTAssertTrue(viewModel.canLockGuess)
        await viewModel.lockGuess()

        XCTAssertEqual(client.submittedGuesses[0].season, 2021)
        XCTAssertEqual(client.submittedGuesses[0].replacement?.playerId, "b")
        XCTAssertEqual(client.submittedGuesses[0].replacement?.season, 2015)
    }

    func test_guess_changingTheGuessRestartsTheReplacement() async {
        await joinTable(activeSeat: 1)
        viewModel.chooseGuessKind(.exact)
        viewModel.chooseGuess(alpha)
        viewModel.replacementChoice = client.pool[3]

        viewModel.chooseGuess(client.pool[5])
        XCTAssertNil(viewModel.replacementChoice, "the replacement answered a question that is being redone")

        viewModel.chooseGuessKind(.player)
        XCTAssertNil(viewModel.guessChoice)
    }

    func test_pass_isTheSameOneActionAsAGuess() async {
        await joinTable(activeSeat: 1)
        await viewModel.pass()

        XCTAssertEqual(client.passCount, 1)
        XCTAssertNotNil(viewModel.myPass)
        XCTAssertTrue(viewModel.hasActed)
        XCTAssertFalse(viewModel.canGuess, "a pass spends the turn's action")
        XCTAssertEqual(viewModel.seatsStillToAct.map(\.name), ["Dana"])
    }

    func test_guess_isSpentPerTurnNotPerRound() async {
        await joinTable(activeSeat: 1)
        await viewModel.pass()
        XCTAssertTrue(viewModel.hasActed)

        client.advanceTurn()
        await eventually { viewModel.activePlayer?.name == "Dana" }

        XCTAssertFalse(viewModel.hasActed, "the same player gets a fresh shot on every seat's turn")
        XCTAssertTrue(viewModel.canGuess)
    }

    func test_guess_cannotBeMadeOnTheViewersOwnTurn() async {
        await joinTable(activeSeat: 0)
        XCTAssertFalse(viewModel.canGuess)
        await viewModel.pass()
        XCTAssertEqual(client.passCount, 0)
    }

    // MARK: - Turns

    func test_aNewTurnClearsHalfMadeMovesAndReloadsThePool() async {
        await joinTable(activeSeat: 1)
        viewModel.chooseGuessKind(.exact)
        viewModel.chooseGuess(alpha)
        viewModel.replacementChoice = client.pool[3]
        viewModel.pickChoice = alpha
        let loads = client.optionCalls.count

        client.advanceTurn()
        await eventually { viewModel.activePlayer?.name == "Dana" }
        await eventually { client.optionCalls.count > loads }

        XCTAssertNil(viewModel.guessKind)
        XCTAssertNil(viewModel.guessChoice)
        XCTAssertNil(viewModel.replacementChoice)
        XCTAssertNil(viewModel.pickChoice)
        XCTAssertEqual(client.optionCalls.last, client.dana)
    }

    func test_realtimeChangeReReadsTheBoard() async {
        await joinTable(activeSeat: 1)
        let before = client.snapshotCount

        client.anotherPlayerLocksPick(client.maya)

        await eventually { client.snapshotCount > before }
        XCTAssertEqual(viewModel.filledCount(of: viewModel.players[1]), 1)
    }

    func test_pausingTheMatchStopsMoves() async {
        await joinTable(activeSeat: 1)
        XCTAssertTrue(viewModel.canGuess)

        client.matchPauses()
        await eventually { viewModel.isPaused }
        XCTAssertFalse(viewModel.canGuess)
    }

    // MARK: - What the viewer may see

    func test_rosters_ownPickIsReadableAndOthersAreConcealedWithTheirFranchise() async {
        client.viewerHasPick(round: 1)
        client.anotherPlayerLocksPick(client.maya, round: 1)
        await joinTable(activeSeat: 0)
        let me = viewModel.players[0], maya = viewModel.players[1], dana = viewModel.players[2]

        if case .pick(let pick) = viewModel.cell(for: me, round: 1).cell {
            XCTAssertEqual(pick.name, "Mine Back")
        } else {
            XCTFail("the viewer's own pick should be readable")
        }
        XCTAssertEqual(viewModel.cell(for: maya, round: 1).cell, .concealed(franchise: "nwe"))
        XCTAssertEqual(viewModel.cell(for: dana, round: 1).cell, .upNext)
    }

    func test_rosters_aSeatYetToDraftReadsChoosingThenUpNextThenNotReached() async {
        await joinTable(activeSeat: 1)
        let me = viewModel.players[0], maya = viewModel.players[1], dana = viewModel.players[2]

        XCTAssertEqual(viewModel.cell(for: maya, round: 1).cell, .choosing)
        XCTAssertEqual(viewModel.cell(for: dana, round: 1).cell, .upNext)
        XCTAssertEqual(viewModel.cell(for: me, round: 2).cell, .notReached)
    }

    func test_rosters_hitsAreFlaggedOnTheRoundTheyLanded() async {
        client.hit(.respin, on: viewerId, round: 1)
        client.hit(.sabotage, on: viewerId, round: 1)
        await joinTable(activeSeat: 0)
        let me = viewModel.players[0]

        let value = viewModel.cell(for: me, round: 1)
        XCTAssertTrue(value.respun)
        XCTAssertTrue(value.sabotaged)
        XCTAssertEqual(viewModel.hitCount(on: me), 2)
        XCTAssertFalse(viewModel.cell(for: me, round: 2).respun)
    }

    // MARK: - The log

    func test_log_listsFinishedTurnsNewestFirstWithWhatHappenedToEach() async {
        client.resolvedPick(user: viewerId, round: 1, name: "Mine Back", season: 2018)
        client.recordPass(by: client.maya, on: viewerId, round: 1)
        client.recordGuess(by: client.dana, on: viewerId, round: 1, season: nil, result: .miss)
        client.resolvedPick(user: client.maya, round: 1, name: "Maya Pick", season: 2012)
        client.hit(.respin, on: client.maya, round: 1)
        client.recordGuess(by: viewerId, on: client.maya, round: 1, season: nil, result: .respun)
        client.recordPass(by: client.dana, on: client.maya, round: 1)
        await joinTable(activeSeat: 2)

        let log = viewModel.turnLog
        XCTAssertEqual(log.map(\.drafter.name), ["Maya", "You"], "newest turn first; Dana's is still open")
        XCTAssertEqual(log[0].outcome, "Respun")
        XCTAssertEqual(log[1].outcome, "Kept")
        XCTAssertEqual(log[0].actions.map(\.kind), [.guess, .pass])
        XCTAssertEqual(log[0].actions[0].result, .respun)
        XCTAssertEqual(log[1].actions.map(\.player.name), ["Maya", "Dana"], "actions follow seat order")
    }

    func test_log_isEmptyOnTheFirstTurn() async {
        await joinTable(activeSeat: 0)
        XCTAssertTrue(viewModel.turnLog.isEmpty)
    }

    // MARK: - X-Factor

    func test_xFactor_offersTheSlotsMatchingThePicksPosition() async {
        client.viewerHasPick(round: 7, name: "Mine Back", season: 2018)
        // A pick the pool knows as an RB.
        client.pool.append(SabotageOption(playerId: "m", name: "Mine Back", season: 2018, category: "RB"))
        await joinTable(activeSeat: 0)
        client.openXFactor(round: 7)
        await eventually { viewModel.board?.xFactorOpen == true }

        XCTAssertTrue(viewModel.canDecideXFactor)
        XCTAssertEqual(viewModel.xFactorSlots, ["RB1", "FLEX"])

        await viewModel.decideXFactor(replacing: "RB1")
        XCTAssertEqual(client.submittedDecisions, ["RB1"])
        XCTAssertEqual(viewModel.myDecision?.replaceSlot, "RB1")
        XCTAssertFalse(viewModel.canDecideXFactor, "the decision is made once")
    }

    func test_xFactor_canBeDiscarded() async {
        await joinTable(activeSeat: 0)
        client.openXFactor(round: 7)
        await eventually { viewModel.board?.xFactorOpen == true }

        await viewModel.decideXFactor(replacing: nil)
        XCTAssertEqual(client.submittedDecisions.count, 1)
        XCTAssertNil(client.submittedDecisions[0])
        XCTAssertNil(viewModel.myDecision?.replaceSlot)
    }

    // MARK: - The ending

    func test_finish_ranksByWinsThenTheTiebreak() async {
        await joinTable(activeSeat: 0)
        let maya = client.maya
        client.seasonEnds([
            SabotageStanding(userId: viewerId, rosterStrength: 90, wins: 11, losses: 6, tiebreakRank: 2),
            SabotageStanding(userId: maya, rosterStrength: 95, wins: 11, losses: 6, tiebreakRank: 1),
            SabotageStanding(userId: client.dana, rosterStrength: 70, wins: 8, losses: 9, tiebreakRank: 1),
        ])
        await eventually { viewModel.isFinished }

        XCTAssertEqual(viewModel.rankedStandings.map(\.userId), [maya, viewerId, client.dana])
    }

    func test_finish_onlyTheHostChoosesWhatIsNext() async {
        await joinTable(activeSeat: 0, isHost: true)
        client.seasonEnds([SabotageStanding(userId: viewerId, rosterStrength: 90, wins: 11, losses: 6, tiebreakRank: 1)])
        await eventually { viewModel.isFinished }

        XCTAssertTrue(viewModel.canChoosePostGame)
        await viewModel.choosePostGame(.replay)
        XCTAssertEqual(client.postGameChoices, [.replay])
        XCTAssertNotNil(viewModel.postGameAction)
        XCTAssertFalse(viewModel.canChoosePostGame, "already chosen")
    }

    func test_finish_aGuestCannotChooseWhatIsNext() async {
        await joinTable(activeSeat: 0, isHost: false)
        client.seasonEnds([SabotageStanding(userId: viewerId, rosterStrength: 90, wins: 11, losses: 6, tiebreakRank: 1)])
        await eventually { viewModel.isFinished }

        XCTAssertFalse(viewModel.canChoosePostGame)
        await viewModel.choosePostGame(.lobby)
        XCTAssertTrue(client.postGameChoices.isEmpty)
    }
}
