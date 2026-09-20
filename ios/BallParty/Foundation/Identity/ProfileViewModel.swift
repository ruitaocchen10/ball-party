import Foundation
import Supabase

/// The slice of a `profiles` row the Profile tab shows.
struct ProfileSummary: Equatable, Sendable {
    let displayName: String?
    let avatarURL: URL?
    let joinedAt: Date?
}

/// The Profile tab's one read, named as its own protocol so tests can
/// substitute a fake instead of hitting the network.
protocol ProfileClient: Sendable {
    /// `nil` when the account has no profile row yet.
    func profile(userId: UUID) async throws -> ProfileSummary?
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
}

/// What the Profile tab shows about the signed-in player. Mirrors the header of
/// the web's `/profile`: the profile row's name and avatar, falling back to the
/// account email while the row is loading or missing, and when they joined.
@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: ProfileSummary?

    let email: String?
    private let client: ProfileClient
    private let userId: UUID

    init(client: ProfileClient, userId: UUID, email: String?) {
        self.client = client
        self.userId = userId
        self.email = email
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

    /// A failed read leaves whatever was already showing — the email
    /// fallback on a first load — rather than replacing a name with an error.
    func load() async {
        if let fresh = try? await client.profile(userId: userId) {
            profile = fresh
        }
    }
}
