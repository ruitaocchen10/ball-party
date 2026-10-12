import Foundation
import OSLog

/// One room, from "host or join" to a dealt match.
///
/// The server owns every rule here — who may start, how full a room is, who is
/// on a run's frozen roster. This decides which RPC to call and what to show,
/// and re-reads the whole room on every channel event, which `realtime.md`
/// records as the deliberate cost difference from a match screen: a round trip
/// per lobby event is cheap, and lobby membership changes rarely.
@MainActor
final class LobbyViewModel: ObservableObject {
    private let log = Logger(subsystem: "com.ballparty.app", category: "lobby")
    private var triedToRestore = false

    enum Stage: Equatable {
        /// No room yet: host one, or take an invite.
        case entry
        /// In a room.
        case room
        /// The room closed under us.
        case closed
    }

    // MARK: Entry


    // MARK: Room

    @Published private(set) var stage: Stage = .entry
    @Published private(set) var snapshot: LobbySnapshot?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    /// Each seated player's career form, for the line under their seat. Empty
    /// until it loads; a missing player reads "New".
    @Published private(set) var memberForm: [UUID: LobbyMemberForm] = [:]

    // MARK: The host's format picker
    //
    // The same two choices, and the same "a picker can never hold an inverted
    // range" rule, as the solo card — see `SoloRunFormat`. They are
    // written out twice rather than shared, because the two screens hand them
    // to different RPCs and the solo one is a player's own format while this
    // is a decision made on behalf of a room.

    // Every picker below saves itself onto the room when the host changes it
    // (`formatChanged`), so the rest of the room can see what is being set up.

    @Published var scoringMode: ScoringMode = .seasonTotal {
        didSet { formatChanged() }
    }
    @Published var seasonFrom = 0 {
        didSet {
            if seasonFrom > seasonTo { seasonTo = seasonFrom }
            formatChanged()
        }
    }
    @Published var seasonTo = 0 {
        didSet {
            if seasonTo < seasonFrom { seasonFrom = seasonTo }
            formatChanged()
        }
    }
    @Published private(set) var seasonBounds: SeasonRange?

    // MARK: The host's auction format
    //
    // Kept apart from Higher or Lower's picker rather than shared: the two
    // games default differently (the auction opens on weekly lots) and the
    // auction's era has a floor the ladder's doesn't — the dealer refuses a
    // window narrower than `AuctionEra.minSpan` seasons.

    @Published var auctionScoringMode: ScoringMode = .weekly {
        didSet { formatChanged() }
    }
    @Published var rosterPreset: RosterPreset = .standard {
        didSet { formatChanged() }
    }
    /// Single-use abilities per player: 0 is off, up to 3.
    @Published var tokenCount = 1 {
        didSet { formatChanged() }
    }
    @Published var auctionFrom = 0 {
        didSet {
            if auctionFrom > auctionTo { auctionTo = auctionFrom }
            formatChanged()
        }
    }
    @Published var auctionTo = 0 {
        didSet {
            if auctionTo < auctionFrom { auctionFrom = auctionTo }
            formatChanged()
        }
    }
    @Published private(set) var auctionEra: AuctionEra?

    // MARK: The host's Wavelength format
    //
    // The mode is part of the roster: co-op seats one pair and 2v2 seats two,
    // and the dealer refuses any other count, so the room says so before the tap.

    @Published var wavelengthMode: WavelengthMode = .coop {
        didSet { formatChanged() }
    }
    @Published var wavelengthPreset: WavelengthPreset = .short {
        didSet { formatChanged() }
    }

    /// A match already entered from this room, so returning to the room
    /// doesn't immediately push the same board back at the player.
    private var dismissedMatchId: UUID?

    let viewerId: UUID
    private let client: LobbyClient
    private let game: HigherOrLowerClient
    private let auction: AuctionClient
    private let wavelength: WavelengthClient
    private let heartbeatInterval: Duration
    private let formatSaveDelay: Duration

    private var observation: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init(
        client: LobbyClient,
        game: HigherOrLowerClient,
        auction: AuctionClient,
        wavelength: WavelengthClient,
        viewerId: UUID,
        heartbeatInterval: Duration = .seconds(10),
        formatSaveDelay: Duration = .milliseconds(600)
    ) {
        self.client = client
        self.game = game
        self.auction = auction
        self.wavelength = wavelength
        self.viewerId = viewerId
        self.heartbeatInterval = heartbeatInterval
        self.formatSaveDelay = formatSaveDelay
    }

    deinit {
        observation?.cancel()
        heartbeatTask?.cancel()
    }

    // MARK: - The host's settings, saved on the room

    /// Whether this room's saved settings have been loaded into the pickers yet:
    /// once per room, so a host who comes back (or inherits the room) finds
    /// them as they were left, and nothing the host is mid-edit on is overwritten.
    private var formatHydrated = false
    /// True while the pickers are being set by something other than the host's
    /// hand (loading defaults, restoring the saved format), which must not be
    /// saved back.
    private var applyingFormat = false
    private var formatSave: Task<Void, Never>?

    /// What the host's pickers hold, in the shape the room stores.
    var currentFormat: LobbyGameFormat {
        LobbyGameFormat(
            higherOrLower: .init(
                scoringMode: scoringMode.rawValue,
                seasonFrom: seasonBounds == nil ? nil : seasonFrom,
                seasonTo: seasonBounds == nil ? nil : seasonTo
            ),
            auction: .init(
                scoringMode: auctionScoringMode.rawValue,
                rosterPreset: rosterPreset.rawValue,
                tokenCount: tokenCount,
                seasonFrom: auctionEra == nil ? nil : auctionFrom,
                seasonTo: auctionEra == nil ? nil : auctionTo
            ),
            wavelength: .init(mode: wavelengthMode.rawValue, preset: wavelengthPreset.rawValue)
        )
    }

    /// The settings to show for the game on offer: the host's own pickers for
    /// the host, what the host saved for everybody else.
    var displayedFormat: LobbyGameFormat {
        isHost ? currentFormat : (lobby?.gameFormat ?? LobbyGameFormat())
    }

    /// Wait out a burst of changes (dragging through seasons), then save once.
    private func formatChanged() {
        guard !applyingFormat, isHost, stage == .room, let lobbyId = lobby?.id else { return }
        formatSave?.cancel()
        formatSave = Task { [weak self, formatSaveDelay] in
            try? await Task.sleep(for: formatSaveDelay)
            guard !Task.isCancelled, let self else { return }
            try? await client.setGameFormat(lobbyId: lobbyId, format: currentFormat)
        }
    }

    /// Put the room's saved settings into the pickers, once per room, for a host.
    /// Eras wait for their bounds (see `loadFormat`).
    private func hydrateFormatIfNeeded() {
        guard isHost, !formatHydrated, let saved = lobby?.gameFormat else { return }
        formatHydrated = true
        applyingFormat = true
        defer { applyingFormat = false }
        if let f = saved.higherOrLower, let mode = ScoringMode(rawValue: f.scoringMode) { scoringMode = mode }
        if let f = saved.auction {
            if let mode = ScoringMode(rawValue: f.scoringMode) { auctionScoringMode = mode }
            if let preset = RosterPreset(rawValue: f.rosterPreset) { rosterPreset = preset }
            tokenCount = min(max(f.tokenCount, 0), 3)
        }
        if let f = saved.wavelength {
            if let mode = WavelengthMode(rawValue: f.mode) { wavelengthMode = mode }
            if let preset = WavelengthPreset(rawValue: f.preset) { wavelengthPreset = preset }
        }
        applySavedEras()
    }

    /// The saved eras, clamped into the bounds that have loaded. Run when either
    /// the bounds or the saved format arrives, whichever is second.
    private func applySavedEras() {
        guard formatHydrated, let saved = lobby?.gameFormat else { return }
        applyingFormat = true
        defer { applyingFormat = false }
        if let bounds = seasonBounds, let f = saved.higherOrLower, let from = f.seasonFrom, let to = f.seasonTo {
            seasonTo = min(max(to, bounds.from), bounds.to)
            seasonFrom = min(max(from, bounds.from), seasonTo)
        }
        if let era = auctionEra, let f = saved.auction, let from = f.seasonFrom, let to = f.seasonTo {
            auctionTo = min(max(to, era.seasonMin), era.seasonMax)
            auctionFrom = min(max(from, era.seasonMin), auctionTo)
        }
    }

    // MARK: - Derived state

    var lobby: Lobby? { snapshot?.lobby }
    var members: [LobbyMember] { snapshot?.members ?? [] }
    var roomCode: String? { lobby?.code }

    /// One row of the room's scoreboard.
    struct Standing: Identifiable, Equatable {
        let member: LobbyMember
        let wins: Int
        /// Players with the same wins share a rank (1, 1, 3). Nil until
        /// somebody has won, since a rank among zeros says nothing.
        let rank: Int?
        var id: UUID { member.userId }
    }

    /// Everyone in the room with their wins, most first. Ties keep join order.
    var standings: [Standing] {
        let wins = snapshot?.wins ?? [:]
        let ordered = members.enumerated()
            .sorted { (wins[$0.element.userId] ?? 0, $1.offset) > (wins[$1.element.userId] ?? 0, $0.offset) }
            .map(\.element)
        return ordered.enumerated().map { index, member in
            let count = wins[member.userId] ?? 0
            let rank = (wins.values.reduce(0, +)) == 0 ? nil : (ordered.firstIndex { (wins[$0.userId] ?? 0) == count } ?? index) + 1
            return Standing(member: member, wins: count, rank: rank)
        }
    }

    var totalWins: Int { standings.reduce(0) { $0 + $1.wins } }
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

    /// Which game the in-flight match is, so the room opens the right screen.
    var gameToEnter: MatchGame { snapshot?.run?.inFlightMatch?.matchGame ?? .higherOrLower }

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
        guard let chosen = selectedGame else { return "Pick a game first" }
        if let reason = headcountReason { return reason }
        if snapshot?.run?.inFlightMatch != nil { return "A game is already running in this room" }
        // The dealer refuses these too; saying so before the tap is what stops
        // it reading as a broken button.
        if chosen == .auctionTeamBuilder, let era = auctionEra {
            if auctionTo < auctionFrom { return "The last season has to come after the first" }
            if auctionTo - auctionFrom + 1 < era.minSpan { return "Pick a span of at least \(era.minSpan) seasons" }
        }
        return wavelengthRosterReason(for: chosen)
    }

    /// Whether the people in the room suit `game`, for the game's card to say so
    /// whoever is looking: the host judges by their own picker, everybody else by
    /// what the host saved.
    func roomReadiness(for game: MatchGame) -> String? {
        headcountReason ?? wavelengthRosterReason(for: game)
    }

    private var headcountReason: String? {
        if members.count < 2 { return "Waiting for one more player" }
        if members.count > 4 { return "That's too many players for one game" }
        return nil
    }

    /// Wavelength seats exactly one pair (co-op) or two (2v2).
    private func wavelengthRosterReason(for game: MatchGame) -> String? {
        guard game == .wavelength else { return nil }
        let raw = displayedFormat.wavelength?.mode ?? WavelengthMode.coop.rawValue
        let mode = WavelengthMode(rawValue: raw) ?? .coop
        guard members.count != mode.playerCount else { return nil }
        return "\(mode.label) needs exactly \(mode.playerCount) players (you have \(members.count))"
    }

    /// The seasons the auction picker may offer, in order.
    var auctionSeasonChoices: [Int] {
        guard let auctionEra else { return [] }
        return Array(auctionEra.seasonMin...auctionEra.seasonMax)
    }

    /// The seasons the host's picker may offer, in order.
    var seasonChoices: [Int] {
        guard let seasonBounds else { return [] }
        return Array(seasonBounds.from...seasonBounds.to)
    }

    // MARK: - Intents

    /// Host a room. Its link and the friend invites are how people get in.
    func createRoom() async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let lobby = try await client.createLobby()
            try await enter(lobby)
            await PushCoordinator.shared.meaningfulActionCompleted()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Join the room a link points at. The server stores codes upper-cased,
    /// so that is the shape it is asked about.
    func joinRoom(code: String) async {
        guard !isBusy else { return }
        let typed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !typed.isEmpty else {
            errorMessage = "That room link isn't valid."
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let lobby = try await client.joinLobby(code: typed)
            try await enter(lobby)
            await PushCoordinator.shared.meaningfulActionCompleted()
        } catch {
            errorMessage = Self.describe(error)
        }
    }

    /// Load the era limits behind the host's format picker. Safe to call
    /// again; it never overwrites a choice the host already made.
    func loadFormat() async {
        if seasonBounds == nil {
            do {
                let bounds = try await game.seasonBounds()
                applyingFormat = true
                seasonBounds = bounds
                seasonFrom = bounds.from
                seasonTo = bounds.to
                applyingFormat = false
                applySavedEras()
            } catch {
                applyingFormat = false
                // The picker just doesn't appear, and the dealer falls back to the
                // whole pool — the same non-fatal treatment the web gives it.
            }
        }
        if auctionEra == nil {
            do {
                let era = try await auction.seasonBounds()
                applyingFormat = true
                auctionEra = era
                auctionFrom = era.seasonMin
                auctionTo = era.seasonMax
                applyingFormat = false
                applySavedEras()
            } catch {
                applyingFormat = false
                // Same treatment as above: no picker, whole pool.
            }
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
            case .auctionTeamBuilder:
                _ = try await auction.start(
                    matchId: matchId,
                    scoringMode: auctionScoringMode,
                    rosterPreset: rosterPreset,
                    era: auctionEra == nil ? nil : SeasonRange(from: auctionFrom, to: auctionTo),
                    tokenCount: tokenCount
                )
            case .wavelength:
                _ = try await wavelength.start(
                    matchId: matchId,
                    mode: wavelengthMode,
                    preset: wavelengthMode == .coop ? wavelengthPreset : nil
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
        formatSave?.cancel()
        formatHydrated = false
        snapshot = nil
        dismissedMatchId = nil
        errorMessage = nil
        do {
            try await enter(lobby)
        } catch {
            log.error("could not step into the joined room: \(String(describing: error))")
            stage = .entry
            errorMessage = Self.describe(error)
        }
    }

    /// Steps back into the room the server still has this player in, after the
    /// app was closed or killed (the room itself is only in memory here). Tried
    /// once per screen: tab switches don't re-ask. It never moves someone who has
    /// already hosted or joined something in the meantime, and a failed look-up
    /// just leaves the entry screen up.
    func restoreCurrentRoom() async {
        guard !triedToRestore, stage == .entry, !isBusy else { return }
        triedToRestore = true
        let current: Lobby?
        do {
            current = try await client.currentLobby()
        } catch {
            log.error("could not look up the current room: \(String(describing: error))")
            return
        }
        guard let current, stage == .entry, !isBusy else { return }
        await adopt(current)
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
        await loadMemberForm()
    }

    /// Re-reads everyone's match history. Failing keeps what was shown.
    private func loadMemberForm() async {
        guard let lobbyId = lobby?.id,
              let rows = try? await client.memberHistory(lobbyId: lobbyId) else { return }
        memberForm = LobbyMemberForm.summaries(from: rows)
    }

    // MARK: - Private

    private func enter(_ lobby: Lobby) async throws {
        let fresh = try await client.snapshot(lobbyId: lobby.id)
        apply(fresh)
        observe()
        await loadMemberForm()
    }

    private func exitRoom() async {
        await stopObservingAndWait()
        formatSave?.cancel()
        formatHydrated = false
        snapshot = nil
        memberForm = [:]
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
        hydrateFormatIfNeeded()
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
        "code_generation_failed": "Couldn't set up the room. Try again.",
        "lobby_closed": "This room has closed.",
        "bad_player_count": "You need between two and four players.",
        "mode_not_supported": "Party mode isn't ready yet.",
        "run_already_active": "A game is already running in this room.",
        "too_few_players": "Not enough players to deal a board.",
        "pool_exhausted": "Couldn't deal a full board. Try again.",
        "invalid_season_range": "The last season has to come after the first.",
        "season_out_of_range": "That season isn't in the player pool.",
        "season_range_too_narrow": "Pick a span of at least four seasons.",
        "invalid_scoring_mode": "Choose a valid scoring mode.",
        "invalid_roster_preset": "Choose a valid roster.",
        "invalid_token_count": "Tokens can be zero to three per player.",
    ]
}
