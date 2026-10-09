import Foundation
@testable import BallParty
import XCTest

/// `FriendsViewModel` against `FakeFriendsClient`: what the Friends screen
/// shows and what each action asks of the server.
@MainActor
final class FriendsViewModelTests: XCTestCase {
    private func request(_ direction: FriendRequest.Direction, _ player: PlayerIdentity) -> FriendRequest {
        FriendRequest(direction: direction, player: player)
    }

    func testLoadFillsTheListsAndSplitsRequestsByDirection() async {
        let client = FakeFriendsClient()
        let a = PlayerIdentity.fixture("amy_a", name: "Amy")
        let b = PlayerIdentity.fixture("bo_b", name: "Bo")
        let c = PlayerIdentity.fixture("cy_c", name: "Cy")
        client.friendRows = [Friend(player: a)]
        client.requestRows = [request(.incoming, b), request(.outgoing, c)]
        client.blockedRows = [BlockedUser(player: c)]
        let viewModel = FriendsViewModel(client: client)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.friends.map(\.player.username), ["amy_a"])
        XCTAssertEqual(viewModel.incoming.map(\.player.username), ["bo_b"])
        XCTAssertEqual(viewModel.outgoing.map(\.player.username), ["cy_c"])
        XCTAssertEqual(viewModel.blocked.count, 1)
    }

    func testAFailedFirstLoadIsFailedAndAFailedRefreshKeepsTheLists() async {
        let client = FakeFriendsClient()
        client.friendRows = [Friend(player: .fixture())]
        let viewModel = FriendsViewModel(client: client)
        client.failing = true
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .failed)

        client.failing = false
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .loaded)

        client.failing = true
        await viewModel.load()
        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.friends.count, 1)
    }

    func testAcceptCallsTheServerThenReloads() async {
        let client = FakeFriendsClient()
        let bo = PlayerIdentity.fixture("bo_b")
        client.requestRows = [request(.incoming, bo)]
        let viewModel = FriendsViewModel(client: client)
        await viewModel.load()

        client.requestRows = []
        client.friendRows = [Friend(player: bo)]
        await viewModel.perform(.accept, on: bo)

        XCTAssertEqual(client.calls, ["accept:\(bo.profileId)"])
        XCTAssertTrue(viewModel.incoming.isEmpty)
        XCTAssertEqual(viewModel.friends.map(\.player.username), ["bo_b"])
    }

    func testEachActionMapsToItsRpc() async {
        let client = FakeFriendsClient()
        let bo = PlayerIdentity.fixture("bo_b")
        let viewModel = FriendsViewModel(client: client)

        for action in [RelationshipAction.decline, .cancel, .remove, .block, .unblock] {
            await viewModel.perform(action, on: bo)
        }

        let id = bo.profileId
        XCTAssertEqual(client.calls, ["decline:\(id)", "cancel:\(id)", "remove:\(id)", "block:\(id)", "unblock:\(id)"])
    }

    func testAFailedActionShowsAGenericNotice() async {
        let client = FakeFriendsClient()
        client.failingActions = true
        let viewModel = FriendsViewModel(client: client)

        await viewModel.perform(.remove, on: .fixture())

        XCTAssertEqual(viewModel.notice, FriendsViewModel.genericFailure)
    }

    func testSearchRejectsAMalformedUsernameWithoutCallingTheServer() async {
        let client = FakeFriendsClient()
        let viewModel = FriendsViewModel(client: client)
        viewModel.query = "no"

        await viewModel.search()

        guard case .invalid = viewModel.searchPhase else { return XCTFail("expected invalid") }
        XCTAssertTrue(client.calls.isEmpty)
    }

    func testSearchTrimsAndDropsAtSignBeforeAsking() async {
        let client = FakeFriendsClient()
        let viewModel = FriendsViewModel(client: client)
        viewModel.query = "  @Sam_K "

        await viewModel.search()

        XCTAssertEqual(client.calls, ["search:Sam_K"])
        XCTAssertEqual(viewModel.searchPhase, .notFound)
    }

    func testSearchFindsAPlayerAndSendingARequestRefreshesTheirRelationship() async {
        let client = FakeFriendsClient()
        let sam = PlayerIdentity.fixture("sam_k")
        client.searchResult = UserSearchResult(player: sam, relationship: .none)
        let viewModel = FriendsViewModel(client: client)
        viewModel.query = "sam_k"
        await viewModel.search()
        XCTAssertEqual(viewModel.searchPhase, .found(UserSearchResult(player: sam, relationship: .none)))

        client.searchResult = UserSearchResult(player: sam, relationship: .outgoing)
        await viewModel.perform(.send, on: sam)

        XCTAssertEqual(viewModel.notice, "Friend request sent.")
        XCTAssertEqual(viewModel.searchPhase, .found(UserSearchResult(player: sam, relationship: .outgoing)))
    }

    func testAnUnavailableSendIsShownNeutrally() async {
        let client = FakeFriendsClient()
        client.sendResult = .unavailable
        let viewModel = FriendsViewModel(client: client)

        await viewModel.perform(.send, on: .fixture())

        XCTAssertEqual(viewModel.notice, SendRequestResult.unavailable.message)
    }

    func testASearchErrorIsFailedNotNotFound() async {
        let client = FakeFriendsClient()
        client.failing = true
        let viewModel = FriendsViewModel(client: client)
        viewModel.query = "sam_k"

        await viewModel.search()

        XCTAssertEqual(viewModel.searchPhase, .failed)
    }

    func testTheInviteURLIsBuiltFromTheCodeAndFetchedOnce() async {
        let client = FakeFriendsClient()
        let viewModel = FriendsViewModel(client: client)
        XCTAssertNil(viewModel.inviteURL)

        await viewModel.loadInviteCode()
        await viewModel.loadInviteCode()

        XCTAssertEqual(viewModel.inviteURL?.absoluteString, "https://ballparty.social/friends/invite/ABC123DEF456")
        XCTAssertEqual(client.calls.filter { $0 == "code" }.count, 1)
    }

    func testResettingTheInviteCodeSwapsTheLink() async {
        let client = FakeFriendsClient()
        let viewModel = FriendsViewModel(client: client)
        await viewModel.loadInviteCode()

        await viewModel.resetInviteCode()

        XCTAssertEqual(viewModel.inviteCode, "NEWCODE00000")
        XCTAssertEqual(viewModel.notice, "Your old invite link no longer works.")
    }

    func testAFailedResetKeepsTheOldCode() async {
        let client = FakeFriendsClient()
        let viewModel = FriendsViewModel(client: client)
        await viewModel.loadInviteCode()
        client.failingActions = true

        await viewModel.resetInviteCode()

        XCTAssertEqual(viewModel.inviteCode, "ABC123DEF456")
        XCTAssertEqual(viewModel.notice, FriendsViewModel.genericFailure)
    }
}
