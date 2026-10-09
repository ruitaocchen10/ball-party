import Foundation
import Supabase

/// The Friends feature's network seam: the friendship RPCs (migration 0185)
/// and the profile reads (migration 0186), named as one protocol so tests can
/// substitute a fake. The `Bool` returns say whether anything changed, which
/// makes every action safe to repeat.
protocol FriendsClient: Sendable {
    func friends() async throws -> [Friend]
    func requests() async throws -> [FriendRequest]
    func blocked() async throws -> [BlockedUser]
    /// `search_users_by_username`: an exact match, or `nil`.
    func search(username: String) async throws -> UserSearchResult?
    func sendRequest(username: String) async throws -> SendRequestResult
    func accept(_ userId: UUID) async throws -> Bool
    func decline(_ userId: UUID) async throws -> Bool
    func cancel(_ userId: UUID) async throws -> Bool
    func remove(_ userId: UUID) async throws -> Bool
    func block(_ userId: UUID) async throws -> Bool
    func unblock(_ userId: UUID) async throws -> Bool
    /// `get_my_friend_code`: created on first use.
    func inviteCode() async throws -> String
    /// `reset_friend_code`: old links stop working.
    func resetInviteCode() async throws -> String
    /// `lookup_friend_code`: who owns an invite code, or `nil` when it is
    /// unknown, expired, your own, or its owner blocked you.
    func lookupInviteCode(_ code: String) async throws -> UserSearchResult?
    /// `redeem_friend_code`: sends the request to the code's owner.
    func redeemInviteCode(_ code: String) async throws -> SendRequestResult
    /// `get_profile`: `nil` for no such player (or one who can't be shown).
    func profile(username: String) async throws -> ProfileLookup?
    /// `get_profile_knower_highlights`: empty unless the body may be opened.
    func knowerHighlights(profileId: UUID) async throws -> [ProfileKnowerHighlightRow]
    /// `get_profile_match_history`: empty unless the body may be opened.
    func matchHistory(profileId: UUID) async throws -> [ProfileMatchHistoryRow]
}

struct SupabaseFriendsClient: FriendsClient {
    let client: SupabaseClient

    private struct UsernameParams: Encodable, Sendable { let p_username: String }
    private struct QueryParams: Encodable, Sendable { let p_query: String }
    private struct CodeParams: Encodable, Sendable { let p_code: String }
    private struct UserParams: Encodable, Sendable { let p_user_id: UUID }
    private struct ProfileParams: Encodable, Sendable { let p_profile_id: UUID }

    func friends() async throws -> [Friend] {
        try await client.rpc("list_friends").execute().value
    }

    func requests() async throws -> [FriendRequest] {
        try await client.rpc("list_friend_requests").execute().value
    }

    func blocked() async throws -> [BlockedUser] {
        try await client.rpc("list_blocked_users").execute().value
    }

    func search(username: String) async throws -> UserSearchResult? {
        let rows: [UserSearchResult] = try await client
            .rpc("search_users_by_username", params: QueryParams(p_query: username))
            .execute().value
        return rows.first
    }

    func sendRequest(username: String) async throws -> SendRequestResult {
        let raw: String = try await client
            .rpc("send_friend_request", params: UsernameParams(p_username: username))
            .execute().value
        return SendRequestResult(rawValue: raw)
    }

    func accept(_ userId: UUID) async throws -> Bool { try await act("accept_friend_request", userId) }
    func decline(_ userId: UUID) async throws -> Bool { try await act("decline_friend_request", userId) }
    func cancel(_ userId: UUID) async throws -> Bool { try await act("cancel_friend_request", userId) }
    func remove(_ userId: UUID) async throws -> Bool { try await act("remove_friend", userId) }
    func block(_ userId: UUID) async throws -> Bool { try await act("block_user", userId) }
    func unblock(_ userId: UUID) async throws -> Bool { try await act("unblock_user", userId) }

    private func act(_ function: String, _ userId: UUID) async throws -> Bool {
        try await client.rpc(function, params: UserParams(p_user_id: userId)).execute().value
    }

    func inviteCode() async throws -> String {
        try await client.rpc("get_my_friend_code").execute().value
    }

    func resetInviteCode() async throws -> String {
        try await client.rpc("reset_friend_code").execute().value
    }

    func lookupInviteCode(_ code: String) async throws -> UserSearchResult? {
        let rows: [UserSearchResult] = try await client
            .rpc("lookup_friend_code", params: CodeParams(p_code: code))
            .execute().value
        return rows.first
    }

    func redeemInviteCode(_ code: String) async throws -> SendRequestResult {
        let raw: String = try await client
            .rpc("redeem_friend_code", params: CodeParams(p_code: code))
            .execute().value
        return SendRequestResult(rawValue: raw)
    }

    func profile(username: String) async throws -> ProfileLookup? {
        let rows: [ProfileLookup] = try await client
            .rpc("get_profile", params: UsernameParams(p_username: username))
            .execute().value
        return rows.first
    }

    func knowerHighlights(profileId: UUID) async throws -> [ProfileKnowerHighlightRow] {
        try await client
            .rpc("get_profile_knower_highlights", params: ProfileParams(p_profile_id: profileId))
            .execute().value
    }

    func matchHistory(profileId: UUID) async throws -> [ProfileMatchHistoryRow] {
        try await client
            .rpc("get_profile_match_history", params: ProfileParams(p_profile_id: profileId))
            .execute().value
    }
}
