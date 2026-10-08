import Foundation

// The Ball Knower leaderboard's types — the mirror of
// `webapp/lib/foundation/content/leaderboard/windows.ts` plus the two RPCs it
// reads (`ball_knower_leaderboard`, `my_ball_knower_standing`, migration 0181).
// Ranking, ties, the visibility opt-out and the pick floor all live in SQL;
// nothing here recomputes them.

/// The windows both RPCs accept.
enum LeaderboardWindow: String, CaseIterable, Equatable, Sendable {
    case week, month, year, lifetime

    var label: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .lifetime: "All time"
        }
    }

    var caption: String {
        switch self {
        case .week: "Last 7 days"
        case .month: "Last 30 days"
        case .year: "Last 365 days"
        case .lifetime: "Every resolved pick"
        }
    }

    /// The leaderboard window matching whatever range the Profile card is on.
    init(_ range: ProfileStatRange) {
        switch range {
        case .week: self = .week
        case .month: self = .month
        case .year: self = .year
        case .lifetime: self = .lifetime
        }
    }
}

/// One ranked player — a row of `ball_knower_leaderboard`.
struct LeaderboardRow: Decodable, Equatable, Sendable, Identifiable {
    let rank: Int
    let profileId: UUID
    let displayName: String
    let avatarURL: URL?
    let totalPoints: Int
    let scoredPicks: Int
    let isMe: Bool
    let rankedCount: Int

    var id: UUID { profileId }

    private enum CodingKeys: String, CodingKey {
        case rank
        case profileId = "profile_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case totalPoints = "total_points"
        case scoredPicks = "scored_picks"
        case isMe = "is_me"
        case rankedCount = "ranked_count"
    }

    init(
        rank: Int, profileId: UUID = UUID(), displayName: String, avatarURL: URL? = nil,
        totalPoints: Int, scoredPicks: Int, isMe: Bool = false, rankedCount: Int
    ) {
        self.rank = rank
        self.profileId = profileId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.totalPoints = totalPoints
        self.scoredPicks = scoredPicks
        self.isMe = isMe
        self.rankedCount = rankedCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decode(Int.self, forKey: .rank)
        profileId = try c.decode(UUID.self, forKey: .profileId)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL).flatMap(URL.init(string:))
        totalPoints = try c.decode(Int.self, forKey: .totalPoints)
        scoredPicks = try c.decode(Int.self, forKey: .scoredPicks)
        isMe = try c.decode(Bool.self, forKey: .isMe)
        rankedCount = try c.decode(Int.self, forKey: .rankedCount)
    }
}

/// Where the caller stands — the one row `my_ball_knower_standing` returns.
struct LeaderboardStanding: Decodable, Equatable, Sendable {
    /// `ranked` is on the board; `hidden` has rankings visibility off;
    /// `unranked` is visible but under the pick floor (including no picks).
    enum Status: String, Equatable, Sendable {
        case ranked, hidden, unranked
    }

    let status: Status
    let rank: Int?
    let totalPoints: Int
    let scoredPicks: Int
    let rankedCount: Int
    let minPicks: Int

    private enum CodingKeys: String, CodingKey {
        case status, rank
        case totalPoints = "total_points"
        case scoredPicks = "scored_picks"
        case rankedCount = "ranked_count"
        case minPicks = "min_picks"
    }

    init(status: Status, rank: Int? = nil, totalPoints: Int = 0, scoredPicks: Int = 0, rankedCount: Int = 0, minPicks: Int = 3) {
        self.status = status
        self.rank = rank
        self.totalPoints = totalPoints
        self.scoredPicks = scoredPicks
        self.rankedCount = rankedCount
        self.minPicks = minPicks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A status this build doesn't know reads as unranked, same as the web.
        status = Status(rawValue: try c.decode(String.self, forKey: .status)) ?? .unranked
        rank = try c.decodeIfPresent(Int.self, forKey: .rank)
        totalPoints = try c.decode(Int.self, forKey: .totalPoints)
        scoredPicks = try c.decode(Int.self, forKey: .scoredPicks)
        rankedCount = try c.decode(Int.self, forKey: .rankedCount)
        minPicks = try c.decode(Int.self, forKey: .minPicks)
    }

    /// "Top N%". Rounded up, so a player is never shown a better band than
    /// they hold. `nil` when nobody is ranked.
    var topPercent: Int? {
        guard let rank, rankedCount > 0 else { return nil }
        return Int((Double(rank * 100) / Double(rankedCount)).rounded(.up))
    }

    /// What the caller's own row says, decided in one place — `standingCopy`
    /// in the web's `windows.ts`. iOS has no settings screen for rankings
    /// visibility yet (BPMO-10), so the hidden line points at the web.
    var copy: (headline: String, detail: String) {
        switch status {
        case .hidden:
            return ("You're hidden", "Turn rankings visibility back on in Settings on the web to appear here")
        case .unranked:
            return unrankedCopy
        case .ranked:
            guard let rank, let band = topPercent else { return unrankedCopy }
            return ("#\(rank)", "Top \(band)% of \(rankedCount.formatted()) ranked players")
        }
    }

    private var unrankedCopy: (headline: String, detail: String) {
        let missing = max(1, minPicks - scoredPicks)
        return ("Not ranked yet", "\(missing) more scored \(missing == 1 ? "pick" : "picks") to join the board")
    }
}
