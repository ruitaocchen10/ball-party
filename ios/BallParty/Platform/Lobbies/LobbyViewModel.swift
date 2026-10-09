import Foundation

/// One room, from "host or join" to a dealt match.
///
/// The server owns every rule here — who may start, how full a room is, who is
/// on a run's frozen roster. This decides which RPC to call and what to show,
/// and re-reads the whole room on every channel event, which `realtime.md`
/// records as the deliberate cost difference from a match screen: a round trip
/// per lobby event is cheap, and lobby membership changes rarely.
@MainActor
final class LobbyViewModel: ObservableObject {
    enum Stage: Equatable {
        /// No room yet: host one, or join by code.
        case entry
        /// In a room.
        case room
        /// The room closed under us.
        case closed
    }

    // MARK: Entry

    /// The join-by-code field.
    @Published var code = ""

    // MARK: Room

    @Published private(set) var stage: Stage = .entry
    @Published private(set) var snapshot: LobbySnapshot?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    // MARK: The host's format picker
    //
    // The same two choices, and the same "a picker can never hold an inverted
    // range" rule, as the solo card — see `SoloRunFormat`. They are
    // written out twice rather than shared, because the two screens hand them
    // to different RPCs and the solo one is a player's own format while this
    // is a decision made on behalf of a room.

    @Published var scoringMode: ScoringMode = .seasonTotal
    @Published var seasonFrom = 0 {
        didSet { if seasonFrom > seasonTo { seasonTo = seasonFrom } }
    }
    @Published var seasonTo = 0 {
        didSet { if seasonTo < seasonFrom { seasonFrom = seasonTo } }
    }
    @Published private(set) var seasonBounds: SeasonRange?

    /// A match already entered from this room, so returning to the room
    /// doesn't immediately push the same board back at the player.
    private var dismissedMatchId: UUID?

    let viewerId: UUID
    private let client: LobbyClient
    private let game: HigherOrLowerClient
    private let heartbeatInterval: Duration

    private var observation: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init(
        client: LobbyClient,
        game: HigherOrLowerClient,
        viewerId: UUID,
        heartbeatInterval: Duration = .seconds(10)
    ) {
        self.client = client
        self.game = game
        self.viewerId = viewerId
        self.heartbeatInterval = heartbeatInterval
    }

    deinit {
        observation?.cancel()
        heartbeatTask?.cancel()
    }

    // MARK: - Derived state

    var lobby: Lobby? { snapshot?.lobby }
    var members: [LobbyMember] { snapshot?.members ?? [] }
    var roomCode: String? { lobby?.code }
    var isHost: Bool { lobby?.hostId == viewerId }

    /// Ending the room for everybody is the host's alone — `close_lobby`
    /// refuses anybody else, so this is the honest rendering of that rule.
    var canClose: Bool { isHost && stage == .room }

    /// What the room plays next, when it is something this app can start.
    var selectedGame: MatchGame? { lobby?.selectedMatchGame }

    /// The board this player should be looking at: a match is under way and
    /// the run's frozen roster has them on it.
    var matchToEnter: UUID? {
        guard let run = snapshot?.run, let match = run.inFlightMatch, run.seats(viewerId),
              match.id != dismissedMatchId
        else { return nil }
        return match.id
    }

    /// A game this player is in but stepped out of. The room offers a way
    /// back in rather than stranding somebody outside their own match — the
    /// server never took their seat away, only this screen stopped pushing
    /// them at it.
    var rejoinableMatch: UUID? {
        guard matchToEnter == nil, let run = snapshot?.run, let match = run.inFlightMatch,
              run.seats(viewerId)
        else { return nil }
        return match.id
    }

    /// A game is running that this player is not in — they joined after the
    /// roster froze, and are in for the next one (`lobbies.md`).
    var waitingForNextRun: Bool {
        guard let run = snapshot?.run, run.inFlightMatch != nil else { return false }
        return !run.seats(viewerId)
    }

    /// Two to four players, a game chosen, and nothing already running. The
    /// rules themselves are `start_run`'s; this only decides what the button
    /// shows.
    var canStart: Bool {
        isHost && stage == .room && !isBusy && startBlockedReason == nil
    }

    /// Why Start is disabled, in the room's own words — or `nil` when it isn't.
    var startBlockedReason: String? {
        guard isHost, stage == .room else { return nil }
        if selectedGame == nil { return "Pick a game first" }
        if members.count < 2 { return "Waiting for one more player" }
        if members.count > 4 { return "That's too many players for one game" }
        if snapshot?.run?.inFlightMatch != nil { return "A game is already running in this room" }
        return nil
    }

    /// The seasons the host's picker may offer, in order.
    var seasonChoices: [Int] {
        guard let seasonBounds else { return [] }
        return Array(seasonBounds.from...seasonBounds.to)
    }

    // MARK: - Intents

    /// Host a room. The code it comes back with is the whole invitation.
    func createRoom() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let lobby = try await client.createLobby()
            try await enter(lobby)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Join the room whose code is in `code`.
    func joinRoom() async {
        guard !isBusy else { return }
        // Codes are read aloud across a table and typed back in; the server
        // stores them upper-cased, so that is the shape one is asked about.
        let typed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !typed.isEmpty else {
            errorMessage = "Enter a room code."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let lobby = try await client.joinLobby(code: typed)
            try await enter(lobby)
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Load the era limits behind the host's format picker. Safe to call
    /// again; it never overwrites a choice the host already made.
    func loadFormat() async {
        guard seasonBounds == nil else { return }
        do {
            let bounds = try await game.seasonBounds()
            seasonBounds = bounds
            seasonFrom = bounds.from
            seasonTo = bounds.to
        } catch {
            // The picker just doesn't appear, and the dealer falls back to the
            // whole pool — the same non-fatal treatment the web gives it.
        }
    }

    /// Point the room at a game. Advisory: it starts nothing by itself, which
    /// is what gives the room a visible "next up" the host can change.
    func selectGame(_ game: MatchGame) async {
        guard let lobbyId = lobby?.id, isHost else { return }
        errorMessage = nil
        do {
            try await client.selectGame(lobbyId: lobbyId, game: game)
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Turn the room into a game: freeze the roster, then deal.
    ///
    /// Two calls, because the platform does not dispatch into a game's setup —
    /// it does not know games exist. This is the one place in the app that has
    /// to know which game it started, the same seam the web's `startRun` draws.
    func startGame() async {
        guard let lobbyId = lobby?.id, let chosen = selectedGame, canStart else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let matchId = try await client.startRun(lobbyId: lobbyId, game: chosen)
            switch chosen {
            case .higherOrLower:
                _ = try await game.start(
                    matchId: matchId,
                    scoringMode: scoringMode,
                    // No bounds loaded means no picker was shown, so the
                    // dealer picks: the whole pool.
                    era: seasonBounds == nil ? nil : SeasonRange(from: seasonFrom, to: seasonTo)
                )
            }
            // Everybody else is carried in by the run appearing in the room;
            // the host doesn't wait for their own event to come back around.
            await refresh()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// The player came back from a match. Named explicitly, rather than
    /// "whatever is in flight now": by the time they land back here the room
    /// may already be showing the *replay*, and that one they do want.
    func matchDismissed(_ matchId: UUID) {
        dismissedMatchId = matchId
    }

    /// Go back into the match they stepped out of.
    func rejoinMatch() {
        dismissedMatchId = nil
    }

    /// Leave the room. The server migrates the host if that was us, and closes
    /// the room entirely if nobody active remains.
    func leaveRoom() async {
        guard let lobbyId = lobby?.id else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.leaveLobby(lobbyId: lobbyId)
        } catch {
            errorMessage = Self.describe(error)
            return
        }
        await exitRoom()
    }

    /// End the room for everybody. Host-only; everybody else finds out because
    /// their own `lobbies` payload now carries a `closed_at`.
    func closeRoom() async {
        guard let lobbyId = lobby?.id, canClose else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.closeLobby(lobbyId: lobbyId)
        } catch {
            errorMessage = Self.describe(error)
            return
        }
        await exitRoom()
    }

    /// Step into a room the server already put us in (an accepted invite).
    /// Joining it left any room we were in, so that one's channel comes down
    /// first; `join_lobby`'s answer is not asked for again.
    func adopt(_ lobby: Lobby) async {
        await stopObservingAndWait()
        snapshot = nil
        dismissedMatchId = nil
        errorMessage = nil
        do {
            try await enter(lobby)
        } catch {
            stage = .entry
            errorMessage = Self.describe(error)
        }
    }

    /// Acknowledge a room that closed under us, from the closed screen.
    func dismissClosedRoom() async {
        await exitRoom()
    }

    // MARK: - Staying in step

    /// Subscribe to the room's channel and start renewing our presence lease.
    /// Idempotent — the screen calls it on appear, and entering a room already
    /// did.
    func observe() {
        guard let lobbyId = lobby?.id else { return }
        if observation == nil {
            // Subscribed here rather than inside the task below, so the
            // channel exists the moment this returns: a task only starts when
            // the actor next yields, and anything the room did in between
            // would be delivered to nobody.
            let events = client.events(lobbyId: lobbyId)
            observation = Task { [weak self] in
                for await event in events {
                    guard let self else { return }
                    // `.subscribed` and `.changed` both land here as one full
                    // re-read: the first is the reconnect contract, the second
                    // is the lobby channel's deliberate refresh-per-event.
                    _ = event
                    await self.refresh()
                }
            }
        }
        startRenewingPresence(lobbyId)
    }

    func stopObserving() {
        observation?.cancel()
        observation = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// The app went to the background. The lease is allowed to lapse — the web
    /// gates its heartbeat on tab visibility for the same reason — while the
    /// subscription itself stays up for whenever the screen comes back.
    func appEnteredBackground() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// The app returned to the foreground. Renew the lease immediately and
    /// re-read the room, which may have moved on entirely while we were away.
    func appBecameActive() {
        guard stage == .room else { return }
        observe()
        Task { await refresh() }
    }

    /// Re-read the whole room and apply it.
    func refresh() async {
        guard let lobbyId = lobby?.id else { return }
        do {
            apply(try await client.snapshot(lobbyId: lobbyId))
        } catch {
            // A failed background re-read leaves the last good screen up; the
            // next event, write, or foreground tries again.
        }
    }

    // MARK: - Private

    private func enter(_ lobby: Lobby) async throws {
        let fresh = try await client.snapshot(lobbyId: lobby.id)
        apply(fresh)
        observe()
    }

    private func exitRoom() async {
        await stopObservingAndWait()
        snapshot = nil
        errorMessage = nil
        dismissedMatchId = nil
        stage = .entry
    }

    /// `stopObserving()`, but waits for the channel to actually come down
    /// rather than only requesting it.
    ///
    /// Cancelling `observation` doesn't close its channel by itself — the
    /// observing task only does that once it notices the cancellation and its
    /// `for await` loop over `LobbyClient.events` returns. Leaving that to
    /// happen on its own time is fine for a screen that's simply gone
    /// (`stopObserving()`, from `.onDisappear`), but leaving or closing a room
    /// needs the old channel gone *before* the screen goes back to `.entry` —
    /// otherwise a stale subscription to the room just exited outlives it.
    private func stopObservingAndWait() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        guard let observation else { return }
        self.observation = nil
        observation.cancel()
        await observation.value
    }

    private func startRenewingPresence(_ lobbyId: UUID) {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task { [client, heartbeatInterval] in
            // Once immediately, then on a fixed cadence, the same shape the
            // web's `LobbyRealtime` uses.
            while !Task.isCancelled {
                try? await client.heartbeat(lobbyId: lobbyId)
                try? await Task.sleep(for: heartbeatInterval)
            }
        }
    }

    private func apply(_ fresh: LobbySnapshot) {
        snapshot = fresh
        stage = fresh.lobby.isClosed ? .closed : .room
    }

    /// Maps a raised message to a sentence for the player, the way the web's
    /// `LOBBY_MESSAGES` does; anything unmapped surfaces raw rather than being
    /// flattened into a friendly lie.
    static func describe(_ error: Error) -> String {
        guard let server = error as? LobbyServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        return messages[server.message] ?? server.message
    }

    nonisolated static let messages: [String: String] = [
        "lobby_not_found": "No room with that code.",
        "lobby_full": "That room is already full.",
        "not_a_member": "You're not in that room.",
        "not_host": "Only the host can start or close the game.",
        "not_authenticated": "Sign in first.",
        "account_required": "Multiplayer needs a real account.",
        "code_generation_failed": "Couldn't find a free room code. Try again.",
        "lobby_closed": "This room has closed.",
        "bad_player_count": "You need between two and four players.",
        "mode_not_supported": "Party mode isn't ready yet.",
        "run_already_active": "A game is already running in this room.",
        "too_few_players": "Not enough players to deal a board.",
        "pool_exhausted": "Couldn't deal a full board. Try again.",
        "invalid_season_range": "The last season has to come after the first.",
        "season_out_of_range": "That season isn't in the player pool.",
    ]
}
