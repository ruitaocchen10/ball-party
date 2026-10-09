import Foundation

// The Gamer and solo leaderboards' types — the mirror of
// `webapp/lib/foundation/content/leaderboard/boards.ts` plus the four RPCs it
// reads (`gamer_leaderboard`, `my_gamer_standing`, `solo_leaderboard`,
// `my_solo_standing`, migration 0192). Ranking, ties, windows and who is
// eligible all live in SQL; nothing here recomputes them.

/// The boards under the leaderboard screen, in tab order.
enum LeaderboardBoard: String, CaseIterable, Equatable, Hashable, Sendable {
    case ballKnower, gamer, higherOrLower, qbSeasonBuilder

    /// Short label for the board picker.
    var label: String {
        switch self {
        case .ballKnower: "Ball Knower"
        case .gamer: "Wins"
        case .higherOrLower: "Higher or Lower"
        case .qbSeasonBuilder: "QB Season"
        }
    }

    var title: String {
        switch self {
        case .ballKnower: "Ball Knower"
        case .gamer: "Multiplayer wins"
        case .higherOrLower: "Higher or Lower"
        case .qbSeasonBuilder: "QB Season Builder"
        }
    }

    func description(for scope: LeaderboardScope) -> String {
        let friends = scope == .friends
        switch self {
        case .ballKnower:
            return scope.description
        case .gamer:
            return friends ? "Multiplayer wins, ranked against your friends." : "Multiplayer wins, ranked against everyone who plays in rooms."
        case .higherOrLower:
            return friends ? "Your best solo streak, ranked against your friends." : "Your best solo streak, ranked against everyone."
        case .qbSeasonBuilder:
            return friends ? "Your best season score, ranked against your friends." : "Your best season score, ranked against everyone."
        }
    }

    /// The solo game a board ranks, as `solo_leaderboard` names it. Nil for the other boards.
    var soloGame: SoloGame? {
        switch self {
        case .higherOrLower: .higherOrLower
        case .qbSeasonBuilder: .qbSeasonBuilder
        case .ballKnower, .gamer: nil
        }
    }

    /// Windows only apply to the boards that count something over time.
    var hasWindows: Bool { self == .gamer }
}

/// The `p_game` argument of `solo_leaderboard` and `my_solo_standing`.
enum SoloGame: String, Equatable, Sendable {
    case higherOrLower = "higher_or_lower"
    case qbSeasonBuilder = "qb_season_builder"
}

/// QB Season Builder scores a visible run and a hidden run separately, so each is its own board.
enum QbMode: String, CaseIterable, Equatable, Sendable {
    case visible, hidden

    var label: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        }
    }
}

/// One ranked player — a row of `gamer_leaderboard`.
struct GamerRow: Decodable, Equatable, Sendable {
    let rank: Int
    let profileId: UUID
    let displayName: String
    let avatarURL: URL?
    let wins: Int
    let gamesPlayed: Int
    let isMe: Bool
    let rankedCount: Int
    let username: String?

    private enum CodingKeys: String, CodingKey {
        case rank
        case profileId = "profile_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case wins
        case gamesPlayed = "games_played"
        case isMe = "is_me"
        case rankedCount = "ranked_count"
        case username
    }

    init(
        rank: Int, profileId: UUID = UUID(), displayName: String, avatarURL: URL? = nil,
        wins: Int, gamesPlayed: Int, isMe: Bool = false, rankedCount: Int, username: String? = nil
    ) {
        self.rank = rank
        self.profileId = profileId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.wins = wins
        self.gamesPlayed = gamesPlayed
        self.isMe = isMe
        self.rankedCount = rankedCount
        self.username = username
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decode(Int.self, forKey: .rank)
        profileId = try c.decode(UUID.self, forKey: .profileId)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL).flatMap(URL.init(string:))
        wins = try c.decode(Int.self, forKey: .wins)
        gamesPlayed = try c.decode(Int.self, forKey: .gamesPlayed)
        isMe = try c.decode(Bool.self, forKey: .isMe)
        rankedCount = try c.decode(Int.self, forKey: .rankedCount)
        username = try c.decodeIfPresent(String.self, forKey: .username)
    }
}

/// Where the caller stands on the wins board — the one row `my_gamer_standing` returns.
struct GamerStanding: Decodable, Equatable, Sendable {
    let status: LeaderboardStanding.Status
    let rank: Int?
    let wins: Int
    let gamesPlayed: Int
    let rankedCount: Int
    let minWins: Int

    private enum CodingKeys: String, CodingKey {
        case status, rank, wins
        case gamesPlayed = "games_played"
        case rankedCount = "ranked_count"
        case minWins = "min_wins"
    }

    init(status: LeaderboardStanding.Status, rank: Int? = nil, wins: Int = 0, gamesPlayed: Int = 0, rankedCount: Int = 0, minWins: Int = 1) {
        self.status = status
        self.rank = rank
        self.wins = wins
        self.gamesPlayed = gamesPlayed
        self.rankedCount = rankedCount
        self.minWins = minWins
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // A status this build doesn't know reads as unranked, same as the web.
        status = LeaderboardStanding.Status(rawValue: try c.decode(String.self, forKey: .status)) ?? .unranked
        rank = try c.decodeIfPresent(Int.self, forKey: .rank)
        wins = try c.decode(Int.self, forKey: .wins)
        gamesPlayed = try c.decode(Int.self, forKey: .gamesPlayed)
        rankedCount = try c.decode(Int.self, forKey: .rankedCount)
        minWins = try c.decode(Int.self, forKey: .minWins)
    }
}

/// One ranked player on a solo board — a row of `solo_leaderboard`.
struct SoloRow: Decodable, Equatable, Sendable {
    let rank: Int
    let profileId: UUID
    let displayName: String
    let avatarURL: URL?
    let bestScore: Double
    let isMe: Bool
    let rankedCount: Int
    let username: String?

    private enum CodingKeys: String, CodingKey {
        case rank
        case profileId = "profile_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case bestScore = "best_score"
        case isMe = "is_me"
        case rankedCount = "ranked_count"
        case username
    }

    init(
        rank: Int, profileId: UUID = UUID(), displayName: String, avatarURL: URL? = nil,
        bestScore: Double, isMe: Bool = false, rankedCount: Int, username: String? = nil
    ) {
        self.rank = rank
        self.profileId = profileId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.bestScore = bestScore
        self.isMe = isMe
        self.rankedCount = rankedCount
        self.username = username
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.decode(Int.self, forKey: .rank)
        profileId = try c.decode(UUID.self, forKey: .profileId)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL).flatMap(URL.init(string:))
        bestScore = try c.decode(Double.self, forKey: .bestScore)
        isMe = try c.decode(Bool.self, forKey: .isMe)
        rankedCount = try c.decode(Int.self, forKey: .rankedCount)
        username = try c.decodeIfPresent(String.self, forKey: .username)
    }
}

/// Where the caller stands on a solo board — the one row `my_solo_standing`
/// returns. `bestScore` is nil until they have a recorded best.
struct SoloStanding: Decodable, Equatable, Sendable {
    let status: LeaderboardStanding.Status
    let rank: Int?
    let bestScore: Double?
    let rankedCount: Int

    private enum CodingKeys: String, CodingKey {
        case status, rank
        case bestScore = "best_score"
        case rankedCount = "ranked_count"
    }

    init(status: LeaderboardStanding.Status, rank: Int? = nil, bestScore: Double? = nil, rankedCount: Int = 0) {
        self.status = status
        self.rank = rank
        self.bestScore = bestScore
        self.rankedCount = rankedCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = LeaderboardStanding.Status(rawValue: try c.decode(String.self, forKey: .status)) ?? .unranked
        rank = try c.decodeIfPresent(Int.self, forKey: .rank)
        bestScore = try c.decodeIfPresent(Double.self, forKey: .bestScore)
        rankedCount = try c.decode(Int.self, forKey: .rankedCount)
    }
}

// MARK: - What the screen shows

/// One row as the screen draws it, whichever board it came from.
struct BoardEntry: Equatable, Identifiable, Sendable {
    let rank: Int
    let profileId: UUID
    let displayName: String
    let avatarURL: URL?
    let isMe: Bool
    /// The username to open this row's profile with: none for yourself or when the server sent none.
    let profileUsername: String?
    /// The small line under the name ("12 picks", "30 games"); nil when a board has none.
    let detail: String?
    /// The ranked number, formatted.
    let value: String
    /// What VoiceOver reads for the whole row.
    let spoken: String

    var id: UUID { profileId }

    init(_ row: LeaderboardRow) {
        rank = row.rank
        profileId = row.profileId
        displayName = row.displayName
        avatarURL = row.avatarURL
        isMe = row.isMe
        profileUsername = row.profileUsername
        detail = "\(row.scoredPicks) picks"
        value = row.totalPoints.formatted()
        spoken = "Rank \(row.rank), \(row.displayName)\(row.isMe ? ", you" : ""), \(row.totalPoints) points, \(row.scoredPicks) picks"
    }

    init(_ row: GamerRow) {
        rank = row.rank
        profileId = row.profileId
        displayName = row.displayName
        avatarURL = row.avatarURL
        isMe = row.isMe
        profileUsername = row.isMe ? nil : row.username
        detail = "\(row.gamesPlayed) \(row.gamesPlayed == 1 ? "game" : "games")"
        value = row.wins.formatted()
        spoken = "Rank \(row.rank), \(row.displayName)\(row.isMe ? ", you" : ""), \(row.wins) \(row.wins == 1 ? "win" : "wins"), \(row.gamesPlayed) \(row.gamesPlayed == 1 ? "game" : "games")"
    }

    init(_ row: SoloRow, board: LeaderboardBoard) {
        rank = row.rank
        profileId = row.profileId
        displayName = row.displayName
        avatarURL = row.avatarURL
        isMe = row.isMe
        profileUsername = row.isMe ? nil : row.username
        detail = nil
        value = Self.formatScore(row.bestScore, board: board)
        spoken = "Rank \(row.rank), \(row.displayName)\(row.isMe ? ", you" : ""), \(value)"
    }

    /// A streak is a whole number; a QB score always keeps its one decimal (91.0, 80.5).
    static func formatScore(_ score: Double, board: LeaderboardBoard) -> String {
        board == .qbSeasonBuilder
            ? score.formatted(.number.precision(.fractionLength(1)))
            : Int(score).formatted()
    }
}

/// The caller's own place, as the screen draws it.
struct BoardStanding: Equatable, Sendable {
    let isRanked: Bool
    let rank: Int?
    /// The caller's number ("3" wins, "91.0"); nil when they have none on this board.
    let value: String?
    let rankedCount: Int
    let headline: String
    let detail: String
    /// What the empty states say a player needs to appear, e.g. "1 win".
    let floor: String?

    init(_ standing: GamerStanding, scope: LeaderboardScope) {
        isRanked = standing.status == .ranked && standing.rank != nil
        rank = standing.rank
        value = standing.wins.formatted()
        rankedCount = standing.rankedCount
        floor = "\(standing.minWins) multiplayer \(standing.minWins == 1 ? "win" : "wins")"
        if let rank = standing.rank, isRanked {
            headline = "#\(rank)"
            detail = Self.rankedDetail(rank: rank, rankedCount: standing.rankedCount, scope: scope)
        } else {
            headline = "Not ranked yet"
            detail = "Win a multiplayer game in this window to join the board"
        }
    }

    init(_ standing: SoloStanding, board: LeaderboardBoard, scope: LeaderboardScope) {
        isRanked = standing.status == .ranked && standing.rank != nil
        rank = standing.rank
        value = standing.bestScore.map { BoardEntry.formatScore($0, board: board) }
        rankedCount = standing.rankedCount
        floor = nil
        if let rank = standing.rank, isRanked {
            headline = "#\(rank)"
            detail = Self.rankedDetail(rank: rank, rankedCount: standing.rankedCount, scope: scope)
        } else {
            headline = "Not ranked yet"
            detail = "Finish a solo run to put a score on this board"
        }
    }

    /// "Top N%" on the everyone board (rounded up, so a player is never shown a
    /// better band than they hold); a plain "2 of 5" among friends, which is
    /// too small a group for a band to mean anything.
    static func rankedDetail(rank: Int, rankedCount: Int, scope: LeaderboardScope) -> String {
        switch scope {
        case .all:
            let band = rankedCount > 0 ? Int((Double(rank * 100) / Double(rankedCount)).rounded(.up)) : 100
            return "Top \(band)% of \(rankedCount.formatted()) ranked players"
        case .friends:
            return "Ranked \(rank) of \(rankedCount.formatted()) on your friends board"
        }
    }
}
