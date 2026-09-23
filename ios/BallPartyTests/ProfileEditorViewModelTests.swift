import Foundation
@testable import BallParty
import XCTest

/// `ProfileEditorViewModel` against a stub `ProfileClient` — validation,
/// saving, and staging a new avatar (device photo or starter design) before
/// it's persisted.
@MainActor
final class ProfileEditorViewModelTests: XCTestCase {
    /// A class, not a struct, so it can record what it was called with while
    /// still being stored behind the `let client: ProfileClient` the view
    /// model holds.
    private final class StubClient: ProfileClient, @unchecked Sendable {
        var uploadResult: Result<URL, Error> = .success(URL(string: "https://example.com/u/avatar.jpg")!)
        var updateResult: Result<Void, Error> = .success(())
        private(set) var uploadedData: Data?
        private(set) var uploadedExtension: String?
        private(set) var updatedDisplayName: String?
        private(set) var updatedAvatarURL: URL?

        func profile(userId: UUID) async throws -> ProfileSummary? { nil }
        func matchHistory() async throws -> [ProfileMatchHistoryRow] { [] }
        func knowerHighlights() async throws -> [ProfileKnowerHighlightRow] { [] }

        func uploadAvatar(_ data: Data, fileExtension: String, contentType: String, for userId: UUID) async throws -> URL {
            uploadedData = data
            uploadedExtension = fileExtension
            return try uploadResult.get()
        }

        func updateProfile(displayName: String, avatarURL: URL?, for userId: UUID) async throws {
            updatedDisplayName = displayName
            updatedAvatarURL = avatarURL
            try updateResult.get()
        }
    }

    private struct Offline: Error {}

    private func makeViewModel(
        client: StubClient = StubClient(), displayName: String = "Sam", avatarURL: URL? = nil
    ) -> ProfileEditorViewModel {
        ProfileEditorViewModel(client: client, userId: UUID(), displayName: displayName, avatarURL: avatarURL)
    }

    // MARK: - Save

    func test_save_withATooShortName_rejectsWithoutCallingTheClient() async {
        let client = StubClient()
        let viewModel = makeViewModel(client: client, displayName: "S")

        await viewModel.save()

        XCTAssertFalse(viewModel.saved)
        XCTAssertNotNil(viewModel.notice)
        XCTAssertNil(client.updatedDisplayName)
    }

    func test_save_trimsAndPersistsTheDisplayNameAndCurrentAvatar() async {
        let avatar = URL(string: "https://example.com/avatar.jpg")!
        let client = StubClient()
        let viewModel = makeViewModel(client: client, displayName: "  Sam  ", avatarURL: avatar)

        await viewModel.save()

        XCTAssertTrue(viewModel.saved)
        XCTAssertEqual(client.updatedDisplayName, "Sam")
        XCTAssertEqual(client.updatedAvatarURL, avatar)
    }

    func test_save_aFailedWrite_surfacesANoticeAndDoesNotMarkSaved() async {
        let client = StubClient()
        client.updateResult = .failure(Offline())
        let viewModel = makeViewModel(client: client)

        await viewModel.save()

        XCTAssertFalse(viewModel.saved)
        XCTAssertNotNil(viewModel.notice)
    }

    // MARK: - Photo upload

    func test_uploadPhoto_overTheSizeLimit_isRejectedBeforeAnyUpload() async {
        let client = StubClient()
        let viewModel = makeViewModel(client: client)
        let tooBig = Data(count: ProfileEditorViewModel.maxAvatarBytes + 1)

        await viewModel.uploadPhoto(tooBig)

        XCTAssertNil(client.uploadedData)
        XCTAssertEqual(viewModel.notice, "Image must be under 5 MB.")
    }

    func test_uploadPhoto_onSuccess_setsTheAvatarAndReturnsToTheForm() async {
        let uploaded = URL(string: "https://example.com/u/avatar.jpg")!
        let client = StubClient()
        client.uploadResult = .success(uploaded)
        let viewModel = makeViewModel(client: client)
        viewModel.step = .photo

        await viewModel.uploadPhoto(Data([0x01, 0x02]))

        XCTAssertEqual(viewModel.step, .form)
        XCTAssertEqual(viewModel.avatarURL?.host, uploaded.host)
        XCTAssertEqual(viewModel.avatarURL?.path, uploaded.path)
        XCTAssertEqual(client.uploadedExtension, "jpg")
        XCTAssertNil(viewModel.selectedPresetSeed)
    }

    func test_uploadPhoto_aFailedUpload_leavesTheAvatarUnchanged() async {
        let original = URL(string: "https://example.com/original.jpg")!
        let client = StubClient()
        client.uploadResult = .failure(Offline())
        let viewModel = makeViewModel(client: client, avatarURL: original)

        await viewModel.uploadPhoto(Data([0x01]))

        XCTAssertEqual(viewModel.avatarURL, original)
        XCTAssertNotNil(viewModel.notice)
    }

    // MARK: - Preset avatars

    func test_choosePreset_uploadsAPNGAndMarksItSelected() async {
        let uploaded = URL(string: "https://example.com/u/avatar.png")!
        let client = StubClient()
        client.uploadResult = .success(uploaded)
        let viewModel = makeViewModel(client: client)

        await viewModel.choosePreset(seed: "captain")

        XCTAssertEqual(viewModel.selectedPresetSeed, "captain")
        XCTAssertEqual(viewModel.step, .form)
        XCTAssertEqual(client.uploadedExtension, "png")
        XCTAssertEqual(viewModel.avatarURL?.query, "preset=captain")
    }

    func test_choosePreset_aFailedUpload_clearsNeitherTheSelectionNorTheAvatar() async {
        let original = URL(string: "https://example.com/original.jpg")!
        let client = StubClient()
        client.uploadResult = .failure(Offline())
        let viewModel = makeViewModel(client: client, avatarURL: original)

        await viewModel.choosePreset(seed: "captain")

        XCTAssertEqual(viewModel.avatarURL, original)
        XCTAssertNil(viewModel.selectedPresetSeed)
        XCTAssertNotNil(viewModel.notice)
    }
}
