import Foundation
import Supabase

/// The slice of a `profiles` row the Profile tab shows.
struct ProfileSummary: Equatable, Sendable {
    let displayName: String?
    let avatarURL: URL?
    let joinedAt: Date?
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
}

struct SupabaseProfileClient: ProfileClient {
    let client: SupabaseClient

    private struct Row: Decodable {
        let displayName: String?
        let avatarURL: String?
        let createdAt: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarURL = "avatar_url"
            case createdAt = "created_at"
        }
    }

    func profile(userId: UUID) async throws -> ProfileSummary? {
        let rows: [Row] = try await client.from("profiles")
            .select("display_name, avatar_url, created_at")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return nil }
        return ProfileSummary(
            displayName: row.displayName,
            avatarURL: row.avatarURL.flatMap(URL.init(string:)),
            joinedAt: try row.createdAt.map(PostgresTimestamp.parse)
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
