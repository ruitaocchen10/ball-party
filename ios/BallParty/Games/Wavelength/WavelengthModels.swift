import Foundation

// Hand-maintained `Codable` mirrors of the `wavelength` schema's rows and RPC
// results, and the pure dial rules the screen derives from them. Same deal as
// `AuctionModels.swift`: there is no Postgres-to-Swift codegen, so a column
// added on the server has to be added here on purpose.
//
// `webapp/lib/games/wavelength/board.ts` is the reference. Everything computed
// here is *display* — where a needle is drawn, which wedge a reveal lights —
// never a rule. The server scores a locked guess and enforces the clue limits
// again when a move arrives.

/// A failed Wavelength RPC, reduced to what a screen can act on: the message.
struct WavelengthServerError: Error, Equatable, Sendable {
    let message: String

    /// The raised message as a sentence for the player. Anything unmapped
    /// surfaces raw rather than being flattened into a friendly lie.
    static func describe(_ error: Error) -> String {
        guard let server = error as? WavelengthServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        return messages[server.message] ?? server.message
    }

    static let messages: [String: String] = [
        "clue_required": "Write a clue before locking it in.",
        "clue_contains_digit": "Clues cannot contain digits.",
        "clue_too_many_words": "Keep your clue to \(WavelengthRules.clueMaxWords) words or fewer.",
        "clue_too_long": "Keep your clue to \(WavelengthRules.clueMaxChars) characters or fewer.",
        "clue_deadline_passed": "Time ran out before that clue landed.",
        "guess_deadline_passed": "Time ran out before that guess landed.",
        "not_guesser": "It isn't your turn to guess.",
        "match_not_playing": "This game isn't accepting moves right now.",
        "not_a_participant": "You're not in this game.",
        "not_authenticated": "Sign in first.",
        "not_host": "Only the host can choose what's next.",
        "match_not_complete": "This game is still in progress.",
        "post_game_choice_already_made": "The next game has already been chosen.",
        "wrong_player_count": "Co-op needs two players and 2v2 needs four.",
        "invalid_mode": "Choose co-op or 2v2.",
        "invalid_preset": "Choose a co-op length.",
    ]
}

// MARK: - Format

enum WavelengthMode: String, Sendable, CaseIterable, Identifiable, Decodable {
    case coop, versus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .coop: "Co-op"
        case .versus: "2v2"
        }
    }

    /// How many players the mode seats; the lobby refuses to start otherwise.
    var playerCount: Int {
        switch self {
        case .coop: 2
        case .versus: 4
        }
    }
}

/// Co-op length. The target and star lines are the server's config, restated
/// here only so the result screen can show the score against its maximum.
enum WavelengthPreset: String, Sendable, CaseIterable, Identifiable, Decodable {
    case short, medium, long

    var id: String { rawValue }

    var label: String {
        switch self {
        case .short: "Short · 4 rounds · target 8"
        case .medium: "Medium · 6 rounds · target 12"
        case .long: "Long · 8 rounds · target 20"
        }
    }

    var shortLabel: String {
        switch self {
        case .short: "Short"
        case .medium: "Medium"
        case .long: "Long"
        }
    }

    var maxScore: Int {
        switch self {
        case .short: 16
        case .medium: 24
        case .long: 32
        }
    }
}

// MARK: - Rules (display only)

enum WavelengthRules {
    static let clueMaxChars = 100
    static let clueMaxWords = 8
    static let scaleMax = 1000
    static let wedgeWidth = 40
    /// The dial starts every round from the middle.
    static let needleStart = 500

    /// The same checks the server makes, so a clue can be refused before the
    /// trip rather than after it. `nil` means it passes.
    static func validateClue(_ raw: String) -> String? {
        let clue = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if clue.isEmpty { return "Write a clue before locking it in." }
        if clue.contains(where: \.isNumber) { return "Clues cannot contain digits." }
        if clue.count > clueMaxChars { return "Keep your clue to \(clueMaxChars) characters or fewer." }
        if wordCount(clue) > clueMaxWords { return "Keep your clue to \(clueMaxWords) words or fewer." }
        return nil
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    struct Wedge: Equatable, Sendable {
        let points: Int
        let from: Int
        let to: Int
    }

    /// Five symmetric scoring bands around a server-revealed target, clipped to
    /// the dial. 2 / 3 / 4 / 3 / 2.
    static func scoringWedges(target: Int, width: Int = wedgeWidth) -> [Wedge] {
        let half = Double(width) / 2
        let center = Double(target)
        let edges: [(Int, Double, Double)] = [
            (2, center - half * 5, center - half * 3),
            (3, center - half * 3, center - half),
            (4, center - half, center + half),
            (3, center + half, center + half * 3),
            (2, center + half * 3, center + half * 5),
        ]
        return edges.map { points, from, to in
            // Clamp both ends, so a wedge that falls wholly off the dial has no width.
            let low = min(max(from, 0), Double(scaleMax))
            let high = min(max(to, 0), Double(scaleMax))
            return Wedge(points: points, from: Int(low.rounded()), to: Int(high.rounded()))
        }
    }

    static func score(position: Int, target: Int, width: Int = wedgeWidth) -> Int {
        let distance = abs(Double(position - target))
        let w = Double(width)
        if distance <= w / 2 { return 4 }
        if distance <= w * 3 / 2 { return 3 }
        return distance <= w * 5 / 2 ? 2 : 0
    }

    /// What a locked round earned, in words.
    static func reaction(points: Int?, skipped: Bool) -> String {
        if skipped { return "Clue skipped" }
        switch points {
        case 4: return "Bullseye!"
        case 3: return "So close!"
        case 2: return "In the zone"
        default: return "Off the mark"
        }
    }

    /// The dial is a half circle drawn left to right; position 0 is the left
    /// end. Angles are measured the way the web does, in radians from the
    /// positive x axis, so `angle(for:)` of 0 is π (left) and of 1000 is 0.
    static func angle(for position: Int) -> Double {
        Double.pi * (1 - Double(position) / Double(scaleMax))
    }

    /// The position a touch at `(dx, dy)` from the pivot is aiming at, with y
    /// growing downward as in screen space. Below the baseline it snaps to
    /// whichever end is nearer, like `dialPosition` on the web.
    static func position(dx: Double, dy: Double) -> Int {
        let angle = atan2(-dy, dx)
        let above = angle >= 0 ? angle : (dx < 0 ? Double.pi : 0)
        let value = Int(((1 - above / Double.pi) * Double(scaleMax)).rounded())
        return min(max(value, 0), scaleMax)
    }

    /// Team label: the lone co-op team is "Your team".
    static func teamName(_ team: Int, mode: WavelengthMode) -> String {
        mode == .coop ? "Your team" : "Team \(team + 1)"
    }

    /// Stable order for a round's rows on the Rounds tab.
    static func settled(_ round: WavelengthRound) -> Bool {
        round.status == .locked || round.status == .skipped
    }
}

// MARK: - Rows

/// `wavelength.state()` — the public projection of the match.
struct WavelengthBoard: Equatable, Sendable, Decodable {
    enum Phase: String, Sendable, Decodable { case fill, guess, reveal, complete }

    let matchId: UUID
    let mode: WavelengthMode
    let preset: WavelengthPreset?
    let roundCount: Int
    let currentRound: Int
    let phase: Phase
    let phaseDeadline: Date?
    let serverNow: Date
    /// Ordered by team; co-op has one entry.
    let teamScores: [Int]

    private enum CodingKeys: String, CodingKey {
        case matchId = "match_id"
        case mode, preset
        case roundCount = "round_count"
        case currentRound = "current_round"
        case phase
        case phaseDeadline = "phase_deadline"
        case serverNow = "server_now"
        case teamScores = "team_scores"
    }

    init(
        matchId: UUID, mode: WavelengthMode, preset: WavelengthPreset? = nil, roundCount: Int, currentRound: Int,
        phase: Phase, phaseDeadline: Date? = nil, serverNow: Date, teamScores: [Int]
    ) {
        self.matchId = matchId
        self.mode = mode
        self.preset = preset
        self.roundCount = roundCount
        self.currentRound = currentRound
        self.phase = phase
        self.phaseDeadline = phaseDeadline
        self.serverNow = serverNow
        self.teamScores = teamScores
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try container.decode(UUID.self, forKey: .matchId)
        mode = try container.decode(WavelengthMode.self, forKey: .mode)
        preset = try container.decodeIfPresent(WavelengthPreset.self, forKey: .preset)
        roundCount = try container.decode(Int.self, forKey: .roundCount)
        currentRound = try container.decode(Int.self, forKey: .currentRound)
        phase = try container.decode(Phase.self, forKey: .phase)
        phaseDeadline = try container.decodeIfPresent(Date.self, forKey: .phaseDeadline)
        serverNow = try container.decode(Date.self, forKey: .serverNow)
        teamScores = try container.decodeIfPresent([Int].self, forKey: .teamScores) ?? []
    }
}

/// `public.wavelength_players` joined to the profile.
struct WavelengthPlayer: Equatable, Sendable, Decodable, Identifiable {
    let userId: UUID
    let seat: Int
    let team: Int
    let absent: Bool
    let name: String
    let avatarURL: URL?

    var id: UUID { userId }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case seat, team, absent, profiles
    }

    private struct Profile: Decodable {
        let displayName: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarURL = "avatar_url"
        }
    }

    init(userId: UUID, seat: Int, team: Int, absent: Bool = false, name: String = "Unknown player", avatarURL: URL? = nil) {
        self.userId = userId
        self.seat = seat
        self.team = team
        self.absent = absent
        self.name = name
        self.avatarURL = avatarURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        seat = try container.decode(Int.self, forKey: .seat)
        team = try container.decode(Int.self, forKey: .team)
        absent = try container.decodeIfPresent(Bool.self, forKey: .absent) ?? false
        let profile = try container.decodeIfPresent(Profile.self, forKey: .profiles)
        name = profile?.displayName ?? "Unknown player"
        avatarURL = profile?.avatarURL.flatMap(URL.init(string:))
    }

    /// A replicated row carries no profile, so it takes the identity of the
    /// row it replaces.
    func named(like existing: WavelengthPlayer) -> WavelengthPlayer {
        WavelengthPlayer(userId: userId, seat: seat, team: team, absent: absent, name: existing.name, avatarURL: existing.avatarURL)
    }
}

/// `public.wavelength_rounds`.
struct WavelengthRound: Equatable, Sendable, Decodable, Identifiable {
    enum Status: String, Sendable, Decodable { case pending, open, locked, skipped }

    let round: Int
    let psychicId: UUID
    let guesserId: UUID
    let status: Status
    let points: Int?
    /// Present only once the server has locked or skipped the round.
    let revealedTarget: Int?
    /// Where the guess was locked; `nil` until then, and for a skipped round.
    let guessPosition: Int?

    var id: Int { round }

    private enum CodingKeys: String, CodingKey {
        case round
        case psychicId = "psychic_id"
        case guesserId = "guesser_id"
        case status, points
        case revealedTarget = "revealed_target"
        case guessPosition = "guess_position"
    }

    init(
        round: Int, psychicId: UUID, guesserId: UUID, status: Status = .pending, points: Int? = nil,
        revealedTarget: Int? = nil, guessPosition: Int? = nil
    ) {
        self.round = round
        self.psychicId = psychicId
        self.guesserId = guesserId
        self.status = status
        self.points = points
        self.revealedTarget = revealedTarget
        self.guessPosition = guessPosition
    }
}

/// `public.wavelength_cards` — the two ends of a round's spectrum. Row-level
/// security shows a card to its psychic until the round opens for guessing.
struct WavelengthCard: Equatable, Sendable, Decodable {
    let round: Int
    let leftLabel: String
    let rightLabel: String

    private enum CodingKeys: String, CodingKey {
        case round
        case leftLabel = "left_label"
        case rightLabel = "right_label"
    }
}

/// `public.wavelength_clues` — a clue, visible to its psychic and then, once
/// the round opens, to the table.
struct WavelengthClue: Equatable, Sendable, Decodable {
    let round: Int
    let clue: String
}

/// `public.wavelength_clue_statuses` — "this round's clue is written", with
/// the clue itself withheld.
struct WavelengthClueStatus: Equatable, Sendable, Decodable {
    let round: Int
}

/// `public.wavelength_targets` — only the rows the viewer is the psychic for.
struct WavelengthTarget: Equatable, Sendable, Decodable {
    let round: Int
    let target: Int
}

/// `public.wavelength_results`.
struct WavelengthResult: Equatable, Sendable, Decodable {
    let mode: WavelengthMode
    let preset: WavelengthPreset?
    let outcome: String
    let score: Int
    let bullseyes: Int
    let stars: Int?

    var won: Bool { outcome == "win" }
}

/// Everything one full read of the match returns.
struct WavelengthSnapshot: Equatable, Sendable {
    var board: WavelengthBoard
    var players: [WavelengthPlayer]
    var rounds: [WavelengthRound]
    var cards: [WavelengthCard]
    var clues: [WavelengthClue]
    var clueStatuses: [WavelengthClueStatus]
    var targets: [WavelengthTarget]
    var result: WavelengthResult?
    var matchStatus: MatchStatus
    var postGame: PostGameAction?
}

/// What the match's channels deliver.
enum WavelengthEvent: Sendable {
    /// A channel (re)joined: re-read everything.
    case subscribed
    /// Any table behind the board changed. Wavelength re-reads rather than
    /// merging — rows are few and the privacy split between tables makes a
    /// partial merge easy to get wrong.
    case changed
    case matchStatus(MatchStatus)
    case postGame(PostGameAction)
    /// Another player's needle, live. Cosmetic and best-effort.
    case needle(round: Int, position: Int)
}
