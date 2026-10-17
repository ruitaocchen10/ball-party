import Foundation
@testable import BallParty
import XCTest

/// `OtherProfileViewModel` against `FakeFriendsClient`: the four profile
/// states and what each fetches.
@MainActor
final class OtherProfileViewModelTests: XCTestCase {
    private let sam = PlayerIdentity.fixture("sam_k", name: "Sam")

    private func viewModel(_ client: FakeFriendsClient) -> OtherProfileViewModel {
        OtherProfileViewModel(client: client, username: "sam_k", now: { Date() })
    }

    func testAPublicProfileLoadsItsBody() async {
        let client = FakeFriendsClient()
        client.profileResult = ProfileLookup(player: sam, isPrivate: false, relationship: .none, canView: true)
        client.highlightRows = [
            ProfileKnowerHighlightRow(windowKey: "lifetime", totalPoints: 120, percentile: 85),
            ProfileKnowerHighlightRow(windowKey: "week", totalPoints: 10, percentile: nil),
        ]
        let model = viewModel(client)

        await model.load()

        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.showsBody)
        XCTAssertFalse(model.isClosed)
        XCTAssertEqual(model.knowerStatus, "Hall of Famer")
        XCTAssertEqual(model.selectedKnowerHighlight.totalPoints, 120)
        XCTAssertTrue(client.calls.contains("highlights"))
        XCTAssertTrue(client.calls.contains("history"))
    }

    func testAPrivateFriendProfileOpens() async {
        let client = FakeFriendsClient()
        client.profileResult = ProfileLookup(player: sam, isPrivate: true, relationship: .friends, canView: true)
        let model = viewModel(client)

        await model.load()

        XCTAssertTrue(model.showsBody)
        XCTAssertTrue(client.calls.contains("highlights"))
    }

    func testAPrivateNonFriendProfileIsHeaderOnlyAndFetchesNoBody() async {
        let client = FakeFriendsClient()
        client.profileResult = ProfileLookup(player: sam, isPrivate: true, relationship: .none, canView: false)
        let model = viewModel(client)

        await model.load()

        XCTAssertEqual(model.phase, .loaded)
        XCTAssertTrue(model.isClosed)
        XCTAssertFalse(model.showsBody)
        XCTAssertEqual(OtherProfileViewModel.privateNote, "Only friends can see this profile.")
        XCTAssertFalse(client.calls.contains("highlights"))
        XCTAssertFalse(client.calls.contains("history"))
        XCTAssertEqual(model.primaryAction?.action, .send)
        XCTAssertEqual(model.primaryAction?.title, "Add friend")
    }

    func testAMissingProfileIsNotFound() async {
        let client = FakeFriendsClient()
        client.profileResult = nil
        let model = viewModel(client)

        await model.load()

        XCTAssertEqual(model.phase, .notFound)
        XCTAssertNil(model.player)
        XCTAssertNil(model.primaryAction)
        XCTAssertFalse(client.calls.contains("highlights"))
    }

    func testAReadErrorIsFailedNotNotFound() async {
        let client = FakeFriendsClient()
        client.failing = true
        let model = viewModel(client)

        await model.load()

        XCTAssertEqual(model.phase, .failed)
    }

    func testHeaderActionsFollowTheRelationship() async {
        let client = FakeFriendsClient()
        let model = viewModel(client)

        func actions(_ relationship: FriendRelationship) async -> (RelationshipAction?, [RelationshipAction]) {
            client.profileResult = ProfileLookup(player: sam, relationship: relationship)
            await model.load()
            return (model.primaryAction?.action, model.secondaryActions.map(\.action))
        }

        var result = await actions(.none)
        XCTAssertEqual(result.0, .send)
        XCTAssertEqual(result.1, [.block])

        result = await actions(.incoming)
        XCTAssertEqual(result.0, .accept)
        XCTAssertEqual(result.1, [.decline])

        result = await actions(.outgoing)
        XCTAssertEqual(result.0, .cancel)

        result = await actions(.friends)
        XCTAssertNil(result.0)
        XCTAssertEqual(result.1, [.remove, .block])

        result = await actions(.blocked)
        XCTAssertEqual(result.0, .unblock)
        XCTAssertEqual(result.1, [])

        result = await actions(.selfUser)
        XCTAssertNil(result.0)
        XCTAssertEqual(result.1, [])
    }

    func testAcceptingReloadsAndCanOpenAPrivateProfile() async {
        let client = FakeFriendsClient()
        client.profileResult = ProfileLookup(player: sam, isPrivate: true, relationship: .incoming, canView: false)
        let model = viewModel(client)
        await model.load()
        XCTAssertTrue(model.isClosed)

        client.profileResult = ProfileLookup(player: sam, isPrivate: true, relationship: .friends, canView: true)
        await model.perform(.accept)

        XCTAssertTrue(client.calls.contains("accept:\(sam.profileId)"))
        XCTAssertTrue(model.showsBody)
        XCTAssertEqual(model.primaryAction == nil, true)
    }

    func testSendingARequestShowsTheServersAnswer() async {
        let client = FakeFriendsClient()
        client.profileResult = ProfileLookup(player: sam, relationship: .none)
        client.sendResult = .unavailable
        let model = viewModel(client)
        await model.load()

        await model.perform(.send)

        XCTAssertEqual(model.notice, SendRequestResult.unavailable.message)
    }

    func testAnActionThatSendsTheRightIdentityUsesTheProfileId() async {
        let client = FakeFriendsClient()
        client.profileResult = ProfileLookup(player: sam, relationship: .friends)
        let model = viewModel(client)
        await model.load()

        await model.perform(.block)

        XCTAssertTrue(client.calls.contains("block:\(sam.profileId)"))
    }
}
