import Foundation
@testable import BallParty
import XCTest

/// `ProfileViewModel` against a stub `ProfileClient` — what the Profile tab
/// shows before, during and after its reads.
@MainActor
final class ProfileViewModelTests: XCTestCase {
    private struct StubClient: ProfileClient {
        var result: Result<ProfileSummary?, Error> = .success(nil)
        var history: [ProfileMatchHistoryRow] = []
        var highlights: [ProfileKnowerHighlightRow] = []

        func profile(userId: UUID) async throws -> ProfileSummary? { try result.get() }
        func matchHistory() async throws -> [ProfileMatchHistoryRow] { history }
        func knowerHighlights() async throws -> [ProfileKnowerHighlightRow] { highlights }
        func uploadAvatar(_ data: Data, fileExtension: String, contentType: String, for userId: UUID) async throws -> URL {
            URL(string: "https://example.com/avatar.\(fileExtension)")!
        }
        func updateProfile(displayName: String, avatarURL: URL?, for userId: UUID) async throws {}
        func usernameAvailable(_ username: String) async throws -> Bool { true }
        func claimUsername(_ username: String) async throws -> String { username }
        func setProfilePrivate(_ isPrivate: Bool) async throws -> Bool { isPrivate }
    }

    private struct Offline: Error {}

    private let epoch = try! PostgresTimestamp.parse("2026-09-23T12:00:00+00:00")

    private func makeViewModel(
        _ result: Result<ProfileSummary?, Error>,
        email: String? = "sam@example.com",
        history: [ProfileMatchHistoryRow] = [],
        highlights: [ProfileKnowerHighlightRow] = []
    ) -> ProfileViewModel {
        ProfileViewModel(
            client: StubClient(result: result, history: history, highlights: highlights),
            userId: UUID(),
            email: email,
            now: { [epoch] in epoch }
        )
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

    // MARK: - Highlights

    func test_knowerHighlights_areKeyedByWindowAndDefaultEmpty() async {
        let viewModel = makeViewModel(.success(nil), highlights: [
            ProfileKnowerHighlightRow(windowKey: "lifetime", totalPoints: 120, percentile: 62),
            ProfileKnowerHighlightRow(windowKey: "week", totalPoints: 10, percentile: nil),
        ])

        await viewModel.load()

        XCTAssertEqual(viewModel.selectedKnowerHighlight, KnowerHighlight(totalPoints: 120, percentile: 62))
        viewModel.statsRange = .week
        XCTAssertEqual(viewModel.selectedKnowerHighlight, KnowerHighlight(totalPoints: 10, percentile: nil))
        // A window the read never mentioned (e.g. "month" missing from a
        // partial response) still has a sensible zero rather than crashing a lookup.
        viewModel.statsRange = .month
        XCTAssertEqual(viewModel.selectedKnowerHighlight, .empty)
    }

    func test_knowerStatus_readsTheLifetimeWindowRegardlessOfTheSelectedRange() async {
        let viewModel = makeViewModel(.success(nil), highlights: [
            ProfileKnowerHighlightRow(windowKey: "lifetime", totalPoints: 500, percentile: 81),
            ProfileKnowerHighlightRow(windowKey: "week", totalPoints: 5, percentile: 12),
        ])

        await viewModel.load()
        viewModel.statsRange = .week

        XCTAssertEqual(viewModel.knowerStatus, "Ball god")
        XCTAssertEqual(viewModel.knowerStatusDetail, "81st percentile")
    }

    func test_knowerStatus_withNoResolvedPicksYet_isUnranked() async {
        let viewModel = makeViewModel(.success(nil), highlights: [
            ProfileKnowerHighlightRow(windowKey: "lifetime", totalPoints: 0, percentile: nil),
        ])

        await viewModel.load()

        XCTAssertEqual(viewModel.knowerStatus, "Unranked")
        XCTAssertEqual(viewModel.knowerStatusDetail, "Not ranked yet")
    }

    func test_gamerHighlight_countsOnlyMultiplayerWinsWithinTheLifetimeWindow() async {
        let solo = UUID()
        let viewModel = makeViewModel(.success(nil), history: [
            ProfileMatchHistoryRow(matchId: UUID(), game: "higher_or_lower", endedAt: epoch, placement: 1, mode: "party"),
            ProfileMatchHistoryRow(matchId: UUID(), game: "higher_or_lower", endedAt: epoch, placement: 2, mode: "arcade"),
            // A solo run has no opponent to beat, so it doesn't count as a game played here.
            ProfileMatchHistoryRow(matchId: solo, game: "higher_or_lower", endedAt: epoch, placement: 1, mode: "solo"),
        ])

        await viewModel.load()

        XCTAssertEqual(viewModel.gamerHighlight, GamerHighlight(gamesPlayed: 2, wins: 1, winRate: 50))
    }

    func test_matchHistory_rowsWithAnUnknownGameOrMode_areLeftOutOfTheGamerHighlight() async {
        let viewModel = makeViewModel(.success(nil), history: [
            ProfileMatchHistoryRow(matchId: UUID(), game: "higher_or_lower", endedAt: epoch, placement: 1, mode: "party"),
            ProfileMatchHistoryRow(matchId: UUID(), game: "future_game", endedAt: epoch, placement: 1, mode: "party"),
            ProfileMatchHistoryRow(matchId: UUID(), game: "higher_or_lower", endedAt: epoch, placement: 1, mode: nil),
        ])

        await viewModel.load()

        XCTAssertEqual(viewModel.gamerHighlight, GamerHighlight(gamesPlayed: 1, wins: 1, winRate: 100))
    }

    // MARK: - Avatar storage

    func test_avatarFolder_isTheLowercaseUid() {
        let id = UUID(uuidString: "0C6771DB-A1B3-4950-A355-37B5A1BA569D")!

        // `uuidString` is uppercase; Storage's `avatars_*_own` policies compare
        // the folder to the lowercase `auth.uid()::text`.
        XCTAssertEqual(AvatarStorage.folder(for: id), "0c6771db-a1b3-4950-a355-37b5a1ba569d")
    }
}
