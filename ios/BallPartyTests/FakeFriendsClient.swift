import Foundation
@testable import BallParty

/// Records every call the Friends view models make and lets a test script the
/// answers, so they are exercised without the network.
final class FakeFriendsClient: FriendsClient, @unchecked Sendable {
    struct Offline: Error {}

    var friendRows: [Friend] = []
    var requestRows: [FriendRequest] = []
    var blockedRows: [BlockedUser] = []
    var searchResult: UserSearchResult?
    var sendResult: SendRequestResult = .requested
    var code = "ABC123DEF456"
    var resetCode = "NEWCODE00000"
    var inviteLookup: UserSearchResult?
    var redeemResult: SendRequestResult = .requested
    var profileResult: ProfileLookup?
    var highlightRows: [ProfileKnowerHighlightRow] = []
    var historyRows: [ProfileMatchHistoryRow] = []
    var failing = false
    var failingActions = false

    private(set) var calls: [String] = []

    private func record(_ call: String) { calls.append(call) }

    func friends() async throws -> [Friend] {
        if failing { throw Offline() }
        return friendRows
    }

    func requests() async throws -> [FriendRequest] {
        if failing { throw Offline() }
        return requestRows
    }

    func blocked() async throws -> [BlockedUser] {
        if failing { throw Offline() }
        return blockedRows
    }

    func search(username: String) async throws -> UserSearchResult? {
        record("search:\(username)")
        if failing { throw Offline() }
        return searchResult
    }

    func sendRequest(username: String) async throws -> SendRequestResult {
        record("send:\(username)")
        if failingActions { throw Offline() }
        return sendResult
    }

    func accept(_ userId: UUID) async throws -> Bool { try act("accept", userId) }
    func decline(_ userId: UUID) async throws -> Bool { try act("decline", userId) }
    func cancel(_ userId: UUID) async throws -> Bool { try act("cancel", userId) }
    func remove(_ userId: UUID) async throws -> Bool { try act("remove", userId) }
    func block(_ userId: UUID) async throws -> Bool { try act("block", userId) }
    func unblock(_ userId: UUID) async throws -> Bool { try act("unblock", userId) }

    private func act(_ name: String, _ userId: UUID) throws -> Bool {
        record("\(name):\(userId)")
        if failingActions { throw Offline() }
        return true
    }

    func inviteCode() async throws -> String {
        record("code")
        if failing { throw Offline() }
        return code
    }

    func resetInviteCode() async throws -> String {
        record("reset")
        if failingActions { throw Offline() }
        return resetCode
    }

    func lookupInviteCode(_ code: String) async throws -> UserSearchResult? {
        record("lookup:\(code)")
        if failing { throw Offline() }
        return inviteLookup
    }

    func redeemInviteCode(_ code: String) async throws -> SendRequestResult {
        record("redeem:\(code)")
        if failingActions { throw Offline() }
        return redeemResult
    }

    func profile(username: String) async throws -> ProfileLookup? {
        record("profile:\(username)")
        if failing { throw Offline() }
        return profileResult
    }

    func knowerHighlights(profileId: UUID) async throws -> [ProfileKnowerHighlightRow] {
        record("highlights")
        return highlightRows
    }

    func matchHistory(profileId: UUID) async throws -> [ProfileMatchHistoryRow] {
        record("history")
        return historyRows
    }
}

extension PlayerIdentity {
    static func fixture(_ username: String = "sam_k", name: String = "Sam", id: UUID = UUID()) -> PlayerIdentity {
        PlayerIdentity(profileId: id, username: username, displayName: name, avatarURL: nil)
    }
}
