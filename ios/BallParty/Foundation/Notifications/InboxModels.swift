import Foundation

/// The notification inbox as `list_inbox` reports it (migration 0204). The
/// server decides which items exist and what state each is in; this file only
/// turns a row into the words and the destination the bell shows. The web
/// carries the same copy (`lib/foundation/notifications/inbox.ts`), so change
/// them together.
enum InboxKind: String, Sendable {
    case friendRequest = "friend_request"
    case takeReply = "take_reply"
    case roomInvite = "room_invite"
}

enum InboxState: String, Sendable {
    case pending, accepted, declined, expired, active
}

/// Where tapping an item goes. Room invites have no page of their own: they act in place.
enum InboxDestination: Hashable, Sendable {
    case profile(username: String)
    case take(postId: UUID, takeId: UUID)

    /// The one place that decides where an item goes, shared by an inbox row
    /// and a tapped push so the two can never disagree.
    static func resolve(kind: InboxKind, username: String?, postId: UUID?, refId: UUID?) -> InboxDestination? {
        switch kind {
        case .friendRequest: username.map { .profile(username: $0) }
        case .takeReply:
            if let postId, let refId { .take(postId: postId, takeId: refId) } else { nil }
        case .roomInvite: nil
        }
    }
}

struct InboxItem: Decodable, Equatable, Sendable, Identifiable {
    /// `n:<uuid>` for a stored notification, `i:<uuid>` for a room invite.
    let key: String
    let kind: InboxKind
    let state: InboxState
    let actorId: UUID
    let actorName: String
    let actorUsername: String?
    let actorAvatarURL: URL?
    /// friend_request: the friendship. take_reply: the take. room_invite: the invite.
    let refId: UUID
    let postId: UUID?
    let selectedGame: String?
    let memberCount: Int
    let replyCount: Int
    let isUnread: Bool

    var id: String { key }

    init(
        key: String = "n:\(UUID())", kind: InboxKind, state: InboxState = .pending, actorId: UUID = UUID(),
        actorName: String = "Ava", actorUsername: String? = "ava", actorAvatarURL: URL? = nil,
        refId: UUID = UUID(), postId: UUID? = nil, selectedGame: String? = nil, memberCount: Int = 1,
        replyCount: Int = 1, isUnread: Bool = true
    ) {
        self.key = key
        self.kind = kind
        self.state = state
        self.actorId = actorId
        self.actorName = actorName
        self.actorUsername = actorUsername
        self.actorAvatarURL = actorAvatarURL
        self.refId = refId
        self.postId = postId
        self.selectedGame = selectedGame
        self.memberCount = memberCount
        self.replyCount = replyCount
        self.isUnread = isUnread
    }

    private enum CodingKeys: String, CodingKey {
        case key = "item_key", kind, state
        case actorId = "actor_id", actorUsername = "actor_username"
        case actorDisplayName = "actor_display_name", actorAvatarURL = "actor_avatar_url"
        case refId = "ref_id", postId = "post_id", selectedGame = "selected_game"
        case memberCount = "member_count", replyCount = "reply_count", isUnread = "is_unread"
    }

    /// Throws on a kind or state this build doesn't know; `InboxItem.list`
    /// drops those so an older app ignores a newer server's items.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let kind = InboxKind(rawValue: try c.decode(String.self, forKey: .kind)),
              let state = InboxState(rawValue: try c.decode(String.self, forKey: .state))
        else { throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "unknown inbox kind or state") }
        self.kind = kind
        self.state = state
        key = try c.decode(String.self, forKey: .key)
        actorId = try c.decode(UUID.self, forKey: .actorId)
        actorUsername = try c.decodeIfPresent(String.self, forKey: .actorUsername)
        let display = try c.decodeIfPresent(String.self, forKey: .actorDisplayName)
        actorName = display ?? actorUsername ?? "A player"
        actorAvatarURL = try c.decodeIfPresent(String.self, forKey: .actorAvatarURL).flatMap(URL.init(string:))
        refId = try c.decode(UUID.self, forKey: .refId)
        postId = try c.decodeIfPresent(UUID.self, forKey: .postId)
        selectedGame = try c.decodeIfPresent(String.self, forKey: .selectedGame)
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 1
        replyCount = try c.decode(Int.self, forKey: .replyCount)
        isUnread = try c.decode(Bool.self, forKey: .isUnread)
    }

    /// Decodes a `list_inbox` response, skipping rows this build doesn't understand.
    static func list(from data: Data) throws -> [InboxItem] {
        struct Lossy: Decodable {
            let item: InboxItem?
            init(from decoder: Decoder) throws { item = try? InboxItem(from: decoder) }
        }
        return try JSONDecoder().decode([Lossy].self, from: data).compactMap(\.item)
    }

    // MARK: Copy (same words as the web's `inboxTitle`, `inboxDetail`)

    var title: String {
        switch kind {
        case .friendRequest:
            return state == .accepted ? "You and \(actorName) are now friends" : "\(actorName) sent you a friend request"
        case .takeReply:
            return replyCount > 1 ? "\(replyCount) new replies to your take" : "\(actorName) replied to your take"
        case .roomInvite:
            switch state {
            case .accepted: return "You joined \(actorName)'s room"
            case .declined: return "You declined \(actorName)'s invite"
            case .expired: return "\(actorName)'s room invite expired"
            default: return "\(actorName) invited you to a room"
            }
        }
    }

    var detail: String? {
        if kind == .takeReply, replyCount > 1 { return "Latest from \(actorName)" }
        if kind == .roomInvite, state == .pending {
            let players = "\(memberCount) of 4 players"
            guard let game = selectedGame.flatMap(MatchGame.init(rawValue:)) else { return players }
            return "\(game.label) · \(players)"
        }
        return nil
    }

    var destination: InboxDestination? {
        InboxDestination.resolve(kind: kind, username: actorUsername, postId: postId, refId: refId)
    }

    /// Whether the item offers Accept / Decline (Join / Decline for a room).
    var hasActions: Bool { (kind == .friendRequest || kind == .roomInvite) && state == .pending }

    /// Dimmed: it can no longer be acted on and never will be.
    var isDead: Bool { state == .expired || state == .declined }

    /// Only stored notifications have a read state; room invites are unread while pending.
    var isStored: Bool { key.hasPrefix("n:") }
}
