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

    /// `prompts.revealed_responses` — every ticket on a post. Raises
    /// `picks_not_revealed` until the post is past `lock_at` or resolved.
    func revealedResponses(postId: UUID) async throws -> [PromptRevealedResponseRow]

    /// `prompts.submit_response` — answers every slot on a post at once, and
    /// posts `comment` as the author's take in the same call.
    func submitResponse(postId: UUID, choices: [UUID: [UUID]], comment: String?) async throws

    /// `prompts.post_comment` — a reply when `parentCommentId` is given.
    func postComment(postId: UUID, body: String, parentCommentId: UUID?) async throws
}

struct SupabaseHuddleClient: HuddleClient {
    let client: SupabaseClient

    private var prompts: PostgrestClient { client.schema("prompts") }

    func feedRows(viewerId: UUID) async throws -> PromptFeedRows {
        try await wrapped {
            let posts: [PromptPostRow] = try await client.from("prompt_posts")
                .select("id, template_kind, template_name, author_id, caption, prompt_text, resolution_criteria, lock_at, created_at, status, void_reason, is_opinion")
                .in("template_kind", values: PromptPost.picksKinds)
                .execute().value
            guard !posts.isEmpty else { return PromptFeedRows() }
            let postIds = posts.map(\.id)

            async let slots: [PromptSlotRow] = client.from("prompt_slots")
                .select("id, post_id, label, shape, pick_count, points, sort_order, correct_option_ids, source_game_id")
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
                .select("id, slot_id, label, sublabel, team_code, headshot_url, sort_order")
                .in("slot_id", values: slotIds)
                .execute().value

            async let games = schedule(for: slotRows.compactMap(\.sourceGameId))

            let commentRows = try await comments
            let authorIds = Set(posts.map(\.authorId) + commentRows.map(\.authorId))
            let profiles: [PromptProfileRow] = try await client.from("profiles")
                .select("id, display_name")
                .in("id", values: Array(authorIds))
                .execute().value

            return try await PromptFeedRows(
                posts: posts, slots: slotRows, options: options,
                viewerResponses: responses, comments: commentRows, profiles: profiles, games: games
            )
        }
    }

    func aggregates(postId: UUID) async throws -> [PromptAggregateRow] {
        try await wrapped {
            try await prompts.rpc("post_aggregates", params: PostParam(p_post_id: postId)).execute().value
        }
    }

    func revealedResponses(postId: UUID) async throws -> [PromptRevealedResponseRow] {
        try await wrapped {
            try await prompts.rpc("revealed_responses", params: PostParam(p_post_id: postId)).execute().value
        }
    }

    func submitResponse(postId: UUID, choices: [UUID: [UUID]], comment: String?) async throws {
        try await wrapped {
            _ = try await prompts.rpc(
                "submit_response",
                params: SubmitResponseParams(postId: postId, choices: choices, comment: comment)
            ).execute()
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

    // MARK: - Private

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
/// A nil `p_comment` is left out of the JSON rather than sent as null, as the
/// web does; the function treats both as "no comment".
struct SubmitResponseParams: Encodable, Sendable {
    let p_post_id: UUID
    let p_choices: [String: [UUID]]
    let p_comment: String?

    init(postId: UUID, choices: [UUID: [UUID]], comment: String?) {
        p_post_id = postId
        p_choices = Dictionary(
            choices.map { ($0.key.uuidString.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        p_comment = comment
    }
}
