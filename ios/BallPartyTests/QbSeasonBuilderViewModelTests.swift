import Foundation
@testable import BallParty
import XCTest

/// `QbSeasonBuilderViewModel` against `FakeQbSeasonBuilderClient` — the single
/// network seam. Every assertion is on what a screen would show or what the app
/// asked the server for, never on how the view model arranges itself internally.
@MainActor
final class QbSeasonBuilderViewModelTests: XCTestCase {
    private var client: FakeQbSeasonBuilderClient!
    private var viewModel: QbSeasonBuilderViewModel!

    override func setUp() async throws {
        client = FakeQbSeasonBuilderClient()
        viewModel = makeViewModel(mode: .visible)
    }

    private func makeViewModel(mode: QbRatingMode) -> QbSeasonBuilderViewModel {
        QbSeasonBuilderViewModel(client: client, viewerId: UUID(), mode: mode)
    }

    // MARK: - Helpers

    /// One quarterback quality from the current spin, locked in.
    private func pickQuality(_ slot: QbSlot) async {
        let quarterback = viewModel.deal!.spin.quarterbacks[0]
        viewModel.choose(slot, from: quarterback.playerId)
        await viewModel.lockInPick()
    }

    /// Every pick, the last of which finishes the run on its own.
    private func fillAllSlots() async {
        await fillAllButTheLast()
        await pickSupportingCast()
    }

    private func fillAllButTheLast() async {
        for slot in QbSlot.qualities { await pickQuality(slot) }
    }

    private func pickSupportingCast() async {
        viewModel.choose(.supportingCast, from: nil)
        await viewModel.lockInPick()
    }

    // MARK: - Starting

    func test_start_dealsTheFirstSpin() async {
        XCTAssertEqual(viewModel.stage, .starting)

        await viewModel.start()

        XCTAssertEqual(viewModel.stage, .picking)
        XCTAssertEqual(viewModel.roundLabel, "Round 1 of 6")
        XCTAssertEqual(viewModel.deal?.franchiseCode, "kan")
        XCTAssertEqual(client.mode, .visible)
    }

    func test_start_inAHiddenRunAsksForHiddenAndShowsNoRatings() async {
        viewModel = makeViewModel(mode: .hidden)
        await viewModel.start()

        XCTAssertEqual(client.mode, .hidden)
        XCTAssertNil(viewModel.deal?.spin.quarterbacks.first?.grades)
        XCTAssertNil(viewModel.deal?.spin.supportingCastGrade)
    }

    func test_start_doesNotDealASecondRunWhenTheScreenReappears() async {
        await viewModel.start()
        await viewModel.start()

        XCTAssertEqual(client.startCount, 1)
    }

    func test_start_failureOffersARetryThatWorks() async {
        client.failNext = "not_authenticated"
        await viewModel.start()

        XCTAssertTrue(viewModel.startFailed)
        XCTAssertEqual(viewModel.errorMessage, "Sign in first.")
        XCTAssertEqual(viewModel.stage, .starting)

        await viewModel.start()

        XCTAssertFalse(viewModel.startFailed)
        XCTAssertEqual(viewModel.stage, .picking)
    }

    // MARK: - Picking

    func test_lockInPick_fillsTheSlotAndOpensTheNextRound() async {
        await viewModel.start()
        await pickQuality(.accuracy)

        XCTAssertTrue(viewModel.isTaken(.accuracy))
        XCTAssertEqual(viewModel.roundLabel, "Round 2 of 6")
        XCTAssertNil(viewModel.choice)
        XCTAssertEqual(viewModel.board?.pick(for: .accuracy)?.displayName, "Quarterback 1")
    }

    func test_lockInPick_withNothingChosenDoesNothing() async {
        await viewModel.start()

        XCTAssertFalse(viewModel.canPick)
        await viewModel.lockInPick()

        XCTAssertEqual(viewModel.roundLabel, "Round 1 of 6")
    }

    func test_choose_aSlotAlreadyFilledCannotBeChosenAgain() async {
        await viewModel.start()
        await pickQuality(.accuracy)

        viewModel.choose(.accuracy, from: "qb-2-1")

        XCTAssertNil(viewModel.choice)
    }

    func test_choose_switchingBetweenOptionsKeepsOnlyTheLastOne() async {
        await viewModel.start()

        viewModel.choose(.accuracy, from: "qb-1-1")
        viewModel.choose(.iq, from: "qb-1-1")

        XCTAssertTrue(viewModel.isChosen(.iq, playerId: "qb-1-1"))
        XCTAssertFalse(viewModel.isChosen(.accuracy, playerId: "qb-1-1"))
        XCTAssertEqual(viewModel.choiceSummary, "Taking IQ from Quarterback 1")
    }

    func test_supportingCast_isPickedFromTheTeamWithNoQuarterback() async {
        await viewModel.start()

        viewModel.choose(.supportingCast, from: nil)
        XCTAssertEqual(viewModel.choiceSummary, "Taking Supporting Cast from Kansas City Chiefs")
        await viewModel.lockInPick()

        XCTAssertEqual(client.pickedPlayerIds, [nil])
    }

    func test_aRefusal_saysWhyAndReReadsTheRun() async {
        await viewModel.start()
        viewModel.choose(.accuracy, from: "qb-1-1")
        client.failNext = "slot_filled"
        let readsBefore = client.stateReads

        await viewModel.lockInPick()

        XCTAssertEqual(viewModel.errorMessage, "That slot is already filled.")
        XCTAssertEqual(client.stateReads, readsBefore + 1)
        XCTAssertNil(viewModel.choice, "a stale choice is dropped along with the stale board")
    }

    // MARK: - Respin

    func test_respin_rerollsOnceThenIsSpent() async {
        await viewModel.start()
        XCTAssertTrue(viewModel.canRespin)

        await viewModel.respin()

        XCTAssertEqual(viewModel.board?.respinUsed, true)
        XCTAssertEqual(viewModel.deal?.spin.quarterbacks.first?.playerId, "qb-1-2")
        XCTAssertFalse(viewModel.canRespin)
    }

    // MARK: - Finishing

    func test_theLastPick_goesStraightToTheReveal() async {
        client.bestScore = 88.2
        await viewModel.start()
        await fillAllSlots()

        XCTAssertEqual(viewModel.stage, .complete)
        XCTAssertEqual(viewModel.result?.score, 71.5)
        XCTAssertEqual(viewModel.result?.record.wins, 12)
        XCTAssertEqual(viewModel.personalBest, 88.2)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_earlierPicks_doNotFinishTheRun() async {
        await viewModel.start()
        await fillAllButTheLast()

        XCTAssertEqual(viewModel.stage, .picking)
        XCTAssertNil(viewModel.result)
    }

    func test_ifFinishingFails_theRunStaysReadyToFinishAndCanBeRetried() async {
        await viewModel.start()
        await fillAllButTheLast()
        client.failNextFinish = "internal_error"

        await pickSupportingCast()

        XCTAssertEqual(viewModel.stage, .readyToFinish)
        XCTAssertNil(viewModel.deal)
        XCTAssertEqual(viewModel.roundLabel, "Round 6 of 6")
        XCTAssertNotNil(viewModel.errorMessage)

        await viewModel.finish()

        XCTAssertEqual(viewModel.stage, .complete)
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_finish_inAVisibleRunHasNoPlayersDealtToReveal() async {
        await viewModel.start()
        await fillAllSlots()

        XCTAssertTrue(viewModel.dealtSpins.isEmpty)
    }

    func test_finish_inAHiddenRunRevealsEveryOptionSeen() async {
        viewModel = makeViewModel(mode: .hidden)
        await viewModel.start()
        await fillAllSlots()

        XCTAssertEqual(viewModel.dealtSpins.count, 1)
        XCTAssertEqual(viewModel.dealtSpins.first?.spin.quarterbacks.first?.grades?[.accuracy], .b)
    }

    func test_finish_aRunAlreadyFinishedElsewhereLandsOnItsReveal() async {
        await viewModel.start()
        await fillAllButTheLast()
        client.finishElsewhere()

        await pickSupportingCast()

        XCTAssertEqual(viewModel.stage, .complete)
        XCTAssertEqual(viewModel.result?.score, 71.5)
        XCTAssertNil(viewModel.errorMessage, "an already-finished run is a place to land, not an error")
    }

    func test_finish_withSlotsOpenDoesNothing() async {
        await viewModel.start()
        await pickQuality(.accuracy)

        await viewModel.finish()

        XCTAssertEqual(viewModel.stage, .picking)
        XCTAssertNil(viewModel.result)
    }

    func test_newSeason_dealsAFreshRunInTheSameMode() async {
        viewModel = makeViewModel(mode: .hidden)
        await viewModel.start()
        await fillAllSlots()

        await viewModel.newSeason()

        XCTAssertEqual(viewModel.stage, .picking)
        XCTAssertNil(viewModel.result)
        XCTAssertEqual(viewModel.roundLabel, "Round 1 of 6")
        XCTAssertEqual(client.startCount, 2)
        XCTAssertEqual(client.mode, .hidden)
    }

    // MARK: - The reveal

    private func finishedRun() async {
        await viewModel.start()
        await fillAllSlots()
    }

    func test_reveal_startsWithOnlyTheScoreAndWalksTheStagesInOrder() async {
        await finishedRun()

        XCTAssertTrue(viewModel.isRevealing)
        XCTAssertTrue(viewModel.shows(.score))
        XCTAssertFalse(viewModel.shows(.statLine))

        let order: [QbSeasonBuilderViewModel.RevealStage] = [.statLine, .awards, .record, .playoffs, .details]
        for stage in order {
            XCTAssertFalse(viewModel.shows(stage), "\(stage) landed early")
            viewModel.advanceReveal()
            XCTAssertTrue(viewModel.shows(stage), "\(stage) never landed")
        }
        XCTAssertFalse(viewModel.isRevealing)
    }

    func test_reveal_canBeSkippedStraightToTheEnd() async {
        await finishedRun()

        viewModel.skipReveal()

        XCTAssertFalse(viewModel.isRevealing)
        XCTAssertTrue(viewModel.shows(.details))
    }

    func test_reveal_aNewSeasonPlaysItsOwnRevealFromTheStart() async {
        await finishedRun()
        viewModel.skipReveal()

        await viewModel.newSeason()
        await fillAllSlots()

        XCTAssertTrue(viewModel.isRevealing)
        XCTAssertFalse(viewModel.shows(.statLine))
    }
}
