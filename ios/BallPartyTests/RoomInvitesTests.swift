import Foundation
@testable import BallParty
import XCTest

@MainActor
final class InviteFriendsViewModelTests: XCTestCase {
    private let lobbyId = UUID()

    private func make(
        _ friends: FakeFriendsClient, _ invites: FakeRoomInvitesClient
    ) -> InviteFriendsViewModel {
        InviteFriendsViewModel(lobbyId: lobbyId, friendsClient: friends, invitesClient: invites)
    }

    func testLoadListsFriends() async {
        let friends = FakeFriendsClient()
        friends.friendRows = [Friend(player: .fixture("amy_a", name: "Amy"))]
        let viewModel = make(friends, FakeRoomInvitesClient())
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.friends.map(\.player.username), ["amy_a"])
    }

    func testAFailedLoadIsReportedAndRetryable() async {
        let friends = FakeFriendsClient()
        friends.failing = true
        let viewModel = make(friends, FakeRoomInvitesClient())
        await viewModel.load()
        guard case .failed = viewModel.phase else { return XCTFail("expected failed") }
        friends.failing = false
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .loaded)
    }

    func testInvitingRecordsTheServersAnswerPerFriend() async {
        let friends = FakeFriendsClient()
        let amy = Friend(player: .fixture("amy_a", name: "Amy"))
        let bo = Friend(player: .fixture("bo_b", name: "Bo"))
        friends.friendRows = [amy, bo]
        let invites = FakeRoomInvitesClient()
        invites.inviteResults = [bo.id: .alreadyInRoom]
        let viewModel = make(friends, invites)
        await viewModel.load()

        await viewModel.invite(amy)
        await viewModel.invite(bo)

        XCTAssertEqual(viewModel.attempts[amy.id], .result(.invited))
        XCTAssertEqual(viewModel.attempts[bo.id], .result(.alreadyInRoom))
        XCTAssertEqual(invites.calls, ["invite:\(amy.id):\(lobbyId)", "invite:\(bo.id):\(lobbyId)"])
    }

    func testASettledResultIsNotAskedAgain() async {
        let amy = Friend(player: .fixture("amy_a"))
        let invites = FakeRoomInvitesClient()
        let viewModel = make(FakeFriendsClient(), invites)
        await viewModel.invite(amy)
        await viewModel.invite(amy)
        XCTAssertEqual(invites.calls.count, 1)
    }

    func testUnavailableMayBeRetried() async {
        let amy = Friend(player: .fixture("amy_a"))
        let invites = FakeRoomInvitesClient()
        invites.defaultResult = .unavailable
        let viewModel = make(FakeFriendsClient(), invites)
        await viewModel.invite(amy)
        invites.defaultResult = .invited
        await viewModel.invite(amy)
        XCTAssertEqual(viewModel.attempts[amy.id], .result(.invited))
        XCTAssertEqual(invites.calls.count, 2)
    }

    func testAnErrorIsShownInTheWebsWordsAndMayBeRetried() async {
        let amy = Friend(player: .fixture("amy_a"))
        let invites = FakeRoomInvitesClient()
        invites.failures["invite"] = LobbyServerError(message: "rate_limited")
        let viewModel = make(FakeFriendsClient(), invites)
        await viewModel.invite(amy)
        XCTAssertEqual(viewModel.attempts[amy.id], .failed("Too many invites. Try again in a bit."))

        invites.failures = [:]
        await viewModel.invite(amy)
        XCTAssertEqual(viewModel.attempts[amy.id], .result(.invited))
    }

    func testErrorCopyMatchesWeb() {
        func copy(_ message: String) -> String { RoomInviteCopy.errorMessage(LobbyServerError(message: message)) }
        XCTAssertEqual(copy("not_a_room_member"), "Only people in the room can invite friends.")
        XCTAssertEqual(copy("invite_not_found"), "That invite is no longer available.")
        XCTAssertEqual(copy("lobby_full"), "That room is already full.")
        XCTAssertEqual(copy("whatever"), "Something went wrong. Try again.")
        XCTAssertEqual(RoomInviteCopy.errorMessage(FakeFriendsClient.Offline()), "Something went wrong. Try again.")
    }

    func testUnknownResultsAreUnavailable() {
        XCTAssertEqual(InviteResult(rawValue: "room_full"), .roomFull)
        XCTAssertEqual(InviteResult(rawValue: "surprise"), .unavailable)
    }
}

@MainActor
final class RoomInvitesInboxViewModelTests: XCTestCase {
    private func make(_ client: FakeRoomInvitesClient) -> RoomInvitesInboxViewModel {
        let viewModel = RoomInvitesInboxViewModel(client: client)
        viewModel.deadInviteDelay = .milliseconds(1)
        return viewModel
    }

    func testLoadListsPendingInvites() async {
        let client = FakeRoomInvitesClient()
        client.inviteRows = [RoomInvite(senderName: "Dana", selectedGame: "higher_or_lower", memberCount: 2)]
        let viewModel = make(client)
        await viewModel.load()
        XCTAssertEqual(viewModel.invites.map(\.senderName), ["Dana"])
        XCTAssertEqual(viewModel.invites[0].summary, "Higher or Lower room · 2 of 4 players")
    }

    func testSummaryWithoutAGameIsJustTheHeadcount() {
        XCTAssertEqual(RoomInvite(senderName: "Dana", memberCount: 3).summary, "3 of 4 players")
        XCTAssertEqual(RoomInvite(senderName: "Dana", selectedGame: "auction", memberCount: 1).summary, "1 of 4 players")
    }

    func testAFailedRefreshKeepsTheList() async {
        let client = FakeRoomInvitesClient()
        client.inviteRows = [RoomInvite(senderName: "Dana")]
        let viewModel = make(client)
        await viewModel.load()
        client.offline = true
        await viewModel.load()
        XCTAssertEqual(viewModel.invites.count, 1)
    }

    func testAcceptReturnsTheRoomAndDropsTheInvite() async {
        let client = FakeRoomInvitesClient()
        let invite = RoomInvite(senderName: "Dana")
        client.inviteRows = [invite]
        let viewModel = make(client)
        await viewModel.load()

        let lobby = await viewModel.accept(invite)

        XCTAssertEqual(lobby?.code, client.acceptedLobby.code)
        XCTAssertTrue(viewModel.invites.isEmpty)
        XCTAssertFalse(viewModel.isBusy)
    }

    func testAFullRoomKeepsTheInviteWithTheServersWords() async {
        let client = FakeRoomInvitesClient()
        let invite = RoomInvite(senderName: "Dana")
        client.inviteRows = [invite]
        client.failures["accept"] = LobbyServerError(message: "lobby_full")
        let viewModel = make(client)
        await viewModel.load()

        let lobby = await viewModel.accept(invite)

        XCTAssertNil(lobby)
        XCTAssertEqual(viewModel.invites.count, 1)
        XCTAssertEqual(viewModel.errors[invite.id], "That room is already full.")
    }

    func testADeadInviteIsShownThenCleared() async {
        let client = FakeRoomInvitesClient()
        let invite = RoomInvite(senderName: "Dana")
        client.inviteRows = [invite]
        client.failures["accept"] = LobbyServerError(message: "invite_not_found")
        let viewModel = make(client)
        await viewModel.load()

        _ = await viewModel.accept(invite)

        XCTAssertEqual(viewModel.errors[invite.id], "That invite is no longer available.")
        XCTAssertTrue(viewModel.invites.isEmpty)
    }

    func testDeclineDropsTheInvite() async {
        let client = FakeRoomInvitesClient()
        let invite = RoomInvite(senderName: "Dana")
        client.inviteRows = [invite]
        let viewModel = make(client)
        await viewModel.load()

        await viewModel.decline(invite)

        XCTAssertTrue(viewModel.invites.isEmpty)
        XCTAssertEqual(client.calls.last, "decline:\(invite.id)")
    }

    func testAFailedDeclineKeepsTheInviteAndSaysWhy() async {
        let client = FakeRoomInvitesClient()
        let invite = RoomInvite(senderName: "Dana")
        client.inviteRows = [invite]
        client.failures["decline"] = LobbyServerError(message: "not_authenticated")
        let viewModel = make(client)
        await viewModel.load()

        await viewModel.decline(invite)

        XCTAssertEqual(viewModel.invites.count, 1)
        XCTAssertEqual(viewModel.errors[invite.id], "Sign in first.")
    }

    func testRowsDecodeFromListRoomInvites() throws {
        let id = UUID(), lobby = UUID()
        let json = """
        [{"invite_id":"\(id)","lobby_id":"\(lobby)","sender_id":"\(UUID())","sender_username":"dana_d",
          "sender_display_name":"Dana","sender_avatar_url":null,"selected_game":null,"member_count":2,
          "created_at":"2026-10-08T12:00:00+00:00"}]
        """
        let rows = try JSONDecoder().decode([RoomInvite].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.inviteId, id)
        XCTAssertEqual(rows.first?.lobbyId, lobby)
        XCTAssertEqual(rows.first?.senderName, "Dana")
        XCTAssertEqual(rows.first?.memberCount, 2)
    }
}
