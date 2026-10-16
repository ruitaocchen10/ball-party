import Foundation
import Supabase

/// A failed Huddle call, reduced to what a screen can act on: the raised
/// message. Every `prompts.*` RPC raises `raise exception '<message>'`, and —
/// like the web's `promptErrorMessage` — iOS matches on the message string,
/// never the SQL error code.
struct HuddleServerError: Error, Equatable, Sendable {
    let message: String

    /// The raised message as a sentence for the player, mirroring the web's
    /// `PROMPT_MESSAGES` (minus its admin-only entries, which no player-facing
    /// call can raise). An unmapped message surfaces raw rather than being
    /// flattened into a friendly lie — an unrecognised failure is a bug to
    /// notice, not a state to paper over.
    static func describe(_ error: Error) -> String {
        guard let server = error as? HuddleServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        return messages[server.message] ?? server.message
    }

    static let picksNotRevealed = "picks_not_revealed"

    private static let messages: [String: String] = [
        "not_authenticated": "Sign in to answer.",
        "post_not_found": "This prompt no longer exists.",
        "post_locked": "This prompt has locked — no more picks.",
        "incomplete_slot": "Finish every pick before locking in.",
        "invalid_option": "One of those picks isn't valid anymore. Refresh and try again.",
        "option_already_used": "You've already used that team in another pick on this prompt.",
        "parent_not_found": "That take isn't available anymore. Refresh and try again.",
        "nested_reply": "You can only reply to a take, not to another reply.",
        "too_many_predictions": "A response holds at most five predictions.",
        "no_predictions": "Add at least one prediction before you lock in.",
        "already_answered": "You've already locked in your predictions.",
        "invalid_target": "That tag isn't valid for this post anymore. Pick another.",
        "not_bold_predictions": "This post doesn't take predictions.",
        "not_authorized": "Sign in to search for players.",
        "guests_cannot_react": "Create an account to give balls.",
        "take_not_found": "That take isn't available anymore.",
        "cannot_react_to_own_take": "You can't give balls to your own take.",
        "dislike_friends_only": "Only friends can take a ball away.",
        "invalid_reaction": "That isn't a valid reaction.",
    ]
}

/// Huddle's whole network surface as the app sees it — one protocol, one
/// substitution point (issue #59, "Testing Decisions" seam 3). Everything
/// above it (`PromptFeed`, `HuddleViewModel`, the screens) is tested against a
/// fake; nothing above it touches `SupabaseClient`.
///
/// Huddle is pure RPC/fetch. There is no Realtime channel and no lobby or
/// match to be in (`realtime.md`), so this protocol has no `events`.
///
/// Reads come back as flat rows, exactly as the web's `fetchPromptFeed` reads
/// them, and are joined by `PromptFeed` — not here — so the joining rules are
/// exercised by tests instead of sitting untested behind the network.
protocol HuddleClient: Sendable {
    /// One read of every table the feed joins: posts, their slots and options,
    /// every take, the author names, and the viewer's own responses.
    ///
    /// Not read: `prompt_slot_exclusions`. Cross-slot exclusions only exist on
    /// `custom_multi` posts, which the feed leaves out, and the server checks
    /// them at submit anyway (`option_already_used`, on `team_code`).
    func feedRows(viewerId: UUID) async throws -> PromptFeedRows

    /// `prompts.post_aggregates` — how everyone answered, per option. The only
    /// sanctioned way to see other players' picks.
    func aggregates(postId: UUID) async throws -> [PromptAggregateRow]

    /// `prompts.power_ranking_top_five` — the teams most often placed in a
    /// Power Rankings ballot's top five. Team-level aggregates only, revealed
    /// under the same conditions as `aggregates`.
    func powerRankingTopFive(postId: UUID) async throws -> [PromptPowerTopFiveRow]

    /// `prompts.revealed_responses` — every ticket on a post. Raises
    /// `picks_not_revealed` until the post is past `lock_at` or resolved.
    func revealedResponses(postId: UUID) async throws -> [PromptRevealedResponseRow]

    /// `prompts.submit_response` — answers every slot on a post at once, and
    /// posts `comment` as the author's take in the same call. A Weekly Awards
    /// player slot is answered with a directory player id (`players`, by slot)
    /// instead of an option id; the server makes the option.
    func submitResponse(postId: UUID, choices: [UUID: [UUID]], players: [UUID: String], comment: String?) async throws

    /// `prompts.bold_predictions_for_post` — the predictions this viewer may read
    /// (their own before they answer; everyone's once they have or the post has
    /// locked), with the people who wrote them.
    func boldPredictions(postId: UUID) async throws -> BoldPredictionRows

    /// `prompts.bold_prediction_counts` — how many predictions each post has.
    /// Safe before lock: a count is not the text.
    func boldPredictionCounts(postIds: [UUID]) async throws -> [UUID: BoldPredictionCountRow]

    /// `prompts.submit_bold_predictions` — locks in the whole response at once.
    func submitBoldPredictions(postId: UUID, predictions: [BoldDraft]) async throws

    /// The games of the week that begins after `lockAt`: the matchups a
    /// prediction may be tagged with. Empty once the schedule has nothing after.
    func weekGames(after lockAt: Date) async throws -> [NFLScheduleGame]

    /// `prompts.search_players` — the directory, searched by name. A blank query
    /// is answered without a round trip.
    func searchPlayers(query: String) async throws -> [NFLPlayer]

    /// `prompts.players_by_ids` — directory rows for ids already known.
    func players(ids: [String]) async throws -> [NFLPlayer]

    /// `prompts.post_comment` — a reply when `parentCommentId` is given.
    func postComment(postId: UUID, body: String, parentCommentId: UUID?) async throws

    /// `list_friends` — the ids of the viewer's accepted friends, so their
    /// takes can be read first.
    func friendIds() async throws -> Set<UUID>

    /// `react_to_take` — 1 gives the take a ball, -1 takes one away, 0 removes
    /// the viewer's reaction. Returns the take as it now stands.
    func reactToTake(takeId: UUID, value: Int) async throws -> TakeReaction
}

extension HuddleClient {
    func friendIds() async throws -> Set<UUID> { [] }
    func reactToTake(takeId: UUID, value: Int) async throws -> TakeReaction {
        throw HuddleServerError(message: "not_supported")
    }
}

struct SupabaseHuddleClient: HuddleClient {
    let client: SupabaseClient

    private var prompts: PostgrestClient { client.schema("prompts") }

    func feedRows(viewerId: UUID) async throws -> PromptFeedRows {
        try await wrapped {
            let posts: [PromptPostRow] = try await client.from("prompt_posts")
                .select("id, template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, created_at, status, void_reason, is_opinion, cover_team_codes")
                .in("template_kind", values: PromptPost.feedKinds)
                .execute().value
            guard !posts.isEmpty else { return PromptFeedRows() }
            let postIds = posts.map(\.id)

            async let slots: [PromptSlotRow] = client.from("prompt_slots")
                .select("id, post_id, label, shape, pick_count, points, sort_order, correct_option_ids, source_game_id, player_search")
                .in("post_id", values: postIds)
                .execute().value
            // Own rows only: `prompt_responses` is `profile_id = auth.uid()`
            // at the database, so the filter states intent rather than
            // enforcing anything.
            async let responses: [PromptResponseRow] = client.from("prompt_responses")
                .select("post_id, slot_id, chosen_option_ids, points_earned")
                .eq("profile_id", value: viewerId)
                .in("post_id", values: postIds)
                .execute().value
            async let comments: [PromptCommentRow] = client.from("prompt_comments")
                .select("id, post_id, author_id, body, posted_with_pick, parent_comment_id, created_at")
                .in("post_id", values: postIds)
                .execute().value

            let slotRows = try await slots
            let slotIds = slotRows.map(\.id)
            async let options: [PromptOptionRow] = slotIds.isEmpty ? [] : client.from("prompt_slot_options")
                .select("id, slot_id, label, sublabel, team_code, headshot_url, sort_order, margin")
                .in("slot_id", values: slotIds)
                .execute().value

            async let games = schedule(for: slotRows.compactMap(\.sourceGameId))

            let commentRows = try await comments
            let authorIds = Set(posts.map(\.authorId) + commentRows.map(\.authorId))
            let profiles: [PromptProfileRow] = try await client.from("profiles")
                .select("id, display_name, avatar_url, username")
                .in("id", values: Array(authorIds))
                .execute().value

            // Balls are garnish like the schedule: a failed read costs the cards their
            // count, never the player their feed.
            let reactions = await takeReactions(for: commentRows.filter { $0.parentCommentId == nil }.map(\.id))

            return try await PromptFeedRows(
                posts: posts, slots: slotRows, options: options,
                viewerResponses: responses, comments: commentRows, profiles: profiles, reactions: reactions, games: games
            )
        }
    }

    func aggregates(postId: UUID) async throws -> [PromptAggregateRow] {
        try await wrapped {
            try await prompts.rpc("post_aggregates", params: PostParam(p_post_id: postId)).execute().value
        }
    }

    func powerRankingTopFive(postId: UUID) async throws -> [PromptPowerTopFiveRow] {
        try await wrapped {
            try await prompts.rpc("power_ranking_top_five", params: PostParam(p_post_id: postId)).execute().value
        }
    }

    func revealedResponses(postId: UUID) async throws -> [PromptRevealedResponseRow] {
        try await wrapped {
            try await prompts.rpc("revealed_responses", params: PostParam(p_post_id: postId)).execute().value
        }
    }

    func submitResponse(postId: UUID, choices: [UUID: [UUID]], players: [UUID: String], comment: String?) async throws {
        try await wrapped {
            _ = try await prompts.rpc(
                "submit_response",
                params: SubmitResponseParams(postId: postId, choices: choices, players: players, comment: comment)
            ).execute()
        }
    }

    func boldPredictions(postId: UUID) async throws -> BoldPredictionRows {
        try await wrapped {
            let predictions: [BoldPredictionRow] = try await prompts.rpc("bold_predictions_for_post", params: PostParam(p_post_id: postId))
                .execute().value
            let authorIds = Array(Set(predictions.map(\.authorId)))
            guard !authorIds.isEmpty else { return BoldPredictionRows() }
            let profiles: [PromptProfileRow] = try await client.from("profiles")
                .select("id, display_name, avatar_url, username")
                .in("id", values: authorIds)
                .execute().value
            return BoldPredictionRows(predictions: predictions, profiles: profiles)
        }
    }

    func friendIds() async throws -> Set<UUID> {
        struct Row: Decodable, Sendable {
            let profileId: UUID
            private enum CodingKeys: String, CodingKey { case profileId = "profile_id" }
        }
        return try await wrapped {
            let rows: [Row] = try await client.rpc("list_friends").execute().value
            return Set(rows.map(\.profileId))
        }
    }

    func boldPredictionCounts(postIds: [UUID]) async throws -> [UUID: BoldPredictionCountRow] {
        guard !postIds.isEmpty else { return [:] }
        struct Params: Encodable, Sendable { let p_post_ids: [UUID] }
        return try await wrapped {
            let rows: [BoldPredictionCountRow] = try await prompts.rpc("bold_prediction_counts", params: Params(p_post_ids: postIds))
                .execute().value
            return Dictionary(rows.map { ($0.postId, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func submitBoldPredictions(postId: UUID, predictions: [BoldDraft]) async throws {
        struct Item: Encodable, Sendable {
            let body: String
            let target_type: String
            let target_id: String
        }
        struct Params: Encodable, Sendable {
            let p_post_id: UUID
            let p_predictions: [Item]
        }
        try await wrapped {
            _ = try await prompts.rpc(
                "submit_bold_predictions",
                params: Params(
                    p_post_id: postId,
                    p_predictions: predictions.map { Item(body: $0.body, target_type: $0.target.type.rawValue, target_id: $0.target.id) }
                )
            ).execute()
        }
    }

    func weekGames(after lockAt: Date) async throws -> [NFLScheduleGame] {
        struct Week: Decodable, Sendable {
            let season: Int
            let week: Int
        }
        let since = ISO8601DateFormatter().string(from: lockAt)
        return try await wrapped {
            // The week a post is about is the one whose first kickoff follows its
            // lock time, which is how `validate_bold_target` (0171) decides too.
            let first: [Week] = try await client.from("nfl_games")
                .select("season, week")
                .gte("kickoff", value: since)
                .order("kickoff")
                .limit(1)
                .execute().value
            guard let week = first.first else { return [] }
            return try await client.from("nfl_games")
                .select("id, kickoff, away_team, home_team")
                .eq("season", value: week.season)
                .eq("week", value: week.week)
                .order("kickoff")
                .order("id")
                .execute().value
        }
    }

    func searchPlayers(query: String) async throws -> [NFLPlayer] {
        struct Params: Encodable, Sendable {
            let p_query: String
            let p_limit: Int
        }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return try await wrapped {
            try await prompts.rpc("search_players", params: Params(p_query: query, p_limit: 20)).execute().value
        }
    }

    func players(ids: [String]) async throws -> [NFLPlayer] {
        struct Params: Encodable, Sendable { let p_ids: [String] }
        guard !ids.isEmpty else { return [] }
        return try await wrapped {
            try await prompts.rpc("players_by_ids", params: Params(p_ids: ids)).execute().value
        }
    }

    func postComment(postId: UUID, body: String, parentCommentId: UUID?) async throws {
        struct Params: Encodable, Sendable {
            let p_post_id: UUID
            let p_body: String
            let p_parent_comment_id: UUID?
        }
        try await wrapped {
            _ = try await prompts.rpc(
                "post_comment",
                params: Params(p_post_id: postId, p_body: body, p_parent_comment_id: parentCommentId)
            ).execute()
        }
    }

    func reactToTake(takeId: UUID, value: Int) async throws -> TakeReaction {
        struct Params: Encodable, Sendable {
            let p_comment_id: UUID
            let p_value: Int
        }
        struct Row: Decodable, Sendable {
            let netBalls: Int
            let myReaction: Int
            private enum CodingKeys: String, CodingKey {
                case netBalls = "net_balls"
                case myReaction = "my_reaction"
            }
        }
        let rows: [Row] = try await wrapped {
            try await client.rpc("react_to_take", params: Params(p_comment_id: takeId, p_value: value)).execute().value
        }
        guard let row = rows.first else { throw HuddleServerError(message: "take_not_found") }
        // The server answers with the net and the viewer's reaction; what the viewer may
        // do did not change by reacting, so the caller keeps its own `canLike`/`canDislike`.
        return TakeReaction(net: row.netBalls, mine: row.myReaction, canLike: true, canDislike: true)
    }

    // MARK: - Private

    /// `take_reaction_summary` for a page of takes. Never throws.
    func takeReactions(for takeIds: [UUID]) async -> [UUID: TakeReaction] {
        struct Params: Encodable, Sendable { let p_comment_ids: [UUID] }
        guard !takeIds.isEmpty else { return [:] }
        let rows: [TakeReactionRow]? = try? await client.rpc("take_reaction_summary", params: Params(p_comment_ids: takeIds)).execute().value
        return Dictionary(uniqueKeysWithValues: (rows ?? []).map { ($0.commentId, $0.reaction) })
    }

    /// The venue and kickoff of the games the feed's slots point at, from the
    /// same `nfl_games` table the web reads. Deliberately never throws: like
    /// the web, a schedule outage costs the covers their details, not the
    /// player their feed.
    private func schedule(for gameIds: [String]) async -> [NFLGame] {
        let ids = Array(Set(gameIds))
        guard !ids.isEmpty else { return [] }
        let games: [NFLGame]? = try? await client.from("nfl_games")
            .select("id, stadium, kickoff, primetime")
            .in("id", values: ids)
            .execute().value
        return games ?? []
    }

    private struct PostParam: Encodable, Sendable { let p_post_id: UUID }

    /// Surfaces a PostgREST failure as its raised message, so callers depend on
    /// `HuddleServerError` rather than on the SDK's error type.
    private func wrapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw HuddleServerError(message: error.message)
        }
    }
}

/// The arguments of `prompts.submit_response`.
///
/// `p_choices` is `{slot_id: [option_id, ...]}`, and the server finds each
/// slot's answer by `p_choices -> slot_id::text`. Postgres prints a uuid in
/// lowercase and `UUID.uuidString` is uppercase, and a jsonb key match is
/// case-sensitive — so the keys are lowercased here, or every slot reads as
/// unanswered (`incomplete_slot`). The uuid *values* are cast by Postgres and
/// are case-insensitive.
///
/// A Weekly Awards player slot's answer is one directory player id, not an
/// option uuid — `submit_response` (0175) turns it into an option — so its
/// value in `p_choices` is that id as a string.
///
/// A nil `p_comment` is left out of the JSON rather than sent as null, as the
/// web does; the function treats both as "no comment".
struct SubmitResponseParams: Encodable, Sendable {
    let p_post_id: UUID
    let p_choices: [String: [String]]
    let p_comment: String?

    init(postId: UUID, choices: [UUID: [UUID]], players: [UUID: String] = [:], comment: String?) {
        p_post_id = postId
        var byKey = Dictionary(
            choices.map { ($0.key.uuidString.lowercased(), $0.value.map(\.uuidString)) },
            uniquingKeysWith: { first, _ in first }
        )
        for (slot, player) in players { byKey[slot.uuidString.lowercased()] = [player] }
        p_choices = byKey
        p_comment = comment
    }
}
