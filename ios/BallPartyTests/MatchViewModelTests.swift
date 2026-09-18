import Foundation
@testable import BallParty
import XCTest

/// `MatchViewModel` against `FakeHigherOrLowerClient` — the single network
/// seam. Every assertion is on what a screen would show or what the app asked
/// the server for, never on how the view model arranges itself internally.
@MainActor
final class MatchViewModelTests: XCTestCase {
    private var viewerId = UUID()
    private var client: FakeHigherOrLowerClient!
    private var viewModel: MatchViewModel!
    /// A controllable local clock, for the timed-path tests.
    private var localNow = Date(timeIntervalSince1970: 1_786_795_200)

    override func setUp() async throws {
        viewerId = UUID()
        client = FakeHigherOrLowerClient(viewerId: viewerId)
        client.serverNow = localNow
    }

    override func tearDown() async throws {
        viewModel?.stopObserving()
    }

    // MARK: - Helpers

    /// A dealt group match with this viewer at the table, already loaded.
    @discardableResult
    private func joinTable(
        others names: [String] = ["Sam"],
        hostedByViewer: Bool = true,
        deadlineIn seconds: TimeInterval? = nil
    ) async -> [UUID] {
        let others = client.dealGroupMatch(others: names)
        // A deadline is set on the server's clock, not this device's — which
        // is the whole point of measuring against `server_now`.
        if let seconds { client.setDeadline(client.serverNow.addingTimeInterval(seconds)) }
        viewModel = MatchViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId,
            // Handed in by the room that pushed the screen, as the app does.
            roomCode: "BRZWK", isHost: hostedByViewer,
            now: { [unowned self] in localNow }
        )
        await viewModel.load()
        return others
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<500 where !condition() { await Task.yield() }
        XCTAssertTrue(condition(), "condition never became true", file: file, line: line)
    }

    private func status(of userId: UUID) -> String? {
        viewModel.standings.first { $0.player.userId == userId }.map { viewModel.status(of: $0.player) }
    }

    // MARK: - The board

    func test_match_showsTheQuestionTheTableIsOnWithBothCards() async {
        await joinTable(others: ["Sam", "Ali"])

        XCTAssertEqual(viewModel.questionLabel, "Question 1 of 12")
        XCTAssertEqual(viewModel.anchor?.points, client.points(ofOrdinal: 0))
        XCTAssertNotNil(viewModel.challenger)
        XCTAssertNil(viewModel.challenger?.points, "the challenger's number was on screen before its reveal")
        XCTAssertEqual(viewModel.standings.count, 3)
        XCTAssertTrue(viewModel.canCall)
    }

    func test_match_theRailNamesEverybodyAtTheTable() async {
        await joinTable(others: ["Sam", "Ali"])

        XCTAssertEqual(Set(viewModel.standings.map(\.player.name)), ["You", "Sam", "Ali"])
    }

    // MARK: - Making a call

    func test_calling_locksTheViewerInAndRefusesASecondCall() async {
        await joinTable()

        await viewModel.call(.higher)

        XCTAssertEqual(client.callDirections, [.higher])
        XCTAssertEqual(viewModel.myCall?.direction, .higher)
        XCTAssertFalse(viewModel.canCall, "the call buttons stayed live after locking in")
    }

    func test_calling_aRefusalShowsItsMessageInTheTablesWords() async {
        await joinTable()
        client.failures["call"] = HigherOrLowerServerError(message: "call_deadline_passed")

        await viewModel.call(.lower)

        XCTAssertEqual(viewModel.errorMessage, "The call window has closed.")
    }

    func test_calling_isClosedWhileTheAnswerIsOnScreen() async {
        await joinTable()
        await viewModel.call(.higher)
        client.questionReveals()

        await eventually { self.viewModel.phase == .reveal }
        XCTAssertFalse(viewModel.canCall)
    }

    // MARK: - Watching the rest of the table

    func test_live_aSeatLockingInShowsUpWithoutSayingWhichWay() async {
        let others = await joinTable()

        client.anotherPlayerLocksIn(others[0], direction: .higher)

        // The status row is visible to every match member; the call itself is
        // not, until this viewer has called too or the question reveals.
        await eventually { self.status(of: others[0]) == "LOCKED" }
    }

    func test_live_aRevealBringsTheWholeTablesCallsIntoView() async {
        let others = await joinTable()
        client.anotherPlayerLocksIn(others[0], direction: .higher)
        await eventually { self.status(of: others[0]) == "LOCKED" }

        client.questionReveals()

        // A reveal changes which call rows RLS permits, and Realtime emits
        // nothing for a row whose visibility — not content — just changed, so
        // the screen has to go back and ask.
        await eventually { self.status(of: others[0]) == "HIGHER" }
    }

    func test_live_theBoardMovingOnIsAppliedWithoutAskingTheServerAgain() async {
        await joinTable()
        await viewModel.call(.higher)
        client.questionReveals()
        await eventually { self.viewModel.phase == .reveal }
        let reads = client.snapshotCount

        client.nextQuestionOpens()

        await eventually { self.viewModel.questionLabel == "Question 2 of 12" }
        XCTAssertEqual(
            client.snapshotCount, reads,
            "a board payload cost a server round trip, which is the latency the payloads exist to avoid"
        )
    }

    func test_live_aBoardPayloadKeepsTheClockItCameWith() async {
        await joinTable(deadlineIn: 12)
        let measuredAgainst = viewModel.board?.serverNow

        client.nextQuestionOpens()

        await eventually { self.viewModel.board?.currentQuestion == 2 }
        // A row payload carries no server timestamp. Substituting this
        // device's clock would corrupt the offset the countdown is measured
        // against, so the last authoritative one stands.
        XCTAssertEqual(viewModel.board?.serverNow, measuredAgainst)
    }

    func test_live_aBrandNewCardIsAppendedRatherThanNeedingARowToUpdate() async {
        await joinTable()
        let ordinals = viewModel.cards.map(\.ordinal)

        client.nextQuestionOpens()

        await eventually { self.viewModel.cards.map(\.ordinal) == ordinals + [ordinals.count] }
    }

    func test_live_aSeatGoingAwayShowsOnTheRail() async {
        let others = await joinTable()

        client.anotherPlayerGoesAway(others[0])

        await eventually { self.status(of: others[0]) == "AWAY" }
    }

    func test_live_aPayloadWithNoNameKeepsTheOneAlreadyOnScreen() async {
        let others = await joinTable(others: ["Sam"])

        // A `higher_or_lower_players` payload is the bare row, with no
        // `profiles` embed to carry a name.
        client.anotherPlayerGoesAway(others[0])

        await eventually { self.status(of: others[0]) == "AWAY" }
        XCTAssertEqual(
            viewModel.standings.first { $0.player.userId == others[0] }?.player.name, "Sam",
            "a seat lost its name to a payload that never carried one"
        )
    }

    // MARK: - Losing and regaining the connection

    func test_live_resubscribingReReadsTheWholeMatch() async {
        await joinTable()
        await eventually { self.client.isObserved }
        let reads = client.snapshotCount

        // The channel dropping and coming back is invisible to the app: the
        // SDK resubscribes and reports success again, and that one signal is
        // the whole of the reconnect contract.
        client.channelSubscribes()

        await eventually { self.client.snapshotCount > reads }
    }

    func test_live_aMatchThatMovedOnWhileTheAppWasAwayIsPickedUpOnReturn() async {
        await joinTable()

        // Two questions went by with the app suspended and no payloads
        // delivered.
        client.questionReveals()
        client.nextQuestionOpens()
        client.questionReveals()
        client.nextQuestionOpens()
        viewModel.stopObserving()

        viewModel.appReturnedToForeground()

        await eventually { self.viewModel.questionLabel == "Question 3 of 12" }
    }

    func test_live_aPausedMatchSaysSoAndClosesTheCallButtons() async {
        await joinTable()

        client.pauses()

        await eventually { self.viewModel.isPaused }
        XCTAssertFalse(viewModel.canCall)

        client.resumes()

        await eventually { !self.viewModel.isPaused }
        XCTAssertTrue(viewModel.canCall)
    }

    // MARK: - The clock

    func test_clock_saysThisPlayerIsStillHereThroughoutTheQuestion() async {
        await joinTable(deadlineIn: 12)
        // A fresh deadline is asked about immediately, which is what puts this
        // player on the record as present for the question that just opened.
        await eventually { self.client.tickCount >= 1 }

        // A player who ticks nowhere inside a question is latched absent at
        // its reveal, so the asking is what keeps a present player present.
        let asked = client.tickCount
        localNow.addTimeInterval(3.1)
        viewModel.clock.tick()

        await eventually { self.client.tickCount > asked }
    }

    func test_clock_keepsAskingTheServerToExpireAPassedDeadline() async {
        await joinTable(deadlineIn: 12)

        localNow.addTimeInterval(13)
        viewModel.clock.tick()
        await eventually { self.client.tickCount >= 2 }
        let asked = client.tickCount

        localNow.addTimeInterval(1.1)
        viewModel.clock.tick()

        await eventually { self.client.tickCount > asked }
    }

    // MARK: - Arriving before the ladder exists

    func test_undealtMatch_picksTheBoardUpTheMomentItIsDealt() async {
        // `start_run` opens a match in `'setup'` and the game deals into it a
        // moment later. A player carried in during that gap asks for a board
        // that does not exist yet — and must not be left looking at nothing
        // once it does.
        client.dealGroupMatch(others: ["Sam"])
        client.holdTheDeal()
        viewModel = MatchViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId,
            roomCode: "BRZWK", isHost: false, now: { [unowned self] in localNow }
        )
        await viewModel.load()
        XCTAssertNil(viewModel.board)

        client.dealLands()

        await eventually { self.viewModel.board != nil }
        XCTAssertEqual(viewModel.questionLabel, "Question 1 of 12")
    }

    func test_undealtMatch_aResubscribeAlsoPicksItUp() async {
        // The other ordering: the deal landed while this screen was still
        // connecting, so no payload for it was ever delivered here.
        client.dealGroupMatch(others: ["Sam"])
        client.holdTheDeal()
        viewModel = MatchViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId,
            roomCode: "BRZWK", isHost: false, now: { [unowned self] in localNow }
        )
        await viewModel.load()
        client.dealLandsSilently()

        client.channelSubscribes()

        await eventually { self.viewModel.board != nil }
    }

    // MARK: - Sudden death

    func test_suddenDeath_namesTheRoundAndOpensCallsOnlyToTheAdmittedField() async {
        let others = await joinTable(others: ["Sam", "Ali"])

        // The main ladder ended level between the viewer and Sam.
        client.suddenDeathBegins(admitting: [viewerId, others[0]])

        await eventually { self.viewModel.questionLabel == "Sudden death · Round 1" }
        XCTAssertTrue(viewModel.canCall)
        XCTAssertEqual(status(of: others[1]), "WATCHING")
    }

    func test_suddenDeath_aWatcherIsNotOfferedTheCallButtons() async {
        let others = await joinTable(others: ["Sam", "Ali"])

        // Two other players tied for the lead; this viewer is out of it.
        client.suddenDeathBegins(admitting: others)

        await eventually { self.viewModel.phase == .suddenDeathCall }
        XCTAssertFalse(viewModel.canCall, "a watcher was offered a call in somebody else's sudden death")
    }

    // MARK: - The ending

    func test_final_namesTheWinnerAndRanksTheWholeTable() async {
        let others = await joinTable(others: ["Sam", "Ali"])

        client.matchCompletes(placements: [others[0]: 1, viewerId: 2, others[1]: 3])

        await eventually { self.viewModel.isComplete }
        XCTAssertEqual(viewModel.headline, "Sam wins")
        XCTAssertEqual(viewModel.finalStandings.map(\.name), ["Sam", "You", "Ali"])
        XCTAssertEqual(viewModel.finalStandings.map(\.rank), [1, 2, 3])
        XCTAssertEqual(viewModel.finalStandings.first { $0.isViewer }?.name, "You")
    }

    func test_final_aSharedWinNamesBothPlayers() async {
        let others = await joinTable(others: ["Sam"])

        // Sudden death ran out of spare cards with the field still level, so
        // the win is shared.
        client.matchCompletes(placements: [viewerId: 1, others[0]: 1])

        await eventually { self.viewModel.isComplete }
        XCTAssertTrue(
            ["You & Sam tie", "Sam & You tie"].contains(viewModel.headline), viewModel.headline
        )
    }

    func test_final_showsWhatEachPlaceWasEarnedWith() async {
        let others = await joinTable()
        await viewModel.call(client.correctDirection(forQuestion: 1))
        client.questionReveals()
        await eventually { self.viewModel.phase == .reveal }

        client.matchCompletes(placements: [viewerId: 1, others[0]: 2])

        await eventually { self.viewModel.isComplete }
        XCTAssertEqual(viewModel.finalStandings.first?.statLine, "1 correct · 1 best")
    }

    func test_final_theHostChoosesWhatTheRoomDoesNext() async {
        let others = await joinTable(others: ["Sam"], hostedByViewer: true)
        client.matchCompletes(placements: [viewerId: 1, others[0]: 2])
        await eventually { self.viewModel.canChoosePostGame }

        await viewModel.choosePostGame(.replay)

        XCTAssertEqual(client.postGameChoices, [.replay])
        XCTAssertEqual(viewModel.postGameAction?.choice, .replay)
        XCTAssertNotNil(viewModel.postGameAction?.nextMatchId)
        XCTAssertFalse(viewModel.canChoosePostGame, "a second choice was still on offer")
    }

    func test_final_everybodyElseWaitsForTheHostsChoice() async {
        let others = await joinTable(others: ["Sam"], hostedByViewer: false)
        client.matchCompletes(placements: [viewerId: 1, others[0]: 2])

        await eventually { self.viewModel.isComplete }
        XCTAssertFalse(viewModel.canChoosePostGame)
        XCTAssertNil(viewModel.postGameAction)
    }

    func test_final_theHostsChoiceCarriesEverybodyElseAlong() async {
        let others = await joinTable(others: ["Sam"], hostedByViewer: false)
        client.matchCompletes(placements: [viewerId: 1, others[0]: 2])
        await eventually { self.viewModel.isComplete }

        // The host tapped Replay in their own app; it reaches this one over
        // the `post-game:${matchId}` channel.
        let next = UUID()
        client.somebodyChoosesPostGame(.replay, nextMatchId: next)

        await eventually { self.viewModel.postGameAction?.nextMatchId == next }
    }

    func test_final_aScreenOpenedAfterTheChoiceFollowsItToo() async {
        let others = await joinTable(others: ["Sam"], hostedByViewer: false)
        client.matchCompletes(placements: [viewerId: 1, others[0]: 2])
        await eventually { self.viewModel.isComplete }
        client.somebodyChoosesPostGame(.lobby)

        // A screen that arrives late reads the choice with everything else
        // rather than sitting on a finished board.
        let late = MatchViewModel(
            client: client, matchId: client.matchId, viewerId: viewerId,
            roomCode: "BRZWK", isHost: false, now: { [unowned self] in localNow }
        )
        await late.load()
        defer { late.stopObserving() }

        XCTAssertEqual(late.postGameAction?.choice, .lobby)
        XCTAssertEqual(late.roomCode, "BRZWK")
    }

    func test_clock_countsDownAgainstTheServersClockRatherThanThisDevices() async {
        // This device's clock runs two seconds fast. The countdown should
        // still show the twelve seconds the server allowed — reading the
        // deadline against this device's clock would show 9.5.
        localNow.addTimeInterval(2)
        await joinTable(deadlineIn: 12)

        XCTAssertEqual(viewModel.clock.remainingMs, 12_000 - MatchClockConstants.visibleSlackMs)
    }
}
