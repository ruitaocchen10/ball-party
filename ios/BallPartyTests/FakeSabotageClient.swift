import Foundation
@testable import BallParty

/// An in-memory stand-in for the Sabotage Draft half of the server, behind the
/// same `SabotageClient` seam the app uses. It plays only the rules a screen's
/// behavior depends on: a pick landing as a status for everyone and as a
/// readable row only for its owner, a guess or pass being spent per turn, and
/// a turn moving to the next seat.
///
/// Its test controls are written from the *table's* point of view, because that
/// is what a match screen has to react to.
final class FakeSabotageClient: SabotageClient, @unchecked Sendable {
    let viewerId: UUID
    let matchId = UUID()
    let maya = UUID()
    let dana = UUID()

    private(set) var board: SabotageBoard
    private(set) var players: [SabotagePlayer] = []
    private(set) var spins: [SabotageSpin] = []
    private(set) var picks: [SabotagePick] = []
    private(set) var statuses: [SabotagePickStatus] = []
    private(set) var hits: [SabotageHit] = []
    private(set) var guesses: [SabotageGuess] = []
    private(set) var passes: [SabotagePass] = []
    private(set) var decisions: [SabotageDecision] = []
    private(set) var standings: [SabotageStanding] = []
    private(set) var pickAvs: [SabotagePickAv] = []
    private(set) var matchStatus: MatchStatus = .playing
    private(set) var postGame: PostGameAction?
    var serverNow = Date(timeIntervalSince1970: 1_786_795_200)

    /// The pool the server offers, whoever's spin it is.
    var pool: [SabotageOption] = [
        SabotageOption(playerId: "a", name: "Alpha Back", season: 2021, category: "RB"),
        SabotageOption(playerId: "a", name: "Alpha Back", season: 2020, category: "RB"),
        SabotageOption(playerId: "a", name: "Alpha Back", season: 2019, category: "RB"),
        SabotageOption(playerId: "b", name: "Bravo Runner", season: 2015, category: "RB"),
        SabotageOption(playerId: "b", name: "Bravo Runner", season: 2014, category: "RB"),
        SabotageOption(playerId: "c", name: "Charlie Carry", season: 2010, category: "RB"),
        SabotageOption(playerId: "d", name: "Delta Dash", season: 2008, category: "RB"),
    ]

    // What the app asked for.
    private(set) var snapshotCount = 0
    private(set) var optionCalls: [UUID?] = []
    private(set) var submittedPicks: [(playerId: String, season: Int)] = []
    private(set) var submittedGuesses: [(playerId: String, season: Int?, replacement: (playerId: String, season: Int)?)] = []
    private(set) var passCount = 0
    private(set) var submittedDecisions: [String?] = []
    private(set) var tickCount = 0
    private(set) var postGameChoices: [PostGameAction.Choice] = []
    private(set) var startCalls: [SabotageMode] = []

    /// Scripted failures, keyed by RPC name.
    var failures: [String: SabotageServerError] = [:]

    private var continuation: AsyncStream<SabotageEvent>.Continuation?

    init(viewerId: UUID) {
        self.viewerId = viewerId
        board = SabotageBoard(
            matchId: matchId, roundCount: 7, currentRound: 1, slot: "QB",
            turnDeadline: nil, serverNow: serverNow, xFactorOpen: false, activeUserId: nil
        )
    }

    // MARK: - Test controls

    /// A three-seat quick match (the viewer, Maya, Dana) on round 1, with
    /// `activeSeat` on the clock.
    func deal(activeSeat: Int = 0, turnSeconds: Double = 30) {
        players = [
            SabotagePlayer(userId: viewerId, seat: 0, name: "You"),
            SabotagePlayer(userId: maya, seat: 1, name: "Maya"),
            SabotagePlayer(userId: dana, seat: 2, name: "Dana"),
        ]
        spins = players.map { SabotageSpin(round: 1, userId: $0.userId, franchiseCode: $0.userId == viewerId ? "pit" : "nwe") }
        setBoard(round: 1, slot: "QB", activeSeat: activeSeat, turnSeconds: turnSeconds)
    }

    /// The next seat's turn opens (the next round after the last seat).
    func advanceTurn(turnSeconds: Double = 30) {
        let index = players.firstIndex { $0.userId == board.activeUserId } ?? 0
        if index + 1 < players.count {
            setBoard(round: board.currentRound, slot: board.slot, activeSeat: index + 1, turnSeconds: turnSeconds)
        } else {
            let round = board.currentRound + 1
            let slot = SabotageRules.slot(forRound: round, roundCount: board.roundCount)
            spins += players.map { SabotageSpin(round: round, userId: $0.userId, franchiseCode: "dal") }
            setBoard(round: round, slot: slot, activeSeat: 0, turnSeconds: turnSeconds)
        }
        emit(.changed)
    }

    /// Another seat locks a pick: everyone sees the status, nobody else sees the row.
    func anotherPlayerLocksPick(_ user: UUID, round: Int? = nil) {
        statuses.append(SabotagePickStatus(round: round ?? board.currentRound, userId: user))
        emit(.changed)
    }

    /// The viewer's own pick for a round, as the server stores it.
    func viewerHasPick(round: Int, name: String = "Mine Back", season: Int = 2018) {
        picks.append(SabotagePick(round: round, userId: viewerId, playerId: "m", name: name, season: season))
        statuses.append(SabotagePickStatus(round: round, userId: viewerId))
    }

    /// A pick whose turn is over, so everyone may now read it.
    func resolvedPick(user: UUID, round: Int, name: String, season: Int) {
        picks.append(SabotagePick(round: round, userId: user, playerId: name, name: name, season: season))
        statuses.append(SabotagePickStatus(round: round, userId: user))
    }

    func hit(_ kind: SabotageHit.Kind, on user: UUID, round: Int) {
        hits.append(SabotageHit(round: round, targetUserId: user, kind: kind))
    }

    func recordGuess(by user: UUID, on target: UUID, round: Int, season: Int?, result: SabotageGuess.Result?) {
        guesses.append(SabotageGuess(round: round, userId: user, targetUserId: target, season: season, result: result))
    }

    func recordPass(by user: UUID, on target: UUID, round: Int) {
        passes.append(SabotagePass(round: round, userId: user, targetUserId: target))
    }

    func openXFactor(round: Int) {
        let slot = SabotageRules.xFactor
        board = SabotageBoard(
            matchId: matchId, roundCount: board.roundCount, currentRound: round, slot: slot,
            turnDeadline: nil, serverNow: serverNow, xFactorOpen: true, activeUserId: viewerId
        )
        emit(.changed)
    }

    func seasonEnds(_ standings: [SabotageStanding]) {
        self.standings = standings
        matchStatus = .complete
        emit(.matchStatus(.complete))
        emit(.changed)
    }

    func matchPauses() {
        matchStatus = .paused
        emit(.matchStatus(.paused))
    }

    func emit(_ event: SabotageEvent) { continuation?.yield(event) }

    // MARK: - SabotageClient

    func start(matchId: UUID, mode: SabotageMode) async throws -> SabotageBoard? {
        startCalls.append(mode)
        try fail("start")
        return board
    }

    func snapshot(matchId: UUID) async throws -> SabotageSnapshot {
        snapshotCount += 1
        try fail("snapshot")
        return SabotageSnapshot(
            board: board, players: players, spins: spins, picks: picks, statuses: statuses, hits: hits,
            guesses: guesses, passes: passes, decisions: decisions, standings: standings, tiebreaks: [],
            pickAvs: pickAvs, matchStatus: matchStatus, postGame: postGame
        )
    }

    func options(matchId: UUID, targetUserId: UUID?) async throws -> [SabotageOption] {
        optionCalls.append(targetUserId)
        try fail("options")
        return pool
    }

    func submitPick(matchId: UUID, playerId: String, season: Int) async throws {
        try fail("submit_pick")
        guard board.activeUserId == viewerId else { throw SabotageServerError(message: "not_your_turn") }
        submittedPicks.append((playerId, season))
        let name = pool.first { $0.playerId == playerId }?.name ?? playerId
        picks.append(SabotagePick(round: board.currentRound, userId: viewerId, playerId: playerId, name: name, season: season))
        statuses.append(SabotagePickStatus(round: board.currentRound, userId: viewerId))
    }

    func submitGuess(
        matchId: UUID, playerId: String, season: Int?, replacement: (playerId: String, season: Int)?
    ) async throws {
        try fail("submit_guess")
        guard board.activeUserId != viewerId, let target = board.activeUserId else {
            throw SabotageServerError(message: "not_your_turn")
        }
        submittedGuesses.append((playerId, season, replacement))
        guesses.append(SabotageGuess(round: board.currentRound, userId: viewerId, targetUserId: target, season: season, result: nil))
    }

    func submitPass(matchId: UUID) async throws {
        try fail("submit_pass")
        guard board.activeUserId != viewerId, let target = board.activeUserId else {
            throw SabotageServerError(message: "not_your_turn")
        }
        passCount += 1
        passes.append(SabotagePass(round: board.currentRound, userId: viewerId, targetUserId: target))
    }

    func submitXFactorDecision(matchId: UUID, replaceSlot: String?) async throws {
        try fail("submit_x_factor_decision")
        submittedDecisions.append(replaceSlot)
        decisions.append(SabotageDecision(userId: viewerId, replaceSlot: replaceSlot))
    }

    func tick(matchId: UUID) async throws -> SabotageBoard? {
        tickCount += 1
        try fail("tick")
        return board
    }

    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction {
        postGameChoices.append(choice)
        try fail("choose_post_game")
        let action = PostGameAction(choice: choice, nextMatchId: choice == .replay ? UUID() : nil)
        postGame = action
        return action
    }

    func events(matchId: UUID) -> AsyncStream<SabotageEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in self.continuation = nil }
        }
    }

    // MARK: - Private

    private func fail(_ rpc: String) throws {
        if let error = failures[rpc] { throw error }
    }

    private func setBoard(round: Int, slot: String, activeSeat: Int, turnSeconds: Double) {
        board = SabotageBoard(
            matchId: matchId, roundCount: board.roundCount, currentRound: round, slot: slot,
            turnDeadline: serverNow.addingTimeInterval(turnSeconds), serverNow: serverNow,
            xFactorOpen: false, activeUserId: players[activeSeat].userId
        )
    }
}
