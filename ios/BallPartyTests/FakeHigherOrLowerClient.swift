import Foundation
@testable import BallParty

/// An in-memory stand-in for the server, behind the same `HigherOrLowerClient`
/// seam the app uses. It plays only the rules a screen's behavior depends on —
/// the endless ladder, a miss ending a solo run, points withheld until reveal,
/// the all-time-high trigger, and for a group match which calls RLS lets this
/// viewer see — so view-model tests can drive whole matches without a network
/// and assert on what would be shown.
///
/// The ladder is generated so that every question's answer is knowable to the
/// test (`correctDirection(forQuestion:)`), which is what lets a test choose to
/// hit or miss on purpose.
///
/// Solo and group share this one fake because they share one protocol. The
/// group half's test controls are written from the *table's* point of view
/// (`anotherPlayerLocksIn`, `questionReveals`), because that is what a match
/// screen has to react to.
final class FakeHigherOrLowerClient: HigherOrLowerClient, @unchecked Sendable {
    let viewerId: UUID
    private(set) var matchId = UUID()

    // Server-side state.
    private var currentQuestion = 1
    private var phase: HigherOrLowerPhase = .call
    private var phaseDeadline: Date?
    private var calls: [LadderCall] = []
    private var correctCount = 0
    private var currentStreak = 0
    private var bestStreak = 0
    private var revealed: Set<Int> = [0]
    private var scoringMode: ScoringMode = .seasonTotal
    private var era = SeasonRange(from: 2010, to: 2025)

    // Group state. A solo match is the degenerate case: no room, one seat.
    private var isSolo = true
    private var questionCount = 12
    private var others: [LadderPlayer] = []
    private var statuses: [CallStatus] = []
    private var standings: [MatchStanding] = []
    private var matchStatus: MatchStatus = .playing
    private var postGame: PostGameAction?
    private var viewerSuddenDeath = false
    /// Opened by `start_run` but not yet dealt into by the game's own `start`.
    private var undealt = false
    private var continuation: AsyncStream<MatchEvent>.Continuation?

    /// The all-time high the stats row holds, updated as a run's best streak
    /// grows — the same effect as `0112`'s trigger.
    var allTimeHigh = 0
    var bounds = SeasonRange(from: 2010, to: 2025)
    /// What `state`/`tick` report as the server's clock.
    var serverNow = Date(timeIntervalSince1970: 1_786_795_200)
    /// Delivers the challenger's card row with its points before the board says
    /// it has revealed — the Realtime race the web guards against.
    var leaksChallengerPoints = false

    // What the app asked for.
    private(set) var startCalls: [(scoringMode: ScoringMode, era: SeasonRange?)] = []
    private(set) var snapshotCount = 0
    private(set) var tickCount = 0
    private(set) var replayCount = 0
    private(set) var postGameChoices: [PostGameAction.Choice] = []
    private(set) var callDirections: [CallDirection] = []

    // Scripted failures, keyed by RPC name.
    var failures: [String: HigherOrLowerServerError] = [:]

    /// When set, the next `snapshot` captures the server's state *now* but does
    /// not return it until `releaseHeldSnapshot()` — a slow response.
    var holdNextSnapshot = false
    private var held: CheckedContinuation<Void, Never>?

    init(viewerId: UUID) {
        self.viewerId = viewerId
    }

    // MARK: - Test controls

    /// Ordinal 0 is the seed anchor; even ordinals score higher than the one
    /// before them, odd ones lower — a fixed, knowable ladder of any length.
    func points(ofOrdinal ordinal: Int) -> Double {
        ordinal % 2 == 0 ? 100 + Double(ordinal) : 50 + Double(ordinal)
    }

    func correctDirection(forQuestion question: Int) -> CallDirection {
        points(ofOrdinal: question) > points(ofOrdinal: question - 1) ? .higher : .lower
    }

    func wrongDirection(forQuestion question: Int) -> CallDirection {
        correctDirection(forQuestion: question) == .higher ? .lower : .higher
    }

    /// Moves the server on without the app asking — as if the match advanced
    /// while the app was suspended.
    func advanceServerBehindTheAppsBack() {
        _ = try? advanceSync()
    }

    func setDeadline(_ deadline: Date?) { phaseDeadline = deadline }

    func releaseHeldSnapshot() {
        held?.resume()
        held = nil
    }

    var hasHeldSnapshot: Bool { held != nil }

    // MARK: - Test controls: a group match

    /// Seeds a dealt group match — the viewer plus one seat per name.
    /// Returns the other players' ids, in the order named.
    ///
    /// Which room it belongs to isn't modelled here: a game never reads that
    /// (`architecture.md`), so the screen is told by whoever pushed it.
    @discardableResult
    func dealGroupMatch(others names: [String] = ["Sam"]) -> [UUID] {
        deal(scoringMode: scoringMode, era: era)
        isSolo = false
        phase = .call
        others = names.enumerated().map { index, name in
            LadderPlayer(
                userId: UUID(), seat: index + 1, displayName: name,
                currentStreak: 0, bestStreak: 0, correctCount: 0
            )
        }
        return others.map(\.userId)
    }

    var otherPlayerIds: [UUID] { others.map(\.userId) }

    /// Put the match back in the state `start_run` leaves it in: opened, but
    /// with no ladder dealt yet, so `state` has no row to answer with.
    func holdTheDeal() {
        undealt = true
    }

    /// The deal lands and says so on the channel, the way inserting the
    /// `higher_or_lower_matches` row does.
    func dealLands() {
        undealt = false
        emit(.board(position()))
    }

    /// The deal lands while nobody is listening — the payload for it reaches
    /// this screen never.
    func dealLandsSilently() {
        undealt = false
    }

    /// A channel (re)subscribed — a first connect or a reconnect.
    func channelSubscribes() { emit(.subscribed) }

    /// Another player locks in. Their *call* stays invisible to this viewer
    /// until the question reveals, exactly as RLS has it; only the status row
    /// — which says that they called, not which way — goes out now.
    func anotherPlayerLocksIn(_ userId: UUID, direction: CallDirection? = nil) {
        let call = LadderCall(
            question: currentQuestion, userId: userId,
            direction: direction ?? correctDirection(forQuestion: currentQuestion), timedOut: false
        )
        calls.append(call)
        let status = CallStatus(question: currentQuestion, userId: userId)
        statuses.append(status)
        emit(.callStatus(status))
    }

    /// The server reveals the question: the card turns over, every seat's
    /// tallies settle, and the calls made on it become visible to everybody.
    func questionReveals() {
        revealed.insert(currentQuestion)
        phase = phase.isSuddenDeath ? .suddenDeathReveal : .reveal
        let correct = correctDirection(forQuestion: currentQuestion)

        // This viewer's own seat scores at the reveal like everybody else's —
        // a group call doesn't settle the moment it is made.
        if let mine = calls.first(where: { $0.question == currentQuestion && $0.userId == viewerId }) {
            if mine.direction == correct {
                correctCount += 1
                currentStreak += 1
                bestStreak = max(bestStreak, currentStreak)
                allTimeHigh = max(allTimeHigh, bestStreak)
            } else {
                currentStreak = 0
            }
            emit(.player(playerPayload(viewer)))
        }

        for (index, player) in others.enumerated() {
            guard let call = calls.first(where: { $0.question == currentQuestion && $0.userId == player.userId })
            else { continue }
            let hit = call.direction == correct
            others[index] = LadderPlayer(
                userId: player.userId, seat: player.seat, displayName: player.displayName,
                currentStreak: hit ? player.currentStreak + 1 : 0,
                bestStreak: max(player.bestStreak, hit ? player.currentStreak + 1 : 0),
                correctCount: player.correctCount + (hit ? 1 : 0),
                absent: player.absent, suddenDeath: player.suddenDeath, eliminatedAt: player.eliminatedAt
            )
            emit(.player(playerPayload(others[index])))
        }
        emit(.card(card(ordinal: currentQuestion)))
        emit(.board(position()))
    }

    /// The server opens the next question.
    func nextQuestionOpens() {
        currentQuestion += 1
        phase = .call
        emit(.card(card(ordinal: currentQuestion)))
        emit(.board(position()))
    }

    /// The main ladder ended in a tie on both measures, so the tied field goes
    /// to sudden death.
    func suddenDeathBegins(admitting admitted: [UUID]) {
        currentQuestion = questionCount + 1
        phase = .suddenDeathCall
        for (index, player) in others.enumerated() where admitted.contains(player.userId) {
            others[index] = LadderPlayer(
                userId: player.userId, seat: player.seat, displayName: player.displayName,
                currentStreak: player.currentStreak, bestStreak: player.bestStreak,
                correctCount: player.correctCount, absent: player.absent, suddenDeath: true
            )
            emit(.player(playerPayload(others[index])))
        }
        viewerSuddenDeath = admitted.contains(viewerId)
        // `enter_sudden_death` updates every admitted row, this viewer's
        // included, so their own seat changes by payload like anybody else's.
        if viewerSuddenDeath { emit(.player(playerPayload(viewer))) }
        emit(.board(position()))
    }

    /// The match is over, with `placements` keyed by player.
    func matchCompletes(placements: [UUID: Int]) {
        phase = .complete
        phaseDeadline = nil
        standings = placements.map { userId, placement in
            MatchStanding(userId: userId, placement: placement, rawScore: Double(10 - placement))
        }
        matchStatus = .complete
        for standing in standings { emit(.standing(standing)) }
        emit(.board(position()))
    }

    func pauses() {
        matchStatus = .paused
        emit(.matchStatus(.paused))
    }

    func resumes() {
        matchStatus = .playing
        emit(.matchStatus(.playing))
    }

    /// Somebody else — the host, in another player's app — chose what happens
    /// next, and it arrives here over the `post-game:${matchId}` channel.
    func somebodyChoosesPostGame(_ choice: PostGameAction.Choice, nextMatchId: UUID? = UUID()) {
        let action = PostGameAction(choice: choice, nextMatchId: choice == .replay ? nextMatchId : nil)
        postGame = action
        emit(.postGame(action))
    }

    /// A seat that never ticked during a question is latched absent at its
    /// reveal.
    func anotherPlayerGoesAway(_ userId: UUID) {
        guard let index = others.firstIndex(where: { $0.userId == userId }) else { return }
        let player = others[index]
        others[index] = LadderPlayer(
            userId: player.userId, seat: player.seat, displayName: player.displayName,
            currentStreak: player.currentStreak, bestStreak: player.bestStreak,
            correctCount: player.correctCount, absent: true,
            suddenDeath: player.suddenDeath, eliminatedAt: player.eliminatedAt
        )
        emit(.player(playerPayload(others[index])))
    }

    func emit(_ event: MatchEvent) {
        continuation?.yield(event)
    }

    var isObserved: Bool { continuation != nil }

    // MARK: - HigherOrLowerClient

    func seasonBounds() async throws -> SeasonRange { try fail("season_bounds"); return bounds }

    func personalBest() async throws -> Int { try fail("personal_best"); return allTimeHigh }

    func start(matchId: UUID, scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard {
        try fail("start")
        startCalls.append((scoringMode, era))
        // The group path's match already exists: `start_run` opened it and
        // this only deals into it, so the id comes from the caller.
        deal(scoringMode: scoringMode, era: era ?? bounds, matchId: matchId)
        return board()
    }

    func startSoloRun(scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard {
        try fail("start")
        startCalls.append((scoringMode, era))
        deal(scoringMode: scoringMode, era: era ?? bounds)
        return board()
    }

    func snapshot(matchId: UUID) async throws -> HigherOrLowerSnapshot {
        try fail("state")
        snapshotCount += 1
        // `board_of` selects the match's own row, and an undealt match has
        // none — the composite comes back null and the read fails.
        if undealt { throw HigherOrLowerServerError(message: "match_not_dealt") }
        let captured = currentSnapshot()
        if holdNextSnapshot {
            holdNextSnapshot = false
            await withCheckedContinuation { held = $0 }
        }
        return captured
    }

    func call(matchId: UUID, direction: CallDirection) async throws -> LadderCall {
        try fail("call")
        guard phase.acceptsCalls else { throw HigherOrLowerServerError(message: "call_not_open") }
        guard !calls.contains(where: { $0.question == currentQuestion && $0.userId == viewerId }) else {
            throw HigherOrLowerServerError(message: "already_called")
        }
        callDirections.append(direction)
        let call = LadderCall(question: currentQuestion, userId: viewerId, direction: direction, timedOut: false)
        calls.append(call)
        let status = CallStatus(question: currentQuestion, userId: viewerId)
        statuses.append(status)

        guard isSolo else {
            // A group question waits for everybody, or for its deadline. The
            // server decides when it reveals — a test says so with
            // `questionReveals()`.
            emit(.call(call))
            emit(.callStatus(status))
            return call
        }

        revealed.insert(currentQuestion)
        if direction == correctDirection(forQuestion: currentQuestion) {
            correctCount += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
            allTimeHigh = max(allTimeHigh, bestStreak)
        } else {
            currentStreak = 0
        }
        phase = .reveal
        return call
    }

    func advance(matchId: UUID) async throws -> HigherOrLowerBoard {
        try fail("advance")
        return try advanceSync()
    }

    func tick(matchId: UUID) async throws -> HigherOrLowerBoard {
        try fail("tick")
        tickCount += 1
        return board()
    }

    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction {
        try fail("replay")
        postGameChoices.append(choice)
        guard choice == .replay else {
            let action = PostGameAction(choice: .lobby, nextMatchId: nil)
            postGame = action
            return action
        }
        replayCount += 1
        let wasGroup = !isSolo
        let seats = others
        deal(scoringMode: scoringMode, era: era)
        if wasGroup {
            // A replay reseats the same roster into a fresh match.
            isSolo = false
            others = seats.map {
                LadderPlayer(
                    userId: $0.userId, seat: $0.seat, displayName: $0.displayName,
                    currentStreak: 0, bestStreak: 0, correctCount: 0
                )
            }
        }
        let action = PostGameAction(choice: .replay, nextMatchId: self.matchId)
        postGame = action
        return action
    }

    func events(matchId: UUID) -> AsyncStream<MatchEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in self.continuation = nil }
        }
    }

    // MARK: - Private

    private func fail(_ rpc: String) throws {
        if let error = failures[rpc] { throw error }
    }

    private func deal(scoringMode: ScoringMode, era: SeasonRange, matchId: UUID = UUID()) {
        self.matchId = matchId
        self.scoringMode = scoringMode
        self.era = era
        currentQuestion = 1
        phase = .call
        calls = []
        statuses = []
        standings = []
        correctCount = 0
        currentStreak = 0
        bestStreak = 0
        revealed = [0]
        matchStatus = .playing
        postGame = nil
        viewerSuddenDeath = false
        isSolo = true
        others = []
    }

    private func advanceSync() throws -> HigherOrLowerBoard {
        guard phase == .reveal else { throw HigherOrLowerServerError(message: "advance_not_open") }
        if currentStreak == 0 {
            phase = .complete
        } else {
            currentQuestion += 1
            phase = .call
        }
        return board()
    }

    private func board() -> HigherOrLowerBoard {
        HigherOrLowerBoard(
            matchId: matchId, questionCount: questionCount, spareCount: 5,
            currentQuestion: currentQuestion, scoringMode: scoringMode, seasonFrom: era.from,
            seasonTo: era.to, phase: phase, phaseDeadline: phaseDeadline, serverNow: serverNow
        )
    }

    private func position() -> BoardPosition {
        BoardPosition(
            questionCount: questionCount, spareCount: 5, currentQuestion: currentQuestion,
            scoringMode: scoringMode, seasonFrom: era.from, seasonTo: era.to, phase: phase,
            phaseDeadline: phaseDeadline
        )
    }

    private func card(ordinal: Int) -> LadderCard {
        let shown = revealed.contains(ordinal) || (leaksChallengerPoints && ordinal == currentQuestion)
        return LadderCard(
            ordinal: ordinal, playerId: "p\(ordinal)", displayName: "Player \(ordinal)",
            position: "RB", season: 2020, team: "KC",
            points: shown ? points(ofOrdinal: ordinal) : nil,
            revealedAt: revealed.contains(ordinal) ? serverNow : nil
        )
    }

    /// A player row as Realtime delivers it: the bare row, with no `profiles`
    /// embed to carry a name.
    private func playerPayload(_ player: LadderPlayer) -> LadderPlayer {
        LadderPlayer(
            userId: player.userId, seat: player.seat, currentStreak: player.currentStreak,
            bestStreak: player.bestStreak, correctCount: player.correctCount, absent: player.absent,
            suddenDeath: player.suddenDeath, eliminatedAt: player.eliminatedAt
        )
    }

    private var viewer: LadderPlayer {
        LadderPlayer(
            userId: viewerId, seat: 0, displayName: "You", currentStreak: currentStreak,
            bestStreak: bestStreak, correctCount: correctCount, suddenDeath: viewerSuddenDeath
        )
    }

    private func currentSnapshot() -> HigherOrLowerSnapshot {
        // The ladder is dealt one ahead of the question being called; past the
        // pre-dealt twelve the server appends (0046) — here it is just longer.
        let cards = (0...currentQuestion).map(card(ordinal:))
        // What RLS would hand this viewer: their own calls always, anybody
        // else's only once that question revealed or they called it too.
        let mine = Set(calls.filter { $0.userId == viewerId }.map(\.question))
        let visible = calls.filter {
            $0.userId == viewerId || revealed.contains($0.question) || mine.contains($0.question)
        }
        return HigherOrLowerSnapshot(
            board: board(),
            cards: cards,
            players: [viewer] + others,
            calls: visible,
            statuses: statuses,
            standings: standings,
            matchStatus: matchStatus,
            postGame: postGame
        )
    }
}
