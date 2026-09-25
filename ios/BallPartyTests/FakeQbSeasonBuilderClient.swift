import Foundation
@testable import BallParty

/// An in-memory stand-in for the server, behind the same `QbSeasonBuilderClient`
/// seam the app uses. It plays only the rules a screen's behavior depends on —
/// one spin per round, a slot filled once, one respin, values withheld in a
/// hidden run until it is finished — so view-model tests can drive whole runs
/// without a network and assert on what would be shown.
final class FakeQbSeasonBuilderClient: QbSeasonBuilderClient, @unchecked Sendable {
    private(set) var matchId = UUID()

    // Server-side state.
    private(set) var mode: QbRatingMode = .visible
    private(set) var era: QbEra = .all
    private var round = 1
    private var attempt = 1
    private var respinUsed = false
    private var picks: [QbPick] = []
    private var finished = false
    private var finishedElsewhere = false
    private var started = false

    // Test controls.
    /// Raised by the next call of any kind, then cleared.
    var failNext: String?
    /// Fails only the next `finish`, leaving the picks before it alone.
    var failNextFinish: String?
    var bestScore: Double?
    private(set) var startCount = 0
    private(set) var pickedPlayerIds: [String?] = []
    private(set) var stateReads = 0

    // MARK: - QbSeasonBuilderClient

    func startRun(mode: QbRatingMode, era: QbEra) async throws -> QbBoard {
        try fail()
        self.mode = mode
        self.era = era
        matchId = UUID()
        round = 1
        attempt = 1
        respinUsed = false
        picks = []
        finished = false
        started = true
        startCount += 1
        return board
    }

    func state(matchId: UUID) async throws -> QbBoard {
        stateReads += 1
        return board
    }

    func pick(matchId: UUID, slot: QbSlot, playerId: String?) async throws -> QbBoard {
        try fail()
        guard !picks.contains(where: { $0.slot == slot }) else {
            throw QbSeasonBuilderServerError(message: "slot_filled")
        }
        pickedPlayerIds.append(playerId)
        let deal = currentDeal
        let quarterback = deal.spin.quarterbacks.first { $0.playerId == playerId }
        picks.append(
            QbPick(
                round: round, slot: slot, franchiseCode: deal.franchiseCode, season: deal.season,
                playerId: playerId, displayName: quarterback?.displayName,
                grade: mode == .visible ? .b : nil
            )
        )
        round += 1
        attempt = 1
        return board
    }

    func respin(matchId: UUID) async throws -> QbBoard {
        try fail()
        guard !respinUsed else { throw QbSeasonBuilderServerError(message: "respin_used") }
        respinUsed = true
        attempt = 2
        return board
    }

    func finish(matchId: UUID) async throws -> QbSeasonResult {
        if let message = failNextFinish {
            failNextFinish = nil
            throw QbSeasonBuilderServerError(message: message)
        }
        try fail()
        guard !finished, !finishedElsewhere else { throw QbSeasonBuilderServerError(message: "match_not_playing") }
        guard picks.count == 6 else { throw QbSeasonBuilderServerError(message: "draft_incomplete") }
        finished = true
        return savedResult
    }

    func result(matchId: UUID) async throws -> QbSeasonResult {
        try fail()
        guard finished || finishedElsewhere else { throw QbSeasonBuilderServerError(message: "result_not_found") }
        return savedResult
    }

    func personalBest(userId: UUID, mode: QbRatingMode) async throws -> Double? {
        bestScore
    }

    // MARK: - Test controls

    /// The run was finished elsewhere — another device, or an earlier tap whose
    /// answer was lost — so this client's next `finish` is refused.
    func finishElsewhere() {
        finishedElsewhere = true
    }

    // MARK: - Private

    private func fail() throws {
        if let message = failNext {
            failNext = nil
            throw QbSeasonBuilderServerError(message: message)
        }
    }

    private var currentDeal: QbDeal {
        let quarterback = QbQuarterback(
            playerId: "qb-\(round)-\(attempt)",
            displayName: "Quarterback \(round)",
            grades: mode == .visible ? Dictionary(uniqueKeysWithValues: QbSlot.qualities.map { ($0, QbGrade.b) }) : nil
        )
        return QbDeal(
            franchiseCode: "kan", season: 2009 + round,
            spin: QbSpin(quarterbacks: [quarterback], supportingCastGrade: mode == .visible ? .bMinus : nil)
        )
    }

    private var board: QbBoard {
        let phase: QbPhase = finished ? .complete : picks.count == 6 ? .readyToFinish : .picking
        let showsSpin = phase == .picking
        return QbBoard(
            matchId: matchId, mode: mode, phase: phase, currentRound: min(round, 6), respinUsed: respinUsed,
            deal: showsSpin ? currentDeal : nil,
            picks: picks,
            shown: finished ? [QbShownSpin(round: 1, attempt: 1, franchiseCode: "kan", season: 2010,
                                           spin: QbSpin(quarterbacks: [QbQuarterback(playerId: "qb-1-1", displayName: "Quarterback 1",
                                                                                      grades: Dictionary(uniqueKeysWithValues: QbSlot.qualities.map { ($0, QbGrade.b) }))],
                                                        supportingCastGrade: .bMinus))] : nil,
            era: era
        )
    }

    private var savedResult: QbSeasonResult {
        QbSeasonResult(
            matchId: matchId, mode: mode,
            statLine: QbStatLine(
                attempts: 560, completions: 370, passYards: 4_100, passTds: 30, interceptions: 10,
                rating: 98.4, rushYards: 250, rushTds: 3
            ),
            record: .init(wins: 12, losses: 5),
            playoffs: .init(depth: 2, result: .lostDivisional),
            awards: [.proBowl],
            score: 71.5,
            breakdown: [
                QbScoreComponent(component: "stat_line", weight: 55, percentile: 0.8, points: 40),
                QbScoreComponent(component: "team_success", weight: 30, percentile: 0.7, points: 21),
                QbScoreComponent(component: "awards", weight: 15, percentile: 0.7, points: 10.5),
            ],
            picks: picks
        )
    }
}
