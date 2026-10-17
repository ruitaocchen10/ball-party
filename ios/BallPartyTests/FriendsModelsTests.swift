import Foundation
@testable import BallParty
import XCTest

/// The friendship RPC rows and the strings they carry, decoded from the JSON
/// PostgREST prints.
final class FriendsModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private let identity = """
    "profile_id":"00000000-0000-0000-0000-000000000001","username":"sam_k","display_name":"Sam",
    "avatar_url":"https://example.com/a.png"
    """

    func testFriendDecodes() throws {
        let friend = try decode(Friend.self, "{\(identity),\"since\":\"2026-09-23T12:00:00.123456+00:00\"}")
        XCTAssertEqual(friend.player.username, "sam_k")
        XCTAssertEqual(friend.player.handle, "@sam_k")
        XCTAssertEqual(friend.player.displayName, "Sam")
        XCTAssertEqual(friend.player.avatarURL, URL(string: "https://example.com/a.png"))
        XCTAssertEqual(friend.id, UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
    }

    func testRequestDirectionsDecode() throws {
        let incoming = try decode(FriendRequest.self, "{\"direction\":\"incoming\",\(identity),\"created_at\":\"2026-09-23T12:00:00+00:00\"}")
        let outgoing = try decode(FriendRequest.self, "{\"direction\":\"outgoing\",\(identity),\"created_at\":\"2026-09-23T12:00:00+00:00\"}")
        XCTAssertEqual(incoming.direction, .incoming)
        XCTAssertEqual(outgoing.direction, .outgoing)
    }

    func testAnUnknownRequestDirectionFailsToDecode() {
        XCTAssertThrowsError(
            try decode(FriendRequest.self, "{\"direction\":\"sideways\",\(identity),\"created_at\":\"2026-09-23T12:00:00+00:00\"}")
        )
    }

    func testBlockedUserDecodes() throws {
        let blocked = try decode(BlockedUser.self, "{\(identity),\"blocked_at\":\"2026-09-23T12:00:00+00:00\"}")
        XCTAssertEqual(blocked.player.username, "sam_k")
    }

    func testSearchResultCarriesTheRelationship() throws {
        let result = try decode(UserSearchResult.self, "{\(identity),\"relationship\":\"incoming\"}")
        XCTAssertEqual(result.relationship, .incoming)
    }

    func testAvatarlessIdentityHasNoURL() throws {
        let result = try decode(UserSearchResult.self, """
        {"profile_id":"00000000-0000-0000-0000-000000000001","username":"sam_k","display_name":"Sam",
         "avatar_url":null,"relationship":"none"}
        """)
        XCTAssertNil(result.player.avatarURL)
    }

    func testProfileLookupDecodes() throws {
        let lookup = try decode(ProfileLookup.self, """
        {\(identity),"is_private":true,"relationship":"friends","can_view":true,
         "member_since":"2026-08-15T12:00:00+00:00"}
        """)
        XCTAssertTrue(lookup.isPrivate)
        XCTAssertTrue(lookup.canView)
        XCTAssertEqual(lookup.relationship, .friends)
        XCTAssertNotNil(lookup.memberSince)
    }

    func testEveryRelationshipStringMapsAndUnknownIsInert() {
        XCTAssertEqual(FriendRelationship(rawValue: "self"), .selfUser)
        XCTAssertEqual(FriendRelationship(rawValue: "none"), .none)
        XCTAssertEqual(FriendRelationship(rawValue: "friends"), .friends)
        XCTAssertEqual(FriendRelationship(rawValue: "outgoing"), .outgoing)
        XCTAssertEqual(FriendRelationship(rawValue: "incoming"), .incoming)
        XCTAssertEqual(FriendRelationship(rawValue: "blocked"), .blocked)
        XCTAssertEqual(FriendRelationship(rawValue: "mystery"), .unknown)
        XCTAssertNil(RelationshipAction.primary(for: .unknown))
    }

    func testSendResultsMapAndUnknownIsUnavailable() {
        XCTAssertEqual(SendRequestResult(rawValue: "requested"), .requested)
        XCTAssertEqual(SendRequestResult(rawValue: "accepted"), .accepted)
        XCTAssertEqual(SendRequestResult(rawValue: "already_requested"), .alreadyRequested)
        XCTAssertEqual(SendRequestResult(rawValue: "already_friends"), .alreadyFriends)
        XCTAssertEqual(SendRequestResult(rawValue: "unavailable"), .unavailable)
        XCTAssertEqual(SendRequestResult(rawValue: "something_new"), .unavailable)
    }

    func testUnavailableStaysNeutral() {
        // It must not hint at why: no "blocked", "no such user" or "not found".
        let message = SendRequestResult.unavailable.message.lowercased()
        XCTAssertFalse(message.contains("block"))
        XCTAssertFalse(message.contains("exist"))
        XCTAssertFalse(message.contains("found"))
    }

    func testPrimaryActionPerRelationship() {
        XCTAssertEqual(RelationshipAction.primary(for: .none)?.action, .send)
        XCTAssertEqual(RelationshipAction.primary(for: .incoming)?.action, .accept)
        XCTAssertEqual(RelationshipAction.primary(for: .outgoing)?.action, .cancel)
        XCTAssertEqual(RelationshipAction.primary(for: .blocked)?.action, .unblock)
        XCTAssertNil(RelationshipAction.primary(for: .friends))
        XCTAssertNil(RelationshipAction.primary(for: .selfUser))
    }

    @MainActor
    func testPrivacyExplanationMatchesTheWeb() {
        XCTAssertEqual(
            PrivacySettingsViewModel.explanation,
            "Only your friends can open your profile. Your name, username and photo still show in search, and you still appear in rankings."
        )
    }

    func testKnowerStatusBandsMatchTheOwnProfile() {
        XCTAssertEqual(KnowerHighlight(totalPoints: 0, percentile: nil).status, "Unranked")
        XCTAssertEqual(KnowerHighlight(totalPoints: 1, percentile: 19).status, "Benchwarmer")
        XCTAssertEqual(KnowerHighlight(totalPoints: 1, percentile: 50).status, "Starter")
        XCTAssertEqual(KnowerHighlight(totalPoints: 1, percentile: 80).status, "Hall of Famer")
    }

    func testInviteLinkUsesTheSiteAndCode() {
        XCTAssertEqual(
            FriendInviteLink.url(code: "ABC123", base: URL(string: "https://example.com")!).absoluteString,
            "https://example.com/friends/invite/ABC123"
        )
        XCTAssertEqual(
            FriendInviteLink.url(code: "ABC123").absoluteString,
            "https://ballparty.social/friends/invite/ABC123"
        )
    }
}
