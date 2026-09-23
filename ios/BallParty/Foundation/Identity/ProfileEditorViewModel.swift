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

    private let client: ProfileClient
    private let userId: UUID

    init(client: ProfileClient, userId: UUID, displayName: String, avatarURL: URL?) {
        self.client = client
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
