import Foundation
import Supabase

/// What `invite_friend_to_room` answers (migration 0189). Anything unknown is
/// `unavailable`, the same fallback the web's `parseInviteResult` uses.
enum InviteResult: Equatable, Sendable {
    case invited, alreadyInvited, alreadyInRoom, roomFull, unavailable

    init(rawValue: String) {
        switch rawValue {
        case "invited": self = .invited
        case "already_invited": self = .alreadyInvited
        case "already_in_room": self = .alreadyInRoom
        case "room_full": self = .roomFull
        default: self = .unavailable
        }
    }

    /// Short badge text, matching the web's `INVITE_RESULT_COPY`.
    var label: String {
        switch self {
        case .invited: "Invited"
        case .alreadyInvited: "Already invited"
        case .alreadyInRoom: "In the room"
        case .roomFull: "Room full"
        case .unavailable: "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .invited: "Invite sent. They'll see it on their Party page."
        case .alreadyInvited: "They already have an invite to this room."
        case .alreadyInRoom: "They're already in this room."
        case .roomFull: "This room has no open spots."
        case .unavailable: "That friend can't be invited right now."
        }
    }

    /// Results after which asking again would only repeat the answer.
    var isSettled: Bool { self != .unavailable }
}

/// A row of `list_room_invites`: a friend asking you into their room.
struct RoomInvite: Decodable, Equatable, Sendable, Identifiable {
    let inviteId: UUID
    let lobbyId: UUID
    let senderName: String
    let senderUsername: String
    let senderAvatarURL: URL?
    let selectedGame: String?
    let memberCount: Int

    var id: UUID { inviteId }

    /// "Higher or Lower room · 2 of 4 players", or just the headcount before a
    /// game is picked (the web's `inviteRoomSummary`).
    var summary: String {
        let players = "\(memberCount) of 4 players"
        guard let game = selectedGame.flatMap(MatchGame.init(rawValue:)) else { return players }
        return "\(game.label) room · \(players)"
    }

    init(
        inviteId: UUID = UUID(), lobbyId: UUID = UUID(), senderName: String, senderUsername: String = "sender",
        senderAvatarURL: URL? = nil, selectedGame: String? = nil, memberCount: Int = 1
    ) {
        self.inviteId = inviteId
        self.lobbyId = lobbyId
        self.senderName = senderName
        self.senderUsername = senderUsername
        self.senderAvatarURL = senderAvatarURL
        self.selectedGame = selectedGame
        self.memberCount = memberCount
    }

    private enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id", lobbyId = "lobby_id"
        case senderName = "sender_display_name", senderUsername = "sender_username"
        case senderAvatarURL = "sender_avatar_url"
        case selectedGame = "selected_game", memberCount = "member_count"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inviteId = try c.decode(UUID.self, forKey: .inviteId)
        lobbyId = try c.decode(UUID.self, forKey: .lobbyId)
        senderName = try c.decode(String.self, forKey: .senderName)
        senderUsername = try c.decode(String.self, forKey: .senderUsername)
        senderAvatarURL = try c.decodeIfPresent(String.self, forKey: .senderAvatarURL).flatMap(URL.init(string:))
        selectedGame = try c.decodeIfPresent(String.self, forKey: .selectedGame)
        memberCount = try c.decode(Int.self, forKey: .memberCount)
    }
}

/// Copy for a failed invite call. Same vocabulary as the web's
/// `inviteErrorMessage`: the lobby messages plus the invite-specific ones,
/// with a generic line for anything else.
enum RoomInviteCopy {
    static func errorMessage(_ error: Error) -> String {
        let generic = "Something went wrong. Try again."
        guard let server = error as? LobbyServerError else { return generic }
        return extra[server.message] ?? LobbyViewModel.messages[server.message] ?? generic
    }

    private static let extra: [String: String] = [
        "not_a_room_member": "Only people in the room can invite friends.",
        "invite_not_found": "That invite is no longer available.",
        "guests_cannot_have_friends": "Friends need a real account.",
        "rate_limited": "Too many invites. Try again in a bit.",
    ]
}

/// Room invites' network seam (migration 0189). Every rule (who may be
/// invited, the 24-hour life, capacity) is the server's.
protocol RoomInvitesClient: Sendable {
    /// `invite_friend_to_room`.
    func invite(friendId: UUID, to lobbyId: UUID) async throws -> InviteResult
    /// `list_room_invites`: the caller's live invites, newest first.
    func invites() async throws -> [RoomInvite]
    /// `accept_room_invite`: joins the room (via `join_lobby`) and returns it.
    func accept(_ inviteId: UUID) async throws -> Lobby
    /// `decline_room_invite`.
    func decline(_ inviteId: UUID) async throws
}

struct SupabaseRoomInvitesClient: RoomInvitesClient {
    let client: SupabaseClient

    private struct InviteParams: Encodable, Sendable { let p_lobby_id: UUID; let p_friend_id: UUID }
    private struct IdParams: Encodable, Sendable { let p_invite_id: UUID }

    func invite(friendId: UUID, to lobbyId: UUID) async throws -> InviteResult {
        let raw: String = try await wrapped {
            try await client.rpc("invite_friend_to_room", params: InviteParams(p_lobby_id: lobbyId, p_friend_id: friendId))
                .execute().value
        }
        return InviteResult(rawValue: raw)
    }

    func invites() async throws -> [RoomInvite] {
        try await wrapped { try await client.rpc("list_room_invites").execute().value }
    }

    func accept(_ inviteId: UUID) async throws -> Lobby {
        try await wrapped {
            try await client.rpc("accept_room_invite", params: IdParams(p_invite_id: inviteId)).execute().value
        }
    }

    func decline(_ inviteId: UUID) async throws {
        try await wrapped {
            _ = try await client.rpc("decline_room_invite", params: IdParams(p_invite_id: inviteId)).execute()
        }
    }

    private func wrapped<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as PostgrestError {
            throw LobbyServerError(message: error.message)
        }
    }
}
