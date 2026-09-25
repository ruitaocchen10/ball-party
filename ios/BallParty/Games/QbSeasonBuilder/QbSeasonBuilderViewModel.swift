import Foundation

/// One QB Season Builder run, from the first spin to the revealed season.
///
/// The server is authoritative for every rule — the spins, which slots are
/// filled, whether a number is shown at all. This only decides which call to
/// make and what to show. Every move answers with the whole new board, and a
/// refusal is followed by a fresh read of the run, so a screen that fell behind
/// (a dropped answer, a second device) catches up instead of staying wrong.
///
/// There is no Realtime subscription: a solo run has exactly one client.
@MainActor
final class QbSeasonBuilderViewModel: ObservableObject {
    enum Stage: Equatable {
        /// Dealing the run's first spin (or failed to).
        case starting
        /// A round is open.
        case picking
        /// All six slots are filled; the season is not generated yet. Normally a
        /// moment on the way to the reveal — it lingers only if finishing failed.
        case readyToFinish
        /// The season is saved and being revealed.
        case complete
    }

    /// What the player has picked out on the spin but not yet locked in.
    struct Choice: Equatable {
        let slot: QbSlot
        /// The quarterback it comes from; nil for the Supporting Cast.
        let playerId: String?
    }

    /// The staged reveal follows its visual order, so a later step never lands
    /// above content already on screen.
    enum RevealStage: Int, CaseIterable, Comparable {
        case score, statLine, awards, record, playoffs, details

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How long each stage holds before the next one lands.
    static let revealStepSeconds = 1.6

    let mode: QbRatingMode
    let era: QbEra
    let viewerId: UUID

    @Published private(set) var board: QbBoard?
    @Published private(set) var choice: Choice?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    /// Set only when the run could not be started at all: there is nothing on
    /// screen to attach the error to, so the screen offers a retry instead.
    @Published private(set) var startFailed = false

    @Published private(set) var result: QbSeasonResult?
    /// The viewer's best in this mode as of the run's end; nil when they have none.
    @Published private(set) var personalBest: Double?
    @Published private(set) var revealStage: RevealStage = .score
    @Published private(set) var revealSkipped = false

    private let client: QbSeasonBuilderClient

    init(client: QbSeasonBuilderClient, viewerId: UUID, mode: QbRatingMode, era: QbEra = .all) {
        self.client = client
        self.viewerId = viewerId
        self.mode = mode
        self.era = era
    }

    // MARK: - Derived state

    var stage: Stage {
        if result != nil { return .complete }
        guard let board else { return .starting }
        return board.phase == .picking ? .picking : .readyToFinish
    }

    var deal: QbDeal? { board?.deal }

    func isTaken(_ slot: QbSlot) -> Bool { board?.isTaken(slot) ?? false }

    func isChosen(_ slot: QbSlot, playerId: String?) -> Bool {
        choice?.slot == slot && choice?.playerId == playerId
    }

    var canPick: Bool { choice != nil && !isBusy }
    var canRespin: Bool { stage == .picking && board?.respinUsed == false && !isBusy }

    /// "Round 3 of 6", with the round capped once every slot is filled.
    var roundLabel: String {
        guard let board else { return "" }
        return "Round \(min(board.currentRound, board.roundCount)) of \(board.roundCount)"
    }

    /// What the lock-in bar says about the current choice.
    var choiceSummary: String {
        guard let choice, let deal else { return "Choose one thing from this spin." }
        let source = choice.playerId.flatMap { id in
            deal.spin.quarterbacks.first { $0.playerId == id }?.displayName
        } ?? QbFranchises.name(for: deal.franchiseCode)
        return "Taking \(choice.slot.label) from \(source)"
    }

    /// What the run took, one entry per round, with every grade of theirs the
    /// run saw. The finished board's spins carry those in either mode; without
    /// them (a result read on its own) a pick still has the grade it was taken for.
    var pickedPlayers: [QbPickedPlayer] {
        let shown = board?.shown ?? []
        return (result?.picks ?? []).sorted { $0.round < $1.round }.map { pick in
            let spin = shown.first {
                $0.round == pick.round && $0.franchiseCode == pick.franchiseCode && $0.season == pick.season
            }?.spin
            var grades: [QbSlot: QbGrade] = [:]
            if let grade = pick.grade { grades[pick.slot] = grade }
            if let spin, pick.slot != .supportingCast,
               let quarterback = spin.quarterbacks.first(where: { $0.playerId == pick.playerId }) {
                grades.merge(quarterback.grades ?? [:]) { _, seen in seen }
                if let cast = spin.supportingCastGrade { grades[.supportingCast] = cast }
            }
            return QbPickedPlayer(pick: pick, grades: grades)
        }
    }

    // MARK: - Moves

    /// Deals the run. A no-op once there is a board, so a screen re-appearing
    /// (coming back from another tab) never abandons a run for a fresh one.
    func start() async {
        guard board == nil, !isBusy else { return }
        isBusy = true
        startFailed = false
        errorMessage = nil
        defer { isBusy = false }
        do {
            board = try await client.startRun(mode: mode, era: era)
        } catch {
            startFailed = true
            errorMessage = QbSeasonBuilderServerError.describe(error)
        }
    }

    func choose(_ slot: QbSlot, from playerId: String?) {
        guard stage == .picking, !isTaken(slot) else { return }
        choice = Choice(slot: slot, playerId: playerId)
    }

    func lockInPick() async {
        guard let board, let choice, !isBusy else { return }
        await move { try await self.client.pick(matchId: board.matchId, slot: choice.slot, playerId: choice.playerId) }
        // The last pick goes straight to the reveal — there is nothing to confirm.
        // If finishing fails, the run stays ready to finish and the screen offers a retry.
        if self.board?.phase == .readyToFinish { await finish() }
    }

    func respin() async {
        guard let board, canRespin else { return }
        await move { try await self.client.respin(matchId: board.matchId) }
    }

    /// Turns the six picks into the season and starts its reveal.
    func finish() async {
        guard let board, board.phase == .readyToFinish, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let saved = try await client.finish(matchId: board.matchId)
            await land(saved, from: board)
        } catch let error as QbSeasonBuilderServerError where error.message == "match_not_playing" {
            // Already finished — another device, or an earlier tap whose answer
            // was lost. Its reveal is where the player should land, not an error.
            do {
                let saved = try await client.result(matchId: board.matchId)
                await land(saved, from: board)
            } catch {
                await refreshAfterRefusal(from: board.matchId)
            }
        } catch {
            errorMessage = QbSeasonBuilderServerError.describe(error)
        }
    }

    /// Abandons nothing — a finished run is finished — and deals a fresh one in
    /// the same mode.
    func newSeason() async {
        guard !isBusy else { return }
        board = nil
        choice = nil
        result = nil
        personalBest = nil
        revealStage = .score
        revealSkipped = false
        await start()
    }

    // MARK: - The reveal

    /// Whether `stage` has been reached, and so should be drawn.
    func shows(_ stage: RevealStage) -> Bool {
        stage <= currentRevealStage
    }

    /// Still playing: there is more to come, and it can be skipped. It plays
    /// once by nature — a finished run has no way back in, so leaving the
    /// screen is the end of its reveal.
    var isRevealing: Bool {
        result != nil && !revealSkipped && revealStage < RevealStage.allCases.last!
    }

    func advanceReveal() {
        guard isRevealing, let next = RevealStage(rawValue: revealStage.rawValue + 1) else { return }
        revealStage = next
    }

    func skipReveal() {
        revealSkipped = true
    }

    private var currentRevealStage: RevealStage {
        isRevealing ? revealStage : RevealStage.allCases.last!
    }

    // MARK: - Private

    /// One move that answers with the whole new board.
    private func move(_ call: () async throws -> QbBoard) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            board = try await call()
            choice = nil
        } catch {
            errorMessage = QbSeasonBuilderServerError.describe(error)
            // A refusal usually means this screen is behind the server, so read
            // the run again rather than leave it stale.
            if let matchId = board?.matchId { await refreshAfterRefusal(from: matchId) }
        }
    }

    private func refreshAfterRefusal(from matchId: UUID) async {
        guard let latest = try? await client.state(matchId: matchId) else { return }
        board = latest
        choice = nil
    }

    /// Takes the saved season, then reads what only the finished run can show:
    /// the run's `shown` spins (in a hidden run, the values of everything the
    /// player saw) and the personal best the run may just have raised. Neither
    /// is worth withholding the season for.
    private func land(_ saved: QbSeasonResult, from board: QbBoard) async {
        result = saved
        choice = nil
        revealStage = .score
        revealSkipped = false
        if let finished = try? await client.state(matchId: board.matchId) { self.board = finished }
        personalBest = try? await client.personalBest(userId: viewerId, mode: saved.mode)
    }
}
