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

        func profile(userId: UUID) async throws -> ProfileSummary? { profileResult }
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

        var availableResult: Result<Bool, Error> = .success(true)
        var claimResult: Result<String, Error>?
        var privateResult: Result<Bool, Error>?
        var profileResult: ProfileSummary?
        private(set) var availabilityChecks: [String] = []
        private(set) var claims: [String] = []
        private(set) var privateCalls: [Bool] = []

        func usernameAvailable(_ username: String) async throws -> Bool {
            availabilityChecks.append(username)
            return try availableResult.get()
        }

        func claimUsername(_ username: String) async throws -> String {
            claims.append(username)
            return try (claimResult ?? .success(username)).get()
        }

        func setProfilePrivate(_ isPrivate: Bool) async throws -> Bool {
            privateCalls.append(isPrivate)
            return try (privateResult ?? .success(isPrivate)).get()
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

    // MARK: - Username

    private func makeFieldModel(client: StubClient, username: String = "sam_k") -> UsernameFieldModel {
        UsernameFieldModel(client: client, username: username, debounceNanoseconds: 1_000_000)
    }

    func test_usernameField_startsUnchanged() {
        let field = makeFieldModel(client: StubClient())

        XCTAssertEqual(field.status, .unchanged)
        XCTAssertEqual(field.text, "sam_k")
    }

    func test_usernameField_aMalformedNameIsRejectedLocallyWithoutACheck() async {
        let client = StubClient()
        let field = makeFieldModel(client: client)

        field.text = "sa"
        field.textChanged()
        await field.settle()

        XCTAssertEqual(field.status, .rejected("Username must be 3–20 characters."))
        XCTAssertTrue(client.availabilityChecks.isEmpty)
    }

    func test_usernameField_anAvailableNameIsReportedAfterTheDebounce() async {
        let client = StubClient()
        let field = makeFieldModel(client: client)

        field.text = "sam_new"
        field.textChanged()
        XCTAssertEqual(field.status, .checking)
        await field.settle()

        XCTAssertEqual(field.status, .available)
        XCTAssertEqual(client.availabilityChecks, ["sam_new"])
    }

    func test_usernameField_aTakenNameIsRejected() async {
        let client = StubClient()
        client.availableResult = .success(false)
        let field = makeFieldModel(client: client)

        field.text = "taken_one"
        field.textChanged()
        await field.settle()

        XCTAssertEqual(field.status, .rejected("That username is taken or reserved."))
    }

    func test_usernameField_aFailedCheckDoesNotBlockSaving() async {
        let client = StubClient()
        client.availableResult = .failure(Offline())
        let field = makeFieldModel(client: client)

        field.text = "sam_new"
        field.textChanged()
        await field.settle()

        XCTAssertEqual(field.status, .unchecked)
    }

    func test_usernameField_typingTheCurrentNameBackIsUnchangedWithoutACheck() async {
        let client = StubClient()
        let field = makeFieldModel(client: client)

        field.text = "sam_k"
        field.textChanged()
        await field.settle()

        XCTAssertEqual(field.status, .unchanged)
        XCTAssertTrue(client.availabilityChecks.isEmpty)
    }

    func test_save_claimsAChangedUsernameBeforeWritingTheProfile() async {
        let client = StubClient()
        let viewModel = ProfileEditorViewModel(
            client: client, userId: UUID(), displayName: "Sam", avatarURL: nil, username: "sam_k"
        )
        viewModel.usernameField?.text = "sam_new"

        await viewModel.save()

        XCTAssertEqual(client.claims, ["sam_new"])
        XCTAssertEqual(client.updatedDisplayName, "Sam")
        XCTAssertTrue(viewModel.saved)
    }

    func test_save_withAnUnchangedUsername_doesNotCallClaim() async {
        let client = StubClient()
        let viewModel = ProfileEditorViewModel(
            client: client, userId: UUID(), displayName: "Sam", avatarURL: nil, username: "sam_k"
        )

        await viewModel.save()

        XCTAssertTrue(client.claims.isEmpty)
        XCTAssertTrue(viewModel.saved)
    }

    func test_save_aRefusedUsernameShowsTheReasonAndSavesNothing() async {
        let client = StubClient()
        client.claimResult = .failure(UsernameError.taken)
        let viewModel = ProfileEditorViewModel(
            client: client, userId: UUID(), displayName: "Sam", avatarURL: nil, username: "sam_k"
        )
        viewModel.usernameField?.text = "taken_one"

        await viewModel.save()

        XCTAssertEqual(viewModel.notice, "That username is taken.")
        XCTAssertFalse(viewModel.saved)
        XCTAssertNil(client.updatedDisplayName)
    }

    func test_save_aMalformedUsernameIsRefusedWithoutCallingClaim() async {
        let client = StubClient()
        let viewModel = ProfileEditorViewModel(
            client: client, userId: UUID(), displayName: "Sam", avatarURL: nil, username: "sam_k"
        )
        viewModel.usernameField?.text = "no spaces"

        await viewModel.save()

        XCTAssertEqual(viewModel.notice, UsernameError.invalid.message)
        XCTAssertTrue(client.claims.isEmpty)
        XCTAssertFalse(viewModel.saved)
    }

    // MARK: - Confirm prompt

    private func makeStore() -> (UsernameConfirmationStore, cleanup: () -> Void) {
        let suite = "confirm-prompt-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (UsernameConfirmationStore(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    func test_confirmPrompt_appearsOnceForAUserWhoHasNotConfirmed() async {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let client = StubClient()
        client.profileResult = ProfileSummary(displayName: "Sam", avatarURL: nil, joinedAt: nil, username: "sam_k")
        let userId = UUID()

        let prompt = await UsernameConfirmViewModel.make(client: client, userId: userId, store: store)
        XCTAssertEqual(prompt?.field.text, "sam_k")

        prompt?.dismissed()
        let again = await UsernameConfirmViewModel.make(client: client, userId: userId, store: store)
        XCTAssertNil(again)
    }

    func test_confirmPrompt_isSkippedWhenTheUsernameCannotBeRead() async {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let prompt = await UsernameConfirmViewModel.make(client: StubClient(), userId: UUID(), store: store)

        XCTAssertNil(prompt)
    }

    func test_confirmPrompt_keepingItMarksItConfirmed() async {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let client = StubClient()
        client.profileResult = ProfileSummary(displayName: "Sam", avatarURL: nil, joinedAt: nil, username: "sam_k")
        let userId = UUID()
        let prompt = await UsernameConfirmViewModel.make(client: client, userId: userId, store: store)

        prompt?.keep()

        XCTAssertEqual(prompt?.finished, true)
        XCTAssertTrue(store.isConfirmed(userId))
        XCTAssertTrue(client.claims.isEmpty)
    }

    func test_confirmPrompt_aRefusedChangeStaysOpenAndUnconfirmed() async {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let client = StubClient()
        client.profileResult = ProfileSummary(displayName: "Sam", avatarURL: nil, joinedAt: nil, username: "sam_k")
        client.claimResult = .failure(UsernameError.reserved)
        let userId = UUID()
        let prompt = await UsernameConfirmViewModel.make(client: client, userId: userId, store: store)
        prompt?.field.text = "admin"

        await prompt?.save()

        XCTAssertEqual(prompt?.notice, UsernameError.reserved.message)
        XCTAssertEqual(prompt?.finished, false)
        XCTAssertFalse(store.isConfirmed(userId))
    }

    func test_confirmPrompt_aSuccessfulChangeFinishesAndMarksConfirmed() async {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let client = StubClient()
        client.profileResult = ProfileSummary(displayName: "Sam", avatarURL: nil, joinedAt: nil, username: "sam_k")
        let userId = UUID()
        let prompt = await UsernameConfirmViewModel.make(client: client, userId: userId, store: store)
        prompt?.field.text = "sam_new"

        await prompt?.save()

        XCTAssertEqual(client.claims, ["sam_new"])
        XCTAssertEqual(prompt?.finished, true)
        XCTAssertTrue(store.isConfirmed(userId))
    }

    // MARK: - Privacy

    func test_privacy_turningItOnCallsTheRpcAndKeepsTheValue() async {
        let client = StubClient()
        let viewModel = PrivacySettingsViewModel(client: client, isPrivate: false)

        await viewModel.set(true)

        XCTAssertEqual(client.privateCalls, [true])
        XCTAssertTrue(viewModel.isPrivate)
        XCTAssertNil(viewModel.notice)
    }

    func test_privacy_aFailedCallPutsTheToggleBack() async {
        let client = StubClient()
        client.privateResult = .failure(Offline())
        let viewModel = PrivacySettingsViewModel(client: client, isPrivate: false)

        await viewModel.set(true)

        XCTAssertFalse(viewModel.isPrivate)
        XCTAssertNotNil(viewModel.notice)
    }

    func test_privacy_settingTheCurrentValueDoesNothing() async {
        let client = StubClient()
        let viewModel = PrivacySettingsViewModel(client: client, isPrivate: true)

        await viewModel.set(true)

        XCTAssertTrue(client.privateCalls.isEmpty)
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
