import Foundation
import Supabase

/// The ranking lists' whole network surface, as the app sees it: one protocol
/// so the screens' view models are tested against a fake. Reads are RPCs that
/// decide in SQL who may see what (`get_ranking_lists`, `get_ranking_list`,
/// `friend_list_updates`); the one write is `save_ranking_list`. The rules
/// themselves (the daily cap, an open prompt, no change) are the server's.
protocol ListsClient: Sendable {
    /// `ranking_list_kinds`, in the order the Lists tab shows them.
    func kinds() async throws -> [ListKind]
    /// `get_ranking_lists` — the newest version of each list a player keeps.
    func lists(username: String) async throws -> [ListSummary]
    /// `get_ranking_list` — one list's whole history, newest first.
    func history(username: String, kind: String) async throws -> [ListVersion]
    /// `ranking_players` — names and faces for player ids. Unknown ids are left out.
    func players(ids: [String]) async throws -> [String: ListPlayer]
    /// The id of the open prompt that feeds a kind of list, if any.
    func openPrompt(kind: String) async throws -> UUID?
    /// `save_ranking_list`. Raises `ListsServerError`.
    func save(kind: String, items: [String], note: String?, publish: Bool) async throws
    /// `friend_list_updates` — the viewer's and their friends' published edits, newest first.
    func updates(limit: Int, before: Date?) async throws -> [ListUpdate]
    /// One update card by its post id, or nil when the viewer may not see it.
    func update(postId: UUID) async throws -> ListUpdate?
    /// The replies under an update card.
    func thread(postId: UUID, viewerId: UUID) async throws -> ListThread
    /// A reply under the card's note (`prompts.post_comment`).
    func reply(postId: UUID, takeId: UUID, body: String) async throws
    /// `prompts.search_players` — the directory, searched by name.
    func searchPlayers(query: String) async throws -> [NFLPlayer]
}

struct SupabaseListsClient: ListsClient {
    let client: SupabaseClient

    private var huddle: SupabaseHuddleClient { SupabaseHuddleClient(client: client) }

    private struct UserKind: Encodable, Sendable { let p_username: String; let p_kind: String }
    private struct User: Encodable, Sendable { let p_username: String }
    private struct Ids: Encodable, Sendable { let p_ids: [String] }
    private struct Save: Encodable, Sendable {
        let p_kind: String
        let p_items: [String]
        /// Left out when empty, as the web does.
        let p_note: String?
        let p_publish: Bool
    }
    private struct Updates: Encodable, Sendable {
        let p_limit: Int
        let p_before: String?
        let p_post_id: UUID?
    }

    func kinds() async throws -> [ListKind] {
        let rows: [ListKind] = try await client.from("ranking_list_kinds").select("id, label, item_kind, sizes").execute().value
        return rows.sorted {
            (ListLogic.kindOrder.firstIndex(of: $0.id) ?? .max) < (ListLogic.kindOrder.firstIndex(of: $1.id) ?? .max)
        }
    }

    func lists(username: String) async throws -> [ListSummary] {
        try await client.rpc("get_ranking_lists", params: User(p_username: username)).execute().value
    }

    func history(username: String, kind: String) async throws -> [ListVersion] {
        try await client.rpc("get_ranking_list", params: UserKind(p_username: username, p_kind: kind)).execute().value
    }

    func players(ids: [String]) async throws -> [String: ListPlayer] {
        let unique = Array(Set(ids))
        guard !unique.isEmpty else { return [:] }
        let rows: [ListPlayer] = try await client.rpc("ranking_players", params: Ids(p_ids: unique)).execute().value
        return Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func openPrompt(kind: String) async throws -> UUID? {
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await client.from("prompt_posts")
            .select("id")
            .eq("ranking_kind", value: kind)
            .eq("status", value: "open")
            .gt("lock_at", value: ISO8601DateFormatter().string(from: Date()))
            .neq("template_kind", value: "ranking_update")
            .order("created_at", ascending: false)
            .limit(1)
            .execute().value
        return rows.first?.id
    }

    func save(kind: String, items: [String], note: String?, publish: Bool) async throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await client.rpc(
                "save_ranking_list",
                params: Save(p_kind: kind, p_items: items, p_note: trimmed?.isEmpty == false ? trimmed : nil, p_publish: publish)
            ).execute()
        } catch let error as PostgrestError {
            throw ListsServerError(message: error.message, detail: error.details)
        }
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func updates(limit: Int, before: Date?) async throws -> [ListUpdate] {
        try await fetchUpdates(Updates(p_limit: limit, p_before: before.map { Self.timestamp($0) }, p_post_id: nil))
    }

    func update(postId: UUID) async throws -> ListUpdate? {
        try await fetchUpdates(Updates(p_limit: 1, p_before: nil, p_post_id: postId)).first
    }

    private func fetchUpdates(_ params: Updates) async throws -> [ListUpdate] {
        try await client.rpc("friend_list_updates", params: params).execute().value
    }

    func thread(postId: UUID, viewerId: UUID) async throws -> ListThread {
        struct Comment: Decodable {
            let id: UUID
            let authorId: UUID
            let body: String
            let createdAt: Date
            let parentCommentId: UUID?
            private enum CodingKeys: String, CodingKey {
                case id, body
                case authorId = "author_id"
                case createdAt = "created_at"
                case parentCommentId = "parent_comment_id"
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try c.decode(UUID.self, forKey: .id)
                authorId = try c.decode(UUID.self, forKey: .authorId)
                body = try c.decode(String.self, forKey: .body)
                createdAt = try c.decodeTimestamp(forKey: .createdAt)
                parentCommentId = try c.decodeIfPresent(UUID.self, forKey: .parentCommentId)
            }
        }
        struct Profile: Decodable {
            let id: UUID
            let displayName: String?
            let avatarUrl: String?
            let username: String?
            private enum CodingKeys: String, CodingKey {
                case id, username
                case displayName = "display_name"
                case avatarUrl = "avatar_url"
            }
        }
        let all: [Comment] = try await client.from("prompt_comments")
            .select("id, author_id, body, created_at, parent_comment_id")
            .eq("post_id", value: postId)
            .order("created_at")
            .execute().value
        let takeId = all.first { $0.parentCommentId == nil }?.id
        let rows = all.filter { $0.parentCommentId != nil }
        guard !rows.isEmpty else { return ListThread(takeId: takeId, replies: []) }
        let authors = Array(Set(rows.map(\.authorId)))
        let profiles: [Profile] = try await client.from("profiles")
            .select("id, display_name, avatar_url, username")
            .in("id", values: authors)
            .execute().value
        let byId = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ListThread(takeId: takeId, replies: rows.map { row in
            let profile = byId[row.authorId]
            return ListReply(
                id: row.id,
                authorName: profile?.displayName ?? "Player",
                authorUsername: profile?.username,
                avatarURL: profile?.avatarUrl.flatMap(URL.init(string:)),
                body: row.body,
                createdAt: row.createdAt,
                isViewer: row.authorId == viewerId
            )
        })
    }

    func reply(postId: UUID, takeId: UUID, body: String) async throws {
        try await huddle.postComment(postId: postId, body: body, parentCommentId: takeId)
    }

    func searchPlayers(query: String) async throws -> [NFLPlayer] {
        try await huddle.searchPlayers(query: query)
    }
}
