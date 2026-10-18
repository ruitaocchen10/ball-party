import Foundation
@testable import BallParty
import XCTest

/// `InviteBarViewModel` against `FakeFriendsClient`.
@MainActor
final class InviteBarTests: XCTestCase {
    func testLoadsTheInviteLink() async {
        let client = FakeFriendsClient()
        let viewModel = InviteBarViewModel(client: client)
        await viewModel.load()

        XCTAssertEqual(viewModel.inviteURL, FriendInviteLink.url(code: client.code))
    }

    func testReadsTheCodeOnlyOnce() async {
        let client = FakeFriendsClient()
        let viewModel = InviteBarViewModel(client: client)
        await viewModel.load()
        await viewModel.load()

        XCTAssertEqual(client.calls.filter { $0 == "code" }.count, 1)
    }

    func testAFailedReadLeavesNoLinkThenRecovers() async {
        let client = FakeFriendsClient()
        client.failing = true
        let viewModel = InviteBarViewModel(client: client)
        await viewModel.load()
        XCTAssertNil(viewModel.inviteURL)

        client.failing = false
        await viewModel.load()
        XCTAssertEqual(viewModel.inviteURL, FriendInviteLink.url(code: client.code))
    }
}
