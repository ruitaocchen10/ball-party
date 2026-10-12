import Foundation
@testable import BallParty

/// An in-memory stand-in for the lobby half of the server, behind the same
/// `LobbyClient` seam the app uses. It plays only the rules a screen's behavior
/// depends on — who is seated, who hosts, when a run freezes its roster, when a
/// room closes — so view-model tests can drive a whole room without a network.
///
/// Its test controls are written from the *other* players' point of view
/// (`anotherPlayerJoins`, `hostStartsARun`), because that is what a room screen
/// actually has to react to.
final class FakeLobbyClient: LobbyClient, @unchecked Sendable {
    let viewerId: UUID

    // Server-side state.
    private(set) var lobby: Lobby?
    private(set) var members: [LobbyMember] = []
    private(set) var run: LiveRun?
    private var wins: [UUID: Int] = [:]
    /// What the host has saved on the room, and each save in order.
    private(set) var savedFormat = LobbyGameFormat()
    private(set) var formatSaves: [LobbyGameFormat] = []
    private var joinedAt = Date(timeIntervalSince1970: 1_786_795_200)

    // What the app asked for.
    private(set) var snapshotCount = 0
    private(set) var currentLobbyLookups = 0
    private(set) var heartbeatCount = 0
    private(set) var joinedCodes: [String] = []
    private(set) var selectedGames: [MatchGame] = []
    private(set) var startedRuns: [MatchGame] = []
    private(set) var leaveCount = 0
    private(set) var closeCount = 0

    /// Scripted failures, keyed by RPC name.
    var failures: [String: LobbyServerError] = [:]

    private var continuation: AsyncStream<LobbyEvent>.Continuation?

    init(viewerId: UUID) {
        self.viewerId = viewerId
    }

    // MARK: - Test controls

    /// Somebody else's room, already hosted by another player, for the join path.
    func roomHostedBySomebodyElse(code: String = "QRTZW", hostName: String = "Dana") -> UUID {
        let hostId = UUID()
        lobby = Lobby(id: UUID(), code: code, hostId: hostId)
        members = [member(hostId, hostName)]
        return hostId
    }

    /// Settings the host saved on the room before the viewer arrived.
    func hostHadSavedFormat(_ format: LobbyGameFormat) {
        savedFormat = format
    }

    /// The host changes the room's saved settings from their own device.
    func hostSavesFormat(_ format: LobbyGameFormat) {
        savedFormat = format
        emit(.changed)
    }

    @discardableResult
    func anotherPlayerJoins(named name: String = "Sam") -> UUID {
        let userId = UUID()
        members.append(member(userId, name))
        emit(.changed)
        return userId
    }

    /// A match in this room finishes with `userId` in first place.
    func playerWinsAMatch(_ userId: UUID) {
        wins[userId, default: 0] += 1
        emit(.changed)
    }

    func playerLeaves(_ userId: UUID) {
        members.removeAll { $0.userId == userId }
        emit(.changed)
    }

    /// The host starts a run without this client asking — the case a member
    /// finds out about only because the room changed under them.
    @discardableResult
    func hostStartsARun(seating seated: [UUID]? = nil, game: MatchGame = .higherOrLower) -> UUID {
        let matchId = freezeRun(seating: seated ?? members.map(\.userId), game: game)
        emit(.changed)
        return matchId
    }

    /// The in-flight match finished — it stops being one the room carries
    /// people into, exactly as a `complete` status does on the server.
    func runFinishes() {
        guard let run else { return }
        self.run = LiveRun(
            matches: run.matches.map { RunMatch(id: $0.id, status: .complete, game: $0.game) },
            seatedUserIds: run.seatedUserIds
        )
        emit(.changed)
    }

    func roomCloses() {
        guard let lobby else { return }
        self.lobby = Lobby(
            id: lobby.id, code: lobby.code, hostId: lobby.hostId,
            selectedGame: lobby.selectedGame, closedAt: Date(timeIntervalSince1970: 1_786_800_000)
        )
        emit(.changed)
    }

    /// The channel (re)subscribed — a first connect or a reconnect.
    func channelSubscribes() {
        emit(.subscribed)
    }

    func emit(_ event: LobbyEvent) {
        continuation?.yield(event)
    }

    var isObserved: Bool { continuation != nil }

    // MARK: - LobbyClient

    func createLobby() async throws -> Lobby {
        try fail("create_lobby")
        let created = Lobby(id: UUID(), code: "BRZWK", hostId: viewerId)
        lobby = created
        members = [member(viewerId, "You")]
        return created
    }

    func joinLobby(code: String) async throws -> Lobby {
        try fail("join_lobby")
        joinedCodes.append(code)
        guard let existing = lobby, existing.code == code else {
            throw LobbyServerError(message: "lobby_not_found")
        }
        if !members.contains(where: { $0.userId == viewerId }) {
            members.append(member(viewerId, "You"))
        }
        return existing
    }

    func currentLobby() async throws -> Lobby? {
        try fail("current_lobby")
        currentLobbyLookups += 1
        guard let lobby, lobby.closedAt == nil, members.contains(where: { $0.userId == viewerId }) else { return nil }
        return lobby
    }

    func snapshot(lobbyId: UUID) async throws -> LobbySnapshot {
        try fail("snapshot")
        snapshotCount += 1
        guard let lobby else { throw LobbyServerError(message: "lobby_not_found") }
        let withFormat = Lobby(
            id: lobby.id, code: lobby.code, hostId: lobby.hostId,
            selectedGame: lobby.selectedGame, closedAt: lobby.closedAt, gameFormat: savedFormat
        )
        return LobbySnapshot(lobby: withFormat, members: members, run: run, wins: wins)
    }

    func setGameFormat(lobbyId: UUID, format: LobbyGameFormat) async throws {
        try fail("set_lobby_game_format")
        savedFormat = format
        formatSaves.append(format)
        emit(.changed)
    }

    func selectGame(lobbyId: UUID, game: MatchGame) async throws {
        try fail("select_lobby_game")
        selectedGames.append(game)
        guard let lobby else { return }
        self.lobby = Lobby(
            id: lobby.id, code: lobby.code, hostId: lobby.hostId,
            selectedGame: game.rawValue, closedAt: lobby.closedAt
        )
        emit(.changed)
    }

    func startRun(lobbyId: UUID, game: MatchGame) async throws -> UUID {
        try fail("start_run")
        startedRuns.append(game)
        return freezeRun(seating: members.map(\.userId), game: game)
    }

    func leaveLobby(lobbyId: UUID) async throws {
        try fail("leave_lobby")
        leaveCount += 1
        members.removeAll { $0.userId == viewerId }
    }

    func closeLobby(lobbyId: UUID) async throws {
        try fail("close_lobby")
        closeCount += 1
        roomCloses()
    }

    func heartbeat(lobbyId: UUID) async throws {
        try fail("heartbeat_lobby")
        heartbeatCount += 1
    }

    func events(lobbyId: UUID) -> AsyncStream<LobbyEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in self.continuation = nil }
        }
    }

    // MARK: - Private

    private func fail(_ rpc: String) throws {
        if let error = failures[rpc] { throw error }
    }

    private func member(_ userId: UUID, _ name: String) -> LobbyMember {
        joinedAt = joinedAt.addingTimeInterval(1)
        return LobbyMember(userId: userId, displayName: name, joinedAt: joinedAt)
    }

    /// One `'setup'` match, with the roster frozen as of now.
    private func freezeRun(seating seated: [UUID], game: MatchGame) -> UUID {
        let matchId = UUID()
        run = LiveRun(
            matches: [RunMatch(id: matchId, status: .setup, game: game.rawValue)], seatedUserIds: Set(seated)
        )
        return matchId
    }
}
