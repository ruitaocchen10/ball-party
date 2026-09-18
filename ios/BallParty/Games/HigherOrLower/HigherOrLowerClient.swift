import Foundation
import Supabase

/// A failed server call, reduced to what a screen can act on: the raised
/// message. Every RPC in `docs/architecture/game-runtime.md` raises with
/// `raise exception '<message>'`, and — like the web's `CALL_MESSAGES` — iOS
/// matches on the message string, never the SQL error code.
struct HigherOrLowerServerError: Error, Equatable, Sendable {
    let message: String

    /// The raised message as a sentence for the player, the way the web's
    /// `CALL_MESSAGES` does it. Anything unmapped falls back to the raw
    /// message rather than being flattened into a friendly lie — an
    /// unrecognised failure is a bug to notice, not a state to paper over.
    ///
    /// One map for both screens: a refusal reads the same whether it was a
    /// solo ladder or a room that hit it.
    static func describe(_ error: Error) -> String {
        guard let server = error as? HigherOrLowerServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        return messages[server.message] ?? server.message
    }

    private static let messages: [String: String] = [
        "already_called": "You already locked in this question.",
        "call_not_open": "Calls are not open right now.",
        "call_deadline_passed": "The call window has closed.",
        "match_not_playing": "This match isn't accepting moves right now.",
        "advance_not_open": "The answer isn't ready to move past yet.",
        "not_alive_in_sudden_death": "You're out of sudden death.",
        "not_a_participant": "You're not in this match.",
        "match_not_complete": "This game is still in progress.",
        "post_game_choice_already_made": "The next game has already been chosen.",
        "not_host": "Only the host can choose what's next.",
        "season_out_of_range": "That era is outside the seasons we have data for.",
        "invalid_season_range": "The first season can't be after the last one.",
    ]
}

/// Higher or Lower's whole network surface as the app sees it — one protocol,
/// one substitution point (issue #59, "Testing Decisions" seam 3). Everything
/// above it (view models, views) is tested against a fake; nothing above it
/// touches `SupabaseClient`.
///
/// TODO(architecture): two of these calls — `start_solo_run` and
/// `choose_post_game` — belong to the platform (`public` schema,
/// orchestration), not to the game. The web has the same violation, tracked by
/// the TODO(architecture) above its `postGameChoice` import in
/// `HigherOrLowerMatch.tsx`. They stayed here through the multiplayer vertical
/// (#65) rather than being moved, so this is still owed: both want to sit
/// behind `Platform/`, with the game left holding only its own schema.
///
/// The *group* start path does take that split, because the room screen holds
/// a `LobbyClient` anyway: the platform freezes the roster
/// (`LobbyClient.startRun`) and the game deals into the match it returns
/// (`start`, below). That is the shape the other two should end up in.
protocol HigherOrLowerClient: Sendable {
    /// `higher_or_lower.season_bounds()` — the first and last season in the pool.
    func seasonBounds() async throws -> SeasonRange

    /// `higher_or_lower.start` — deals the ladder into a `'setup'` match and
    /// opens its clock. Called once, by any participant, after `start_run`.
    /// `era == nil` lets the server default to the full pool.
    func start(matchId: UUID, scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard

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

    /// `choose_post_game` on a finished match: replay in the same format, or
    /// send the room back to its lobby. Each match accepts exactly one choice
    /// — host-owned in a room, the player's own solo.
    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction

    /// The match's live channels, as a stream the screen can consume.
    /// Cancelling the consuming task tears them down.
    func events(matchId: UUID) -> AsyncStream<MatchEvent>
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

    func start(matchId: UUID, scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard {
        try await wrapped { try await deal(matchId: matchId, scoringMode: scoringMode, era: era) }
    }

    func startSoloRun(scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard {
        struct StartSoloRun: Encodable, Sendable { let p_game = "higher_or_lower" }
        struct Match: Decodable { let id: UUID }
        return try await wrapped {
            let match: Match = try await client.rpc("start_solo_run", params: StartSoloRun()).execute().value
            return try await deal(matchId: match.id, scoringMode: scoringMode, era: era)
        }
    }

    func snapshot(matchId: UUID) async throws -> HigherOrLowerSnapshot {
        try await wrapped {
            // The same set the web's `refetch` reads, in parallel. Player and
            // call rows are RLS-narrowed to what this viewer may see.
            async let board: HigherOrLowerBoard = game.rpc("state", params: MatchParam(p_match_id: matchId)).execute().value
            async let cards: [LadderCard] = client.from("higher_or_lower_cards")
                .select().eq("match_id", value: matchId).order("ordinal").execute().value
            // The compound (match_id, user_id) foreign keys on the calls and
            // call-statuses tables give PostgREST a second path to `profiles`
            // alongside this table's direct one, so an unqualified embed is
            // ambiguous (PGRST201) — name the direct one.
            async let players: [LadderPlayer] = client.from("higher_or_lower_players")
                .select("*, profiles!higher_or_lower_players_user_id_fkey(display_name)")
                .eq("match_id", value: matchId).order("seat").execute().value
            async let calls: [LadderCall] = client.from("higher_or_lower_calls")
                .select().eq("match_id", value: matchId).order("created_at").execute().value
            async let statuses: [CallStatus] = client.from("higher_or_lower_call_statuses")
                .select().eq("match_id", value: matchId).execute().value
            async let standings: [MatchStanding] = client.from("match_players")
                .select().eq("match_id", value: matchId).execute().value
            // `status` and nothing else: it is the one column of this
            // platform table the contract hands to a game, to detect a pause.
            // Which room the match belongs to, and who hosts it, are the
            // lobby's facts — a game may not read them (`architecture.md`),
            // so the room screen passes them into `MatchViewModel` instead,
            // exactly as the web's match page passes them as props.
            async let matches: [MatchRow] = client.from("matches")
                .select("status").eq("id", value: matchId).execute().value
            // A choice already made, so a screen opened after the host chose
            // still follows everybody else rather than sitting on a finished
            // board.
            async let postGame: [PostGameAction] = client.from("post_game_actions")
                .select("choice, next_match_id").eq("match_id", value: matchId).execute().value

            let match = try await matches.first
            return try await HigherOrLowerSnapshot(
                board: board,
                cards: cards,
                players: players,
                calls: calls,
                statuses: statuses,
                standings: standings,
                matchStatus: match?.status ?? .playing,
                postGame: postGame.first
            )
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

    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_choice: String }
        return try await wrapped {
            try await client.rpc(
                "choose_post_game", params: Params(p_match_id: matchId, p_choice: choice.rawValue)
            ).execute().value
        }
    }

    func events(matchId: UUID) -> AsyncStream<MatchEvent> {
        realtimeEvents(
            client: client,
            topics: ["higher-or-lower:\(matchId)", "post-game:\(matchId)"],
            subscribed: .subscribed
        ) { channels, yield in
            let match = channels[0]
            let postGame = channels[1]
            let filter: RealtimePostgresFilter = .eq("match_id", value: matchId)

            // The event per table is the contract's, not a preference: the
            // two append-only tables are INSERT, everything whose row changes
            // in place is `*`, and `matches` is UPDATE keyed on its own id
            // (`realtime.md`).
            let boards = match.postgresChange(AnyAction.self, table: "higher_or_lower_matches", filter: filter)
            let cards = match.postgresChange(AnyAction.self, table: "higher_or_lower_cards", filter: filter)
            let players = match.postgresChange(AnyAction.self, table: "higher_or_lower_players", filter: filter)
            let calls = match.postgresChange(InsertAction.self, table: "higher_or_lower_calls", filter: filter)
            let statuses = match.postgresChange(
                InsertAction.self, table: "higher_or_lower_call_statuses", filter: filter
            )
            let standings = match.postgresChange(AnyAction.self, table: "match_players", filter: filter)
            let matches = match.postgresChange(
                UpdateAction.self, table: "matches", filter: .eq("id", value: matchId)
            )
            let actions = postGame.postgresChange(
                InsertAction.self, table: "post_game_actions", filter: filter
            )

            return [
                { await forwardRows(boards, to: yield, as: MatchEvent.board) },
                { await forwardRows(cards, to: yield, as: MatchEvent.card) },
                { await forwardRows(players, to: yield, as: MatchEvent.player) },
                { await forwardRows(calls, to: yield, as: MatchEvent.call) },
                { await forwardRows(statuses, to: yield, as: MatchEvent.callStatus) },
                { await forwardRows(standings, to: yield, as: MatchEvent.standing) },
                { await forwardRows(actions, to: yield, as: MatchEvent.postGame) },
                { await forwardRows(matches, to: yield) { (row: MatchRow) in .matchStatus(row.status) } },
            ]
        }
    }

    // MARK: - Private

    private struct MatchParam: Encodable, Sendable { let p_match_id: UUID }

    /// `public.matches`, narrowed to the one column the contract hands a game.
    private struct MatchRow: Decodable {
        let status: MatchStatus
    }

    /// `higher_or_lower.start` itself, shared by the solo and group paths —
    /// the same deal either way; only how the match got here differs.
    private func deal(matchId: UUID, scoringMode: ScoringMode, era: SeasonRange?) async throws -> HigherOrLowerBoard {
        struct Start: Encodable, Sendable {
            let p_match_id: UUID
            let p_scoring_mode: String
            let p_season_from: Int?
            let p_season_to: Int?
        }
        return try await game.rpc(
            "start",
            params: Start(
                p_match_id: matchId,
                p_scoring_mode: scoringMode.rawValue,
                p_season_from: era?.from,
                p_season_to: era?.to
            )
        ).execute().value
    }

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
