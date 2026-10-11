import Foundation
import Supabase

/// Sabotage Draft's whole network surface as the app sees it — one protocol, one
/// substitution point. Everything above it is tested against a fake; nothing
/// above it touches `SupabaseClient`.
///
/// Moves go straight to Postgres with `rpc()`: each derives identity from
/// `auth.uid()` and validates the move itself. What a viewer may know is decided
/// by row-level security, not by this layer — `sabotage_draft_picks` is narrowed
/// to a seat's own picks (plus resolved ones), so the app reads the table
/// unconditionally and gets only what it may see.
protocol SabotageClient: Sendable {
    /// `sabotage_draft.start` — deals the match, which `start_run` left in
    /// `'setup'`. Called once, by any participant.
    func start(matchId: UUID, mode: SabotageMode) async throws -> SabotageBoard?

    /// A full re-read of the match.
    func snapshot(matchId: UUID) async throws -> SabotageSnapshot

    /// `sabotage_draft.options` — the player-seasons the pool offers. With no
    /// target, the caller's own spun franchise (to pick from); with one, that
    /// seat's (to guess against).
    func options(matchId: UUID, targetUserId: UUID?) async throws -> [SabotageOption]

    /// `sabotage_draft.submit_pick` — the active seat's hidden pick.
    func submitPick(matchId: UUID, playerId: String, season: Int) async throws

    /// `sabotage_draft.submit_guess` — aimed at whoever is on the clock. Naming
    /// the exact `season` also needs a replacement, which the guesser chooses.
    func submitGuess(
        matchId: UUID, playerId: String, season: Int?, replacement: (playerId: String, season: Int)?
    ) async throws

    /// `sabotage_draft.submit_pass` — an explicit, legal "no guess".
    func submitPass(matchId: UUID) async throws

    /// `sabotage_draft.submit_x_factor_decision` — a slot to replace, or `nil`
    /// to discard.
    func submitXFactorDecision(matchId: UUID, replaceSlot: String?) async throws

    /// `sabotage_draft.tick` — the expiry ask; any participant may call it. It
    /// is also the presence heartbeat.
    func tick(matchId: UUID) async throws -> SabotageBoard?

    /// `choose_post_game` on a finished match.
    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction

    /// The match's live channels. Cancelling the consuming task tears them down.
    func events(matchId: UUID) -> AsyncStream<SabotageEvent>
}

struct SupabaseSabotageClient: SabotageClient {
    let client: SupabaseClient

    private var game: PostgrestClient { client.schema("sabotage_draft") }

    func start(matchId: UUID, mode: SabotageMode) async throws -> SabotageBoard? {
        struct Start: Encodable, Sendable { let p_match_id: UUID; let p_mode: String }
        return try await wrapped {
            try await game.rpc("start", params: Start(p_match_id: matchId, p_mode: mode.rawValue))
                .execute().value
        }
    }

    func snapshot(matchId: UUID) async throws -> SabotageSnapshot {
        try await wrapped {
            // The same set the web's `refetch` reads, in parallel. Picks and
            // spins are RLS-narrowed to what the viewer may see.
            async let state: SabotageBoard? = game.rpc("state", params: MatchParam(p_match_id: matchId)).execute().value
            async let players: [SabotagePlayer] = client.from("sabotage_draft_players")
                .select("*, profiles(display_name, avatar_url)")
                .eq("match_id", value: matchId).order("seat").execute().value
            async let spins: [SabotageSpin] = client.from("sabotage_draft_round_spins")
                .select().eq("match_id", value: matchId).execute().value
            async let picks: [SabotagePick] = client.from("sabotage_draft_picks")
                .select().eq("match_id", value: matchId).execute().value
            async let statuses: [SabotagePickStatus] = client.from("sabotage_draft_pick_statuses")
                .select().eq("match_id", value: matchId).execute().value
            async let hits: [SabotageHit] = client.from("sabotage_draft_pick_hits")
                .select().eq("match_id", value: matchId).execute().value
            async let guesses: [SabotageGuess] = client.from("sabotage_draft_guesses")
                .select().eq("match_id", value: matchId).execute().value
            async let passes: [SabotagePass] = client.from("sabotage_draft_passes")
                .select().eq("match_id", value: matchId).execute().value
            async let decisions: [SabotageDecision] = client.from("sabotage_draft_x_factor_decisions")
                .select().eq("match_id", value: matchId).execute().value
            async let standings: [SabotageStanding] = client.from("sabotage_draft_standings")
                .select().eq("match_id", value: matchId).execute().value
            async let tiebreaks: [SabotageTiebreak] = client.from("sabotage_draft_tiebreak_games")
                .select().eq("match_id", value: matchId).execute().value
            async let pickAvs: [SabotagePickAv] = game.rpc("pick_avs", params: MatchParam(p_match_id: matchId)).execute().value
            async let matches: [MatchRow] = client.from("matches")
                .select("status").eq("id", value: matchId).execute().value
            async let postGame: [PostGameAction] = client.from("post_game_actions")
                .select("choice, next_match_id").eq("match_id", value: matchId).execute().value

            guard let board = try await state else { throw SabotageServerError(message: "board_not_found") }
            return try await SabotageSnapshot(
                board: board,
                players: players,
                spins: spins,
                picks: picks,
                statuses: statuses,
                hits: hits,
                guesses: guesses,
                passes: passes,
                decisions: decisions,
                standings: standings,
                tiebreaks: tiebreaks,
                pickAvs: pickAvs,
                matchStatus: matches.first?.status ?? .playing,
                postGame: postGame.first
            )
        }
    }

    func options(matchId: UUID, targetUserId: UUID?) async throws -> [SabotageOption] {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_target_user_id: UUID? }
        return try await wrapped {
            try await game.rpc("options", params: Params(p_match_id: matchId, p_target_user_id: targetUserId))
                .execute().value
        }
    }

    func submitPick(matchId: UUID, playerId: String, season: Int) async throws {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_player_id: String; let p_season: Int }
        try await wrapped {
            try await game.rpc("submit_pick", params: Params(p_match_id: matchId, p_player_id: playerId, p_season: season))
                .execute()
        }
    }

    func submitGuess(
        matchId: UUID, playerId: String, season: Int?, replacement: (playerId: String, season: Int)?
    ) async throws {
        struct Params: Encodable, Sendable {
            let p_match_id: UUID
            let p_player_id: String
            let p_season: Int?
            let p_replacement_player_id: String?
            let p_replacement_season: Int?
        }
        try await wrapped {
            try await game.rpc(
                "submit_guess",
                params: Params(
                    p_match_id: matchId, p_player_id: playerId, p_season: season,
                    p_replacement_player_id: replacement?.playerId, p_replacement_season: replacement?.season
                )
            ).execute()
        }
    }

    func submitPass(matchId: UUID) async throws {
        try await wrapped {
            try await game.rpc("submit_pass", params: MatchParam(p_match_id: matchId)).execute()
        }
    }

    func submitXFactorDecision(matchId: UUID, replaceSlot: String?) async throws {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_replace_slot: String? }
        try await wrapped {
            try await game.rpc("submit_x_factor_decision", params: Params(p_match_id: matchId, p_replace_slot: replaceSlot))
                .execute()
        }
    }

    func tick(matchId: UUID) async throws -> SabotageBoard? {
        try await wrapped { try await game.rpc("tick", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_choice: String }
        return try await wrapped {
            try await client.rpc(
                "choose_post_game", params: Params(p_match_id: matchId, p_choice: choice.rawValue)
            ).execute().value
        }
    }

    func events(matchId: UUID) -> AsyncStream<SabotageEvent> {
        realtimeEvents(
            client: client,
            topics: ["sabotage-tables:\(matchId)", "post-game:\(matchId)"],
            subscribed: SabotageEvent.subscribed
        ) { channels, yield in
            let match = channels[0]
            let postGame = channels[1]
            let filter: RealtimePostgresFilter = .eq("match_id", value: matchId)

            // Any change behind the board re-reads it. The picks tables are
            // narrowed per viewer, so a partial merge would be easy to get wrong.
            let tables = [
                "sabotage_draft_matches", "sabotage_draft_players", "sabotage_draft_round_spins",
                "sabotage_draft_picks", "sabotage_draft_pick_statuses", "sabotage_draft_guesses",
                "sabotage_draft_passes", "sabotage_draft_pick_hits", "sabotage_draft_x_factor_decisions",
                "sabotage_draft_standings", "sabotage_draft_tiebreak_games",
            ].map { match.postgresChange(AnyAction.self, table: $0, filter: filter) }
            let platform = match.postgresChange(UpdateAction.self, table: "matches", filter: .eq("id", value: matchId))
            let actions = postGame.postgresChange(InsertAction.self, table: "post_game_actions", filter: filter)

            var jobs: [@Sendable () async -> Void] = tables.map { stream in
                { for await _ in stream { yield(.changed) } }
            }
            jobs.append { await forwardRows(platform, to: yield) { (row: MatchRow) in .matchStatus(row.status) } }
            jobs.append { await forwardRows(actions, to: yield, as: SabotageEvent.postGame) }
            return jobs
        }
    }

    // MARK: - Private

    private struct MatchParam: Encodable, Sendable { let p_match_id: UUID }

    /// `public.matches`, narrowed to the one column the contract hands a game.
    private struct MatchRow: Decodable {
        let status: MatchStatus
    }

    private func wrapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw SabotageServerError(message: error.message)
        }
    }
}
