import Foundation
import Supabase

/// The auction's whole network surface as the app sees it — one protocol, one
/// substitution point. Everything above it (view models, views) is tested
/// against a fake; nothing above it touches `SupabaseClient`.
///
/// Moves go straight from the app to Postgres with `rpc()`: every one derives
/// identity from `auth.uid()` and validates the move itself, so there is nothing
/// a server hop in between would add. And nothing here is optimistic — a bid is
/// not on screen until the server confirms it.
///
/// The group start path takes the platform/game split the room screen draws:
/// the platform freezes the roster (`LobbyClient.startRun`) and the game deals
/// into the match it returns (`start`, below).
protocol AuctionClient: Sendable {
    /// `auction.season_bounds()` — the pool's first and last season, and the
    /// narrowest window the dealer accepts.
    func seasonBounds() async throws -> AuctionEra

    /// `auction.start` — deals the board into a `'setup'` match and opens its
    /// first lot. Called once, by any participant, after `start_run`.
    /// `era == nil` lets the server default to the whole pool.
    func start(
        matchId: UUID, scoringMode: ScoringMode, rosterPreset: RosterPreset, era: SeasonRange?, tokenCount: Int
    ) async throws -> AuctionTurn

    /// A full re-read of the match — `state` plus the tables the screen shows.
    func snapshot(matchId: UUID) async throws -> AuctionSnapshot

    /// `auction.place_bid`. A bid of `0` takes an uncontested lot for free.
    func placeBid(matchId: UUID, amount: Int) async throws -> AuctionTurn

    /// `auction.pass_lot` — drops the caller from this lot permanently.
    func pass(matchId: UUID) async throws -> AuctionTurn

    /// `auction.expire_turn` — the expiry ask. Any participant may call it;
    /// the server re-checks the deadline under its own lock and no-ops if it
    /// disagrees, so duplicate calls are harmless.
    func expireTurn(matchId: UUID) async throws -> AuctionTurn

    /// `auction.use_scout_token` — returns the coarse tier it just wrote.
    func useScoutToken(matchId: UUID) async throws -> String

    /// `auction.use_seal_token`.
    func useSealToken(matchId: UUID) async throws -> AuctionTurn

    /// `auction.submit_sealed_bid`.
    func submitSealedBid(matchId: UUID, amount: Int) async throws -> AuctionTurn

    /// `choose_post_game` on a finished match: an exact replay of the format,
    /// or the room back to its lobby. Each match accepts exactly one choice,
    /// owned by the host.
    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction

    /// The match's live channels, as a stream the screen can consume.
    /// Cancelling the consuming task tears them down.
    func events(matchId: UUID) -> AsyncStream<AuctionEvent>
}

struct SupabaseAuctionClient: AuctionClient {
    let client: SupabaseClient

    private var game: PostgrestClient { client.schema("auction") }

    func seasonBounds() async throws -> AuctionEra {
        try await wrapped { try await game.rpc("season_bounds").execute().value }
    }

    func start(
        matchId: UUID, scoringMode: ScoringMode, rosterPreset: RosterPreset, era: SeasonRange?, tokenCount: Int
    ) async throws -> AuctionTurn {
        struct Start: Encodable, Sendable {
            let p_match_id: UUID
            let p_scoring_mode: String
            let p_roster_preset: String
            let p_season_from: Int?
            let p_season_to: Int?
            let p_token_count: Int
        }
        return try await wrapped {
            try await game.rpc(
                "start",
                params: Start(
                    p_match_id: matchId,
                    p_scoring_mode: scoringMode.rawValue,
                    p_roster_preset: rosterPreset.rawValue,
                    p_season_from: era?.from,
                    p_season_to: era?.to,
                    p_token_count: tokenCount
                )
            ).execute().value
        }
    }

    func snapshot(matchId: UUID) async throws -> AuctionSnapshot {
        try await wrapped {
            // The same set the web's `refetch` reads, in parallel. Hint and
            // sealed-bid rows are RLS-narrowed to the viewer's own; the status
            // table is presence only, readable by every member.
            async let state: AuctionTurn = game.rpc("state", params: MatchParam(p_match_id: matchId)).execute().value
            async let lots: [AuctionLot] = client.from("auction_lots")
                .select().eq("match_id", value: matchId).order("seq").execute().value
            async let seats: [AuctionSeat] = client.from("auction_players")
                .select("*, profiles(display_name, avatar_url)")
                .eq("match_id", value: matchId).order("seat").execute().value
            async let bids: [AuctionBid] = client.from("auction_bids")
                .select().eq("match_id", value: matchId).order("bid_seq").execute().value
            async let standings: [MatchStanding] = client.from("match_players")
                .select().eq("match_id", value: matchId).execute().value
            async let hints: [ScoutHint] = client.from("auction_scouting_hints")
                .select().eq("match_id", value: matchId).execute().value
            async let sealedBids: [SealedBid] = client.from("auction_sealed_bids")
                .select().eq("match_id", value: matchId).execute().value
            async let sealedStatuses: [SealedBidStatus] = client.from("auction_sealed_bid_statuses")
                .select().eq("match_id", value: matchId).execute().value
            // The format is immutable once dealt, but it is read with the rest
            // so a screen opened mid-match never waits on a second trip.
            async let formats: [AuctionFormat] = client.from("auction_matches")
                .select("scoring_mode, roster_preset, qb_slots, rb_slots, wr_slots, te_slots, flex_slots, purse, season_from, season_to, token_count")
                .eq("match_id", value: matchId).execute().value
            // `status` and nothing else: the one column of this platform table
            // the contract hands a game, to detect a pause or the end.
            async let matches: [MatchRow] = client.from("matches")
                .select("status").eq("id", value: matchId).execute().value
            // A choice already made, so a screen opened after the host chose
            // still follows everybody else rather than sitting on a finished
            // board.
            async let postGame: [PostGameAction] = client.from("post_game_actions")
                .select("choice, next_match_id").eq("match_id", value: matchId).execute().value

            let turn = try await state
            return try await AuctionSnapshot(
                turn: turn,
                serverNow: turn.serverNow ?? Date(),
                lots: lots,
                seats: seats,
                bids: bids,
                standings: standings,
                // Rows from before roster formats carry nulls and fail to
                // decode; those boards keep the original shape.
                format: (try? await formats)?.first,
                scoutHints: hints,
                sealedBids: sealedBids,
                sealedStatuses: sealedStatuses,
                matchStatus: matches.first?.status ?? .playing,
                postGame: postGame.first
            )
        }
    }

    func placeBid(matchId: UUID, amount: Int) async throws -> AuctionTurn {
        try await wrapped { try await game.rpc("place_bid", params: AmountParam(p_match_id: matchId, p_amount: amount)).execute().value }
    }

    func pass(matchId: UUID) async throws -> AuctionTurn {
        try await wrapped { try await game.rpc("pass_lot", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func expireTurn(matchId: UUID) async throws -> AuctionTurn {
        try await wrapped { try await game.rpc("expire_turn", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func useScoutToken(matchId: UUID) async throws -> String {
        try await wrapped { try await game.rpc("use_scout_token", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func useSealToken(matchId: UUID) async throws -> AuctionTurn {
        try await wrapped { try await game.rpc("use_seal_token", params: MatchParam(p_match_id: matchId)).execute().value }
    }

    func submitSealedBid(matchId: UUID, amount: Int) async throws -> AuctionTurn {
        try await wrapped {
            try await game.rpc("submit_sealed_bid", params: AmountParam(p_match_id: matchId, p_amount: amount)).execute().value
        }
    }

    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction {
        struct Params: Encodable, Sendable { let p_match_id: UUID; let p_choice: String }
        return try await wrapped {
            try await client.rpc(
                "choose_post_game", params: Params(p_match_id: matchId, p_choice: choice.rawValue)
            ).execute().value
        }
    }

    func events(matchId: UUID) -> AsyncStream<AuctionEvent> {
        realtimeEvents(
            client: client,
            topics: ["auction:\(matchId)", "post-game:\(matchId)"],
            subscribed: .subscribed
        ) { channels, yield in
            let match = channels[0]
            let postGame = channels[1]
            let filter: RealtimePostgresFilter = .eq("match_id", value: matchId)

            // The event per table is the contract's, not a preference: the
            // append-only tables are INSERT, everything whose row changes in
            // place is `*`, and `matches` is UPDATE keyed on its own id
            // (`realtime.md`). The two private tables only ever deliver the
            // viewer's own rows — RLS filters before the socket.
            let turns = match.postgresChange(AnyAction.self, table: "auction_matches", filter: filter)
            let lots = match.postgresChange(AnyAction.self, table: "auction_lots", filter: filter)
            let seats = match.postgresChange(AnyAction.self, table: "auction_players", filter: filter)
            let bids = match.postgresChange(InsertAction.self, table: "auction_bids", filter: filter)
            let hints = match.postgresChange(InsertAction.self, table: "auction_scouting_hints", filter: filter)
            let sealedBids = match.postgresChange(InsertAction.self, table: "auction_sealed_bids", filter: filter)
            let statuses = match.postgresChange(AnyAction.self, table: "auction_sealed_bid_statuses", filter: filter)
            let standings = match.postgresChange(AnyAction.self, table: "match_players", filter: filter)
            let matches = match.postgresChange(UpdateAction.self, table: "matches", filter: .eq("id", value: matchId))
            let actions = postGame.postgresChange(InsertAction.self, table: "post_game_actions", filter: filter)

            return [
                { await forwardRows(turns, to: yield, as: AuctionEvent.turn) },
                { await forwardRows(lots, to: yield, as: AuctionEvent.lot) },
                { await forwardRows(seats, to: yield, as: AuctionEvent.seat) },
                { await forwardRows(bids, to: yield, as: AuctionEvent.bid) },
                { await forwardRows(hints, to: yield, as: AuctionEvent.scoutHint) },
                { await forwardRows(sealedBids, to: yield, as: AuctionEvent.sealedBid) },
                { await forwardRows(statuses, to: yield, as: AuctionEvent.sealedStatus) },
                { await forwardRows(standings, to: yield, as: AuctionEvent.standing) },
                { await forwardRows(actions, to: yield, as: AuctionEvent.postGame) },
                { await forwardRows(matches, to: yield) { (row: MatchRow) in .matchStatus(row.status) } },
            ]
        }
    }

    // MARK: - Private

    private struct MatchParam: Encodable, Sendable { let p_match_id: UUID }
    private struct AmountParam: Encodable, Sendable { let p_match_id: UUID; let p_amount: Int }

    /// `public.matches`, narrowed to the one column the contract hands a game.
    private struct MatchRow: Decodable {
        let status: MatchStatus
    }

    /// Surfaces a PostgREST failure as its raised message, so callers depend on
    /// `AuctionServerError` rather than on the SDK's error type.
    private func wrapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw AuctionServerError(message: error.message)
        }
    }
}
