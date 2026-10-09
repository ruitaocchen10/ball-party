import Foundation
@testable import BallParty
import XCTest

/// `FriendInviteLink.code(from:)` and `FriendInviteViewModel` against
/// `FakeFriendsClient`: the states the web's invite card shows.
@MainActor
final class FriendInviteViewModelTests: XCTestCase {
    private let sam = PlayerIdentity.fixture("sam_k", name: "Sam")

    private func model(_ client: FakeFriendsClient, code: String = "ABC123DEF456") -> FriendInviteViewModel {
        FriendInviteViewModel(client: client, code: code)
    }

    // MARK: link parsing

    func testParsesAnInviteLink() {
        let url = URL(string: "https://ballparty.social/friends/invite/ABC123DEF456")!
        XCTAssertEqual(FriendInviteLink.code(from: url), "ABC123DEF456")
        XCTAssertEqual(FriendInviteLink.code(from: FriendInviteLink.url(code: "ABC123")), "ABC123")
    }

    func testParsesTrailingSlashAndWww() {
        XCTAssertEqual(FriendInviteLink.code(from: URL(string: "https://ballparty.social/friends/invite/AB12/")!), "AB12")
        XCTAssertEqual(FriendInviteLink.code(from: URL(string: "https://www.ballparty.social/friends/invite/AB12?x=1")!), "AB12")
    }

    func testRejectsOtherLinks() {
        for raw in [
            "http://ballparty.social/friends/invite/AB12",
            "https://evil.example/friends/invite/AB12",
            "https://ballparty.social.evil.example/friends/invite/AB12",
            "https://ballparty.social/friends/invite",
            "https://ballparty.social/friends/invite/",
            "https://ballparty.social/friends/invite/AB12/extra",
            "https://ballparty.social/friends/AB12",
            "https://ballparty.social/privacy",
            "https://ballparty.social/friends/invite/AB-12",
            "com.ballparty.app://friends/invite/AB12",
        ] {
            XCTAssertNil(FriendInviteLink.code(from: URL(string: raw)!), raw)
        }
    }

    // MARK: view model

    func testLoadsTheInviter() async {
        let client = FakeFriendsClient()
        client.inviteLookup = UserSearchResult(player: sam, relationship: .none)
        let model = model(client)

        await model.load()

        XCTAssertEqual(model.phase, .loaded(UserSearchResult(player: sam, relationship: .none)))
        XCTAssertNil(model.result)
        XCTAssertEqual(client.calls, ["lookup:ABC123DEF456"])
    }

    func testAnUnknownOrOwnCodeIsUnavailable() async {
        let model = model(FakeFriendsClient())
        await model.load()
        XCTAssertEqual(model.phase, .unavailable)
    }

    func testALookupFailureCanBeRetried() async {
        let client = FakeFriendsClient()
        client.failing = true
        let model = model(client)
        await model.load()
        XCTAssertEqual(model.phase, .failed(FriendInviteViewModel.genericError))

        client.failing = false
        client.inviteLookup = UserSearchResult(player: sam, relationship: .none)
        await model.load()
        XCTAssertEqual(model.phase, .loaded(UserSearchResult(player: sam, relationship: .none)))
    }

    func testExistingRelationshipsSkipTheButton() async {
        for (relationship, expected) in [(FriendRelationship.friends, SendRequestResult.alreadyFriends), (.outgoing, .alreadyRequested)] {
            let client = FakeFriendsClient()
            client.inviteLookup = UserSearchResult(player: sam, relationship: relationship)
            let model = model(client)
            await model.load()
            XCTAssertEqual(model.result, expected)
            await model.addFriend()
            XCTAssertFalse(client.calls.contains { $0.hasPrefix("redeem") })
        }
    }

    func testAddFriendRedeemsOnceAndShowsTheResult() async {
        let client = FakeFriendsClient()
        client.inviteLookup = UserSearchResult(player: sam, relationship: .none)
        client.redeemResult = .accepted
        let model = model(client)
        await model.load()

        await model.addFriend()
        await model.addFriend()

        XCTAssertEqual(model.result, .accepted)
        XCTAssertEqual(client.calls.filter { $0 == "redeem:ABC123DEF456" }.count, 1)
        XCTAssertNil(model.error)
    }

    func testAFailedRedeemKeepsTheButton() async {
        let client = FakeFriendsClient()
        client.inviteLookup = UserSearchResult(player: sam, relationship: .none)
        client.failingActions = true
        let model = model(client)
        await model.load()

        await model.addFriend()

        XCTAssertNil(model.result)
        XCTAssertEqual(model.error, FriendInviteViewModel.genericError)
    }

    func testCopyMatchesTheWeb() {
        XCTAssertEqual(FriendInviteViewModel.copy(for: .requested), "Friend request sent.")
        XCTAssertEqual(FriendInviteViewModel.copy(for: .accepted), "You’re now friends.")
        XCTAssertEqual(FriendInviteViewModel.copy(for: .alreadyRequested), "You’ve already sent a request.")
        XCTAssertEqual(FriendInviteViewModel.copy(for: .alreadyFriends), "You’re already friends.")
        XCTAssertEqual(FriendInviteViewModel.copy(for: .unavailable), "Couldn’t add that player.")
    }
}
