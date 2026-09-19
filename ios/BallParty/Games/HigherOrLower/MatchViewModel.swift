import Foundation

/// One live Higher or Lower match, from the first question to the final table.
///
/// The server is authoritative for every rule — dealing, scoring, whose call
/// counts, when a question expires, who won. This decides which RPC to call
/// and what to show.
///
/// Three things keep the screen honest, and they are the reason this is not
/// just "read once and render":
///
/// - **Payloads are applied directly.** A round trip per move would reintroduce
///   the latency the whole design avoids, so a board, card, call or player row
///   arriving over the channel is merged into what's on screen.
/// - **Realtime is the fast path, not the only path.** A full re-read fires
///   whenever a channel (re)subscribes, when the app returns to the foreground,
///   when a deadline stays past too long, and when a card reveals — the last
///   because a reveal changes which *existing* call rows RLS permits, and
///   Realtime emits nothing for a row whose visibility just changed.
/// - **The clock is asked, repeatedly.** `tick` both expires a passed deadline
///   and stamps this player present, so it is asked throughout a question
///   rather than only once it has run out.
///
/// See `docs/architecture/realtime.md` and `game-runtime.md`; this is those two
/// documents, in one screen's terms.
@MainActor
final class MatchViewModel: ObservableObject {
    /// A row of the final table.
    struct FinalStanding: Equatable, Identifiable {
        let userId: UUID
        /// 1-based; shared by a genuine tie.
        let rank: Int
        let name: String
        /// The record that earned the place, in this game's terms.
        let statLine: String
        let isViewer: Bool

        var id: UUID { userId }
    }

    @Published private(set) var snapshot: HigherOrLowerSnapshot?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    let matchId: UUID
    let viewerId: UUID
    /// The room this match was started from, and whether this player hosts
    /// it. Handed in by the room that pushed this screen rather than read
    /// from the match: which lobby a run belongs to is the lobby's fact, and
    /// a game may never reach for it (`architecture.md`). The web passes the
    /// same two as props from its match page. `nil`/`false` for a solo run.
    let roomCode: String?
    let isHost: Bool
    private let client: HigherOrLowerClient
    private let now: () -> Date

    /// Drives the countdown and the expiry/heartbeat/reconcile asks.
    private(set) lazy var clock = MatchClockDriver(
        now: now,
        expire: { [weak self] in await self?.expire() },
        reconcile: { [weak self] in await self?.reconcile() }
    )

    private var observation: Task<Void, Never>?

    /// Full re-reads can overlap (a reveal's re-read racing a foreground's).
    /// Each is numbered when issued and only applied if no later one has been,
    /// so a slow older read never rolls the screen back.
    private var readsIssued = 0
    private var latestApplied = 0

    init(
        client: HigherOrLowerClient,
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
    }

    // MARK: - Derived state

    var board: HigherOrLowerBoard? { snapshot?.board }
    var phase: HigherOrLowerPhase? { board?.phase }
    var cards: [LadderCard] { snapshot?.cards ?? [] }
    var isComplete: Bool { phase == .complete }

    /// A paused match freezes rather than counting down or sitting at zero.
    /// The server refuses moves against one independently; this is the client
    /// not bothering to ask.
    var isPaused: Bool { snapshot?.matchStatus == .paused }

    var viewer: LadderPlayer? { snapshot?.player(viewerId) }
    var anchor: LadderCard? { snapshot?.anchor }
    var challenger: LadderCard? { snapshot?.challenger }
    var myCall: LadderCall? { snapshot?.currentCall(by: viewerId) }

    var canCall: Bool {
        guard let phase, let viewer, !isPaused, !isBusy else { return false }
        return viewer.canCall(in: phase) && myCall == nil
    }

    /// Who has locked in on the question the table is on.
    var lockedIn: Set<UUID> {
        guard let snapshot else { return [] }
        return Set(
            snapshot.statuses
                .filter { $0.question == snapshot.board.currentQuestion }
                .map(\.userId)
        )
    }

    var standings: [LiveStanding] {
        guard let snapshot else { return [] }
        return liveStandings(snapshot.players, phase: snapshot.board.phase)
    }

    /// What one seat is doing right now, for the rail's second line.
    func status(of player: LadderPlayer) -> String {
        guard let snapshot else { return "" }
        return seatStatus(
            player,
            call: snapshot.currentCall(by: player.userId),
            lockedIn: lockedIn.contains(player.userId),
            phase: snapshot.board.phase
        )
    }

    /// The visible heading. Sudden death names its round; a ladder that has
    /// run past its pre-dealt questions drops the "of N" it no longer has.
    var questionLabel: String {
        guard let board else { return "" }
        if board.phase.isSuddenDeath {
            return "Sudden death · Round \(suddenDeathRound(question: board.currentQuestion, questionCount: board.questionCount))"
        }
        return board.currentQuestion > board.questionCount
            ? "Question \(board.currentQuestion)"
            : "Question \(board.currentQuestion) of \(board.questionCount)"
    }

    var formatLabel: String {
        guard let board else { return "" }
        return "\(board.scoringMode.label) · \(board.season.label)"
    }

    // MARK: The ending

    /// The final table, ranked as the platform recorded it.
    var finalStandings: [FinalStanding] {
        guard let snapshot, isComplete else { return [] }
        let ranked = byPlacement(snapshot.standings)
        return ranked.enumerated().map { index, standing in
            let player = snapshot.players.first { $0.userId == standing.userId }
            return FinalStanding(
                userId: standing.userId,
                rank: standing.placement ?? index + 1,
                name: player?.name ?? "Unknown player",
                statLine: player.map { "\($0.correctCount) correct · \($0.bestStreak) best" } ?? "",
                isViewer: standing.userId == viewerId
            )
        }
    }

    /// Names a winner, so the match ends rather than merely stopping.
    var headline: String {
        let winners = finalStandings.filter { $0.rank == 1 }
        switch winners.count {
        case 0: return "Game over"
        case 1: return "\(winners[0].name) wins"
        default: return "\(winners.map(\.name).joined(separator: " & ")) tie"
        }
    }

    /// The choice made for this finished match, by whoever made it. Non-nil is
    /// the screen's cue to leave: the room carries everybody to the replay, or
    /// back to the lobby.
    var postGameAction: PostGameAction? { snapshot?.postGame }

    /// Only the host advances a room, and only once — `choose_post_game`
    /// refuses anybody else and refuses a second choice.
    var canChoosePostGame: Bool {
        isComplete && isHost && postGameAction == nil && !isBusy
    }

    // MARK: - Intents

    /// Read the match and start following it. Subscribing first means the
    /// `SUBSCRIBED` re-read covers anything that changed while this was in
    /// flight.
    func load() async {
        observe()
        await reconcile()
        clock.start()
    }

    func call(_ direction: CallDirection) async {
        guard canCall else { return }
        isBusy = true
        errorMessage = nil
        do {
            let call = try await client.call(matchId: matchId, direction: direction)
            // Apply our own call rather than waiting for it to come back
            // around: the buttons must close now, not a round trip from now.
            apply(call: call)
            apply(status: CallStatus(question: call.question, userId: call.userId))
            // A player who locks in after somebody else needs the rows that
            // became visible with their own call.
            await reconcile()
        } catch {
            errorMessage = HigherOrLowerServerError.describe(error)
            // Put the screen back on the server's truth: a refusal usually
            // means it already knows something this screen doesn't.
            await reconcile()
        }
        isBusy = false
    }

    /// Replay in the same format, or send the room back to its lobby.
    func choosePostGame(_ choice: PostGameAction.Choice) async {
        guard canChoosePostGame else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let action = try await client.choosePostGame(matchId: matchId, choice: choice)
            snapshot?.postGame = action
        } catch {
            errorMessage = HigherOrLowerServerError.describe(error)
        }
    }

    /// The app returned to the foreground. Hands off to the clock, which
    /// reconciles unconditionally — a suspended app's countdown may barely
    /// have run, and the match may have moved several questions without it.
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
        clock.stop()
    }

    // MARK: - Private

    private func observe() {
        guard observation == nil else { return }
        // Subscribed here rather than inside the task, so the channels exist
        // the moment this returns: a task only starts when the actor next
        // yields, and anything the match did in between would reach nobody.
        let events = client.events(matchId: matchId)
        observation = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: MatchEvent) async {
        guard snapshot != nil else {
            // Nothing to merge into yet, so there is nothing to apply — but a
            // payload arriving at all means the match has moved, and this is
            // the state a screen most needs rescuing from. `start_run` opens a
            // match in `'setup'` and the game deals into it a moment later, so
            // a player carried in during that gap asks for a board that does
            // not exist yet and gets nothing back. The deal itself then
            // arrives here as the first payload; re-reading on it is what
            // turns a permanently empty screen into a dealt one.
            await reconcile()
            return
        }
        switch event {
        case .subscribed:
            await reconcile()
        case .board(let position):
            if let board = snapshot?.board { snapshot?.board = board.applying(position) }
            observeClock()
        case .card(let card):
            apply(card: card)
            if card.isRevealed {
                // A reveal changes which call rows RLS permits for that
                // question, and Realtime does not emit an event for a row
                // whose visibility — not content — just changed. Without this
                // re-read, an opponent's already-made call would never appear.
                await reconcile()
            }
        case .player(let player):
            apply(player: player)
        case .call(let call):
            apply(call: call)
        case .callStatus(let status):
            apply(status: status)
        case .standing(let standing):
            snapshot?.standings.removeAll { $0.userId == standing.userId }
            snapshot?.standings.append(standing)
        case .matchStatus(let status):
            snapshot?.matchStatus = status
            observeClock()
        case .postGame(let action):
            snapshot?.postGame = action
        }
    }

    private func apply(_ fresh: HigherOrLowerSnapshot) {
        snapshot = fresh
        observeClock()
    }

    private func apply(card: LadderCard) {
        guard var cards = snapshot?.cards else { return }
        if let index = cards.firstIndex(where: { $0.ordinal == card.ordinal }) {
            cards[index] = card
        } else {
            // An endless ladder extends past its pre-dealt cards by inserting
            // a brand-new ordinal, which arrives with no existing row to
            // replace — append it or the card never reaches the screen.
            cards.append(card)
            cards.sort { $0.ordinal < $1.ordinal }
        }
        snapshot?.cards = cards
    }

    private func apply(player: LadderPlayer) {
        guard let index = snapshot?.players.firstIndex(where: { $0.userId == player.userId }) else { return }
        snapshot?.players[index] = player.named(like: snapshot?.players[index])
    }

    private func apply(call: LadderCall) {
        guard let calls = snapshot?.calls else { return }
        guard !calls.contains(where: { $0.question == call.question && $0.userId == call.userId }) else { return }
        snapshot?.calls.append(call)
    }

    private func apply(status: CallStatus) {
        guard let statuses = snapshot?.statuses else { return }
        guard !statuses.contains(where: { $0.question == status.question && $0.userId == status.userId })
        else { return }
        snapshot?.statuses.append(status)
    }

    /// The clock's `expire`: ask the server to advance a passed deadline and,
    /// by the same call, say we are here. If the board moved, everything
    /// behind it moved too, so re-read rather than applying the board alone.
    private func expire() async {
        do {
            let ticked = try await client.tick(matchId: matchId)
            if let current = board, !ticked.samePosition(as: current) {
                await reconcile()
            } else {
                observeClock(ticked)
            }
        } catch {
            // Asking again is free; the clock retries.
        }
    }

    private func observeClock(_ board: HigherOrLowerBoard? = nil) {
        guard let board = board ?? self.board else { return }
        clock.observe(
            serverNow: board.serverNow,
            // A finished match has no deadline to chase, whatever the row says.
            deadline: board.phase == .complete ? nil : board.phaseDeadline,
            config: MatchClockConfig(
                // A phase a move can be sent in reaches zero early, so a call
                // sent as the bar empties still lands inside the real
                // deadline; a phase nobody can act in doesn't need the slack.
                visibleSlackMs: board.phase.acceptsCalls ? MatchClockConstants.visibleSlackMs : 0,
                // The tick is also how a player says they are still here.
                heartbeatMs: MatchClockConstants.heartbeatMs,
                paused: isPaused
            )
        )
    }
}
