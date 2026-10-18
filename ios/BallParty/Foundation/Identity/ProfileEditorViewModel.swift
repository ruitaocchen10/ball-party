import Foundation
import SwiftUI

/// Drives the "Edit profile" sheet: the display-name field, and staging a
/// new avatar (a device photo or a starter design) by uploading it
/// immediately, then persisting both fields together on Save — the same
/// two-step interaction as `webapp/components/foundation/identity/ProfileEditor.tsx`.
@MainActor
final class ProfileEditorViewModel: ObservableObject, Identifiable {
    /// Mirrors the dialog's two screens: the name/avatar form, and the photo chooser.
    enum Step: Equatable { case form, photo }

    /// Matches the web's `MAX_AVATAR_BYTES`.
    static let maxAvatarBytes = 5 * 1024 * 1024

    /// Only so `.sheet(item:)` can key off an instance — one is minted fresh
    /// each time the "Edit profile" menu item is tapped.
    let id = UUID()

    @Published var displayName: String
    @Published private(set) var avatarURL: URL?
    @Published var step: Step = .form
    @Published var paletteColors: [Color] = BeamAvatar.defaultPalette
    @Published private(set) var selectedPresetSeed: String?
    @Published private(set) var isSaving = false
    @Published private(set) var isUploadingAvatar = false
    @Published var notice: String?
    @Published private(set) var saved = false
    /// Present when the profile has a username to edit (every non-guest one does).
    let usernameField: UsernameFieldModel?

    private let client: ProfileClient
    private let userId: UUID

    init(client: ProfileClient, userId: UUID, displayName: String, avatarURL: URL?, username: String? = nil) {
        self.client = client
        self.usernameField = username.map { UsernameFieldModel(client: client, username: $0) }
        self.userId = userId
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    /// Unwraps a `FieldValidation`, surfacing `.invalid` as `notice` and
    /// returning `nil` so the caller can `guard` its way out — same helper
    /// `AuthViewModel` uses.
    private func require(_ validation: FieldValidation) -> String? {
        switch validation {
        case .valid(let value): return value
        case .invalid(let message): notice = message; return nil
        }
    }

    /// Uploads a photo picked from the library. Always normalized to JPEG
    /// first: the web keeps whatever format the browser hands it, but HEIC
    /// (what the Photos picker usually returns) doesn't render in every
    /// browser, so this settles on one format every client can show.
    func uploadPhoto(_ data: Data) async {
        notice = nil
        guard data.count <= Self.maxAvatarBytes else {
            notice = "Image must be under 5 MB."
            return
        }

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            let url = try await client.uploadAvatar(data, fileExtension: "jpg", contentType: "image/jpeg", for: userId)
            avatarURL = url.appendingQueryItem(name: "t", value: String(Int(Date().timeIntervalSince1970 * 1000)))
            selectedPresetSeed = nil
            step = .form
        } catch {
            notice = "Upload failed. Please try again."
        }
    }

    /// Renders `seed` against the current palette and uploads it as a PNG —
    /// the starter-avatar counterpart of `uploadPhoto`.
    func choosePreset(seed: String) async {
        notice = nil
        guard let data = BeamAvatarView(seed: seed, palette: paletteColors).png() else {
            notice = "That avatar could not be prepared. Please try another one."
            return
        }

        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            let url = try await client.uploadAvatar(data, fileExtension: "png", contentType: "image/png", for: userId)
            avatarURL = url.appendingQueryItem(name: "preset", value: seed)
            selectedPresetSeed = seed
            step = .form
        } catch {
            notice = "Avatar upload failed. Please try again."
        }
    }

    /// Persists the display name and whatever avatar is currently staged —
    /// even an unchanged one, matching the web, which always resends its
    /// `avatar` state on save rather than only when it changed.
    func save() async {
        notice = nil
        guard let name = require(IdentityConstants.validateDisplayName(displayName)) else { return }

        isSaving = true
        defer { isSaving = false }

        // The username goes first: it is the write that can be refused (taken,
        // reserved), and a refusal should leave the sheet open with nothing
        // else half-saved.
        if let usernameField {
            do {
                _ = try await usernameField.claimIfChanged()
            } catch let error as UsernameError {
                notice = error.message
                return
            } catch {
                notice = UsernameError.other.message
                return
            }
        }

        do {
            try await client.updateProfile(displayName: name, avatarURL: avatarURL, for: userId)
            saved = true
        } catch {
            notice = "We couldn’t save your profile. Please try again."
        }
    }
}

private extension URL {
    /// Appends a cache-busting query item so a re-upload to the same storage
    /// path (avatars are upserted in place) reads as a new URL — otherwise a
    /// client that already fetched the old file at this path could keep
    /// showing it.
    func appendingQueryItem(name: String, value: String) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: name, value: value))
        components.queryItems = items
        return components.url ?? self
    }
}

/// A username text field with a debounced availability check. Shared by the
/// edit-profile sheet. The check
/// (`username_available`) is advisory, so a failed or stale one never blocks a
/// save; `claim_username` is authoritative and its refusal is what the player
/// finally sees.
@MainActor
final class UsernameFieldModel: ObservableObject {
    enum Status: Equatable {
        /// Nothing worth saying yet (empty field).
        case idle
        /// The text matches the current username.
        case unchanged
        case checking
        case available
        /// Malformed (local rule) or taken/reserved (server said no).
        case rejected(String)
        /// The availability call itself failed; saving may still work.
        case unchecked
    }

    @Published var text: String
    @Published private(set) var status: Status
    /// The username as last stored; what "unchanged" is measured against.
    private(set) var current: String

    private let client: ProfileClient
    private let debounceNanoseconds: UInt64
    private var checkTask: Task<Void, Never>?

    init(client: ProfileClient, username: String, debounceNanoseconds: UInt64 = 400_000_000) {
        self.client = client
        self.current = username
        self.text = username
        self.debounceNanoseconds = debounceNanoseconds
        self.status = .unchanged
    }

    /// Call whenever `text` changes (the view's `.onChange`).
    func textChanged() {
        checkTask?.cancel()
        checkTask = nil

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            status = .idle
            return
        }
        switch IdentityConstants.validateUsername(text) {
        case .invalid(let message):
            status = .rejected(message)
        case .valid(let name):
            if name == current {
                status = .unchanged
                return
            }
            status = .checking
            checkTask = Task { [client, debounceNanoseconds] in
                try? await Task.sleep(nanoseconds: debounceNanoseconds)
                guard !Task.isCancelled else { return }
                let result: Result<Bool, Error>
                do { result = .success(try await client.usernameAvailable(name)) } catch { result = .failure(error) }
                // A newer keystroke cancelled this check; its answer is stale.
                guard !Task.isCancelled else { return }
                switch result {
                case .success(true): self.status = .available
                case .success(false): self.status = .rejected("That username is taken or reserved.")
                case .failure: self.status = .unchecked
                }
            }
        }
    }

    /// Waits for the in-flight availability check, if any (tests).
    func settle() async {
        await checkTask?.value
    }

    /// Claims the typed username when it differs from the stored one.
    /// Returns the stored value, or `nil` when there was nothing to change.
    /// Throws `UsernameError` (local format failures included).
    func claimIfChanged() async throws -> String? {
        checkTask?.cancel()
        guard case .valid(let name) = IdentityConstants.validateUsername(text) else {
            throw UsernameError.invalid
        }
        if name == current { return nil }
        let stored: String
        do {
            stored = try await client.claimUsername(name)
        } catch let error as UsernameError {
            throw error
        } catch {
            throw UsernameError.other
        }
        current = stored
        text = stored
        status = .unchanged
        return stored
    }
}
