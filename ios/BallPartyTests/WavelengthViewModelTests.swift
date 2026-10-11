import Foundation
@testable import BallParty
import XCTest

/// `WavelengthViewModel` against `FakeWavelengthClient` — the single network
/// seam. Every assertion is on what a screen would show or what the app asked
/// the server for.
@MainActor
final class WavelengthViewModelTests: XCTestCase {
    private var viewerId = UUID()
    private var client: FakeWavelengthClient!
    private var viewModel: WavelengthViewModel!
    private var localNow = Date(timeIntervalSince1970: 1_786_795_200)

    override func setUp() async throws {
        viewerId = UUID()
        client = FakeWavelengthClient(viewerId: viewerId)
        client.serverNow = localNow
    }

    override func tearDown() async throws {
        viewModel?.stopObserving()
    }

    // MARK: - Helpers

    @discardableResult
    private func joinTable(isHost: Bool = true) async -> UUID {
        let partner = client.dealCoop()
        viewModel = WavelengthViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId,
            roomCode: "BRZWK", isHost: isHost, now: { [unowned self] in localNow },
            revealDuration: .milliseconds(300)
        )
        await viewModel.load()
        return partner
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        // Time-based: a screen's reads cross several async hops that a yield
        // loop can burn through before they land.
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(for: .milliseconds(2)) }
        XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
    }

    // MARK: - Fill phase

    func test_fill_thePsychicSeesTheirOwnCardAndTargetAndWritesTheFirstRoundFirst() async {
        await joinTable()

        XCTAssertEqual(viewModel.board?.phase, .fill)
        XCTAssertTrue(viewModel.canFill)
        XCTAssertEqual(viewModel.fillRound?.round, 1)
        XCTAssertEqual(viewModel.fillCard?.leftLabel, "Cold 1")
        XCTAssertEqual(viewModel.fillTarget, 500)
        XCTAssertEqual(viewModel.fillTotal, 2)
        XCTAssertEqual(viewModel.fillWritten, 0)
    }

    func test_fill_submittingAClueMovesOnToTheNextOfTheViewersRounds() async {
        await joinTable()
        viewModel.clueDraft = "A cold tailgate"
        await viewModel.submitClue()

        XCTAssertEqual(client.submittedClues.first?.round, 1)
        XCTAssertEqual(client.submittedClues.first?.clue, "A cold tailgate")
        XCTAssertEqual(viewModel.clueDraft, "", "the draft was kept after it was sent")
        XCTAssertEqual(viewModel.fillRound?.round, 3)
        XCTAssertEqual(viewModel.fillWritten, 1)
    }

    func test_fill_aBadClueIsRefusedBeforeTheServerIsAsked() async {
        await joinTable()
        viewModel.clueDraft = "Gronk 87"
        await viewModel.submitClue()

        XCTAssertTrue(client.submittedClues.isEmpty)
        XCTAssertEqual(viewModel.errorMessage, "Clues cannot contain digits.")
    }

    func test_fill_aServerRefusalIsShownInPlainWords() async {
        await joinTable()
        client.failures["submit_clue"] = WavelengthServerError(message: "clue_deadline_passed")
        viewModel.clueDraft = "Late clue"
        await viewModel.submitClue()

        XCTAssertEqual(viewModel.errorMessage, "Time ran out before that clue landed.")
    }

    func test_fill_afterWritingEveryClueThereIsNothingLeftToWrite() async {
        await joinTable()
        viewModel.clueDraft = "First"
        await viewModel.submitClue()
        viewModel.clueDraft = "Second"
        await viewModel.submitClue()

        XCTAssertFalse(viewModel.canFill)
        XCTAssertEqual(viewModel.fillWritten, 2)
    }

    func test_fill_theTableSeesThatAClueExistsButNotWhatItSays() async {
        let partner = await joinTable()
        client.anotherPlayerWritesClue(round: 2)
        await eventually { self.viewModel.snapshot?.clueStatuses.contains { $0.round == 2 } == true }

        let sam = viewModel.player(partner)!
        XCTAssertNil(viewModel.snapshot?.clues.first { $0.round == 2 })
        XCTAssertEqual(viewModel.status(of: sam).text, "Writing…", "one of two clues written is still writing")
    }

    // MARK: - Guess phase

    func test_guess_theGuesserSeesTheClueAndNoTarget() async {
        await joinTable()
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }

        XCTAssertTrue(viewModel.isGuesser)
        XCTAssertFalse(viewModel.isPsychic)
        XCTAssertEqual(viewModel.currentClue, "Clue 2")
        XCTAssertNil(viewModel.currentTarget, "the target was readable by the guesser")
        XCTAssertTrue(viewModel.canLock)
    }

    func test_guess_thePsychicSeesTheirTargetAndCannotLock() async {
        await joinTable()
        client.beginGuessing(round: 1)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }

        XCTAssertTrue(viewModel.isPsychic)
        XCTAssertEqual(viewModel.currentTarget, 500)
        XCTAssertFalse(viewModel.canLock)
    }

    func test_guess_everyRoundStartsWithTheNeedleInTheMiddle() async {
        await joinTable()
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }
        viewModel.moveNeedle(to: 800)
        XCTAssertEqual(viewModel.needle, 800)

        client.roundSettles(round: 2, position: 800)
        await eventually { self.viewModel.board?.phase == .reveal }
        client.beginGuessing(round: 3)
        await eventually { self.viewModel.board?.currentRound == 3 }

        XCTAssertEqual(viewModel.needle, WavelengthRules.needleStart)
    }

    func test_guess_lockingSendsTheNeedlePositionAndShowsTheScore() async {
        await joinTable()
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }
        viewModel.moveNeedle(to: 590)
        await viewModel.lockGuess()

        XCTAssertEqual(client.lockedGuesses.first?.round, 2)
        XCTAssertEqual(client.lockedGuesses.first?.position, 590)
        // Target for round 2 is 600; 10 away is a bullseye.
        XCTAssertEqual(viewModel.current?.points, 4)
        XCTAssertEqual(viewModel.current?.revealedTarget, 600)
        XCTAssertEqual(viewModel.board?.phase, .reveal)
        XCTAssertEqual(viewModel.board?.teamScores, [4])
    }

    func test_guess_theNeedleIsBroadcastButOnlyByTheGuesser() async {
        await joinTable()
        client.beginGuessing(round: 1)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }
        // The viewer is round 1's psychic, not its guesser.
        viewModel.moveNeedle(to: 300)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(client.sentNeedles.isEmpty)

        client.roundSettles(round: 1, position: 300)
        await eventually { self.viewModel.board?.phase == .reveal }
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.currentRound == 2 }
        viewModel.moveNeedle(to: 310)
        await eventually { !self.client.sentNeedles.isEmpty }
        XCTAssertEqual(client.sentNeedles.first?.round, 2)
        XCTAssertEqual(client.sentNeedles.first?.position, 310)
    }

    func test_guess_broadcastsAreThrottled() async {
        await joinTable()
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }
        for position in stride(from: 100, through: 900, by: 50) {
            viewModel.moveNeedle(to: position)
        }
        await eventually { !self.client.sentNeedles.isEmpty }
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(client.sentNeedles.count, 1, "a drag within one interval sent more than one update")
    }

    func test_guess_aSpectatorFollowsTheGuessersNeedleAndIgnoresStaleRounds() async {
        await joinTable()
        client.beginGuessing(round: 1)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }

        client.needleMoves(round: 1, to: 640)
        await eventually { self.viewModel.needle == 640 }

        client.needleMoves(round: 7, to: 10)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.needle, 640)
    }

    func test_guess_theGuessersOwnNeedleIsNeverOverwrittenByABroadcast() async {
        await joinTable()
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }
        viewModel.moveNeedle(to: 420)

        client.needleMoves(round: 2, to: 900)
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.needle, 420)
    }

    func test_guess_aRefusedLockPutsTheScreenBackOnTheServersTruth() async {
        await joinTable()
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }
        client.failures["lock_guess"] = WavelengthServerError(message: "guess_deadline_passed")
        let before = client.snapshotCount
        await viewModel.lockGuess()

        XCTAssertEqual(viewModel.errorMessage, "Time ran out before that guess landed.")
        XCTAssertGreaterThan(client.snapshotCount, before)
    }

    // MARK: - Reveal

    func test_reveal_aRoundThatSettlesIsShownForAMomentThenCleared() async {
        await joinTable()
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }
        client.roundSettles(round: 2, position: 600)
        await eventually { self.viewModel.revealRound == 2 }

        await eventually { self.viewModel.revealRound == nil }
    }

    func test_reveal_roundsAlreadySettledWhenTheScreenOpensAreNotReplayed() async {
        client.dealCoop()
        client.beginGuessing(round: 2)
        client.roundSettles(round: 2, position: 600)
        viewModel = WavelengthViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId, now: { [unowned self] in localNow }
        )
        await viewModel.load()

        XCTAssertNil(viewModel.revealRound)
    }

    // MARK: - The table

    func test_table_statusLinesNameWhatEachPlayerIsDoing() async {
        let partner = await joinTable()
        let sam = viewModel.player(partner)!
        let me = viewModel.player(viewerId)!
        client.beginGuessing(round: 2)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }

        // Sam is round 2's psychic; the viewer guesses.
        XCTAssertEqual(viewModel.status(of: sam).text, "Clue locked")
        XCTAssertTrue(viewModel.status(of: sam).concealed, "a hidden clue read as revealed")
        XCTAssertEqual(viewModel.status(of: me).text, "Guessing now")
    }

    // MARK: - The clock

    func test_clock_countsDownTheGuessDeadline() async {
        await joinTable()
        client.beginGuessing(round: 2, guessSeconds: 60)
        await eventually { self.viewModel.board?.phase == .guess && self.viewModel.currentCard != nil }

        let remaining = viewModel.clock.remainingMs ?? 0
        // 60s less the half-second the visible clock ends early.
        XCTAssertEqual(remaining, 59_500)
        XCTAssertNotNil(viewModel.clockFraction)
    }

    func test_clock_theFillPhaseGivesNinetySecondsPerClue() async {
        client.dealCoop(fillSeconds: 180)
        viewModel = WavelengthViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId, now: { [unowned self] in localNow }
        )
        await viewModel.load()

        XCTAssertEqual(viewModel.clock.remainingMs, 180_000)
    }

    // MARK: - Pausing and ending

    func test_pause_closesTheControls() async {
        await joinTable()
        client.matchPauses()
        await eventually { self.viewModel.isPaused }

        XCTAssertFalse(viewModel.canFill)
    }

    func test_ending_theResultIsReadAndTheHostMayChooseWhatIsNext() async {
        await joinTable()
        let result = WavelengthResult(mode: .coop, preset: .short, outcome: "win", score: 11, bullseyes: 2, stars: 1)
        client.matchEnds(result: result)
        await eventually { self.viewModel.isFinished }
        await eventually { self.viewModel.result != nil }

        XCTAssertEqual(viewModel.result, result)
        XCTAssertTrue(viewModel.canChoosePostGame)
        await viewModel.choosePostGame(.replay)
        XCTAssertEqual(client.postGameChoices, [.replay])
        XCTAssertNotNil(viewModel.postGameAction)
    }

    func test_ending_onlyTheHostChoosesWhatIsNext() async {
        await joinTable(isHost: false)
        client.matchEnds(result: WavelengthResult(mode: .coop, preset: .short, outcome: "lose", score: 3, bullseyes: 0, stars: 0))
        await eventually { self.viewModel.isFinished }

        XCTAssertFalse(viewModel.canChoosePostGame)
        await viewModel.choosePostGame(.lobby)
        XCTAssertTrue(client.postGameChoices.isEmpty)
    }
}
