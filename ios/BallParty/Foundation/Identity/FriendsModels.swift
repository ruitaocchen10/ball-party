import Foundation

// The Friends feature's types: the rows of the friendship RPCs (migrations
// 0185-0186) and the small enums that name their string results. Every rule
// (who can see whom, what a request does, rate limits) lives in SQL; nothing
// here decides it, it only names what comes back.

/// How the caller relates to another player, from the caller's side. The
/// `relationship` column of `search_users_by_username`, `lookup_friend_code`
/// and `get_profile`.
enum FriendRelationship: Equatable, Sendable {
    case selfUser, none, friends, outgoing, incoming, blocked
    /// A value this build doesn't know: no action is offered for it.
    case unknown

    init(rawValue: String) {
        switch rawValue {
        case "self": self = .selfUser
        case "none": self = .none
        case "friends": self = .friends
        case "outgoing": self = .outgoing
        case "incoming": self = .incoming
        case "blocked": self = .blocked
        default: self = .unknown
        }
    }
}

/// What `send_friend_request` (and `redeem_friend_code`) answers.
enum SendRequestResult: Equatable, Sendable {
    case requested, accepted, alreadyRequested, alreadyFriends
    /// No such player, or one who can't be asked. Deliberately one answer for
    /// every reason, so it is no oracle for who exists or who blocked whom.
    case unavailable

    init(rawValue: String) {
        switch rawValue {
        case "requested": self = .requested
        case "accepted": self = .accepted
        case "already_requested": self = .alreadyRequested
        case "already_friends": self = .alreadyFriends
        default: self = .unavailable
        }
    }

    /// The line shown after sending. `unavailable` stays neutral on purpose.
    var message: String {
        switch self {
        case .requested: "Friend request sent."
        case .accepted: "You’re now friends."
        case .alreadyRequested: "You already sent a request."
        case .alreadyFriends: "You’re already friends."
        case .unavailable: "That request can’t be sent."
        }
    }
}

/// `profile_id`, `username`, `display_name`, `avatar_url`: the four columns
/// every friends RPC leads with.
struct PlayerIdentity: Equatable, Sendable {
    let profileId: UUID
    let username: String
    let displayName: String
    let avatarURL: URL?

    var handle: String { "@\(username)" }
}

private enum IdentityKeys: String, CodingKey {
    case profileId = "profile_id", username, displayName = "display_name", avatarURL = "avatar_url"
}

private func decodeIdentity(from decoder: Decoder) throws -> PlayerIdentity {
    let c = try decoder.container(keyedBy: IdentityKeys.self)
    return PlayerIdentity(
        profileId: try c.decode(UUID.self, forKey: .profileId),
        username: try c.decode(String.self, forKey: .username),
        displayName: try c.decode(String.self, forKey: .displayName),
        avatarURL: try c.decodeIfPresent(String.self, forKey: .avatarURL).flatMap(URL.init(string:))
    )
}

/// A row of `list_friends`.
struct Friend: Decodable, Equatable, Sendable, Identifiable {
    let player: PlayerIdentity
    let since: Date

    var id: UUID { player.profileId }

    private enum CodingKeys: String, CodingKey { case since }

    init(player: PlayerIdentity, since: Date = Date(timeIntervalSince1970: 0)) {
        self.player = player
        self.since = since
    }

    init(from decoder: Decoder) throws {
        player = try decodeIdentity(from: decoder)
        since = try decoder.container(keyedBy: CodingKeys.self).decodeTimestamp(forKey: .since)
    }
}

/// A row of `list_friend_requests`.
struct FriendRequest: Decodable, Equatable, Sendable, Identifiable {
    enum Direction: String, Equatable, Sendable {
        /// They asked you.
        case incoming
        /// You asked them.
        case outgoing
    }

    let direction: Direction
    let player: PlayerIdentity
    let createdAt: Date

    var id: UUID { player.profileId }

    private enum CodingKeys: String, CodingKey { case direction, createdAt = "created_at" }

    init(direction: Direction, player: PlayerIdentity, createdAt: Date = Date(timeIntervalSince1970: 0)) {
        self.direction = direction
        self.player = player
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        player = try decodeIdentity(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decode(String.self, forKey: .direction)
        guard let direction = Direction(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .direction, in: c, debugDescription: "Unknown direction \(raw)")
        }
        self.direction = direction
        createdAt = try c.decodeTimestamp(forKey: .createdAt)
    }
}

/// A row of `list_blocked_users`.
struct BlockedUser: Decodable, Equatable, Sendable, Identifiable {
    let player: PlayerIdentity
    let blockedAt: Date

    var id: UUID { player.profileId }

    private enum CodingKeys: String, CodingKey { case blockedAt = "blocked_at" }

    init(player: PlayerIdentity, blockedAt: Date = Date(timeIntervalSince1970: 0)) {
        self.player = player
        self.blockedAt = blockedAt
    }

    init(from decoder: Decoder) throws {
        player = try decodeIdentity(from: decoder)
        blockedAt = try decoder.container(keyedBy: CodingKeys.self).decodeTimestamp(forKey: .blockedAt)
    }
}

/// A row of `search_users_by_username` or `lookup_friend_code`.
struct UserSearchResult: Decodable, Equatable, Sendable, Identifiable {
    let player: PlayerIdentity
    let relationship: FriendRelationship

    var id: UUID { player.profileId }

    private enum CodingKeys: String, CodingKey { case relationship }

    init(player: PlayerIdentity, relationship: FriendRelationship) {
        self.player = player
        self.relationship = relationship
    }

    init(from decoder: Decoder) throws {
        player = try decodeIdentity(from: decoder)
        relationship = FriendRelationship(
            rawValue: try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .relationship)
        )
    }
}

/// The one row of `get_profile`: a player's header and whether the body below
/// it may be opened.
struct ProfileLookup: Decodable, Equatable, Sendable {
    let player: PlayerIdentity
    let isPrivate: Bool
    let relationship: FriendRelationship
    let canView: Bool
    let memberSince: Date?

    private enum CodingKeys: String, CodingKey {
        case isPrivate = "is_private", relationship, canView = "can_view", memberSince = "member_since"
    }

    init(
        player: PlayerIdentity, isPrivate: Bool = false, relationship: FriendRelationship = .none,
        canView: Bool = true, memberSince: Date? = nil
    ) {
        self.player = player
        self.isPrivate = isPrivate
        self.relationship = relationship
        self.canView = canView
        self.memberSince = memberSince
    }

    init(from decoder: Decoder) throws {
        player = try decodeIdentity(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isPrivate = try c.decode(Bool.self, forKey: .isPrivate)
        relationship = FriendRelationship(rawValue: try c.decode(String.self, forKey: .relationship))
        canView = try c.decode(Bool.self, forKey: .canView)
        memberSince = try c.decodeTimestampIfPresent(forKey: .memberSince)
    }
}

/// The invite link a player shares. The path must match the web's invite
/// route; the clients build it, SQL only owns the code.
enum FriendInviteLink {
    static let pathPrefix = "friends/invite"

    static func url(code: String, base: URL = SiteLinks.home) -> URL {
        base.appendingPathComponent(pathPrefix).appendingPathComponent(code)
    }
}
