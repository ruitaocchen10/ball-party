import Foundation
import Supabase

/// Wavelength's whole network surface as the app sees it — one protocol, one
/// substitution point. Everything above it is tested against a fake; nothing
/// above it touches `SupabaseClient`.
///
/// Moves go straight to Postgres with `rpc()`: each derives identity from
/// `auth.uid()` and validates the move itself. The hidden target is never
/// fetched by anyone but its psychic — `wavelength_targets` is narrowed by
/// row-level security before it reaches the socket or a select, so the app
/// reads the table unconditionally and gets only what it may see.
protocol WavelengthClient: Sendable {
    /// `wavelength.start` — deals the match, which `start_run` left in
    /// `'setup'`. Called once, by any participant. `preset` is co-op only.
    func start(matchId: UUID, mode: WavelengthMode, preset: WavelengthPreset?) async throws -> WavelengthBoard

    /// A full re-read of the match.
    func snapshot(matchId: UUID) async throws -> WavelengthSnapshot

    /// `wavelength.submit_clue` — one shot at a round's clue, during fill.
    func submitClue(matchId: UUID, round: Int, clue: String) async throws -> WavelengthBoard

    /// `wavelength.lock_guess` — the position here is the authoritative one.
    func lockGuess(matchId: UUID, round: Int, position: Int) async throws -> WavelengthBoard

    /// `wavelength.next_card` — the host leaves a revealed card: the next one
    /// opens, or the match finishes after the last.
    func nextCard(matchId: UUID) async throws -> WavelengthBoard

    /// `wavelength.report_needle` — lazy, best-effort: it only tells the
    /// server where to auto-lock if the clock runs out.
    func reportNeedle(matchId: UUID, round: Int, position: Int) async throws

    /// `wavelength.tick` — the expiry ask; any participant may call it. It is
    /// also the presence heartbeat.
    func tick(matchId: UUID) async throws -> WavelengthBoard

    /// Broadcast the guesser's needle to the table. Best-effort.
    func sendNeedle(matchId: UUID, round: Int, position: Int) async

    /// `choose_post_game` on a finished match.
    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction

    /// The match's live channels. Cancelling the consuming task tears them down.
    func events(matchId: UUID) -> AsyncStream<WavelengthEvent>
}

struct SupabaseWavelengthClient: WavelengthClient {
    let client: SupabaseClient

    private var game: PostgrestClient { client.schema("wavelength") }

    func start(matchId: UUID, mode: WavelengthMode, preset: WavelengthPreset?) async throws -> WavelengthBoard {
        struct Start: Encodable, Sendable {
            let p_match_id: UUID
            let p_mode: String
            let p_preset: String?
        }
        return try await wrapped {
            try await game.rpc("start", params: Start(p_match_id: matchId, p_mode: mode.rawValue, p_preset: preset?.rawValue))
                .execute().value
        }
    }

    func snapshot(matchId: UUID) async throws -> WavelengthSnapshot {
        try await wrapped {
            // The same set the web's `refetch` reads, in parallel. Cards,
            // clues and targets are RLS-narrowed to what the viewer may see.
            async let state: WavelengthBoard = game.rpc("state", params: MatchParam(p_match_id: matchId)).execute().value
            async let players: [WavelengthPlayer] = client.from("wavelength_players")
                .select("*, profiles(display_name, avatar_url)")
                .eq("match_id", value: matchId).order("seat").execute().value
            async let rounds: [WavelengthRound] = client.from("wavelength_rounds")
                .select().eq("match_id", value: matchId).order("round").execute().value
            async let cards: [WavelengthCard] = client.from("wavelength_cards")
                .select().eq("match_id", value: matchId).order("round").execute().value
            async let clues: [WavelengthClue] = client.from("wavelength_clues")
                .select().eq("match_id", value: matchId).order("round").execute().value
            async let statuses: [WavelengthClueStatus] = client.from("wavelength_clue_statuses")
                .select().eq("match_id", value: matchId).execute().value
            async let targets: [WavelengthTarget] = client.from("wavelength_targets")
                .select().eq("match_id", value: matchId).execute().value
            async let results: [WavelengthResult] = client.from("wavelength_results")
                .select().eq("match_id", value: matchId).execute().value
            async let matches: [MatchRow] = client.from("matches")
                .select("status").eq("id", value: matchId).execute().value
            async let postGame: [PostGameAction] = client.from("post_game_actions")
                .select("choice, next_match_id").eq("match_id", value: matchId).execute().value

            return try await WavelengthSnapshot(
                board: state,
                players: players,
                rounds: rounds,
                cards: cards,
                clues: clues,
                clueStatuses: statuses,
                targets: targets,
                result: results.first,
                matchStatus: matches.first?.status ?? .playing,
                postGame: postGame.first
            )
        }
    }

    func submitClue(matchId: UUID, round: Int, clue: String) async throws -> WavelengthBoard {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_round: Int; let p_clue: String }
        return try await wrapped {
            try await game.rpc("submit_clue", params: Params(p_match_id: matchId, p_round: round, p_clue: clue))
                .execute().value
        }
    }

    func lockGuess(matchId: UUID, round: Int, position: Int) async throws -> WavelengthBoard {
        try await wrapped {
            try await game.rpc("lock_guess", params: PositionParams(p_match_id: matchId, p_round: round, p_position: position))
                .execute().value
        }
    }

    func nextCard(matchId: UUID) async throws -> WavelengthBoard {
        try await wrapped { try await game.rpc("next_card", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func reportNeedle(matchId: UUID, round: Int, position: Int) async throws {
        try await wrapped {
            try await game.rpc("report_needle", params: PositionParams(p_match_id: matchId, p_round: round, p_position: position))
                .execute()
        }
    }

    func tick(matchId: UUID) async throws -> WavelengthBoard {
        try await wrapped { try await game.rpc("tick", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func sendNeedle(matchId: UUID, round: Int, position: Int) async {
        // The channel `events` subscribed; asking for the same private topic
        // returns that instance. A needle sent before it has joined would fall
        // back to REST, which isn't worth a request for a cosmetic update.
        let channel = client.realtimeV2.channel("wavelength:\(matchId.uuidString.lowercased())") { $0.isPrivate = true }
        guard channel.status == .subscribed else { return }
        struct Needle: Codable, Sendable { let round: Int; let position: Int }
        try? await channel.broadcast(event: "needle", message: Needle(round: round, position: position))
    }

    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_choice: String }
        return try await wrapped {
            try await client.rpc(
                "choose_post_game", params: Params(p_match_id: matchId, p_choice: choice.rawValue)
            ).execute().value
        }
    }

    func events(matchId: UUID) -> AsyncStream<WavelengthEvent> {
        let tables = realtimeEvents(
            client: client,
            topics: ["wavelength-tables:\(matchId)", "post-game:\(matchId)"],
            subscribed: WavelengthEvent.subscribed
        ) { channels, yield in
            let match = channels[0]
            let postGame = channels[1]
            let filter: RealtimePostgresFilter = .eq("match_id", value: matchId)

            // Any change behind the board re-reads it: the tables are small
            // and the privacy split between them makes a partial merge easy
            // to get wrong. The status table is presence only.
            let matches = match.postgresChange(AnyAction.self, table: "wavelength_matches", filter: filter)
            let rounds = match.postgresChange(AnyAction.self, table: "wavelength_rounds", filter: filter)
            let players = match.postgresChange(AnyAction.self, table: "wavelength_players", filter: filter)
            let statuses = match.postgresChange(AnyAction.self, table: "wavelength_clue_statuses", filter: filter)
            let platform = match.postgresChange(UpdateAction.self, table: "matches", filter: .eq("id", value: matchId))
            let actions = postGame.postgresChange(InsertAction.self, table: "post_game_actions", filter: filter)

            return [
                { for await _ in matches { yield(.changed) } },
                { for await _ in rounds { yield(.changed) } },
                { for await _ in players { yield(.changed) } },
                { for await _ in statuses { yield(.changed) } },
                { await forwardRows(platform, to: yield) { (row: MatchRow) in .matchStatus(row.status) } },
                { await forwardRows(actions, to: yield, as: WavelengthEvent.postGame) },
            ]
        }

        let client = client
        return AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await event in tables { continuation.yield(event) }
                    }
                    group.addTask {
                        // The needle rides a private broadcast channel, as on
                        // the web; its policy needs the socket authenticated
                        // before the join.
                        let channel = client.realtimeV2.channel("wavelength:\(matchId.uuidString.lowercased())") { $0.isPrivate = true }
                        let needles = channel.broadcastStream(event: "needle")
                        await client.realtimeV2.setAuth(try? await client.auth.session.accessToken)
                        try? await channel.subscribeWithError()
                        for await message in needles {
                            // The callback hands over the whole envelope; the
                            // update itself sits under `payload`.
                            let body = message["payload"]?.objectValue ?? message
                            guard let round = body["round"]?.intValue, let position = body["position"]?.intValue,
                                  (0...WavelengthRules.scaleMax).contains(position)
                            else { continue }
                            continuation.yield(.needle(round: round, position: position))
                        }
                    }
                }
                let channel = client.realtimeV2.channel("wavelength:\(matchId.uuidString.lowercased())") { $0.isPrivate = true }
                await client.realtimeV2.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private struct MatchParam: Encodable, Sendable { let p_match_id: UUID }
    private struct PositionParams: Encodable, Sendable { let p_match_id: UUID; let p_round: Int; let p_position: Int }

    /// `public.matches`, narrowed to the one column the contract hands a game.
    private struct MatchRow: Decodable {
        let status: MatchStatus
    }

    private func wrapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw WavelengthServerError(message: error.message)
        }
    }
}
