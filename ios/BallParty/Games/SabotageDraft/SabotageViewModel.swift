import Foundation

/// One live Sabotage Draft match, from the first spin to the season result.
///
/// The server is authoritative for every rule — the spins, whether a pick or a
/// guess is in the pool, which guesses hit, the simulated season. This decides
/// which RPC to call and what to show. Nothing it reads is secret that the
/// viewer may not see: picks arrive already narrowed by row-level security, so
/// "is this pick mine to see?" is answered by the data, and the UI only decides
/// how to draw what it was given. Red means concealed, cream means revealed.
///
/// The same three things that keep the other match screens honest apply here:
///
/// - **Realtime is the fast path, not the only path.** Any change behind the
///   board re-reads it; so does every (re)subscribe, a foreground, and a
///   deadline that stays past too long.
/// - **Expiry is asked for repeatedly, and by everyone.** `tick` is idempotent
///   on the server, and it doubles as the presence heartbeat, so the clock asks
///   before the deadline too.
/// - **One shared clock per turn.** The drafter may lock a pick any time within
///   it, and every other seat one guess or one pass, so there is no pick/guess
///   phase to key off — only "is the turn open" and "have I already acted".
@MainActor
final class SabotageViewModel: ObservableObject {
    enum GuessKind: Equatable { case player, exact }

    @Published private(set) var snapshot: SabotageSnapshot?
    /// The player-seasons the current turn's franchise offers: the viewer's own
    /// spin when they are drafting, otherwise the drafter's (to guess against).
    @Published private(set) var pool: [SabotageOption] = []
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    // Half-made moves live here, not in the view, so they survive a tab switch.
    // All are cleared when the turn changes.
    @Published var pickChoice: SabotageOption?
    @Published var guessKind: GuessKind?
    @Published var guessChoice: SabotageOption?
    @Published var replacementChoice: SabotageOption?

    let matchId: UUID
    let viewerId: UUID
    let roomCode: String?
    let isHost: Bool
    private let client: SabotageClient
    private let now: () -> Date

    private(set) lazy var clock = MatchClockDriver(
        now: now,
        expire: { [weak self] in await self?.expire() },
        reconcile: { [weak self] in await self?.reconcile() }
    )

    private var observation: Task<Void, Never>?
    private var poolTask: Task<Void, Never>?
    private var readsIssued = 0
    private var latestApplied = 0
    private var finalReadRequested = false
    private var turnKey: String?
    private var poolKey: String?

    init(
        client: SabotageClient,
        matchId: UUID,
        viewerId: UUID,
        roomCode: String? = nil,
        isHost: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.matchId = matchId
        self.viewerId = viewerId
        self.roomCode = roomCode
        self.isHost = isHost
        self.now = now
    }

    deinit {
        observation?.cancel()
        poolTask?.cancel()
    }

    // MARK: - Derived state

    var board: SabotageBoard? { snapshot?.board }
    /// In seat order, which is the order turns come around.
    var players: [SabotagePlayer] { (snapshot?.players ?? []).sorted { $0.seat < $1.seat } }
    var standings: [SabotageStanding] { snapshot?.standings ?? [] }
    var isPaused: Bool { snapshot?.matchStatus == .paused }
    var isFinished: Bool { !standings.isEmpty }
    var mode: SabotageMode { board?.mode ?? .full }
    var roundCount: Int { board?.roundCount ?? 0 }

    func player(_ id: UUID) -> SabotagePlayer? { players.first { $0.userId == id } }

    var activePlayer: SabotagePlayer? { board?.activeUserId.flatMap(player) }
    var isActive: Bool { board?.activeUserId == viewerId }
    var activeIndex: Int? { players.firstIndex { $0.userId == board?.activeUserId } }

    /// The turn is open for moves: there is a clock running.
    var turnOpen: Bool { board?.turnDeadline != nil }

    /// The active seat's spin for the current round — public once that seat's
    /// turn is reached.
    var activeSpin: SabotageSpin? {
        snapshot?.spins.first { $0.round == board?.currentRound && $0.userId == board?.activeUserId }
    }

    var myPick: SabotagePick? {
        snapshot?.picks.first { $0.round == board?.currentRound && $0.userId == viewerId }
    }

    /// A guess or a pass is spent per (round, target) — the same player gets a
    /// fresh shot on every seat's own turn — so "have I acted?" is scoped to
    /// whoever currently holds the turn.
    var myGuess: SabotageGuess? {
        snapshot?.guesses.first {
            $0.round == board?.currentRound && $0.targetUserId == board?.activeUserId && $0.userId == viewerId
        }
    }

    var myPass: SabotagePass? {
        snapshot?.passes.first {
            $0.round == board?.currentRound && $0.targetUserId == board?.activeUserId && $0.userId == viewerId
        }
    }

    var hasActed: Bool { myGuess != nil || myPass != nil }

    /// Seats still to act on this turn: everyone but the drafter, minus those
    /// who have guessed or passed.
    var seatsStillToAct: [SabotagePlayer] {
        guard let snapshot, let board else { return [] }
        return players.filter { seat in
            guard seat.userId != board.activeUserId else { return false }
            let guessed = snapshot.guesses.contains {
                $0.round == board.currentRound && $0.targetUserId == board.activeUserId && $0.userId == seat.userId
            }
            let passed = snapshot.passes.contains {
                $0.round == board.currentRound && $0.targetUserId == board.activeUserId && $0.userId == seat.userId
            }
            return !guessed && !passed
        }
    }

    /// Rounds the viewer has locked a pick for, out of the match's rounds.
    var myFilledCount: Int {
        snapshot?.statuses.filter { $0.userId == viewerId }.count ?? 0
    }

    func filledCount(of player: SabotagePlayer) -> Int {
        snapshot?.statuses.filter { $0.userId == player.userId }.count ?? 0
    }

    func hitCount(on player: SabotagePlayer) -> Int {
        snapshot?.hits.filter { $0.targetUserId == player.userId }.count ?? 0
    }

    /// The turn clock's status line.
    var turnLabel: String {
        guard let board else { return "" }
        let name = activePlayer?.name ?? "…"
        if isActive {
            if board.turnDeadline != nil { return "Your pick" }
            return board.xFactorOpen ? "Your X-Factor" : ""
        }
        if board.turnDeadline != nil { return "Sabotage \(name)" }
        return board.xFactorOpen ? "\(name)'s X-Factor" : "Locked"
    }

    /// 0...1 of the turn left, or `nil` when nothing is timed.
    var clockFraction: Double? {
        guard let remaining = clock.remainingMs else { return nil }
        let span = SabotageRules.turnDurationMs - MatchClockConstants.visibleSlackMs
        return min(1, max(0, Double(remaining) / Double(span)))
    }

    // MARK: Moves

    var canLockPick: Bool {
        turnOpen && isActive && myPick == nil && pickChoice != nil && !isSaving && !isPaused
    }

    var canGuess: Bool { turnOpen && !isActive && !hasActed && !isSaving && !isPaused }

    var canLockGuess: Bool {
        guard canGuess, guessChoice != nil, let kind = guessKind else { return false }
        return kind == .player || replacementChoice != nil
    }

    var canDecideXFactor: Bool {
        guard let board else { return false }
        return board.xFactorOpen && isActive && myDecision == nil && !isSaving && !isPaused
    }

    var myDecision: SabotageDecision? {
        snapshot?.decisions.first { $0.userId == viewerId }
    }

    /// The slots the viewer's X-Factor pick may replace, from its position.
    var xFactorSlots: [String] {
        guard let board, let pick = snapshot?.picks.first(where: { $0.round == board.roundCount && $0.userId == viewerId })
        else { return [] }
        let category = pool.first { $0.playerId == pick.playerId && $0.season == pick.season }?.category
        return SabotageRules.xFactorTargets(category: category, roundCount: board.roundCount)
    }

    var xFactorPick: SabotagePick? {
        snapshot?.picks.first { $0.round == board?.roundCount && $0.userId == viewerId }
    }

    // MARK: Rosters

    /// What one cell of a seat's roster shows, given what the viewer may know.
    enum RosterCell: Equatable {
        /// The pick itself is visible: the viewer's own, or one whose turn is over.
        case pick(SabotagePick)
        /// The viewer's own pick is locked but its row has not arrived.
        case locked
        /// Someone else's locked pick — concealed, but the spun franchise shows.
        case concealed(franchise: String?)
        case choosing
        case upNext
        case notReached
    }

    func cell(for player: SabotagePlayer, round: Int) -> (cell: RosterCell, respun: Bool, sabotaged: Bool) {
        guard let snapshot, let board else { return (.notReached, false, false) }
        let hits = snapshot.hits.filter { $0.round == round && $0.targetUserId == player.userId }
        let respun = hits.contains { $0.kind == .respin }
        let sabotaged = hits.contains { $0.kind == .sabotage }
        let filled = snapshot.statuses.contains { $0.round == round && $0.userId == player.userId }
        let pick = snapshot.picks.first { $0.round == round && $0.userId == player.userId }
        let spin = snapshot.spins.first { $0.round == round && $0.userId == player.userId }
        let seatIndex = players.firstIndex { $0.userId == player.userId } ?? 0

        let cell: RosterCell
        if let pick {
            cell = .pick(pick)
        } else if filled {
            cell = player.userId == viewerId ? .locked : .concealed(franchise: spin?.franchiseCode)
        } else if round == board.currentRound && player.userId == board.activeUserId {
            cell = .choosing
        } else if round == board.currentRound, let activeIndex, seatIndex > activeIndex {
            cell = .upNext
        } else {
            cell = .notReached
        }
        return (cell, respun, sabotaged)
    }

    // MARK: The log

    struct TurnAction: Equatable, Identifiable {
        enum Kind: Equatable { case guess, exactGuess, pass }

        let player: SabotagePlayer
        let kind: Kind
        let result: SabotageGuess.Result?

        var id: UUID { player.userId }
    }

    struct TurnRecord: Identifiable {
        let round: Int
        let slot: String
        let drafter: SabotagePlayer
        let spin: SabotageSpin?
        let pick: SabotagePick?
        let actions: [TurnAction]
        let respun: Bool
        let sabotaged: Bool

        var id: String { "\(round)-\(drafter.userId)" }
        var outcome: String {
            if respun && sabotaged { return "Respun · Sabotaged" }
            if sabotaged { return "Sabotaged" }
            return respun ? "Respun" : "Kept"
        }
    }

    /// Every turn that is over, newest first. What a turn resolved to is public
    /// even when the pick it resolved is not.
    var turnLog: [TurnRecord] {
        guard let snapshot, let board, let activeIndex else { return [] }
        let seated = players
        var records: [TurnRecord] = []
        for round in stride(from: board.currentRound, through: 1, by: -1) {
            for (index, drafter) in seated.enumerated().reversed() {
                let past = round < board.currentRound || index < activeIndex
                guard past else { continue }
                let hits = snapshot.hits.filter { $0.round == round && $0.targetUserId == drafter.userId }
                let guesses: [TurnAction] = snapshot.guesses
                    .filter { $0.round == round && $0.targetUserId == drafter.userId }
                    .compactMap { guess in
                        player(guess.userId).map {
                            TurnAction(player: $0, kind: guess.isExact ? .exactGuess : .guess, result: guess.result)
                        }
                    }
                let passes: [TurnAction] = snapshot.passes
                    .filter { $0.round == round && $0.targetUserId == drafter.userId }
                    .compactMap { pass in player(pass.userId).map { TurnAction(player: $0, kind: .pass, result: nil) } }
                let order = Dictionary(uniqueKeysWithValues: seated.enumerated().map { ($1.userId, $0) })
                records.append(
                    TurnRecord(
                        round: round,
                        slot: SabotageRules.slot(forRound: round, roundCount: board.roundCount),
                        drafter: drafter,
                        spin: snapshot.spins.first { $0.round == round && $0.userId == drafter.userId },
                        pick: snapshot.picks.first { $0.round == round && $0.userId == drafter.userId },
                        actions: (guesses + passes).sorted { (order[$0.player.userId] ?? 0) < (order[$1.player.userId] ?? 0) },
                        respun: hits.contains { $0.kind == .respin },
                        sabotaged: hits.contains { $0.kind == .sabotage }
                    )
                )
            }
        }
        return records
    }

    /// Whether the viewer's own roster has been changed by a hit they have not
    /// looked at yet — drives the Log tab's dot.
    var hitsOnViewer: Int {
        snapshot?.hits.filter { $0.targetUserId == viewerId }.count ?? 0
    }

    // MARK: The ending

    var rankedStandings: [SabotageStanding] {
        standings.sorted { $0.wins != $1.wins ? $0.wins > $1.wins : $0.tiebreakRank < $1.tiebreakRank }
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

    func lockPick() async {
        guard canLockPick, let choice = pickChoice else { return }
        await perform {
            try await self.client.submitPick(matchId: self.matchId, playerId: choice.playerId, season: choice.season)
        }
    }

    func lockGuess() async {
        guard canLockGuess, let guess = guessChoice, let kind = guessKind else { return }
        await perform {
            try await self.client.submitGuess(
                matchId: self.matchId,
                playerId: guess.playerId,
                season: kind == .exact ? guess.season : nil,
                replacement: kind == .exact ? self.replacementChoice.map { ($0.playerId, $0.season) } : nil
            )
        }
    }

    func pass() async {
        guard canGuess else { return }
        await perform { try await self.client.submitPass(matchId: self.matchId) }
    }

    func decideXFactor(replacing slot: String?) async {
        guard canDecideXFactor else { return }
        await perform { try await self.client.submitXFactorDecision(matchId: self.matchId, replaceSlot: slot) }
    }

    /// Choosing a guess type starts the guess over; changing the guess restarts
    /// the replacement, which was an answer to a question now being redone.
    func chooseGuessKind(_ kind: GuessKind?) {
        guessKind = kind
        guessChoice = nil
        replacementChoice = nil
    }

    func chooseGuess(_ option: SabotageOption?) {
        guessChoice = option
        replacementChoice = nil
    }

    func choosePostGame(_ choice: PostGameAction.Choice) async {
        guard canChoosePostGame else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            snapshot?.postGame = try await client.choosePostGame(matchId: matchId, choice: choice)
        } catch {
            errorMessage = SabotageServerError.describe(error)
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
        poolTask?.cancel()
        poolTask = nil
        clock.stop()
    }

    // MARK: - Private

    /// Runs a move, then re-reads: the server's answer is the board, and a quick
    /// second tap must not repeat the move before the new state arrives.
    private func perform(_ move: @escaping () async throws -> Void) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await move()
            await reconcile()
        } catch {
            errorMessage = SabotageServerError.describe(error)
            await reconcile()
        }
    }

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

    private func handle(_ event: SabotageEvent) async {
        switch event {
        case .subscribed, .changed:
            await reconcile()
        case .matchStatus(let status):
            snapshot?.matchStatus = status
            observeClock()
        case .postGame(let action):
            snapshot?.postGame = action
        }
    }

    private func apply(_ fresh: SabotageSnapshot) {
        snapshot = fresh
        noteTurnChange()
        observeClock()
        requestFinalReadIfNeeded()
    }

    private func apply(board: SabotageBoard) {
        snapshot?.board = board
        noteTurnChange()
        observeClock()
    }

    /// A new turn clears whatever was half-made for the last one and loads the
    /// new franchise's pool.
    private func noteTurnChange() {
        guard let board else { return }
        let key = "\(board.currentRound)-\(board.activeUserId?.uuidString ?? "none")"
        if key != turnKey {
            turnKey = key
            pickChoice = nil
            chooseGuessKind(nil)
            errorMessage = nil
        }
        loadPoolIfNeeded()
    }

    private func loadPoolIfNeeded() {
        guard let board, !isFinished else { return }
        guard let active = board.activeUserId else { return }
        // The viewer's own pool while drafting, the drafter's while guessing.
        let key = "\(board.currentRound)-\(active.uuidString)-\(active == viewerId)"
        guard key != poolKey else { return }
        poolKey = key
        pool = []
        poolTask?.cancel()
        let target: UUID? = active == viewerId ? nil : active
        poolTask = Task { [weak self] in
            guard let self else { return }
            do {
                let options = try await self.client.options(matchId: self.matchId, targetUserId: target)
                guard !Task.isCancelled, self.poolKey == key else { return }
                self.pool = options
            } catch {
                // The pool can be unavailable between turns; let the next turn
                // (or a re-read) ask again.
                if self.poolKey == key { self.poolKey = nil }
            }
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
            guard let fresh = try await client.tick(matchId: matchId) else { return }
            let changed = fresh != snapshot?.board
            apply(board: fresh)
            // A turn that moved on changed picks and hits too; realtime would
            // bring them, but asking is cheap and the clock may be the first to know.
            if changed { await reconcile() }
        } catch {
            // Asking again is free; the clock retries.
        }
    }

    private func observeClock() {
        guard let snapshot else { return }
        clock.observe(
            serverNow: snapshot.board.serverNow,
            deadline: isFinished ? nil : snapshot.board.turnDeadline,
            config: MatchClockConfig(
                // A move can still be sent right up to the deadline, so the
                // visible countdown ends early for it.
                visibleSlackMs: MatchClockConstants.visibleSlackMs,
                skipExpiry: false,
                heartbeatMs: MatchClockConstants.heartbeatMs,
                paused: isPaused
            )
        )
    }
}
