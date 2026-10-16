import Foundation

// The Profile tab's "what have I done" numbers — the mirror of
// `webapp/lib/foundation/identity/summary.ts` plus the two RPCs it reads
// (`my_match_history`, migration 0085; `my_profile_knower_highlights`,
// migrations 0107–0109). Same two-layer shape as `PromptModels`: `*Row` is
// what PostgREST prints, the rest is what the Profile tab reads.

/// `public.run_mode` — which kind of run a completed match came out of.
enum RunMode: String, Equatable, Sendable {
    case arcade, party, solo
}

/// One of the caller's own completed matches, resolved into a game and mode
/// this app knows.
struct CompletedMatch: Equatable, Sendable {
    let game: MatchGame
    let endedAt: Date
    let placement: Int?
    let mode: RunMode
}

/// The reporting windows the Profile tab's highlights card switches between —
/// `ProfileStatRange` in `summary.ts`.
enum ProfileStatRange: String, CaseIterable, Equatable, Sendable {
    case lifetime, year, month, week

    var label: String {
        switch self {
        case .lifetime: "Lifetime"
        case .year: "Year"
        case .month: "Month"
        case .week: "Week"
        }
    }

    /// How the "total points" tile explains a non-lifetime range.
    var windowLabel: String {
        switch self {
        case .lifetime: "All-time prediction points"
        case .year: "Last 365 days"
        case .month: "Last 30 days"
        case .week: "Last 7 days"
        }
    }

    /// The rolling window's length; `nil` for `.lifetime`, which has none.
    fileprivate var days: Double? {
        switch self {
        case .lifetime: nil
        case .year: 365
        case .month: 30
        case .week: 7
        }
    }
}

/// A window's worth of Ball Knower prompt scoring.
struct KnowerHighlight: Equatable, Sendable {
    static let empty = KnowerHighlight(totalPoints: 0, percentile: nil)

    let totalPoints: Int
    /// 1–100, higher is better; `nil` until a resolved pick has scored.
    let percentile: Int?
    /// The server's split of `totalPoints`; likes are net of dislikes, so
    /// `likePoints` can be negative.
    let pickPoints: Int
    let likePoints: Int

    init(totalPoints: Int, percentile: Int?, pickPoints: Int = 0, likePoints: Int = 0) {
        self.totalPoints = totalPoints
        self.percentile = percentile
        self.pickPoints = pickPoints
        self.likePoints = likePoints
    }
}

extension KnowerHighlight {
    /// "Rookie" through "Ball god", from a lifetime percentile: mirrors the
    /// web's `KnowerStatus`. Only meaningful for the lifetime window.
    var status: String {
        guard let percentile else { return "Unranked" }
        switch percentile {
        case ..<20: return "Rookie"
        case ..<40: return "Casual"
        case ..<60: return "Fan"
        case ..<80: return "Ball knower"
        default: return "Ball god"
        }
    }

    /// What sits under the status; `unrankedDetail` is the no-percentile
    /// line, which differs between your own profile and someone else's.
    func statusDetail(unrankedDetail: String) -> String {
        guard let percentile else { return unrankedDetail }
        return "\(percentile.ordinal) percentile"
    }
}

/// Multiplayer results. The web only ever shows the lifetime window for this
/// half of the card, so unlike `KnowerHighlight` there is no per-range table.
struct GamerHighlight: Equatable, Sendable {
    static let empty = GamerHighlight(gamesPlayed: 0, wins: 0, winRate: 0)

    let gamesPlayed: Int
    let wins: Int
    let winRate: Int
}

/// Pure summary math, kept apart from any network read so it is exercised the
/// same way the web's `summary.ts` functions are: against plain values.
enum ProfileStats {
    /// A rolling window ending `now` — the same "always current" windows
    /// `my_profile_knower_highlights` computes server-side.
    static func matches(_ matches: [CompletedMatch], in range: ProfileStatRange, now: Date) -> [CompletedMatch] {
        guard let days = range.days else { return matches }
        let startsAt = now.addingTimeInterval(-days * 86400)
        return matches.filter { $0.endedAt >= startsAt }
    }

    /// Multiplayer wins are a separate measure from a solo score: solo
    /// matches count toward a player's history but have no opponent to beat.
    static func gamerHighlight(_ matches: [CompletedMatch], in range: ProfileStatRange, now: Date) -> GamerHighlight {
        let played = Self.matches(matches, in: range, now: now).filter { $0.mode != .solo }
        let wins = played.filter { $0.placement == 1 }.count
        let winRate = played.isEmpty ? 0 : Int((Double(wins) / Double(played.count) * 100).rounded())
        return GamerHighlight(gamesPlayed: played.count, wins: wins, winRate: winRate)
    }
}

// MARK: - Rows

/// One row of `my_match_history` (migration 0085). Every field is nullable at
/// the type level the way the web's `ProfileHistoryRow` is, even though only
/// a stale read should ever actually miss one.
struct ProfileMatchHistoryRow: Decodable, Equatable, Sendable {
    let matchId: UUID?
    let game: String?
    let endedAt: Date?
    let placement: Int?
    let mode: String?

    private enum CodingKeys: String, CodingKey {
        case matchId = "match_id", game, endedAt = "ended_at", placement, mode
    }

    init(matchId: UUID? = nil, game: String? = nil, endedAt: Date? = nil, placement: Int? = nil, mode: String? = nil) {
        self.matchId = matchId
        self.game = game
        self.endedAt = endedAt
        self.placement = placement
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try c.decodeIfPresent(UUID.self, forKey: .matchId)
        game = try c.decodeIfPresent(String.self, forKey: .game)
        endedAt = try c.decodeTimestampIfPresent(forKey: .endedAt)
        placement = try c.decodeIfPresent(Int.self, forKey: .placement)
        mode = try c.decodeIfPresent(String.self, forKey: .mode)
    }

    /// `nil` when the row is missing a field the app needs, or names a game
    /// or mode it doesn't know — the same call `completedMatchesFromHistory`
    /// makes on the web.
    var completed: CompletedMatch? {
        guard let game, let matchGame = MatchGame(rawValue: game),
              let endedAt, let mode, let runMode = RunMode(rawValue: mode)
        else { return nil }
        return CompletedMatch(game: matchGame, endedAt: endedAt, placement: placement, mode: runMode)
    }
}

/// One row of `my_profile_knower_highlights` (migrations 0107–0109) — already
/// one row per reporting window, so no joining is needed here.
struct ProfileKnowerHighlightRow: Decodable, Equatable, Sendable {
    let windowKey: String
    let totalPoints: Int
    let percentile: Int?
    let pickPoints: Int
    let likePoints: Int

    private enum CodingKeys: String, CodingKey {
        case windowKey = "window_key", totalPoints = "total_points", percentile
        case pickPoints = "pick_points", likePoints = "like_points"
    }

    init(windowKey: String, totalPoints: Int, percentile: Int? = nil, pickPoints: Int = 0, likePoints: Int = 0) {
        self.windowKey = windowKey
        self.totalPoints = totalPoints
        self.percentile = percentile
        self.pickPoints = pickPoints
        self.likePoints = likePoints
    }
}
