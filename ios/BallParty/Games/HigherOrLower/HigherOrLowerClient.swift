import Foundation
import Supabase

/// A failed server call, reduced to what a screen can act on: the raised
/// message. Every RPC in `docs/architecture/game-runtime.md` raises with
/// `raise exception '<message>'`, and — like the web's `CALL_MESSAGES` — iOS
/// matches on the message string, never the SQL error code.
struct HigherOrLowerServerError: Error, Equatable, Sendable {
    let message: String
}

/// Higher or Lower's whole network surface as the app sees it — one protocol,
/// one substitution point (issue #59, "Testing Decisions" seam 3). Everything
/// above it (view models, views) is tested against a fake; nothing above it
/// touches `SupabaseClient`.
///
/// Solo-only for now: there is no lobby, `start_run`, or Realtime here yet.
///
/// Two of these calls — `start_solo_run` and `choose_post_game` — belong to the
/// platform (`public` schema, orchestration), not to the game; the web has the
/// same boundary violation, tracked by the TODO(architecture) above its
/// `postGameChoice` import in `HigherOrLowerMatch.tsx`. They live here so the
/// game has one seam to fake; move them behind `Platform/` when the multiplayer
/// vertical needs the same lobby/orchestration calls.
protocol HigherOrLowerClient: Sendable {
    /// `higher_or_lower.season_bounds()` — the first and last season in the pool.
    func seasonBounds() async throws -> SeasonRange

    /// The viewer's all-time-high streak from `higher_or_lower_player_stats`;
    /// 0 for a player with no solo history yet.
    func personalBest() async throws -> Int

    /// `start_solo_run` then `higher_or_lower.start`: creates the one-player
    /// match and deals its ladder. `era == nil` lets the server default to the
    /// full pool.
    func startSoloRun(scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard

    /// A full re-read of the match — `state` plus the tables the screen shows.
    func snapshot(matchId: UUID) async throws -> HigherOrLowerSnapshot

    /// `higher_or_lower.call`.
    func call(matchId: UUID, direction: CallDirection) async throws -> LadderCall

    /// `higher_or_lower.advance` — solo's "Continue" out of a reveal.
    func advance(matchId: UUID) async throws -> HigherOrLowerBoard

    /// `higher_or_lower.tick` — the expiry ask, which doubles as the heartbeat.
    func tick(matchId: UUID) async throws -> HigherOrLowerBoard

    /// `choose_post_game(..., 'replay')` on a finished solo match: a fresh,
    /// already-dealt match in the same format. Returns its id.
    func replay(matchId: UUID) async throws -> UUID
}

struct SupabaseHigherOrLowerClient: HigherOrLowerClient {
    let client: SupabaseClient

    private var game: PostgrestClient { client.schema("higher_or_lower") }

    func seasonBounds() async throws -> SeasonRange {
        struct Era: Decodable { let seasonMin: Int; let seasonMax: Int
            enum CodingKeys: String, CodingKey { case seasonMin = "season_min", seasonMax = "season_max" }
        }
        let era: Era = try await wrapped { try await game.rpc("season_bounds").execute().value }
        return SeasonRange(from: era.seasonMin, to: era.seasonMax)
    }

    func personalBest() async throws -> Int {
        struct Row: Decodable { let allTimeHigh: Int
            enum CodingKeys: String, CodingKey { case allTimeHigh = "all_time_high" }
        }
        // RLS narrows this table to the caller's own row.
        let rows: [Row] = try await wrapped {
            try await client.from("higher_or_lower_player_stats").select("all_time_high").limit(1).execute().value
        }
        return rows.first?.allTimeHigh ?? 0
    }

    func startSoloRun(scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard {
        struct StartSoloRun: Encodable, Sendable { let p_game = "higher_or_lower" }
        struct Match: Decodable { let id: UUID }
        struct Start: Encodable, Sendable {
            let p_match_id: UUID
            let p_scoring_mode: String
            let p_season_from: Int?
            let p_season_to: Int?
        }
        return try await wrapped {
            let match: Match = try await client.rpc("start_solo_run", params: StartSoloRun()).execute().value
            return try await game.rpc(
                "start",
                params: Start(
                    p_match_id: match.id,
                    p_scoring_mode: scoringMode.rawValue,
                    p_season_from: era?.from,
                    p_season_to: era?.to
                )
            ).execute().value
        }
    }

    func snapshot(matchId: UUID) async throws -> HigherOrLowerSnapshot {
        try await wrapped {
            // The same set the web's `refetch` reads, in parallel. Player and
            // call rows are RLS-narrowed to what this viewer may see.
            async let board: HigherOrLowerBoard = game.rpc("state", params: MatchParam(p_match_id: matchId)).execute().value
            async let cards: [LadderCard] = client.from("higher_or_lower_cards")
                .select().eq("match_id", value: matchId).order("ordinal").execute().value
            async let players: [LadderPlayer] = client.from("higher_or_lower_players")
                .select().eq("match_id", value: matchId).order("seat").execute().value
            async let calls: [LadderCall] = client.from("higher_or_lower_calls")
                .select().eq("match_id", value: matchId).order("created_at").execute().value
            return try await HigherOrLowerSnapshot(board: board, cards: cards, players: players, calls: calls)
        }
    }

    func call(matchId: UUID, direction: CallDirection) async throws -> LadderCall {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_direction: String }
        return try await wrapped {
            try await game.rpc("call", params: Params(p_match_id: matchId, p_direction: direction.rawValue)).execute().value
        }
    }

    func advance(matchId: UUID) async throws -> HigherOrLowerBoard {
        try await wrapped { try await game.rpc("advance", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func tick(matchId: UUID) async throws -> HigherOrLowerBoard {
        try await wrapped { try await game.rpc("tick", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func replay(matchId: UUID) async throws -> UUID {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_choice = "replay" }
        struct Action: Decodable {
            let nextMatchId: UUID?
            enum CodingKeys: String, CodingKey { case nextMatchId = "next_match_id" }
        }
        let action: Action = try await wrapped {
            try await client.rpc("choose_post_game", params: Params(p_match_id: matchId)).execute().value
        }
        guard let next = action.nextMatchId else { throw HigherOrLowerServerError(message: "replay_not_supported") }
        return next
    }

    // MARK: - Private

    private struct MatchParam: Encodable, Sendable { let p_match_id: UUID }

    /// Surfaces a PostgREST failure as its raised message, so callers depend on
    /// `HigherOrLowerServerError` rather than on the SDK's error type.
    private func wrapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw HigherOrLowerServerError(message: error.message)
        }
    }
}
