import Foundation
import Supabase

/// The slice of a `profiles` row the Profile tab shows.
struct ProfileSummary: Equatable, Sendable {
    let displayName: String?
    let avatarURL: URL?
    let joinedAt: Date?
    /// `profiles.username` — always set for non-guest accounts (generated at
    /// signup); `nil` only for a row we couldn't read it from.
    var username: String? = nil
    /// `profiles.is_private`: only friends can open the profile body.
    var isPrivate: Bool = false
}

/// Where a player's avatar files live in Storage. The folder name must be the
/// lowercase uid: the `avatars_*_own` policies compare it to `auth.uid()::text`,
/// and `UUID.uuidString` is uppercase, which Storage rejects with a 403.
enum AvatarStorage {
    static let bucket = "avatars"

    static func folder(for userId: UUID) -> String {
        userId.uuidString.lowercased()
    }
}

/// The Profile tab's reads, named as their own protocol so tests can
/// substitute a fake instead of hitting the network.
protocol ProfileClient: Sendable {
    /// `nil` when the account has no profile row yet.
    func profile(userId: UUID) async throws -> ProfileSummary?
    /// `my_match_history` — every completed match the caller has played,
    /// newest first, including ones from lobbies they have since left.
    func matchHistory() async throws -> [ProfileMatchHistoryRow]
    /// `my_profile_knower_highlights` — the caller's prompt-scoring totals
    /// and standing, one row per reporting window.
    func knowerHighlights() async throws -> [ProfileKnowerHighlightRow]

    /// Uploads to the `avatars` bucket under `{userId}/avatar.<fileExtension>`,
    /// overwriting anything already there, and returns its public URL — the
    /// Swift counterpart of the web's direct-to-Storage avatar upload.
    /// Storage RLS (`avatars_insert_own`/`avatars_update_own`) already
    /// confines the write to the caller's own prefix; `userId` only shapes
    /// the path, it isn't what enforces the boundary.
    func uploadAvatar(_ data: Data, fileExtension: String, contentType: String, for userId: UUID) async throws -> URL

    /// Persists `profiles.display_name` / `profiles.avatar_url` — the web's
    /// `updateProfile` server action.
    func updateProfile(displayName: String, avatarURL: URL?, for userId: UUID) async throws

    /// `username_available` — whether the caller could claim `username` now.
    /// `false` also covers a malformed or reserved name.
    func usernameAvailable(_ username: String) async throws -> Bool
    /// `claim_username` — authoritative. Returns the username as stored;
    /// throws `UsernameError` for the refusals the RPC defines.
    func claimUsername(_ username: String) async throws -> String
}

/// The two username RPCs, shared by the profile client and the auth backend
/// (signup claims right after the session exists).
enum UsernameRPC {
    private struct Params: Encodable {
        let p_username: String
    }

    static func available(_ username: String, client: SupabaseClient) async throws -> Bool {
        do {
            return try await client.rpc("username_available", params: Params(p_username: username))
                .execute().value
        } catch let error as PostgrestError {
            throw UsernameError(message: error.message, code: error.code)
        }
    }

    static func claim(_ username: String, client: SupabaseClient) async throws -> String {
        do {
            return try await client.rpc("claim_username", params: Params(p_username: username))
                .execute().value
        } catch let error as PostgrestError {
            throw UsernameError(message: error.message, code: error.code)
        }
    }
}

/// Remembers, per user and on this device only, that the one-time "confirm
/// your username" prompt has been dealt with (kept, changed or dismissed).
/// Same client-side flag the web keeps in localStorage.
struct UsernameConfirmationStore: @unchecked Sendable {
    let defaults: UserDefaults

    static let standard = UsernameConfirmationStore(defaults: .standard)

    static func key(for userId: UUID) -> String {
        "username-confirmed.\(userId.uuidString.lowercased())"
    }

    func isConfirmed(_ userId: UUID) -> Bool {
        defaults.bool(forKey: Self.key(for: userId))
    }

    func markConfirmed(_ userId: UUID) {
        defaults.set(true, forKey: Self.key(for: userId))
    }
}

struct SupabaseProfileClient: ProfileClient {
    let client: SupabaseClient

    private struct Row: Decodable {
        let displayName: String?
        let avatarURL: String?
        let createdAt: String?
        let username: String?
        let isPrivate: Bool?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarURL = "avatar_url"
            case createdAt = "created_at"
            case username
            case isPrivate = "is_private"
        }
    }

    func profile(userId: UUID) async throws -> ProfileSummary? {
        let rows: [Row] = try await client.from("profiles")
            .select("display_name, avatar_url, created_at, username, is_private")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return ProfileSummary(
            displayName: row.displayName,
            avatarURL: row.avatarURL.flatMap(URL.init(string:)),
            joinedAt: try row.createdAt.map(PostgresTimestamp.parse),
            username: row.username,
            isPrivate: row.isPrivate ?? false
        )
    }

    func matchHistory() async throws -> [ProfileMatchHistoryRow] {
        try await client.rpc("my_match_history").execute().value
    }

    func knowerHighlights() async throws -> [ProfileKnowerHighlightRow] {
        try await client.rpc("my_profile_knower_highlights").execute().value
    }

    func uploadAvatar(_ data: Data, fileExtension: String, contentType: String, for userId: UUID) async throws -> URL {
        let path = "\(AvatarStorage.folder(for: userId))/avatar.\(fileExtension)"
        try await client.storage.from(AvatarStorage.bucket).upload(
            path, data: data, options: FileOptions(cacheControl: "3600", contentType: contentType, upsert: true)
        )
        return try client.storage.from(AvatarStorage.bucket).getPublicURL(path: path)
    }

    private struct ProfileUpdate: Encodable {
        let displayName: String
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarURL = "avatar_url"
        }
    }

    func updateProfile(displayName: String, avatarURL: URL?, for userId: UUID) async throws {
        try await client.from("profiles")
            .update(ProfileUpdate(displayName: displayName, avatarURL: avatarURL?.absoluteString))
            .eq("id", value: userId.uuidString)
            .execute()
    }

    func usernameAvailable(_ username: String) async throws -> Bool {
        try await UsernameRPC.available(username, client: client)
    }

    func claimUsername(_ username: String) async throws -> String {
        try await UsernameRPC.claim(username, client: client)
    }
}

/// What the Profile tab shows about the signed-in player. Mirrors the web's
/// `/profile`: the header (name, avatar, join date), the Ball Knower / Gamer
/// highlights card, and — via a `HuddleViewModel` the screen owns alongside
/// this one — the take history.
@MainActor
final class ProfileViewModel: ObservableObject {
    /// The highlights card's two halves — `ProfileHighlightsCard`'s `view` state on the web.
    enum StatsView: Equatable { case knower, gamer }

    @Published private(set) var profile: ProfileSummary?
    @Published private(set) var knowerHighlights: [ProfileStatRange: KnowerHighlight] = [:]
    @Published private(set) var gamerHighlight: GamerHighlight = .empty
    /// UI-only state the screen binds directly to, same as `LobbyViewModel`'s form fields.
    @Published var statsView: StatsView = .knower
    @Published var statsRange: ProfileStatRange = .lifetime

    let email: String?
    private let client: ProfileClient
    private let userId: UUID
    private let now: () -> Date

    init(client: ProfileClient, userId: UUID, email: String?, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.userId = userId
        self.email = email
        self.now = now
    }

    var displayName: String {
        profile?.displayName ?? email ?? "Player"
    }

    var avatarURL: URL? { profile?.avatarURL }

    /// "@sam_k", once the profile row has said.
    var usernameLabel: String? { profile?.username.map { "@\($0)" } }

    /// "Playing since August 2026", once the profile row has said when.
    var joinedLabel: String? {
        profile?.joinedAt.map {
            "Playing since \($0.formatted(Date.FormatStyle(locale: Locale(identifier: "en_US")).month(.wide).year()))"
        }
    }

    /// The knower highlight for whatever range the picker is on.
    var selectedKnowerHighlight: KnowerHighlight { knowerHighlights[statsRange] ?? .empty }

    /// A player's status is always lifetime — the range picker only ever
    /// changes the points and standing beside it, same split the web's card
    /// makes (`highlights.knower.lifetime.percentile`).
    private var lifetimeKnowerHighlight: KnowerHighlight { knowerHighlights[.lifetime] ?? .empty }

    /// "Rookie" through "Ball god", from the lifetime percentile — mirrors the web's `KnowerStatus`.
    var knowerStatus: String {
        guard let percentile = lifetimeKnowerHighlight.percentile else { return "Unranked" }
        switch percentile {
        case ..<20: return "Rookie"
        case ..<40: return "Casual"
        case ..<60: return "Fan"
        case ..<80: return "Ball knower"
        default: return "Ball god"
        }
    }

    /// What sits under the status, mirroring `KnowerStatus`'s detail line.
    var knowerStatusDetail: String {
        guard let percentile = lifetimeKnowerHighlight.percentile else {
            return "Your lifetime score will set your status"
        }
        return "Lifetime · \(percentile.ordinal) percentile"
    }

    /// A failed read leaves whatever was already showing — the email
    /// fallback on a first load — rather than replacing a name with an error.
    /// Match history and highlights are best-effort the same way: a failure
    /// there leaves the card at its previous (or empty) numbers.
    func load() async {
        if let fresh = try? await client.profile(userId: userId) {
            profile = fresh
        }

        let history = (try? await client.matchHistory()) ?? []
        let matches = history.compactMap(\.completed)
        gamerHighlight = ProfileStats.gamerHighlight(matches, in: .lifetime, now: now())

        let highlightRows = (try? await client.knowerHighlights()) ?? []
        knowerHighlights = Dictionary(uniqueKeysWithValues: highlightRows.compactMap { row in
            ProfileStatRange(rawValue: row.windowKey).map {
                ($0, KnowerHighlight(totalPoints: row.totalPoints, percentile: row.percentile))
            }
        })
    }
}

extension Int {
    /// "42nd", "3rd", "11th" — mirrors the web's `ordinal`.
    var ordinal: String {
        let remainder = self % 100
        if (11...13).contains(remainder) { return "\(self)th" }
        switch self % 10 {
        case 1: return "\(self)st"
        case 2: return "\(self)nd"
        case 3: return "\(self)rd"
        default: return "\(self)th"
        }
    }
}
