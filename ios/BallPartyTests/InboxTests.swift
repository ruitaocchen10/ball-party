import Foundation
@testable import BallParty
import XCTest

final class InboxModelsTests: XCTestCase {
    private func json(_ kind: String, state: String = "pending", extra: String = "") -> String {
        """
        {"item_key":"n:\(UUID())","kind":"\(kind)","state":"\(state)","actor_id":"\(UUID())",
         "actor_username":"ava","actor_display_name":"Ava","actor_avatar_url":null,"ref_id":"\(UUID())",
         "post_id":null,"selected_game":null,"lobby_id":null,"member_count":null,"reply_count":1,
         "is_unread":true,"sort_at":"2026-11-08T10:00:00Z"\(extra)}
        """
    }

    func testDecodesARowAndSkipsKindsThisBuildDoesNotKnow() throws {
        let body = "[\(json("friend_request")),\(json("badge_earned")),\(json("take_reply", state: "active"))]"
        let items = try InboxItem.list(from: Data(body.utf8))
        XCTAssertEqual(items.map(\.kind), [.friendRequest, .takeReply])
    }

    func testCopyMatchesTheWeb() {
        XCTAssertEqual(InboxItem(kind: .friendRequest).title, "Ava sent you a friend request")
        XCTAssertEqual(InboxItem(kind: .friendRequest, state: .accepted).title, "You and Ava are now friends")
        XCTAssertEqual(InboxItem(kind: .takeReply, state: .active).title, "Ava replied to your take")
        XCTAssertEqual(InboxItem(kind: .takeReply, state: .active, replyCount: 3).title, "3 new replies to your take")
        XCTAssertEqual(InboxItem(kind: .roomInvite).title, "Ava invited you to a room")
        XCTAssertEqual(InboxItem(kind: .roomInvite, state: .expired).title, "Ava's room invite expired")
        XCTAssertEqual(InboxItem(kind: .roomInvite, state: .accepted).title, "You joined Ava's room")
        XCTAssertEqual(InboxItem(kind: .roomInvite, state: .declined).title, "You declined Ava's invite")
    }

    func testDetailDescribesALiveInvitesRoom() {
        let live = InboxItem(kind: .roomInvite, selectedGame: "higher_or_lower", memberCount: 2)
        XCTAssertEqual(live.detail, "Higher or Lower · 2 of 4 players")
        XCTAssertNil(InboxItem(kind: .roomInvite, state: .expired).detail)
        XCTAssertNil(InboxItem(kind: .friendRequest).detail)
    }

    func testRoutingAndActions() {
        XCTAssertEqual(InboxItem(kind: .friendRequest).destination, .profile(username: "ava"))
        let post = UUID(), take = UUID()
        XCTAssertEqual(
            InboxItem(kind: .takeReply, state: .active, refId: take, postId: post).destination,
            .take(postId: post, takeId: take)
        )
        XCTAssertNil(InboxItem(kind: .roomInvite).destination)
        XCTAssertTrue(InboxItem(kind: .friendRequest).hasActions)
        XCTAssertFalse(InboxItem(kind: .friendRequest, state: .accepted).hasActions)
        XCTAssertTrue(InboxItem(kind: .roomInvite).hasActions)
        XCTAssertFalse(InboxItem(kind: .roomInvite, state: .expired).hasActions)
        XCTAssertFalse(InboxItem(kind: .takeReply, state: .active).hasActions)
    }
}

@MainActor
final class InboxViewModelTests: XCTestCase {
    private func make(
        _ inbox: FakeInboxClient = FakeInboxClient(), _ friends: FakeFriendsClient = FakeFriendsClient(),
        _ invites: FakeRoomInvitesClient = FakeRoomInvitesClient()
    ) -> InboxViewModel {
        InboxViewModel(client: inbox, friends: friends, invites: invites)
    }

    func testLoadShowsTheServersItemsAndCount() async {
        let inbox = FakeInboxClient()
        inbox.rows = [InboxItem(kind: .friendRequest)]
        inbox.unread = 1
        let viewModel = make(inbox)
        await viewModel.load()
        XCTAssertEqual(viewModel.items.count, 1)
        XCTAssertEqual(viewModel.unreadCount, 1)
    }

    func testAFailedReadKeepsWhatWasListed() async {
        let inbox = FakeInboxClient()
        inbox.rows = [InboxItem(kind: .friendRequest)]
        let viewModel = make(inbox)
        await viewModel.load()
        inbox.offline = true
        inbox.rows = []
        await viewModel.load()
        XCTAssertEqual(viewModel.items.count, 1)
    }

    func testAcceptingAFriendRequestCallsTheServerMarksReadAndRereads() async {
        let inbox = FakeInboxClient()
        let friends = FakeFriendsClient()
        let request = InboxItem(key: "n:abc", kind: .friendRequest)
        inbox.rows = [request]
        let viewModel = make(inbox, friends)
        await viewModel.load()

        let lobby = await viewModel.accept(request)

        XCTAssertNil(lobby)
        XCTAssertEqual(friends.calls, ["accept:\(request.actorId)"])
        XCTAssertTrue(inbox.calls.contains("markRead:n:abc"))
        XCTAssertEqual(inbox.calls.filter { $0 == "items" }.count, 3)
    }

    func testJoiningAnInviteReturnsTheRoom() async {
        let invites = FakeRoomInvitesClient()
        let invite = InboxItem(key: "i:abc", kind: .roomInvite)
        let viewModel = make(FakeInboxClient(), FakeFriendsClient(), invites)

        let lobby = await viewModel.accept(invite)

        XCTAssertEqual(lobby, invites.acceptedLobby)
        XCTAssertEqual(invites.calls, ["accept:\(invite.refId)"])
    }

    func testAFailedJoinShowsTheMessageAndRereadsSoTheServersStateReplacesIt() async {
        let invites = FakeRoomInvitesClient()
        invites.failures["accept"] = LobbyServerError(message: "invite_not_found")
        let inbox = FakeInboxClient()
        let invite = InboxItem(key: "i:abc", kind: .roomInvite)
        inbox.rows = [invite]
        let viewModel = make(inbox, FakeFriendsClient(), invites)
        await viewModel.load()

        let lobby = await viewModel.accept(invite)

        XCTAssertNil(lobby)
        XCTAssertEqual(viewModel.errors[invite.key], "That invite is no longer available.")
        XCTAssertEqual(inbox.calls.filter { $0 == "items" }.count, 2)
    }

    func testDecliningCallsTheRightServerAction() async {
        let friends = FakeFriendsClient()
        let invites = FakeRoomInvitesClient()
        let request = InboxItem(kind: .friendRequest)
        let invite = InboxItem(key: "i:1", kind: .roomInvite)
        let viewModel = make(FakeInboxClient(), friends, invites)

        await viewModel.decline(request)
        await viewModel.decline(invite)

        XCTAssertEqual(friends.calls, ["decline:\(request.actorId)"])
        XCTAssertEqual(invites.calls, ["decline:\(invite.refId)"])
    }

    func testAnExpiredInviteOffersNoActions() async {
        let invites = FakeRoomInvitesClient()
        let expired = InboxItem(kind: .roomInvite, state: .expired)
        let viewModel = make(FakeInboxClient(), FakeFriendsClient(), invites)
        let lobby = await viewModel.accept(expired)
        XCTAssertNil(lobby)
        XCTAssertTrue(invites.calls.isEmpty)
    }

    func testOnlyAnUnreadStoredItemIsMarkedRead() async {
        let inbox = FakeInboxClient()
        let viewModel = make(inbox)
        await viewModel.markRead(InboxItem(key: "i:1", kind: .roomInvite))
        await viewModel.markRead(InboxItem(key: "n:1", kind: .takeReply, state: .active, isUnread: false))
        XCTAssertFalse(inbox.calls.contains { $0.hasPrefix("markRead") })
        await viewModel.markRead(InboxItem(key: "n:2", kind: .takeReply, state: .active))
        XCTAssertTrue(inbox.calls.contains("markRead:n:2"))
    }

    func testAnEventRereadsTheList() async {
        let inbox = FakeInboxClient()
        let viewModel = make(inbox)
        let task = Task { await viewModel.observe(recipientId: UUID()) }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        inbox.emit(.changed)
        try? await Task.sleep(for: .milliseconds(100))
        inbox.finishEvents()
        await task.value
        XCTAssertTrue(inbox.calls.contains("items"))
    }

    func testBadgeLabel() {
        XCTAssertEqual([0, 1, 9, 10].map(NotificationBadge.label(count:)), [nil, "1", "9", "9+"])
    }
}
