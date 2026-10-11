import Foundation

/// One live Wavelength match, from the clue-writing phase to the result.
///
/// The server is authoritative for every rule — the hidden target, the clue
/// limits, the score for a locked guess, whose turn it is. This decides which
/// RPC to call and what to show. Nothing it reads is secret that the viewer may
/// not see: the target, the cards and the clues arrive already narrowed by
/// row-level security, so "am I the psychic?" is answered by the data, and the
/// UI only decides how to draw what it was given.
///
/// The same three things that keep the other match screens honest apply here:
///
/// - **Realtime is the fast path, not the only path.** Any change behind the
///   board re-reads it; so does every (re)subscribe, a foreground, and a
///   deadline that stays past too long.
/// - **Expiry is asked for repeatedly, and by everyone.** `tick` is idempotent
///   on the server, and it doubles as the presence heartbeat, so the clock asks
///   before the deadline too.
/// - **The needle is cosmetic until it is locked.** It is broadcast to the table
///   a few times a second and reported to the server lazily, so an auto-lock
///   lands where the guesser left it — but only `lock_guess` scores.
@MainActor
final class WavelengthViewModel: ObservableObject {
    @Published private(set) var snapshot: WavelengthSnapshot?
    @Published private(set) var isSaving = false
    @Published private(set) var isLocking = false
    @Published private(set) var errorMessage: String?
    /// The clue being typed. Kept here, not in the view, so it survives a tab
    /// switch.
    @Published var clueDraft = ""
    /// The needle as the guesser has it, and as spectators see it.
    @Published private(set) var needle = WavelengthRules.needleStart
    /// A round that just settled, shown above whatever the table moved on to.
    @Published private(set) var revealRound: Int?

    let matchId: UUID
    let viewerId: UUID
    let roomCode: String?
    let isHost: Bool
    private let client: WavelengthClient
    private let now: () -> Date
    private let revealDuration: Duration

    private(set) lazy var clock = MatchClockDriver(
        now: now,
        expire: { [weak self] in await self?.expire() },
        reconcile: { [weak self] in await self?.reconcile() }
    )

    private var observation: Task<Void, Never>?
    private var revealTask: Task<Void, Never>?
    private var readsIssued = 0
    private var latestApplied = 0
    private var finalReadRequested = false
    private var settledRounds: Set<Int>?
    private var needleRound: Int?
    private var lastBroadcastAt = Date.distantPast
    private var lastReportAt = Date.distantPast
    private var pendingReport: Task<Void, Never>?
    /// How long the current phase's clock started at, for the countdown bar.
    private var phaseSpanMs = 0
    private var spanDeadline: Date?

    static let broadcastInterval: TimeInterval = 0.1
    static let reportInterval: TimeInterval = 1

    init(
        client: WavelengthClient,
        matchId: UUID,
        viewerId: UUID,
        roomCode: String? = nil,
        isHost: Bool = false,
        now: @escaping () -> Date = Date.init,
        revealDuration: Duration = .seconds(5)
    ) {
        self.client = client
        self.matchId = matchId
        self.viewerId = viewerId
        self.roomCode = roomCode
        self.isHost = isHost
        self.now = now
        self.revealDuration = revealDuration
    }

    deinit {
        observation?.cancel()
        revealTask?.cancel()
        pendingReport?.cancel()
    }

    // MARK: - Derived state

    var board: WavelengthBoard? { snapshot?.board }
    var players: [WavelengthPlayer] { snapshot?.players ?? [] }
    var rounds: [WavelengthRound] { snapshot?.rounds ?? [] }
    var result: WavelengthResult? { snapshot?.result }
    var isPaused: Bool { snapshot?.matchStatus == .paused }
    var isFinished: Bool { board?.phase == .complete || snapshot?.matchStatus == .complete }
    var mode: WavelengthMode { board?.mode ?? .versus }

    var current: WavelengthRound? { rounds.first { $0.round == board?.currentRound } }
    var currentCard: WavelengthCard? { snapshot?.cards.first { $0.round == board?.currentRound } }
    var currentClue: String? { snapshot?.clues.first { $0.round == board?.currentRound }?.clue }
    /// Non-nil only for the round's psychic, until the guess locks.
    var currentTarget: Int? { snapshot?.targets.first { $0.round == board?.currentRound }?.target }

    var isPsychic: Bool { current?.psychicId == viewerId }
    var isGuesser: Bool { current?.guesserId == viewerId }

    func player(_ id: UUID) -> WavelengthPlayer? { players.first { $0.userId == id } }

    private func hasClue(_ round: Int) -> Bool {
        snapshot?.clueStatuses.contains { $0.round == round } ?? false
    }

    /// Fill is parallel: `currentRound` is the first round that will be
    /// guessed, not necessarily this psychic's card. A psychic may own several
    /// rounds, and a written round stays pending until it is guessed, so the
    /// one to write next is their first pending round with no clue yet.
    var fillRound: WavelengthRound? {
        rounds.first { $0.psychicId == viewerId && $0.status == .pending && !hasClue($0.round) }
    }
    var fillTotal: Int { rounds.filter { $0.psychicId == viewerId && $0.status == .pending }.count }
    var fillWritten: Int {
        rounds.filter { $0.psychicId == viewerId && $0.status == .pending && hasClue($0.round) }.count
    }
    var fillCard: WavelengthCard? {
        fillRound.flatMap { round in snapshot?.cards.first { $0.round == round.round } }
    }
    var fillTarget: Int? {
        fillRound.flatMap { round in snapshot?.targets.first { $0.round == round.round }?.target }
    }
    var canFill: Bool { board?.phase == .fill && fillRound != nil && fillCard != nil && !isPaused }

    var canLock: Bool {
        board?.phase == .guess && isGuesser && currentCard != nil && !isLocking && !isPaused
    }

    /// The clue draft's problem, if any — shown as the player types.
    var clueProblem: String? {
        clueDraft.isEmpty ? nil : WavelengthRules.validateClue(clueDraft)
    }

    /// What one player is doing right now, for the Table lines.
    func status(of player: WavelengthPlayer) -> (text: String, concealed: Bool) {
        guard let board else { return ("", false) }
        if board.phase == .fill {
            let pending = rounds.filter { $0.psychicId == player.userId && $0.status == .pending }
            let done = !pending.isEmpty && pending.allSatisfy { hasClue($0.round) }
            return (done ? "Clues written" : player.absent ? "Absent" : "Writing…", false)
        }
        if current?.psychicId == player.userId {
            return (board.phase == .reveal ? "Clue revealed" : "Clue locked", board.phase != .reveal)
        }
        if current?.guesserId == player.userId {
            return (board.phase == .reveal ? "Locked \(current?.points ?? 0)" : "Guessing now", false)
        }
        return (player.absent ? "Absent" : "Watching", false)
    }

    /// 0...1 of the phase left, or `nil` when nothing is timed.
    var clockFraction: Double? {
        guard let remaining = clock.remainingMs, phaseSpanMs > 0 else { return nil }
        return min(1, Double(remaining) / Double(phaseSpanMs))
    }

    func teamPlayers(_ team: Int) -> [WavelengthPlayer] { players.filter { $0.team == team } }
    var teams: [Int] { mode == .coop ? [0] : [0, 1] }
    func score(of team: Int) -> Int { board?.teamScores[safe: team] ?? 0 }

    /// The team the viewer plays on, for "you lead / trail" copy.
    var myTeam: Int { player(viewerId)?.team ?? 0 }

    // MARK: The ending

    /// Versus: the winning team, from the recorded outcome.
    var winningTeam: Int? {
        switch result?.outcome {
        case "team_0_win": 0
        case "team_1_win": 1
        default: nil
        }
    }

    /// How a versus tie was settled, if it was.
    var settledBy: String? {
        guard mode == .versus, let board else { return nil }
        if rounds.count > board.roundCount { return "Sudden death" }
        if board.teamScores.count == 2, board.teamScores[0] == board.teamScores[1] { return "Bullseye tiebreak" }
        return nil
    }

    var postGameAction: PostGameAction? { snapshot?.postGame }

    var canChoosePostGame: Bool {
        isFinished && isHost && postGameAction == nil && !isSaving
    }

    // MARK: - Intents

    /// Read the match and start following it. Subscribing first means the
    /// `SUBSCRIBED` re-read covers anything that changed while this was in flight.
    func load() async {
        observe()
        await reconcile()
        clock.start()
    }

    func submitClue() async {
        guard canFill, !isSaving, let round = fillRound else { return }
        if let problem = WavelengthRules.validateClue(clueDraft) {
            errorMessage = problem
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let board = try await client.submitClue(
                matchId: matchId, round: round.round,
                clue: clueDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            clueDraft = ""
            apply(board: board)
            await reconcile()
        } catch {
            errorMessage = WavelengthServerError.describe(error)
            await reconcile()
        }
    }

    /// Move the needle. For the guesser this also tells the table (throttled)
    /// and the server (lazily, for an auto-lock).
    func moveNeedle(to position: Int) {
        let clamped = min(max(position, 0), WavelengthRules.scaleMax)
        needle = clamped
        guard canLock, let round = current?.round else { return }

        let stamp = now()
        if stamp.timeIntervalSince(lastBroadcastAt) >= Self.broadcastInterval {
            lastBroadcastAt = stamp
            let client = client, matchId = matchId
            Task { await client.sendNeedle(matchId: matchId, round: round, position: clamped) }
        }
        // Lazy and best-effort: `lock_guess` carries the authoritative position.
        if pendingReport == nil {
            let delay = max(0, Self.reportInterval - stamp.timeIntervalSince(lastReportAt))
            pendingReport = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.pendingReport = nil
                self.lastReportAt = self.now()
                try? await self.client.reportNeedle(matchId: self.matchId, round: round, position: self.needle)
            }
        }
    }

    func lockGuess() async {
        guard canLock, let round = current?.round else { return }
        isLocking = true
        errorMessage = nil
        pendingReport?.cancel()
        pendingReport = nil
        defer { isLocking = false }
        do {
            apply(board: try await client.lockGuess(matchId: matchId, round: round, position: needle))
            await reconcile()
        } catch {
            errorMessage = WavelengthServerError.describe(error)
            await reconcile()
        }
    }

    func choosePostGame(_ choice: PostGameAction.Choice) async {
        guard canChoosePostGame else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            snapshot?.postGame = try await client.choosePostGame(matchId: matchId, choice: choice)
        } catch {
            errorMessage = WavelengthServerError.describe(error)
        }
    }

    func appReturnedToForeground() {
        clock.appReturnedToForeground()
    }

    /// Re-read the whole match and apply it. This is the clock's `reconcile`.
    func reconcile() async {
        readsIssued += 1
        let issued = readsIssued
        do {
            let fresh = try await client.snapshot(matchId: matchId)
            guard issued > latestApplied else { return }
            latestApplied = issued
            apply(fresh)
        } catch {
            // A failed background re-read leaves the last good screen up; the
            // next payload, write, or foreground tries again.
        }
    }

    func stopObserving() {
        observation?.cancel()
        observation = nil
        pendingReport?.cancel()
        pendingReport = nil
        clock.stop()
    }

    // MARK: - Private

    private func observe() {
        guard observation == nil else { return }
        // Subscribed here rather than inside the task so the channels exist
        // the moment this returns.
        let events = client.events(matchId: matchId)
        observation = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: WavelengthEvent) async {
        switch event {
        case .subscribed, .changed:
            await reconcile()
        case .matchStatus(let status):
            snapshot?.matchStatus = status
            observeClock()
        case .postGame(let action):
            snapshot?.postGame = action
        case .needle(let round, let position):
            // The guesser has their own exact value; never replace it with a
            // round trip, even if the server echoes.
            guard board?.phase == .guess, !isGuesser, round == board?.currentRound else { return }
            needle = position
        }
    }

    private func apply(_ fresh: WavelengthSnapshot) {
        snapshot = fresh
        noteSettledRounds()
        resetNeedleIfRoundChanged()
        observeClock()
        requestFinalReadIfNeeded()
    }

    private func apply(board: WavelengthBoard) {
        snapshot?.board = board
        resetNeedleIfRoundChanged()
        observeClock()
        requestFinalReadIfNeeded()
    }

    /// Every round starts from the middle of the dial.
    private func resetNeedleIfRoundChanged() {
        guard let round = board?.currentRound, round != needleRound else { return }
        needleRound = round
        needle = WavelengthRules.needleStart
        errorMessage = nil
        pendingReport?.cancel()
        pendingReport = nil
    }

    /// A round that just settled is shown to everyone for a few seconds above
    /// whatever the table has moved on to. Rounds already settled when the
    /// screen mounted (or on rejoin) are not replayed.
    private func noteSettledRounds() {
        let settled = Set(rounds.filter(WavelengthRules.settled).map(\.round))
        defer { settledRounds = settled }
        guard let known = settledRounds else { return }
        guard let fresh = settled.subtracting(known).max() else { return }
        revealRound = fresh
        revealTask?.cancel()
        revealTask = Task { [weak self, revealDuration] in
            try? await Task.sleep(for: revealDuration)
            guard !Task.isCancelled else { return }
            self?.revealRound = nil
        }
    }

    private func requestFinalReadIfNeeded() {
        guard isFinished, !finalReadRequested else { return }
        finalReadRequested = true
        Task { await reconcile() }
    }

    /// The clock's `expire`: ask the server to advance a passed deadline.
    private func expire() async {
        do {
            apply(board: try await client.tick(matchId: matchId))
        } catch {
            // Asking again is free; the clock retries.
        }
    }

    private func observeClock() {
        guard let snapshot else { return }
        if let deadline = snapshot.board.phaseDeadline, deadline != spanDeadline {
            spanDeadline = deadline
            phaseSpanMs = max(0, Int(deadline.timeIntervalSince(snapshot.board.serverNow) * 1000))
        }
        clock.observe(
            serverNow: snapshot.board.serverNow,
            deadline: isFinished ? nil : snapshot.board.phaseDeadline,
            config: MatchClockConfig(
                // A guess can still be sent right up to the deadline, so the
                // visible countdown ends early for it.
                visibleSlackMs: snapshot.board.phase == .guess ? MatchClockConstants.visibleSlackMs : 0,
                skipExpiry: false,
                heartbeatMs: MatchClockConstants.heartbeatMs,
                paused: isPaused
            )
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
