import Foundation

/// One solo Higher or Lower run, from format picker to recap.
///
/// The server is authoritative for every rule — dealing, scoring, the endless
/// ladder, when a run ends. This only decides which RPC to call and what to
/// show, and re-reads the whole match after every write and whenever the app
/// returns to the foreground (`MatchClock`'s reconciliation), so no single
/// dropped response or suspended interval can leave the screen wrong.
///
/// There is no Realtime subscription: a solo match has exactly one client, so
/// every change to it is one this view model made and already re-read.
@MainActor
final class SoloRunViewModel: ObservableObject {
    enum Stage: Equatable {
        /// Picking scoring mode and era.
        case setup
        /// A dealt ladder is in play.
        case playing
        /// The run ended; show the recap.
        case complete
    }

    /// How the viewer's call at a question came out, for the reveal banner and
    /// the recap. Derived from the cards' points — the same comparison the
    /// server made when it scored it.
    enum Outcome: Equatable {
        case startingPoint
        case correct(CallDirection)
        case miss(CallDirection)
        case timedOut

        var isCorrect: Bool {
            if case .correct = self { true } else { false }
        }

        var label: String {
            switch self {
            case .startingPoint: "Starting point"
            case .correct(let direction): "Called \(direction.rawValue) · correct"
            case .miss(let direction): "Called \(direction.rawValue) · miss"
            case .timedOut: "Timed out"
            }
        }
    }

    struct RecapEntry: Equatable, Identifiable {
        let card: LadderCard
        let outcome: Outcome
        var id: Int { card.ordinal }
    }

    struct Recap: Equatable {
        /// The run's score: total correct answers.
        let correct: Int
        let bestStreak: Int
        /// The viewer's all-time high, including this run.
        let personalBest: Int
        /// This run beat the all-time high the viewer had when it started.
        let isNewPersonalBest: Bool
        let ladder: [RecapEntry]
    }

    // MARK: Format picker

    @Published var scoringMode: ScoringMode = .seasonTotal
    /// Moving either end past the other drags the other along, so the picker
    /// can never hold an inverted range (`invalid_season_range`).
    @Published var seasonFrom = 0 {
        didSet { if seasonFrom > seasonTo { seasonTo = seasonFrom } }
    }
    @Published var seasonTo = 0 {
        didSet { if seasonTo < seasonFrom { seasonFrom = seasonTo } }
    }
    /// The pool's first and last season, once loaded; the picker's limits.
    @Published private(set) var seasonBounds: SeasonRange?

    // MARK: Run

    @Published private(set) var snapshot: HigherOrLowerSnapshot?
    /// The viewer's all-time high as it stood *before* this run's first call.
    /// The stats row is updated by a trigger as the run's streak grows, so the
    /// personal-best comparison at the end needs the value from before it.
    @Published private(set) var personalBestBeforeRun = 0
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    let viewerId: UUID
    private let client: HigherOrLowerClient

    /// Drives the countdown and the expiry/heartbeat/reconcile asks. Solo boards
    /// never carry a deadline (`0084`), so today this only ever does its
    /// foreground reconcile — but the screen reads the same board fields a
    /// timed one would, so a deadline needs no special case.
    private(set) lazy var clock = MatchClockDriver(
        now: now,
        expire: { [weak self] in await self?.expire() },
        reconcile: { [weak self] in await self?.reconcile() }
    )
    private let now: () -> Date

    /// Full re-reads can overlap (a foreground reconcile racing a call's
    /// refresh). Each is numbered when issued and only applied if no later one
    /// has already been, so a slow older read never rolls the screen back.
    private var readsIssued = 0
    private var latestApplied = 0

    /// The match a `playAgain` replay created, until it has loaded. Replaying
    /// spends the finished match's one post-game choice, so a retry after a
    /// failed load must reuse this rather than replay again.
    private var replayedMatchId: UUID?

    init(client: HigherOrLowerClient, viewerId: UUID, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.viewerId = viewerId
        self.now = now
    }

    // MARK: - Derived state

    var stage: Stage {
        guard let snapshot else { return .setup }
        return snapshot.board.phase == .complete ? .complete : .playing
    }

    var board: HigherOrLowerBoard? { snapshot?.board }

    var viewer: LadderPlayer? { snapshot?.players.first { $0.userId == viewerId } }

    var correctCount: Int { viewer?.correctCount ?? 0 }
    var currentStreak: Int { viewer?.currentStreak ?? 0 }

    /// The best streak on record: the viewer's all-time high, or this run's if
    /// it has already passed it.
    var allTimeHigh: Int { max(personalBestBeforeRun, viewer?.bestStreak ?? 0) }

    /// Solo has no fixed ceiling — the ladder keeps extending until a miss — so
    /// it is only ever "Question N", never "N of 12".
    var questionLabel: String {
        guard let board else { return "" }
        return "Question \(board.currentQuestion)"
    }

    var formatLabel: String {
        guard let board else { return "" }
        return "\(board.scoringMode.label) · \(board.season.label)"
    }

    /// The face-up card the challenger is priced against.
    var anchor: LadderCard? {
        guard let snapshot else { return nil }
        return snapshot.cards.first { $0.ordinal == snapshot.board.currentQuestion - 1 }
    }

    /// The card being called. Its points stay concealed until the phase says
    /// the question has revealed, even if a card row raced ahead of the board.
    var challenger: LadderCard? {
        guard let snapshot,
              let card = snapshot.cards.first(where: { $0.ordinal == snapshot.board.currentQuestion })
        else { return nil }
        return snapshot.board.phase.showsChallengerPoints ? card : card.concealingPoints()
    }

    var myCall: LadderCall? {
        guard let snapshot else { return nil }
        return snapshot.calls.first { $0.question == snapshot.board.currentQuestion && $0.userId == viewerId }
    }

    var canCall: Bool {
        board?.phase == .call && myCall == nil && !isBusy
    }

    /// Solo has no timer pushing the player out of a reveal; they tap Continue.
    var canContinue: Bool {
        board?.phase == .reveal && !isBusy
    }

    /// What became of the viewer's call at the current question, once it has
    /// revealed.
    var currentOutcome: Outcome? {
        guard let snapshot, snapshot.board.phase.showsChallengerPoints,
              let card = challenger
        else { return nil }
        return outcome(for: card, in: snapshot)
    }

    var recap: Recap? {
        guard let snapshot, stage == .complete else { return nil }
        let revealed = snapshot.cards.filter { $0.points != nil }.sorted { $0.ordinal < $1.ordinal }
        let best = viewer?.bestStreak ?? 0
        return Recap(
            correct: correctCount,
            bestStreak: best,
            personalBest: allTimeHigh,
            isNewPersonalBest: best > personalBestBeforeRun,
            ladder: revealed.map { RecapEntry(card: $0, outcome: outcome(for: $0, in: snapshot)) }
        )
    }

    /// The seasons the picker may offer, in order.
    var seasonChoices: [Int] {
        guard let seasonBounds else { return [] }
        return Array(seasonBounds.from...seasonBounds.to)
    }

    var canStart: Bool {
        seasonBounds != nil && seasonFrom <= seasonTo && !isBusy
    }

    // MARK: - Intents

    /// Loads the picker's limits and defaults it to the whole pool. Safe to
    /// call again; it never overwrites a choice the player already made.
    func loadSetup() async {
        guard seasonBounds == nil else { return }
        do {
            let bounds = try await client.seasonBounds()
            seasonBounds = bounds
            seasonFrom = bounds.from
            seasonTo = bounds.to
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func start() async {
        guard canStart else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            // Read before dealing: nothing can have moved the stats row yet.
            let best = try await client.personalBest()
            let board = try await client.startSoloRun(
                scoringMode: scoringMode,
                era: SeasonRange(from: seasonFrom, to: seasonTo)
            )
            personalBestBeforeRun = best
            try await beginRun(matchId: board.matchId)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    func call(_ direction: CallDirection) async {
        guard canCall, let matchId = board?.matchId else { return }
        isBusy = true
        errorMessage = nil
        do {
            _ = try await client.call(matchId: matchId, direction: direction)
        } catch {
            errorMessage = Self.describe(error)
        }
        // Read back either way: on success this is what shows the reveal, and
        // on a rejection (`already_called`, ...) it puts the screen back on the
        // server's truth. Stay busy until it lands — until then the board still
        // says "call" with no call of ours in it, which would re-enable the
        // buttons for a second tap.
        await reconcile()
        isBusy = false
    }

    func continueRun() async {
        guard canContinue, let matchId = board?.matchId else { return }
        isBusy = true
        errorMessage = nil
        do {
            _ = try await client.advance(matchId: matchId)
        } catch {
            errorMessage = Self.describe(error)
        }
        await reconcile()
        isBusy = false
    }

    /// A fresh ladder in the format just played, dealt by the server.
    func playAgain() async {
        guard stage == .complete, let matchId = board?.matchId else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            // The finished run's streak is in the stats row already, and the
            // new ladder will have had no calls, so this is the "before" for
            // the next run. Read it *first*: the replay below spends the
            // match's one-time post-game choice, and a failure after that
            // would leave nothing for a retry to do.
            let best = try await client.personalBest()
            // If a previous attempt made the replay but then failed to load the
            // new match, that choice is spent — pick the match up instead of
            // asking again (`post_game_choice_already_made`).
            let nextMatchId: UUID
            if let pending = replayedMatchId {
                nextMatchId = pending
            } else {
                nextMatchId = try await client.replay(matchId: matchId)
                replayedMatchId = nextMatchId
            }
            personalBestBeforeRun = best
            try await beginRun(matchId: nextMatchId)
            replayedMatchId = nil
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Back to the format picker, e.g. from the recap.
    func returnToSetup() {
        clock.stop()
        snapshot = nil
        errorMessage = nil
        replayedMatchId = nil
        // Anything still in flight was a read of the run just left. Marking
        // every issued read as already superseded stops a late one from
        // re-applying it and dragging the player back to the recap.
        latestApplied = readsIssued
    }

    /// The app returned to the foreground. Hands off to the clock, which
    /// reconciles unconditionally — a suspended app's countdown may barely have
    /// run, and the match may have moved without it.
    func appReturnedToForeground() {
        guard snapshot != nil else { return }
        clock.appReturnedToForeground()
    }

    /// Re-reads the whole match and applies it. This is the clock's `reconcile`.
    func reconcile() async {
        guard let matchId = board?.matchId else { return }
        await refresh(matchId: matchId)
    }

    // MARK: - Private

    private func beginRun(matchId: UUID) async throws {
        readsIssued += 1
        let issued = readsIssued
        let fresh = try await client.snapshot(matchId: matchId)
        latestApplied = issued
        apply(fresh)
        clock.start()
    }

    private func refresh(matchId: UUID) async {
        readsIssued += 1
        let issued = readsIssued
        do {
            let fresh = try await client.snapshot(matchId: matchId)
            guard issued > latestApplied else { return }
            latestApplied = issued
            apply(fresh)
        } catch {
            // A failed background re-read leaves the last good screen up; the
            // next tick, write, or foreground tries again.
        }
    }

    private func apply(_ fresh: HigherOrLowerSnapshot) {
        snapshot = fresh
        observeClock(fresh.board)
    }

    /// The clock's `expire`: ask the server to advance a passed deadline (and,
    /// via `tick`'s presence stamp, say we are here). If the board moved, the
    /// cards and calls behind it did too, so re-read everything.
    private func expire() async {
        guard let matchId = board?.matchId else { return }
        do {
            let ticked = try await client.tick(matchId: matchId)
            if let current = board, !ticked.samePosition(as: current) {
                await refresh(matchId: matchId)
            } else {
                observeClock(ticked)
            }
        } catch {
            // Asking again is free; the clock retries.
        }
    }

    private func observeClock(_ board: HigherOrLowerBoard) {
        clock.observe(
            serverNow: board.serverNow,
            // A finished match has no deadline to chase, whatever the row says.
            deadline: board.phase == .complete ? nil : board.phaseDeadline,
            config: MatchClockConfig(
                visibleSlackMs: MatchClockConstants.visibleSlackMs,
                // The tick is also how a player says they are still here.
                heartbeatMs: MatchClockConstants.heartbeatMs
            )
        )
    }

    private func outcome(for card: LadderCard, in snapshot: HigherOrLowerSnapshot) -> Outcome {
        guard let prior = snapshot.cards.first(where: { $0.ordinal == card.ordinal - 1 }),
              let priorPoints = prior.points, let points = card.points
        else { return .startingPoint }
        guard let call = snapshot.calls.first(where: { $0.question == card.ordinal && $0.userId == viewerId }),
              !call.timedOut, let direction = call.direction
        else { return .timedOut }
        let correct = points > priorPoints ? direction == .higher : direction == .lower
        return correct ? .correct(direction) : .miss(direction)
    }

    /// Maps a raised message to a sentence for the player, the way the web's
    /// `CALL_MESSAGES` does; anything unmapped falls back to the raw message.
    static func describe(_ error: Error) -> String {
        guard let server = error as? HigherOrLowerServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        return messages[server.message] ?? server.message
    }

    private static let messages: [String: String] = [
        "already_called": "You already locked in this question.",
        "call_not_open": "Calls are not open right now.",
        "call_deadline_passed": "The call window has closed.",
        "match_not_playing": "This match isn't accepting moves right now.",
        "advance_not_open": "The answer isn't ready to move past yet.",
        "season_out_of_range": "That era is outside the seasons we have data for.",
        "invalid_season_range": "The first season can't be after the last one.",
    ]
}
