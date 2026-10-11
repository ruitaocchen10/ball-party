import Foundation
import Supabase

/// The lobby module's whole network surface as the app sees it — one protocol,
/// one substitution point (issue #59, "Testing Decisions" seam 3). The room
/// screen and its view model are tested against a fake; nothing above this
/// touches `SupabaseClient`.
///
/// Every call here is a `public`-schema RPC or table read, and every one of
/// them derives identity from `auth.uid()` rather than from an argument — see
/// `docs/architecture/game-runtime.md`, "Getting into a match".
///
/// Deliberately *not* here: `higher_or_lower.start`, the call that deals a
/// ladder into the `'setup'` match `startRun` returns. That belongs to the
/// game's own schema and so to `HigherOrLowerClient`; the room screen holds
/// both and makes the two calls in order, which is the same seam the web draws
/// in `startRun` (`webapp/lib/platform/lobbies/actions.ts`) — the platform
/// starts a run, the game deals it.
protocol LobbyClient: Sendable {
    /// `create_lobby()` — hosts a room and seats the caller in it.
    func createLobby() async throws -> Lobby

    /// `join_lobby(p_code)`. Idempotent for a player already in the room, so a
    /// retry after a flaky connection is safe.
    func joinLobby(code: String) async throws -> Lobby

    /// A full re-read of the room: the lobby row, its active members, and its
    /// active run if a game is under way.
    func snapshot(lobbyId: UUID) async throws -> LobbySnapshot

    /// `select_lobby_game(p_lobby_id, p_game)` — host-only, advisory "next up".
    func selectGame(lobbyId: UUID, game: MatchGame) async throws

    /// `set_lobby_game_format(p_lobby_id, p_format)` — host-only. Saves the
    /// host's settings on the room (replacing what was there) so everybody in it
    /// can see them.
    func setGameFormat(lobbyId: UUID, format: LobbyGameFormat) async throws

    /// `start_run(p_lobby_id, 'arcade', p_game)` — host-only. Freezes the
    /// roster and returns the id of the `'setup'` match the game then deals
    /// into.
    func startRun(lobbyId: UUID, game: MatchGame) async throws -> UUID

    /// `leave_lobby(p_lobby_id)`.
    func leaveLobby(lobbyId: UUID) async throws

    /// `close_lobby(p_lobby_id)` — host-only; ends the room for everybody.
    func closeLobby(lobbyId: UUID) async throws

    /// `heartbeat_lobby(p_lobby_id)` — renews this member's `last_seen_at`.
    /// Nothing in the app reads that column back; it keeps the server's
    /// host-recovery and janitor sweeps working for a mobile-hosted lobby
    /// (`realtime.md`, "Presence is a heartbeat RPC").
    func heartbeat(lobbyId: UUID) async throws

    /// The `lobby:${lobbyId}` channel, as a stream the screen can consume.
    /// Cancelling the consuming task tears the channel down.
    func events(lobbyId: UUID) -> AsyncStream<LobbyEvent>
}

struct SupabaseLobbyClient: LobbyClient {
    let client: SupabaseClient

    func createLobby() async throws -> Lobby {
        try await wrapped { try await client.rpc("create_lobby").execute().value }
    }

    func joinLobby(code: String) async throws -> Lobby {
        struct Params: Encodable, Sendable { let p_code: String }
        let params = Params(p_code: code)
        do {
            return try await client.rpc("join_lobby", params: params).execute().value
        } catch let error as PostgrestError where error.code == "40P01" {
            // Two players swapping rooms at the same instant take the lobby
            // locks in opposite order and Postgres kills one of them. Retrying
            // immediately is safe because `join_lobby` is idempotent for a
            // player already in the room — the same retry the web does.
            return try await wrapped { try await client.rpc("join_lobby", params: params).execute().value }
        } catch let error as PostgrestError {
            throw LobbyServerError(message: error.message)
        }
    }

    func snapshot(lobbyId: UUID) async throws -> LobbySnapshot {
        try await wrapped {
            async let lobby: Lobby = client.from("lobbies")
                .select("id, code, host_id, closed_at, selected_game, game_format")
                .eq("id", value: lobbyId)
                .single()
                .execute().value
            async let members: [LobbyMember] = client.from("lobby_members")
                .select("user_id, joined_at, profiles(display_name, avatar_url)")
                .eq("lobby_id", value: lobbyId)
                .is("left_at", value: nil)
                .order("joined_at")
                .execute().value
            // At most one active run per lobby (`start_run` refuses a second),
            // but read as a list: "no run" is the room's normal resting state,
            // not a failure.
            async let runs: [LiveRun] = client.from("runs")
                .select("matches(id, status, game), run_participants(user_id)")
                .eq("lobby_id", value: lobbyId)
                .eq("status", value: "active")
                .execute().value
            // The room's wins: every game writes `placement` on finish, and
            // 1 is the winner whatever the game (the web reads it the same way).
            async let wins: [LobbySnapshot.WinRow] = client.from("match_players")
                .select("user_id, matches!inner(status, runs!inner(lobby_id))")
                .eq("placement", value: 1)
                .eq("matches.status", value: "complete")
                .eq("matches.runs.lobby_id", value: lobbyId)
                .execute().value
            return try await LobbySnapshot(
                lobby: lobby, members: members, run: runs.first, wins: LobbySnapshot.tallyWins(wins)
            )
        }
    }

    func selectGame(lobbyId: UUID, game: MatchGame) async throws {
        struct Params: Encodable, Sendable { let p_lobby_id: UUID; let p_game: String }
        try await wrapped {
            _ = try await client.rpc(
                "select_lobby_game", params: Params(p_lobby_id: lobbyId, p_game: game.rawValue)
            ).execute()
        }
    }

    func setGameFormat(lobbyId: UUID, format: LobbyGameFormat) async throws {
        struct Params: Encodable, Sendable { let p_lobby_id: UUID; let p_format: LobbyGameFormat }
        try await wrapped {
            _ = try await client.rpc(
                "set_lobby_game_format", params: Params(p_lobby_id: lobbyId, p_format: format)
            ).execute()
        }
    }

    func startRun(lobbyId: UUID, game: MatchGame) async throws -> UUID {
        struct Params: Encodable, Sendable { let p_lobby_id: UUID; let p_mode = "arcade"; let p_game: String }
        struct Match: Decodable { let id: UUID }
        let match: Match = try await wrapped {
            try await client.rpc("start_run", params: Params(p_lobby_id: lobbyId, p_game: game.rawValue))
                .execute().value
        }
        return match.id
    }

    func leaveLobby(lobbyId: UUID) async throws {
        try await wrapped { _ = try await client.rpc("leave_lobby", params: LobbyParam(p_lobby_id: lobbyId)).execute() }
    }

    func closeLobby(lobbyId: UUID) async throws {
        try await wrapped { _ = try await client.rpc("close_lobby", params: LobbyParam(p_lobby_id: lobbyId)).execute() }
    }

    func heartbeat(lobbyId: UUID) async throws {
        try await wrapped { _ = try await client.rpc("heartbeat_lobby", params: LobbyParam(p_lobby_id: lobbyId)).execute() }
    }

    func events(lobbyId: UUID) -> AsyncStream<LobbyEvent> {
        realtimeEvents(
            client: client, topics: ["lobby:\(lobbyId)"], subscribed: .subscribed
        ) { channels, yield in
            let channel = channels[0]
            let members = channel.postgresChange(
                AnyAction.self, table: "lobby_members", filter: .eq("lobby_id", value: lobbyId)
            )
            let lobbies = channel.postgresChange(
                AnyAction.self, table: "lobbies", filter: .eq("id", value: lobbyId)
            )
            let runs = channel.postgresChange(
                AnyAction.self, table: "runs", filter: .eq("lobby_id", value: lobbyId)
            )
            // Unfiltered, because a match is keyed on its run — which this
            // screen doesn't know until one exists. RLS already scopes the
            // stream to matches of runs this subscriber belongs to, so
            // unfiltered is not unguarded (`realtime.md`).
            let matches = channel.postgresChange(AnyAction.self, table: "matches")

            // No payload is applied here, so none is decoded: a lobby event
            // is only ever the fact that the room changed.
            return [members, lobbies, runs, matches].map { payloads in
                { for await _ in payloads { yield(.changed) } }
            }
        }
    }

    // MARK: - Private

    private struct LobbyParam: Encodable, Sendable { let p_lobby_id: UUID }

    /// Surfaces a PostgREST failure as its raised message, so callers depend on
    /// `LobbyServerError` rather than on the SDK's error type.
    private func wrapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw LobbyServerError(message: error.message)
        }
    }
}
