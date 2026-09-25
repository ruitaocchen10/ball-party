import Foundation
import Supabase

/// A failed server call, reduced to what a screen can act on: the raised
/// message. Like every game API here it raises with
/// `raise exception '<message>'` and the client matches the message string,
/// never the SQL error code.
struct QbSeasonBuilderServerError: Error, Equatable, Sendable {
    let message: String

    /// The raised message as a sentence for the player — the web's
    /// `QB_MESSAGES`. Anything unmapped falls back to the raw message rather
    /// than being flattened into a friendly lie.
    static func describe(_ error: Error) -> String {
        guard let server = error as? QbSeasonBuilderServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        return messages[server.message] ?? server.message
    }

    private static let messages: [String: String] = [
        "not_authenticated": "Sign in first.",
        "not_a_participant": "This run isn't yours.",
        "match_not_found": "This run no longer exists.",
        "match_not_playing": "This run has already ended.",
        "slot_filled": "That slot is already filled.",
        "source_not_on_spin": "That option isn't on this spin any more.",
        "respin_used": "You've already used your respin.",
        "draft_complete": "All six slots are filled.",
        "draft_incomplete": "Fill all six slots first.",
        "pool_exhausted": "Couldn't deal a spin. Try again.",
    ]
}

/// QB Season Builder's whole network surface as the app sees it — one protocol,
/// one substitution point. Everything above it is tested against a fake;
/// nothing above it touches `SupabaseClient`.
protocol QbSeasonBuilderClient: Sendable {
    /// `start_solo_run` then `qb_season_builder.start`: a new one-player run,
    /// dealt its first spin. Starting again is a new game.
    func startRun(mode: QbRatingMode, era: QbEra) async throws -> QbBoard

    /// `qb_season_builder.state` — a full re-read of the run.
    func state(matchId: UUID) async throws -> QbBoard

    /// `qb_season_builder.pick` — fills one slot from the current spin and
    /// answers with the board, next round's spin already dealt.
    func pick(matchId: UUID, slot: QbSlot, playerId: String?) async throws -> QbBoard

    /// `qb_season_builder.respin` — rerolls the current spin, once per run.
    func respin(matchId: UUID) async throws -> QbBoard

    /// `qb_season_builder.finish` — turns the six picks into a saved season.
    func finish(matchId: UUID) async throws -> QbSeasonResult

    /// `qb_season_builder.result` — the saved season of a run that is already
    /// finished. A second `finish` refuses (`match_not_playing`); this reads it.
    func result(matchId: UUID) async throws -> QbSeasonResult

    /// The viewer's best score in one mode, from `qb_season_builder_player_stats`;
    /// nil for a player with no finished run in it.
    func personalBest(userId: UUID, mode: QbRatingMode) async throws -> Double?
}

struct SupabaseQbSeasonBuilderClient: QbSeasonBuilderClient {
    let client: SupabaseClient

    private var game: PostgrestClient { client.schema("qb_season_builder") }

    func startRun(mode: QbRatingMode, era: QbEra) async throws -> QbBoard {
        struct StartSoloRun: Encodable, Sendable { let p_game = "qb_season_builder" }
        struct Match: Decodable { let id: UUID }
        struct Start: Encodable, Sendable { let p_match_id: UUID; let p_mode: String; let p_era: String }
        return try await wrapped {
            let match: Match = try await client.rpc("start_solo_run", params: StartSoloRun()).execute().value
            return try await game.rpc(
                "start", params: Start(p_match_id: match.id, p_mode: mode.rawValue, p_era: era.rawValue)
            ).execute().value
        }
    }

    func state(matchId: UUID) async throws -> QbBoard {
        try await wrapped { try await game.rpc("state", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func pick(matchId: UUID, slot: QbSlot, playerId: String?) async throws -> QbBoard {
        struct Params: Encodable, Sendable {
            let p_match_id: UUID
            let p_slot: String
            let p_player_id: String?

            // The Supporting Cast has no quarterback, and the server refuses
            // a `null` player id differently from an absent one.
            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(p_match_id, forKey: .p_match_id)
                try container.encode(p_slot, forKey: .p_slot)
                try container.encodeIfPresent(p_player_id, forKey: .p_player_id)
            }

            private enum CodingKeys: String, CodingKey { case p_match_id, p_slot, p_player_id }
        }
        return try await wrapped {
            try await game.rpc(
                "pick", params: Params(p_match_id: matchId, p_slot: slot.rawValue, p_player_id: playerId)
            ).execute().value
        }
    }

    func respin(matchId: UUID) async throws -> QbBoard {
        try await wrapped { try await game.rpc("respin", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func finish(matchId: UUID) async throws -> QbSeasonResult {
        try await wrapped { try await game.rpc("finish", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func result(matchId: UUID) async throws -> QbSeasonResult {
        try await wrapped { try await game.rpc("result", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func personalBest(userId: UUID, mode: QbRatingMode) async throws -> Double? {
        struct Row: Decodable {
            let bestScore: Double
            enum CodingKeys: String, CodingKey { case bestScore = "best_score" }
        }
        let rows: [Row] = try await wrapped {
            try await client.from("qb_season_builder_player_stats")
                .select("best_score")
                .eq("user_id", value: userId)
                .eq("mode", value: mode.rawValue)
                .limit(1)
                .execute().value
        }
        return rows.first?.bestScore
    }

    // MARK: - Private

    private struct MatchParam: Encodable, Sendable { let p_match_id: UUID }

    /// Surfaces a PostgREST failure as its raised message, so callers depend on
    /// `QbSeasonBuilderServerError` rather than on the SDK's error type.
    private func wrapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw QbSeasonBuilderServerError(message: error.message)
        }
    }
}
