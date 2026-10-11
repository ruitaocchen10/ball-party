import Foundation
@testable import BallParty

/// An in-memory stand-in for the Wavelength half of the server, behind the same
/// `WavelengthClient` seam the app uses. It plays only the rules a screen's
/// behavior depends on: a clue landing as a status (and as readable text only
/// for its psychic), a locked guess scoring against the hidden target, the
/// target staying out of the viewer's rows unless the viewer is its psychic.
///
/// Its test controls are written from the *table's* point of view, because that
/// is what a match screen has to react to.
final class FakeWavelengthClient: WavelengthClient, @unchecked Sendable {
    let viewerId: UUID
    let matchId = UUID()

    private(set) var board: WavelengthBoard
    private(set) var players: [WavelengthPlayer] = []
    private(set) var rounds: [WavelengthRound] = []
    private(set) var cards: [WavelengthCard] = []
    private(set) var clues: [WavelengthClue] = []
    private(set) var clueStatuses: [WavelengthClueStatus] = []
    private(set) var targets: [WavelengthTarget] = []
    private(set) var result: WavelengthResult?
    private(set) var matchStatus: MatchStatus = .playing
    private(set) var postGame: PostGameAction?
    var serverNow = Date(timeIntervalSince1970: 1_786_795_200)

    /// Every target the server holds, whoever may read it.
    private var secretTargets: [Int: Int] = [:]

    // What the app asked for.
    private(set) var snapshotCount = 0
    private(set) var submittedClues: [(round: Int, clue: String)] = []
    private(set) var lockedGuesses: [(round: Int, position: Int)] = []
    private(set) var reportedNeedles: [(round: Int, position: Int)] = []
    private(set) var sentNeedles: [(round: Int, position: Int)] = []
    private(set) var tickCount = 0
    private(set) var postGameChoices: [PostGameAction.Choice] = []
    private(set) var startCalls: [(mode: WavelengthMode, preset: WavelengthPreset?)] = []

    /// Scripted failures, keyed by RPC name.
    var failures: [String: WavelengthServerError] = [:]

    private var continuation: AsyncStream<WavelengthEvent>.Continuation?

    init(viewerId: UUID) {
        self.viewerId = viewerId
        board = WavelengthBoard(
            matchId: matchId, mode: .coop, preset: .short, roundCount: 4, currentRound: 1,
            phase: .fill, serverNow: serverNow, teamScores: [0]
        )
    }

    // MARK: - Test controls

    /// A co-op table of the viewer and one teammate, four rounds, in the fill
    /// phase. The viewer is the psychic for rounds 1 and 3. Returns the
    /// teammate's id.
    @discardableResult
    func dealCoop(partner name: String = "Sam", fillSeconds: Double = 180) -> UUID {
        let partner = UUID()
        players = [
            WavelengthPlayer(userId: viewerId, seat: 0, team: 0, name: "You"),
            WavelengthPlayer(userId: partner, seat: 1, team: 0, name: name),
        ]
        rounds = (1...4).map { round in
            let viewerPsychic = round % 2 == 1
            return WavelengthRound(
                round: round,
                psychicId: viewerPsychic ? viewerId : partner,
                guesserId: viewerPsychic ? partner : viewerId
            )
        }
        // RLS: a card and its target are the psychic's alone during fill.
        for round in rounds {
            secretTargets[round.round] = 400 + round.round * 100
        }
        cards = rounds.filter { $0.psychicId == viewerId }.map {
            WavelengthCard(round: $0.round, leftLabel: "Cold \($0.round)", rightLabel: "Hot \($0.round)")
        }
        targets = rounds.filter { $0.psychicId == viewerId }.map {
            WavelengthTarget(round: $0.round, target: secretTargets[$0.round] ?? 500)
        }
        board = WavelengthBoard(
            matchId: matchId, mode: .coop, preset: .short, roundCount: 4, currentRound: 1, phase: .fill,
            phaseDeadline: serverNow.addingTimeInterval(fillSeconds), serverNow: serverNow, teamScores: [0]
        )
        return partner
    }

    /// The teammate writes their clue for `round`; the table sees only that it
    /// exists.
    func anotherPlayerWritesClue(round: Int) {
        clueStatuses.append(WavelengthClueStatus(round: round))
        emit(.changed)
    }

    /// The fill clock ends and `round` opens for guessing. Cards and clues for
    /// the open round become readable by everyone.
    func beginGuessing(round: Int = 1, guessSeconds: Double = 60) {
        updateRound(round) { old in
            WavelengthRound(
                round: old.round, psychicId: old.psychicId, guesserId: old.guesserId, status: .open,
                points: old.points, revealedTarget: old.revealedTarget, guessPosition: old.guessPosition
            )
        }
        if !cards.contains(where: { $0.round == round }) {
            cards.append(WavelengthCard(round: round, leftLabel: "Cold \(round)", rightLabel: "Hot \(round)"))
        }
        if !clues.contains(where: { $0.round == round }) {
            clues.append(WavelengthClue(round: round, clue: "Clue \(round)"))
        }
        setBoard(phase: .guess, round: round, deadline: serverNow.addingTimeInterval(guessSeconds))
        emit(.changed)
    }

    /// The guesser (another player) moves their needle.
    func needleMoves(round: Int, to position: Int) {
        emit(.needle(round: round, position: position))
    }

    /// `round` settles on the server (the partner locked, or the clock did).
    func roundSettles(round: Int, position: Int) {
        settle(round: round, position: position)
        emit(.changed)
    }

    func matchEnds(result: WavelengthResult) {
        self.result = result
        matchStatus = .complete
        setBoard(phase: .complete, round: board.currentRound, deadline: nil)
        emit(.matchStatus(.complete))
        emit(.changed)
    }

    func matchPauses() {
        matchStatus = .paused
        emit(.matchStatus(.paused))
    }

    func emit(_ event: WavelengthEvent) { continuation?.yield(event) }

    // MARK: - WavelengthClient

    func start(matchId: UUID, mode: WavelengthMode, preset: WavelengthPreset?) async throws -> WavelengthBoard {
        startCalls.append((mode, preset))
        try fail("start")
        return board
    }

    func snapshot(matchId: UUID) async throws -> WavelengthSnapshot {
        snapshotCount += 1
        try fail("snapshot")
        return WavelengthSnapshot(
            board: board, players: players, rounds: rounds, cards: cards, clues: clues,
            clueStatuses: clueStatuses, targets: targets, result: result, matchStatus: matchStatus, postGame: postGame
        )
    }

    func submitClue(matchId: UUID, round: Int, clue: String) async throws -> WavelengthBoard {
        try fail("submit_clue")
        submittedClues.append((round, clue))
        clueStatuses.append(WavelengthClueStatus(round: round))
        clues.append(WavelengthClue(round: round, clue: clue))
        return board
    }

    func lockGuess(matchId: UUID, round: Int, position: Int) async throws -> WavelengthBoard {
        try fail("lock_guess")
        lockedGuesses.append((round, position))
        settle(round: round, position: position)
        return board
    }

    func reportNeedle(matchId: UUID, round: Int, position: Int) async throws {
        try fail("report_needle")
        reportedNeedles.append((round, position))
    }

    func tick(matchId: UUID) async throws -> WavelengthBoard {
        tickCount += 1
        try fail("tick")
        return board
    }

    func sendNeedle(matchId: UUID, round: Int, position: Int) async {
        sentNeedles.append((round, position))
    }

    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction {
        postGameChoices.append(choice)
        try fail("choose_post_game")
        let action = PostGameAction(choice: choice, nextMatchId: choice == .replay ? UUID() : nil)
        postGame = action
        return action
    }

    func events(matchId: UUID) -> AsyncStream<WavelengthEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in self.continuation = nil }
        }
    }

    // MARK: - Private

    private func fail(_ rpc: String) throws {
        if let error = failures[rpc] { throw error }
    }

    private func updateRound(_ number: Int, _ change: (WavelengthRound) -> WavelengthRound) {
        guard let index = rounds.firstIndex(where: { $0.round == number }) else { return }
        rounds[index] = change(rounds[index])
    }

    private func setBoard(phase: WavelengthBoard.Phase, round: Int, deadline: Date?) {
        board = WavelengthBoard(
            matchId: matchId, mode: board.mode, preset: board.preset, roundCount: board.roundCount,
            currentRound: round, phase: phase, phaseDeadline: deadline, serverNow: serverNow,
            teamScores: board.teamScores
        )
    }

    /// Locks a round: scores the guess against the hidden target and, only now,
    /// publishes the target and the guess.
    private func settle(round: Int, position: Int) {
        let target = secretTargets[round] ?? 500
        let points = WavelengthRules.score(position: position, target: target)
        updateRound(round) { old in
            WavelengthRound(
                round: old.round, psychicId: old.psychicId, guesserId: old.guesserId, status: .locked,
                points: points, revealedTarget: target, guessPosition: position
            )
        }
        // The viewer was not necessarily this round's psychic, so the target
        // row never reached them; the revealed one on the round row does.
        let total = rounds.compactMap(\.points).reduce(0, +)
        board = WavelengthBoard(
            matchId: matchId, mode: board.mode, preset: board.preset, roundCount: board.roundCount,
            currentRound: round, phase: .reveal, phaseDeadline: nil, serverNow: serverNow, teamScores: [total]
        )
    }
}
