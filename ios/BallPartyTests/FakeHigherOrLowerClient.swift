import Foundation
@testable import BallParty

/// An in-memory stand-in for the solo half of the server, behind the same
/// `HigherOrLowerClient` seam the app uses. It plays only the rules a screen's
/// behavior depends on — the endless ladder, a miss ending the run, points
/// being withheld until reveal, the all-time-high trigger — so view-model tests
/// can drive whole runs without a network and assert on what would be shown.
///
/// The ladder is generated so that every question's answer is knowable to the
/// test (`correctDirection(forQuestion:)`), which is what lets a test choose to
/// hit or miss on purpose.
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

    // MARK: - HigherOrLowerClient

    func seasonBounds() async throws -> SeasonRange { try fail("season_bounds"); return bounds }

    func personalBest() async throws -> Int { try fail("personal_best"); return allTimeHigh }

    func startSoloRun(scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard {
        try fail("start")
        startCalls.append((scoringMode, era))
        deal(scoringMode: scoringMode, era: era ?? bounds)
        return board()
    }

    func snapshot(matchId: UUID) async throws -> HigherOrLowerSnapshot {
        try fail("state")
        snapshotCount += 1
        let captured = currentSnapshot()
        if holdNextSnapshot {
            holdNextSnapshot = false
            await withCheckedContinuation { held = $0 }
        }
        return captured
    }

    func call(matchId: UUID, direction: CallDirection) async throws -> LadderCall {
        try fail("call")
        guard phase == .call else { throw HigherOrLowerServerError(message: "call_not_open") }
        guard !calls.contains(where: { $0.question == currentQuestion }) else {
            throw HigherOrLowerServerError(message: "already_called")
        }
        callDirections.append(direction)
        let call = LadderCall(question: currentQuestion, userId: viewerId, direction: direction, timedOut: false)
        calls.append(call)

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

    func replay(matchId: UUID) async throws -> UUID {
        try fail("replay")
        replayCount += 1
        deal(scoringMode: scoringMode, era: era)
        return self.matchId
    }

    // MARK: - Private

    private func fail(_ rpc: String) throws {
        if let error = failures[rpc] { throw error }
    }

    private func deal(scoringMode: ScoringMode, era: SeasonRange) {
        matchId = UUID()
        self.scoringMode = scoringMode
        self.era = era
        currentQuestion = 1
        phase = .call
        calls = []
        correctCount = 0
        currentStreak = 0
        bestStreak = 0
        revealed = [0]
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
            matchId: matchId, questionCount: 12, spareCount: 5, currentQuestion: currentQuestion,
            scoringMode: scoringMode, seasonFrom: era.from, seasonTo: era.to, phase: phase,
            phaseDeadline: phaseDeadline, serverNow: serverNow
        )
    }

    private func currentSnapshot() -> HigherOrLowerSnapshot {
        // The ladder is dealt one ahead of the question being called; past the
        // pre-dealt twelve the server appends (0046) — here it is just longer.
        let cards = (0...currentQuestion).map { ordinal in
            LadderCard(
                ordinal: ordinal, playerId: "p\(ordinal)", displayName: "Player \(ordinal)",
                position: "RB", season: 2020, team: "KC",
                points: revealed.contains(ordinal) || (leaksChallengerPoints && ordinal == currentQuestion)
                    ? points(ofOrdinal: ordinal) : nil
            )
        }
        let player = LadderPlayer(
            userId: viewerId, currentStreak: currentStreak, bestStreak: bestStreak, correctCount: correctCount
        )
        return HigherOrLowerSnapshot(board: board(), cards: cards, players: [player], calls: calls)
    }
}
