import Foundation
@testable import BallParty
import XCTest

/// `SoloRunViewModel` against `FakeHigherOrLowerClient` — the single network
/// seam. Every assertion is on what a screen would show or what the app asked
/// the server for, never on how the view model arranges itself internally.
@MainActor
final class SoloRunViewModelTests: XCTestCase {
    private var viewerId = UUID()
    private var client: FakeHigherOrLowerClient!
    private var viewModel: SoloRunViewModel!
    /// A controllable local clock, for the timed-path tests.
    private var localNow = Date(timeIntervalSince1970: 1_786_795_200)

    override func setUp() async throws {
        viewerId = UUID()
        client = FakeHigherOrLowerClient(viewerId: viewerId)
        viewModel = SoloRunViewModel(client: client, viewerId: viewerId, now: { [unowned self] in localNow })
    }

    override func tearDown() async throws {
        viewModel.clock.stop()
    }

    // MARK: - Helpers

    private func startRun() async {
        await viewModel.loadSetup()
        await viewModel.start()
    }

    private var question: Int { viewModel.board?.currentQuestion ?? 0 }

    private func callCorrectly() async {
        await viewModel.call(client.correctDirection(forQuestion: question))
    }

    private func callWrongly() async {
        await viewModel.call(client.wrongDirection(forQuestion: question))
    }

    /// One correct call and the tap on Continue.
    private func climb() async {
        await callCorrectly()
        await viewModel.continueRun()
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
    }

    // MARK: - Choosing a format

    func test_setup_loadsTheEraLimitsAndDefaultsToTheWholePool() async {
        client.bounds = SeasonRange(from: 2010, to: 2025)
        await viewModel.loadSetup()

        XCTAssertEqual(viewModel.stage, .setup)
        XCTAssertEqual(viewModel.seasonFrom, 2010)
        XCTAssertEqual(viewModel.seasonTo, 2025)
        XCTAssertEqual(viewModel.seasonChoices.first, 2010)
        XCTAssertEqual(viewModel.seasonChoices.last, 2025)
        XCTAssertEqual(viewModel.scoringMode, .seasonTotal)
    }

    func test_setup_reloadingDoesNotOverwriteAChoiceThePlayerMade() async {
        await viewModel.loadSetup()
        viewModel.seasonFrom = 2020
        await viewModel.loadSetup()

        XCTAssertEqual(viewModel.seasonFrom, 2020)
    }

    func test_setup_movingTheFirstSeasonPastTheLastDragsTheLastAlong() async {
        await viewModel.loadSetup()
        viewModel.seasonTo = 2015
        viewModel.seasonFrom = 2020

        XCTAssertEqual(viewModel.seasonTo, 2020)
    }

    func test_setup_movingTheLastSeasonBeforeTheFirstDragsTheFirstAlong() async {
        await viewModel.loadSetup()
        viewModel.seasonFrom = 2020
        viewModel.seasonTo = 2015

        XCTAssertEqual(viewModel.seasonFrom, 2015)
    }

    func test_setup_cannotStartUntilTheEraLimitsHaveLoaded() {
        XCTAssertFalse(viewModel.canStart)
    }

    func test_setup_aFailedLimitsLoadShowsAnError() async {
        client.failures["season_bounds"] = HigherOrLowerServerError(message: "boom")
        await viewModel.loadSetup()

        XCTAssertEqual(viewModel.errorMessage, "boom")
        XCTAssertFalse(viewModel.canStart)
    }

    func test_start_asksForTheChosenScoringModeAndEra() async {
        await viewModel.loadSetup()
        viewModel.scoringMode = .weekly
        viewModel.seasonFrom = 2018
        viewModel.seasonTo = 2022
        await viewModel.start()

        XCTAssertEqual(client.startCalls.count, 1)
        XCTAssertEqual(client.startCalls.first?.scoringMode, .weekly)
        XCTAssertEqual(client.startCalls.first?.era, SeasonRange(from: 2018, to: 2022))
        XCTAssertEqual(viewModel.formatLabel, "Weekly · 2018–2022")
    }

    func test_start_aServerRefusalShowsItsMessageAndStaysOnTheSetupScreen() async {
        await viewModel.loadSetup()
        client.failures["start"] = HigherOrLowerServerError(message: "season_out_of_range")
        await viewModel.start()

        XCTAssertEqual(viewModel.stage, .setup)
        XCTAssertEqual(viewModel.errorMessage, "That era is outside the seasons we have data for.")
    }

    // MARK: - The core call loop

    func test_playing_showsTheAnchorsPointsAndKeepsTheChallengersHidden() async {
        await startRun()

        XCTAssertEqual(viewModel.stage, .playing)
        XCTAssertEqual(viewModel.questionLabel, "Question 1")
        XCTAssertEqual(viewModel.anchor?.points, client.points(ofOrdinal: 0))
        XCTAssertNotNil(viewModel.challenger)
        XCTAssertNil(viewModel.challenger?.points)
        XCTAssertNil(viewModel.currentOutcome)
        XCTAssertTrue(viewModel.canCall)
    }

    func test_playing_aChallengerRowThatRacedAheadOfItsRevealStaysConcealed() async {
        // The card row carries points while the board still says "call": the
        // phase is the permission to display them, not the row.
        client.leaksChallengerPoints = true
        await startRun()

        XCTAssertEqual(viewModel.board?.phase, .call)
        XCTAssertNil(viewModel.challenger?.points)
    }

    func test_calling_correctlyRevealsTheChallengerAndCountsTheAnswer() async {
        await startRun()
        await callCorrectly()

        XCTAssertEqual(viewModel.challenger?.points, client.points(ofOrdinal: 1))
        XCTAssertEqual(viewModel.currentOutcome, .correct(client.correctDirection(forQuestion: 1)))
        XCTAssertEqual(viewModel.correctCount, 1)
        XCTAssertEqual(viewModel.currentStreak, 1)
        XCTAssertTrue(viewModel.currentOutcome?.isCorrect == true)
    }

    func test_calling_locksTheButtonsUntilTheNextQuestion() async {
        await startRun()
        await callCorrectly()

        XCTAssertFalse(viewModel.canCall)
        XCTAssertNotNil(viewModel.myCall)
        XCTAssertTrue(viewModel.canContinue)
    }

    func test_calling_sendsTheDirectionTheOwnerChose() async {
        await startRun()
        await viewModel.call(.lower)

        XCTAssertEqual(client.callDirections, [.lower])
    }

    func test_continuing_promotesTheChallengerToTheNextAnchor() async {
        await startRun()
        await callCorrectly()
        let revealedChallenger = viewModel.challenger
        await viewModel.continueRun()

        XCTAssertEqual(viewModel.questionLabel, "Question 2")
        XCTAssertEqual(viewModel.anchor?.ordinal, revealedChallenger?.ordinal)
        XCTAssertEqual(viewModel.anchor?.points, revealedChallenger?.points)
        XCTAssertNil(viewModel.challenger?.points)
        XCTAssertTrue(viewModel.canCall)
    }

    func test_streak_growsWithEveryCorrectCall() async {
        await startRun()
        await climb()
        await climb()
        await climb()

        XCTAssertEqual(viewModel.correctCount, 3)
        XCTAssertEqual(viewModel.currentStreak, 3)
    }

    func test_aServerRejectionShowsAFriendlyMessageAndReReadsTheMatch() async {
        await startRun()
        client.failures["call"] = HigherOrLowerServerError(message: "already_called")
        let readsBefore = client.snapshotCount
        await viewModel.call(.higher)

        XCTAssertEqual(viewModel.errorMessage, "You already locked in this question.")
        XCTAssertGreaterThan(client.snapshotCount, readsBefore)
    }

    func test_anUnexpectedFailureShowsAGenericMessage() async {
        await startRun()
        struct Offline: Error {}
        XCTAssertEqual(
            SoloRunViewModel.describe(Offline()),
            "Something went wrong. Check your connection and try again."
        )
    }

    // MARK: - The endless ladder

    func test_theRunContinuesPastQuestionTwelveWithNoCeiling() async {
        await startRun()
        for _ in 1...14 { await climb() }

        XCTAssertEqual(viewModel.stage, .playing)
        XCTAssertEqual(viewModel.questionLabel, "Question 15")
        XCTAssertEqual(viewModel.correctCount, 14)
        XCTAssertTrue(viewModel.canCall)
    }

    func test_theQuestionLabelNeverPromisesAnOfTwelveCeiling() async {
        await startRun()
        for _ in 1...5 { await climb() }

        XCTAssertFalse(viewModel.questionLabel.contains(" of "))
    }

    // MARK: - Missing ends the run

    func test_aMissRevealsTheAnswerThenEndsTheRunOnContinue() async {
        await startRun()
        await climb()
        await callWrongly()

        XCTAssertEqual(viewModel.stage, .playing, "the miss is revealed before the run ends")
        XCTAssertEqual(viewModel.currentOutcome, .miss(client.wrongDirection(forQuestion: 2)))
        XCTAssertEqual(viewModel.currentStreak, 0)

        await viewModel.continueRun()
        XCTAssertEqual(viewModel.stage, .complete)
    }

    // MARK: - The recap

    func test_recap_showsTheFinalScoreAndTheLadderTheyClimbed() async {
        await startRun()
        await climb()
        await climb()
        await callWrongly() // the third question misses
        await viewModel.continueRun()

        let recap = viewModel.recap
        XCTAssertEqual(recap?.correct, 2)
        XCTAssertEqual(recap?.ladder.count, 4, "the seed anchor plus the three questions")
        XCTAssertEqual(recap?.ladder.first?.outcome, .startingPoint)
        XCTAssertEqual(recap?.ladder.dropFirst().map(\.outcome.isCorrect), [true, true, false])
        XCTAssertNotNil(recap?.ladder.last?.card.points)
    }

    func test_recap_isOnlyAvailableOnceTheRunHasEnded() async {
        await startRun()
        XCTAssertNil(viewModel.recap)
        await callCorrectly()
        XCTAssertNil(viewModel.recap)
    }

    func test_recap_beatingThePersonalBestIsCalledOut() async {
        client.allTimeHigh = 1
        await startRun()
        await climb()
        await climb()
        await callWrongly()
        await viewModel.continueRun()

        let recap = viewModel.recap
        XCTAssertEqual(recap?.isNewPersonalBest, true)
        XCTAssertEqual(recap?.personalBest, 2)
    }

    func test_recap_fallingShortOfThePersonalBestShowsTheBestToBeat() async {
        client.allTimeHigh = 9
        await startRun()
        await climb()
        await callWrongly()
        await viewModel.continueRun()

        let recap = viewModel.recap
        XCTAssertEqual(recap?.isNewPersonalBest, false)
        XCTAssertEqual(recap?.personalBest, 9)
        XCTAssertEqual(recap?.correct, 1)
    }

    func test_recap_aFirstEverRunIsNotAPersonalBestUntilItScores() async {
        await startRun()
        await callWrongly()
        await viewModel.continueRun()

        XCTAssertEqual(viewModel.recap?.correct, 0)
        XCTAssertEqual(viewModel.recap?.isNewPersonalBest, false)
    }

    func test_recap_comparesAgainstTheBestFromBeforeTheRunNotTheOneTheRunJustSet() async {
        // The stats row is bumped as the streak grows, so by the end it already
        // includes this run. The comparison must use the value from the start.
        client.allTimeHigh = 2
        await startRun()
        for _ in 1...3 { await climb() }
        await callWrongly()
        await viewModel.continueRun()

        XCTAssertEqual(client.allTimeHigh, 3, "the server's row now includes this run")
        XCTAssertEqual(viewModel.recap?.isNewPersonalBest, true)
        XCTAssertEqual(viewModel.recap?.personalBest, 3)
    }

    func test_playAgain_dealsAFreshLadderInTheSameFormat() async {
        await viewModel.loadSetup()
        viewModel.scoringMode = .weekly
        await viewModel.start()
        let firstMatch = viewModel.board?.matchId
        await callWrongly()
        await viewModel.continueRun()
        XCTAssertEqual(viewModel.stage, .complete)

        await viewModel.playAgain()

        XCTAssertEqual(client.replayCount, 1)
        XCTAssertEqual(viewModel.stage, .playing)
        XCTAssertNotEqual(viewModel.board?.matchId, firstMatch)
        XCTAssertEqual(viewModel.board?.scoringMode, .weekly)
        XCTAssertEqual(viewModel.correctCount, 0)
        XCTAssertEqual(viewModel.questionLabel, "Question 1")
    }

    func test_playAgain_theNextRunsPersonalBestIsTheOneJustSet() async {
        await startRun()
        await climb()
        await climb()
        await callWrongly()
        await viewModel.continueRun()
        await viewModel.playAgain()

        XCTAssertEqual(viewModel.personalBestBeforeRun, 2)
    }

    func test_changeFormat_returnsToTheSetupScreen() async {
        await startRun()
        await callWrongly()
        await viewModel.continueRun()
        viewModel.returnToSetup()

        XCTAssertEqual(viewModel.stage, .setup)
        XCTAssertNil(viewModel.recap)
    }

    // MARK: - Races and failures in the middle of a write

    func test_callingKeepsTheButtonsLockedUntilTheReReadLands() async {
        await startRun()

        // The call is accepted but the re-read that shows its reveal is slow.
        // In that window the board still says "call" with no call of ours in
        // it — the buttons must not come back to life for a second tap.
        client.holdNextSnapshot = true
        let pending = Task { await viewModel.call(client.correctDirection(forQuestion: 1)) }
        await eventually { client.hasHeldSnapshot }

        XCTAssertFalse(viewModel.canCall)

        client.releaseHeldSnapshot()
        await pending.value
        XCTAssertEqual(client.callDirections.count, 1)
        XCTAssertEqual(viewModel.currentOutcome?.isCorrect, true)
    }

    func test_playAgain_readsThePersonalBestBeforeSpendingTheOneTimeReplayChoice() async {
        await startRun()
        await callWrongly()
        await viewModel.continueRun()

        // If this read fails after the replay had been made, the new match
        // would be orphaned and "Play again" could never succeed again.
        client.failures["personal_best"] = HigherOrLowerServerError(message: "offline")
        await viewModel.playAgain()

        XCTAssertEqual(client.replayCount, 0)
        XCTAssertEqual(viewModel.stage, .complete)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func test_playAgain_afterTheNewMatchFailedToLoadRetryingDoesNotReplayAgain() async {
        await startRun()
        await callWrongly()
        await viewModel.continueRun()

        // The replay is made, but reading the new match fails.
        client.failures["state"] = HigherOrLowerServerError(message: "offline")
        await viewModel.playAgain()
        XCTAssertEqual(viewModel.stage, .complete)
        XCTAssertEqual(client.replayCount, 1)

        // The choice is spent; a retry must pick the new match up, not ask again.
        client.failures["state"] = nil
        await viewModel.playAgain()

        XCTAssertEqual(client.replayCount, 1)
        XCTAssertEqual(viewModel.stage, .playing)
        XCTAssertEqual(viewModel.questionLabel, "Question 1")
    }

    func test_changeFormat_aLateReReadNeverPullsThePlayerBackToTheRecap() async {
        await startRun()
        await callWrongly()
        await viewModel.continueRun()
        XCTAssertEqual(viewModel.stage, .complete)

        client.holdNextSnapshot = true
        viewModel.appReturnedToForeground()
        await eventually { client.hasHeldSnapshot }

        viewModel.returnToSetup()
        client.releaseHeldSnapshot()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(viewModel.stage, .setup)
        XCTAssertNil(viewModel.recap)
    }

    // MARK: - Backgrounding mid-question (issue #64)

    func test_returningToTheForeground_rereadsTheMatchAndShowsWhereItReallyIs() async {
        await startRun()
        await callCorrectly()
        XCTAssertEqual(viewModel.questionLabel, "Question 1")

        // While the app was suspended the match moved on without it.
        client.advanceServerBehindTheAppsBack()
        let readsBefore = client.snapshotCount
        viewModel.appReturnedToForeground()

        await eventually { viewModel.questionLabel == "Question 2" }
        XCTAssertGreaterThan(client.snapshotCount, readsBefore)
        XCTAssertTrue(viewModel.canCall)
    }

    func test_returningToTheForeground_keepsTheTalliesIntact() async {
        await startRun()
        await climb()
        await climb()
        await callCorrectly() // question 3, correct, still at the reveal

        let readsBefore = client.snapshotCount
        viewModel.appReturnedToForeground()
        await eventually { client.snapshotCount > readsBefore }

        XCTAssertEqual(viewModel.correctCount, 3)
        XCTAssertEqual(viewModel.currentStreak, 3)
        XCTAssertEqual(viewModel.currentOutcome?.isCorrect, true)
    }

    func test_returningToTheForeground_beforeAnyRunIsAHarmlessNoOp() async {
        viewModel.appReturnedToForeground()
        await Task.yield()

        XCTAssertEqual(client.snapshotCount, 0)
        XCTAssertEqual(viewModel.stage, .setup)
    }

    func test_returningToTheForeground_afterTheRunEndedStillShowsTheRecap() async {
        await startRun()
        await callWrongly()
        await viewModel.continueRun()

        let readsBefore = client.snapshotCount
        viewModel.appReturnedToForeground()
        await eventually { client.snapshotCount > readsBefore }

        XCTAssertEqual(viewModel.stage, .complete)
        XCTAssertEqual(viewModel.recap?.correct, 0)
    }

    func test_aSlowReReadThatArrivesLateNeverRollsTheScreenBack() async {
        await startRun()

        // A foreground re-read goes out and is slow: it captured the server as
        // it stood before the player's call.
        client.holdNextSnapshot = true
        viewModel.appReturnedToForeground()
        await eventually { client.hasHeldSnapshot }

        // Meanwhile the player calls, and that read comes back promptly.
        await callCorrectly()
        XCTAssertEqual(viewModel.correctCount, 1)
        XCTAssertNotNil(viewModel.challenger?.points)

        // Now the stale one finally lands. It must be ignored.
        client.releaseHeldSnapshot()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(viewModel.correctCount, 1)
        XCTAssertNotNil(viewModel.challenger?.points, "the reveal is still showing")
        XCTAssertEqual(viewModel.currentOutcome?.isCorrect, true)
    }

    func test_aFailedForegroundReReadLeavesTheLastGoodScreenUp() async {
        await startRun()
        await callCorrectly()
        client.failures["state"] = HigherOrLowerServerError(message: "offline")

        viewModel.appReturnedToForeground()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(viewModel.correctCount, 1)
        XCTAssertEqual(viewModel.stage, .playing)
    }

    // MARK: - The countdown, when the server times a question

    func test_aSoloBoardHasNoCountdown() async {
        await startRun()

        XCTAssertNil(viewModel.clock.remainingMs)
    }

    func test_aTimedBoardShowsACountdownMeasuredAgainstServerTime() async {
        client.setDeadline(client.serverNow.addingTimeInterval(12))
        await startRun()

        // 12s to the deadline, less the 500ms the visible bar finishes early.
        XCTAssertEqual(viewModel.clock.remainingMs, 11_500)

        localNow = localNow.addingTimeInterval(4)
        viewModel.clock.tick()
        XCTAssertEqual(viewModel.clock.remainingMs, 7_500)
    }

    func test_aTimedBoardSaysItIsStillHereOnAHeartbeat() async {
        client.setDeadline(client.serverNow.addingTimeInterval(12))
        await startRun()

        // A fresh phase is asked about immediately, then on the 3s beat.
        localNow = localNow.addingTimeInterval(0.1)
        viewModel.clock.tick()
        await eventually { client.tickCount >= 1 }
        let first = client.tickCount

        localNow = localNow.addingTimeInterval(3.1)
        viewModel.clock.tick()
        await eventually { client.tickCount > first }
    }

    func test_aPassedDeadlineIsAskedToExpireAndTheNewPositionIsShown() async {
        client.setDeadline(client.serverNow.addingTimeInterval(12))
        await startRun()
        await callCorrectly()
        XCTAssertEqual(viewModel.questionLabel, "Question 1")

        // The server times the reveal out and moves on behind the app's back.
        client.advanceServerBehindTheAppsBack()
        let ticksBefore = client.tickCount

        localNow = localNow.addingTimeInterval(20) // well past deadline + jitter
        viewModel.clock.tick()

        await eventually { client.tickCount > ticksBefore }
        await eventually { viewModel.questionLabel == "Question 2" }
    }

    func test_aDeadlineStalePastTheWatchdogThresholdReReadsTheWholeMatch() async {
        client.setDeadline(client.serverNow.addingTimeInterval(1))
        await startRun()
        let readsBefore = client.snapshotCount

        localNow = localNow.addingTimeInterval(6) // 5s past the deadline > STALE_MS
        viewModel.clock.tick()

        await eventually { client.snapshotCount > readsBefore }
    }
}
