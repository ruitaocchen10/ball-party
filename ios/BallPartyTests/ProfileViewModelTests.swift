import Foundation
@testable import BallParty
import XCTest

/// `ProfileViewModel` against a stub `ProfileClient` — what the Profile tab
/// shows before, during and after its one read.
@MainActor
final class ProfileViewModelTests: XCTestCase {
    private struct StubClient: ProfileClient {
        var result: Result<ProfileSummary?, Error>
        func profile(userId: UUID) async throws -> ProfileSummary? { try result.get() }
    }

    private struct Offline: Error {}

    private func makeViewModel(_ result: Result<ProfileSummary?, Error>, email: String? = "sam@example.com") -> ProfileViewModel {
        ProfileViewModel(client: StubClient(result: result), userId: UUID(), email: email)
    }

    func test_beforeTheProfileLoads_theEmailStandsInForTheName() {
        let viewModel = makeViewModel(.success(nil))

        XCTAssertEqual(viewModel.displayName, "sam@example.com")
        XCTAssertNil(viewModel.joinedLabel)
    }

    func test_withNeitherProfileNorEmail_itSaysPlayer() async {
        let viewModel = makeViewModel(.success(nil), email: nil)

        await viewModel.load()

        XCTAssertEqual(viewModel.displayName, "Player")
    }

    func test_loadedProfile_suppliesNameAvatarAndJoinMonth() async throws {
        let joined = try PostgresTimestamp.parse("2026-08-15T12:00:00.123456+00:00")
        let avatar = URL(string: "https://example.com/sam.png")
        let viewModel = makeViewModel(.success(ProfileSummary(displayName: "Sam", avatarURL: avatar, joinedAt: joined)))

        await viewModel.load()

        XCTAssertEqual(viewModel.displayName, "Sam")
        XCTAssertEqual(viewModel.avatarURL, avatar)
        XCTAssertEqual(viewModel.joinedLabel, "Playing since August 2026")
    }

    func test_aFailedRead_keepsWhatWasAlreadyShowing() async {
        let viewModel = makeViewModel(.failure(Offline()))

        await viewModel.load()

        XCTAssertEqual(viewModel.displayName, "sam@example.com")
    }
}
