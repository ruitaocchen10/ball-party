import Foundation

// Hand-maintained `Codable` mirrors of the shapes in
// `docs/architecture/game-runtime.md` ("Higher or Lower's write API" and
// "tables"). There is no Postgres-to-Swift codegen, so a column added on the
// server has to be added here on purpose — the web equivalent is
// `webapp/lib/games/higher-or-lower/board.ts` over `database.types.ts`.

enum HigherOrLowerPhase: String, Decodable, Sendable {
    case boardIntro = "board_intro"
    case call
    case reveal
    case suddenDeathCall = "sudden_death_call"
    case suddenDeathReveal = "sudden_death_reveal"
    case complete

    /// A card's points are only ever shown from its reveal onward. The server
    /// already withholds them until then (they are `null` in the row); this is
    /// the same guard the web keeps against a card update racing the phase.
    var showsChallengerPoints: Bool {
        self == .reveal || self == .suddenDeathReveal || self == .complete
    }
}

enum ScoringMode: String, Decodable, Sendable, CaseIterable, Identifiable {
    case seasonTotal = "season_total"
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .seasonTotal: "Season total"
        case .weekly: "Weekly"
        }
    }

    var summary: String {
        switch self {
        case .seasonTotal: "Whole-season PPR points"
        case .weekly: "A single game's PPR points"
        }
    }
}

enum CallDirection: String, Codable, Sendable {
    case higher
    case lower
}

/// An inclusive span of NFL seasons — the era a ladder is dealt from.
struct SeasonRange: Equatable, Sendable {
    var from: Int
    var to: Int

    var label: String { from == to ? "\(from)" : "\(from)–\(to)" }
}

/// `higher_or_lower.board`: every RPC that returns board state returns this.
struct HigherOrLowerBoard: Equatable, Sendable, Decodable {
    let matchId: UUID
    let questionCount: Int
    let spareCount: Int
    let currentQuestion: Int
    let scoringMode: ScoringMode
    let seasonFrom: Int
    let seasonTo: Int
    let phase: HigherOrLowerPhase
    /// `nil` whenever nothing is timed — which is the entire duration of a solo
    /// match (`0084`) and any finished match.
    let phaseDeadline: Date?
    /// `now()` on the server at read time; feeds the clock's offset measurement.
    let serverNow: Date

    var season: SeasonRange { SeasonRange(from: seasonFrom, to: seasonTo) }

    /// Everything but `serverNow`, which changes on every read: two boards that
    /// agree on this describe the same game position.
    func samePosition(as other: HigherOrLowerBoard) -> Bool {
        matchId == other.matchId && currentQuestion == other.currentQuestion && phase == other.phase
            && phaseDeadline == other.phaseDeadline
    }

    private enum CodingKeys: String, CodingKey {
        case matchId = "match_id"
        case questionCount = "question_count"
        case spareCount = "spare_count"
        case currentQuestion = "current_question"
        case scoringMode = "scoring_mode"
        case seasonFrom = "season_from"
        case seasonTo = "season_to"
        case phase
        case phaseDeadline = "phase_deadline"
        case serverNow = "server_now"
    }

    init(
        matchId: UUID,
        questionCount: Int,
        spareCount: Int,
        currentQuestion: Int,
        scoringMode: ScoringMode,
        seasonFrom: Int,
        seasonTo: Int,
        phase: HigherOrLowerPhase,
        phaseDeadline: Date?,
        serverNow: Date
    ) {
        self.matchId = matchId
        self.questionCount = questionCount
        self.spareCount = spareCount
        self.currentQuestion = currentQuestion
        self.scoringMode = scoringMode
        self.seasonFrom = seasonFrom
        self.seasonTo = seasonTo
        self.phase = phase
        self.phaseDeadline = phaseDeadline
        self.serverNow = serverNow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try container.decode(UUID.self, forKey: .matchId)
        questionCount = try container.decode(Int.self, forKey: .questionCount)
        spareCount = try container.decode(Int.self, forKey: .spareCount)
        currentQuestion = try container.decode(Int.self, forKey: .currentQuestion)
        scoringMode = try container.decode(ScoringMode.self, forKey: .scoringMode)
        seasonFrom = try container.decode(Int.self, forKey: .seasonFrom)
        seasonTo = try container.decode(Int.self, forKey: .seasonTo)
        phase = try container.decode(HigherOrLowerPhase.self, forKey: .phase)
        phaseDeadline = try container.decodeIfPresent(String.self, forKey: .phaseDeadline)
            .map { try PostgresTimestamp.parse($0) }
        serverNow = try PostgresTimestamp.parse(try container.decode(String.self, forKey: .serverNow))
    }
}

/// One row of `higher_or_lower_cards`. `points` is `nil` until that card's
/// question reveals — withheld by the server, not by this client.
struct LadderCard: Equatable, Sendable, Decodable, Identifiable {
    let ordinal: Int
    let playerId: String
    let displayName: String
    let position: String
    let season: Int
    let team: String
    /// Weekly-mode recall cues; `nil` in season-total mode.
    let week: Int?
    let opponent: String?
    let headshotUrl: String?
    let points: Double?

    var id: Int { ordinal }

    /// Weekly cards place a specific game; season cards are a whole season and
    /// have no honest week or opponent.
    var identityLine: String {
        guard let week, let opponent else { return "\(season) · \(team)" }
        return "\(season) · Week \(week) · \(team) vs. \(opponent)"
    }

    func concealingPoints() -> LadderCard {
        LadderCard(
            ordinal: ordinal, playerId: playerId, displayName: displayName, position: position,
            season: season, team: team, week: week, opponent: opponent, headshotUrl: headshotUrl,
            points: nil
        )
    }

    init(
        ordinal: Int, playerId: String, displayName: String, position: String, season: Int,
        team: String, week: Int? = nil, opponent: String? = nil, headshotUrl: String? = nil,
        points: Double?
    ) {
        self.ordinal = ordinal
        self.playerId = playerId
        self.displayName = displayName
        self.position = position
        self.season = season
        self.team = team
        self.week = week
        self.opponent = opponent
        self.headshotUrl = headshotUrl
        self.points = points
    }

    private enum CodingKeys: String, CodingKey {
        case ordinal
        case playerId = "player_id"
        case displayName = "display_name"
        case position, season, team, week, opponent
        case headshotUrl = "headshot_url"
        case points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ordinal = try container.decode(Int.self, forKey: .ordinal)
        playerId = try container.decode(String.self, forKey: .playerId)
        displayName = try container.decode(String.self, forKey: .displayName)
        position = try container.decode(String.self, forKey: .position)
        season = try container.decode(Int.self, forKey: .season)
        team = try container.decode(String.self, forKey: .team)
        week = try container.decodeIfPresent(Int.self, forKey: .week)
        opponent = try container.decodeIfPresent(String.self, forKey: .opponent)
        headshotUrl = try container.decodeIfPresent(String.self, forKey: .headshotUrl)
        points = try container.decodeNumericIfPresent(forKey: .points)
    }
}

/// One row of `higher_or_lower_players` — the viewer's tallies.
struct LadderPlayer: Equatable, Sendable, Decodable {
    let userId: UUID
    let currentStreak: Int
    let bestStreak: Int
    let correctCount: Int

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case correctCount = "correct_count"
    }
}

/// One row of `higher_or_lower_calls`. `direction` is `nil` for the miss the
/// server writes when a question runs out of time (`timedOut`).
struct LadderCall: Equatable, Sendable, Decodable {
    let question: Int
    let userId: UUID
    let direction: CallDirection?
    let timedOut: Bool

    private enum CodingKeys: String, CodingKey {
        case question
        case userId = "user_id"
        case direction
        case timedOut = "timed_out"
    }
}

/// Everything a screen needs to render one moment of a match — the projection
/// the web's `refetch` assembles from six queries. Always read as a set, so a
/// screen never shows a board from one moment beside cards from another.
struct HigherOrLowerSnapshot: Equatable, Sendable {
    let board: HigherOrLowerBoard
    let cards: [LadderCard]
    let players: [LadderPlayer]
    let calls: [LadderCall]
}

// MARK: - Decoding helpers

/// Postgres `timestamptz` as PostgREST prints it: `2026-08-15T12:00:00.123456+00:00`
/// — microsecond fractions, sometimes none, `+00:00` or `Z`. Kept as its own
/// parser so nothing depends on a Foundation formatter's tolerance for more
/// than three fractional digits.
enum PostgresTimestamp {
    struct Malformed: Error { let value: String }

    static func parse(_ value: String) throws -> Date {
        // Foundation's fractional-seconds parser is dependable at millisecond
        // precision; trim anything beyond it.
        let trimmed = value.replacingOccurrences(
            of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression
        )
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: trimmed) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: trimmed) { return date }
        throw Malformed(value: value)
    }
}

extension KeyedDecodingContainer {
    /// Postgres `numeric` arrives as a JSON number from PostgREST, but as a
    /// string from some paths (the web's `formatPoints` accepts both) — take
    /// either.
    fileprivate func decodeNumericIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let number = try? decode(Double.self, forKey: key) { return number }
        let text = try decode(String.self, forKey: key)
        guard let number = Double(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not a number: \(text)")
        }
        return number
    }
}
