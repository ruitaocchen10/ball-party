import Foundation

// Hand-maintained `Codable` mirrors of the `sabotage_draft` schema's rows and RPC
// results, and the pure display rules the screen derives from them. Same deal as
// `AuctionModels.swift` and `WavelengthModels.swift`: there is no Postgres-to-
// Swift codegen, so a column added on the server has to be added here on purpose.
//
// `webapp/lib/games/sabotage-draft/{rounds,grades}.ts` are the reference.
// Everything computed here is *display* — which slot a round is, what letter a
// pick earns — never a rule. The server deals the spins, checks every pick and
// guess against the pool, resolves the hits and simulates the season.

/// A failed Sabotage Draft RPC, reduced to what a screen can act on: the message.
struct SabotageServerError: Error, Equatable, Sendable {
    let message: String

    /// The raised message as a sentence for the player. Anything unmapped
    /// surfaces raw rather than being flattened into a friendly lie.
    static func describe(_ error: Error) -> String {
        guard let server = error as? SabotageServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        return messages[server.message] ?? server.message
    }

    static let messages: [String: String] = [
        "already_picked": "Your pick is already locked.",
        "already_acted": "You have already guessed or passed on this turn.",
        "turn_closed": "This turn has closed.",
        "invalid_pick": "Choose a player from this round's pool.",
        "invalid_guess": "Choose a player from this round's pool.",
        "invalid_replacement": "Choose a replacement from this round's pool.",
        "x_factor_position_mismatch": "Your X-Factor can only replace a slot at the same position.",
        "match_not_playing": "This match isn't accepting moves right now.",
        "not_your_turn": "It isn't your turn right now.",
        "not_a_participant": "You're not in this game.",
        "not_authenticated": "Sign in first.",
        "not_host": "Only the host can choose what's next.",
        "match_not_complete": "This game is still in progress.",
        "post_game_choice_already_made": "The next game has already been chosen.",
        "too_few_players": "Sabotage Draft needs at least two players.",
        "invalid_mode": "Choose Full, Standard or Quick.",
    ]
}

// MARK: - Format

/// How long a match is. The host picks it at start; the server derives the
/// round count (and so everything else) from it.
enum SabotageMode: String, Sendable, CaseIterable, Identifiable, Decodable {
    case full, standard, quick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: "Full"
        case .standard: "Standard"
        case .quick: "Quick"
        }
    }

    var blurb: String {
        switch self {
        case .full: "14 rounds · every position, offense through special teams"
        case .standard: "10 rounds · skill positions, a defender and special teams"
        case .quick: "7 rounds · skill positions and a defender"
        }
    }

    /// One slot per round, in the order the server deals them. The last round of
    /// every mode is the X-Factor.
    var slots: [String] {
        switch self {
        case .full: ["QB", "RB1", "RB2", "WR1", "WR2", "WR3", "TE", "OL", "DL", "LB", "CB", "S", "ST", "X_FACTOR"]
        case .standard: ["QB", "RB1", "RB2", "WR1", "WR2", "TE", "FLEX", "DEF", "ST", "X_FACTOR"]
        case .quick: ["QB", "RB1", "WR1", "TE", "FLEX", "DEF", "X_FACTOR"]
        }
    }

    /// The board only carries `round_count`, and each mode has a distinct one, so
    /// the mode is recoverable from it. Anything unrecognised reads as the
    /// original full game.
    static func forRoundCount(_ count: Int) -> SabotageMode {
        allCases.first { $0.slots.count == count } ?? .full
    }
}

// MARK: - Rules (display only)

enum SabotageRules {
    /// One shared clock per turn; the same length for every turn.
    static let turnDurationMs = 60_000
    static let xFactor = "X_FACTOR"

    /// Slot for a round, defaulting to the full game's order. Past the last
    /// round falls to the X-Factor.
    static func slot(forRound round: Int, roundCount: Int) -> String {
        let slots = SabotageMode.forRoundCount(roundCount).slots
        return slots.indices.contains(round - 1) ? slots[round - 1] : xFactor
    }

    /// The roster slots a mode drafts directly: every round but the X-Factor.
    static func rosterSlots(roundCount: Int) -> [String] {
        Array(SabotageMode.forRoundCount(roundCount).slots.dropLast())
    }

    private static let skillSlots: Set<String> = ["QB", "RB1", "RB2", "WR1", "WR2", "WR3", "TE", "FLEX"]

    /// The slots an X-Factor of this position category may replace in this mode.
    /// Mirrors `submit_x_factor_decision`'s validation: the slot has to exist in
    /// the mode and match the category (FLEX takes an RB, WR or TE).
    static func xFactorTargets(category: String?, roundCount: Int) -> [String] {
        guard let category else { return [] }
        return rosterSlots(roundCount: roundCount).filter { slot in
            guard skillSlots.contains(slot) else { return false }
            if slot == "FLEX" { return ["RB", "WR", "TE"].contains(category) }
            return slot.filter { !$0.isNumber } == category
        }
    }

    /// What a slot is called where there is room to spell it out.
    static func slotLabel(_ slot: String) -> String {
        slot == "DEF" ? "Defensive Player" : slot.replacingOccurrences(of: "_", with: " ")
    }

    /// The short form used in dense rows.
    static func slotShort(_ slot: String) -> String {
        slot.replacingOccurrences(of: "_", with: " ")
    }

    /// The "choosing …" line for a round: what the drafter may take from a spin.
    static func chooseLabel(_ slot: String) -> String {
        switch slot {
        case xFactor: "any offensive skill player"
        case "FLEX": "an RB, WR or TE"
        case "DEF": "a defensive player"
        default: "a \(slot.filter { !$0.isNumber })"
        }
    }

    // MARK: Franchises

    /// Pro Football Reference's franchise codes, which stay stable across a
    /// franchise's whole history, mapped to its current name. Display only.
    static let franchiseNames: [String: String] = [
        "atl": "Atlanta Falcons", "buf": "Buffalo Bills", "car": "Carolina Panthers",
        "chi": "Chicago Bears", "cin": "Cincinnati Bengals", "cle": "Cleveland Browns",
        "clt": "Indianapolis Colts", "crd": "Arizona Cardinals", "dal": "Dallas Cowboys",
        "den": "Denver Broncos", "det": "Detroit Lions", "gnb": "Green Bay Packers",
        "htx": "Houston Texans", "jax": "Jacksonville Jaguars", "kan": "Kansas City Chiefs",
        "mia": "Miami Dolphins", "min": "Minnesota Vikings", "nor": "New Orleans Saints",
        "nwe": "New England Patriots", "nyg": "New York Giants", "nyj": "New York Jets",
        "oti": "Tennessee Titans", "phi": "Philadelphia Eagles", "pit": "Pittsburgh Steelers",
        "rai": "Las Vegas Raiders", "ram": "Los Angeles Rams", "rav": "Baltimore Ravens",
        "sdg": "Los Angeles Chargers", "sea": "Seattle Seahawks", "sfo": "San Francisco 49ers",
        "tam": "Tampa Bay Buccaneers", "was": "Washington Commanders",
    ]

    /// Falls back to the raw code so an unmapped future entry never disappears.
    static func franchiseName(_ code: String) -> String {
        franchiseNames[code] ?? code
    }

    // MARK: Grades

    /// Letter grades, lowest to highest above F. A pick or roster that clears no
    /// cutoff is an F.
    static let ladder = ["D-", "D", "D+", "C-", "C", "C+", "B-", "B", "B+", "A-", "A", "A+"]

    /// Position-relative AV cutoffs, one per rung of `ladder`.
    private static let positionCutoffs: [String: [Int]] = [
        "QB": [3, 6, 7, 10, 12, 13, 15, 16, 17, 18, 19, 20],
        "RB": [1, 3, 3, 5, 7, 9, 10, 12, 13, 16, 16, 18],
        "WR": [2, 3, 4, 5, 7, 8, 10, 11, 12, 14, 15, 16],
        "TE": [0, 1, 1, 2, 4, 5, 6, 7, 8, 9, 11, 12],
        "OL": [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 14, 15],
        "DL": [2, 4, 4, 6, 7, 8, 9, 11, 13, 15, 17, 18],
        "LB": [2, 3, 4, 5, 7, 8, 9, 10, 12, 15, 16, 17],
        "CB": [2, 3, 3, 4, 5, 6, 8, 9, 11, 13, 14, 16],
        "S": [2, 3, 4, 5, 5, 6, 7, 8, 9, 11, 13, 13],
        "ST": [1, 2, 2, 2, 3, 3, 4, 4, 4, 5, 5, 5],
    ]

    private static let teamCutoffs = [60, 69, 72, 82, 93, 102, 110, 114, 120, 126, 130, 136]
    private static let baselines: [SabotageMode: Int] = [.full: 93, .standard: 62, .quick: 52]

    private static func letter(for value: Double, cutoffs: [Int]) -> String {
        for index in cutoffs.indices.reversed() where value >= Double(cutoffs[index]) {
            return ladder[index]
        }
        return "F"
    }

    /// Slot labels fold onto the AV pool's broader category; FLEX and DEF say
    /// nothing about the player's position, so the pick's own category is used.
    private static func category(slot: String, pickCategory: String?) -> String {
        if (slot == "FLEX" || slot == "DEF"), let pickCategory { return pickCategory }
        if slot.hasPrefix("RB") { return "RB" }
        if slot.hasPrefix("WR") { return "WR" }
        return slot
    }

    /// A single drafted player's grade, relative to real players at their own
    /// position.
    static func gradeForPick(slot: String, av: Int, pickCategory: String? = nil) -> String {
        let cutoffs = positionCutoffs[category(slot: slot, pickCategory: pickCategory)] ?? positionCutoffs["QB"]!
        return letter(for: Double(av), cutoffs: cutoffs)
    }

    /// A whole roster's grade. The cutoffs are written for a full roster
    /// (baseline 93); a smaller mode is stretched onto that scale by the ratio
    /// of baselines.
    static func gradeForTeam(rosterStrength: Int, mode: SabotageMode) -> String {
        let baseline = Double(baselines[mode] ?? 93)
        // Multiply before dividing so a roster exactly on its baseline lands
        // exactly on 93, rather than a hair under it.
        return letter(for: Double(rosterStrength * 93) / baseline, cutoffs: teamCutoffs)
    }
}

// MARK: - Rows

/// `sabotage_draft.state()` — the public projection of the match.
struct SabotageBoard: Equatable, Sendable {
    let matchId: UUID
    let roundCount: Int
    let currentRound: Int
    let slot: String
    /// Nil between turns and while the X-Factor decision is open.
    let turnDeadline: Date?
    let serverNow: Date
    let xFactorOpen: Bool
    /// The seat whose turn it is.
    let activeUserId: UUID?

    var mode: SabotageMode { SabotageMode.forRoundCount(roundCount) }

    private enum CodingKeys: String, CodingKey {
        case matchId = "match_id"
        case roundCount = "round_count"
        case currentRound = "current_round"
        case slot
        case turnDeadline = "turn_deadline"
        case serverNow = "server_now"
        case xFactorOpen = "x_factor_open"
        case activeUserId = "active_user_id"
    }
}

extension SabotageBoard: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try container.decode(UUID.self, forKey: .matchId)
        roundCount = try container.decode(Int.self, forKey: .roundCount)
        currentRound = try container.decode(Int.self, forKey: .currentRound)
        slot = try container.decodeIfPresent(String.self, forKey: .slot) ?? ""
        turnDeadline = try container.decodeIfPresent(Date.self, forKey: .turnDeadline)
        serverNow = try container.decode(Date.self, forKey: .serverNow)
        xFactorOpen = try container.decodeIfPresent(Bool.self, forKey: .xFactorOpen) ?? false
        activeUserId = try container.decodeIfPresent(UUID.self, forKey: .activeUserId)
    }
}

/// `public.sabotage_draft_players` joined to the profile.
struct SabotagePlayer: Equatable, Sendable, Identifiable {
    let userId: UUID
    let seat: Int
    let absent: Bool
    let name: String
    let avatarURL: URL?

    var id: UUID { userId }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case seat, absent, profiles
    }

    private struct Profile: Decodable {
        let displayName: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarURL = "avatar_url"
        }
    }

    init(userId: UUID, seat: Int, absent: Bool = false, name: String = "Unknown player", avatarURL: URL? = nil) {
        self.userId = userId
        self.seat = seat
        self.absent = absent
        self.name = name
        self.avatarURL = avatarURL
    }

    /// A replicated row carries no profile, so it takes the identity of the
    /// row it replaces.
    func named(like existing: SabotagePlayer) -> SabotagePlayer {
        SabotagePlayer(userId: userId, seat: seat, absent: absent, name: existing.name, avatarURL: existing.avatarURL)
    }
}

extension SabotagePlayer: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        seat = try container.decode(Int.self, forKey: .seat)
        absent = try container.decodeIfPresent(Bool.self, forKey: .absent) ?? false
        let profile = try container.decodeIfPresent(Profile.self, forKey: .profiles)
        name = profile?.displayName ?? "Unknown player"
        avatarURL = profile?.avatarURL.flatMap(URL.init(string:))
    }
}

/// `public.sabotage_draft_round_spins` — the franchise a seat spun for a round.
/// Public for past rounds and for a seat whose turn has been reached.
struct SabotageSpin: Equatable, Sendable, Decodable {
    let round: Int
    let userId: UUID
    let franchiseCode: String

    private enum CodingKeys: String, CodingKey {
        case round = "round_number"
        case userId = "user_id"
        case franchiseCode = "franchise_code"
    }
}

/// `public.sabotage_draft_picks` — row-level security shows a pick to its owner,
/// and to everyone once its turn has resolved.
struct SabotagePick: Equatable, Sendable, Decodable {
    let round: Int
    let userId: UUID
    let playerId: String
    let name: String
    let season: Int
    let byTimeout: Bool
    let headshotURL: URL?

    private enum CodingKeys: String, CodingKey {
        case round = "round_number"
        case userId = "user_id"
        case playerId = "player_id"
        case name = "display_name"
        case season
        case byTimeout = "by_timeout"
        case headshotURL = "headshot_url"
    }

    init(
        round: Int, userId: UUID, playerId: String, name: String, season: Int,
        byTimeout: Bool = false, headshotURL: URL? = nil
    ) {
        self.round = round
        self.userId = userId
        self.playerId = playerId
        self.name = name
        self.season = season
        self.byTimeout = byTimeout
        self.headshotURL = headshotURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        round = try container.decode(Int.self, forKey: .round)
        userId = try container.decode(UUID.self, forKey: .userId)
        playerId = try container.decode(String.self, forKey: .playerId)
        name = try container.decode(String.self, forKey: .name)
        season = try container.decode(Int.self, forKey: .season)
        byTimeout = try container.decodeIfPresent(Bool.self, forKey: .byTimeout) ?? false
        headshotURL = try container.decodeIfPresent(String.self, forKey: .headshotURL).flatMap(URL.init(string:))
    }
}

/// `public.sabotage_draft_pick_statuses` — "this seat has locked a pick for the
/// round", with the pick itself withheld.
struct SabotagePickStatus: Equatable, Sendable, Decodable {
    let round: Int
    let userId: UUID

    private enum CodingKeys: String, CodingKey {
        case round = "round_number"
        case userId = "user_id"
    }
}

/// `public.sabotage_draft_pick_hits` — a guess that landed on a seat's pick.
struct SabotageHit: Equatable, Sendable, Decodable {
    enum Kind: String, Sendable, Decodable { case respin, sabotage }

    let round: Int
    let targetUserId: UUID
    let kind: Kind

    private enum CodingKeys: String, CodingKey {
        case round = "round_number"
        case targetUserId = "target_user_id"
        case kind
    }
}

/// `public.sabotage_draft_guesses`. `result` is nil until the whole turn's
/// action set is complete.
struct SabotageGuess: Equatable, Sendable, Decodable {
    enum Result: String, Sendable, Decodable { case miss, respun, sabotaged }

    let round: Int
    let userId: UUID
    let targetUserId: UUID
    /// Set only for a player-and-year guess.
    let season: Int?
    let result: Result?

    var isExact: Bool { season != nil }

    private enum CodingKeys: String, CodingKey {
        case round = "round_number"
        case userId = "user_id"
        case targetUserId = "target_user_id"
        case season, result
    }
}

/// `public.sabotage_draft_passes`.
struct SabotagePass: Equatable, Sendable, Decodable {
    let round: Int
    let userId: UUID
    let targetUserId: UUID

    private enum CodingKeys: String, CodingKey {
        case round = "round_number"
        case userId = "user_id"
        case targetUserId = "target_user_id"
    }
}

/// `sabotage_draft.options()` — one player-season in a spun franchise's pool.
struct SabotageOption: Equatable, Sendable, Decodable, Identifiable {
    let playerId: String
    let name: String
    let season: Int
    let category: String
    let headshotURL: URL?

    var id: String { "\(playerId)-\(season)" }

    private enum CodingKeys: String, CodingKey {
        case playerId = "player_id"
        case name = "display_name"
        case season
        case category = "slot_category"
        case headshotURL = "headshot_url"
    }

    init(playerId: String, name: String, season: Int, category: String = "", headshotURL: URL? = nil) {
        self.playerId = playerId
        self.name = name
        self.season = season
        self.category = category
        self.headshotURL = headshotURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try container.decode(String.self, forKey: .playerId)
        name = try container.decode(String.self, forKey: .name)
        season = try container.decode(Int.self, forKey: .season)
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        headshotURL = try container.decodeIfPresent(String.self, forKey: .headshotURL).flatMap(URL.init(string:))
    }
}

/// One player in a round's pool, with every season they could be picked in.
struct SabotageTenured: Equatable, Identifiable {
    let playerId: String
    let name: String
    let category: String
    let headshotURL: URL?
    /// Newest first.
    let seasons: [Int]

    var id: String { playerId }
    var span: String {
        guard let newest = seasons.first, let oldest = seasons.last else { return "" }
        return newest == oldest ? "\(newest)" : "\(oldest)–\(newest)"
    }

    /// Groups a pool by player, most tenured first (ties broken by recency).
    static func group(_ options: [SabotageOption]) -> [SabotageTenured] {
        var order: [String] = []
        var byPlayer: [String: [SabotageOption]] = [:]
        for option in options {
            if byPlayer[option.playerId] == nil { order.append(option.playerId) }
            byPlayer[option.playerId, default: []].append(option)
        }
        return order.compactMap { id -> SabotageTenured? in
            guard let rows = byPlayer[id], let first = rows.first else { return nil }
            return SabotageTenured(
                playerId: id,
                name: first.name,
                category: first.category,
                // Every season's row carries the same portrait, but one a pool
                // build had no fresher data for can still be null: keep the
                // first real one.
                headshotURL: rows.compactMap(\.headshotURL).first,
                seasons: rows.map(\.season).sorted(by: >)
            )
        }
        .sorted { $0.seasons.count != $1.seasons.count ? $0.seasons.count > $1.seasons.count : ($0.seasons.first ?? 0) > ($1.seasons.first ?? 0) }
    }
}

/// `public.sabotage_draft_x_factor_decisions` — nil `replaceSlot` is a discard.
struct SabotageDecision: Equatable, Sendable, Decodable {
    let userId: UUID
    let replaceSlot: String?

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case replaceSlot = "replace_slot"
    }
}

/// `public.sabotage_draft_standings` — written once, when the season is run.
struct SabotageStanding: Equatable, Sendable, Decodable {
    let userId: UUID
    let rosterStrength: Int
    let wins: Int
    let losses: Int
    let tiebreakRank: Int

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case rosterStrength = "roster_strength"
        case wins, losses
        case tiebreakRank = "tiebreak_rank"
    }
}

/// `public.sabotage_draft_tiebreak_games` — one game of a tie's playoff bracket.
struct SabotageTiebreak: Equatable, Sendable, Decodable {
    let recordWins: Int
    let bracketRound: Int
    let gameNumber: Int
    let playerA: UUID
    /// Nil for a bye.
    let playerB: UUID?
    let winnerUserId: UUID
    let playerAScore: Int?
    let playerBScore: Int?

    private enum CodingKeys: String, CodingKey {
        case recordWins = "record_wins"
        case bracketRound = "bracket_round"
        case gameNumber = "game_number"
        case playerA = "player_a"
        case playerB = "player_b"
        case winnerUserId = "winner_user_id"
        case playerAScore = "player_a_score"
        case playerBScore = "player_b_score"
    }
}

/// `sabotage_draft.pick_avs()` — each visible pick's Approximate Value.
struct SabotagePickAv: Equatable, Sendable, Decodable {
    let userId: UUID
    let round: Int
    let av: Int
    let category: String?

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case round = "round_number"
        case av
        case category = "slot_category"
    }
}

/// Everything one full read of the match returns.
struct SabotageSnapshot: Equatable, Sendable {
    var board: SabotageBoard
    var players: [SabotagePlayer]
    var spins: [SabotageSpin]
    var picks: [SabotagePick]
    var statuses: [SabotagePickStatus]
    var hits: [SabotageHit]
    var guesses: [SabotageGuess]
    var passes: [SabotagePass]
    var decisions: [SabotageDecision]
    var standings: [SabotageStanding]
    var tiebreaks: [SabotageTiebreak]
    var pickAvs: [SabotagePickAv]
    var matchStatus: MatchStatus
    var postGame: PostGameAction?
}

/// What the match's channels deliver.
enum SabotageEvent: Sendable {
    /// A channel (re)joined: re-read everything.
    case subscribed
    /// Any table behind the board changed. Sabotage Draft re-reads rather than
    /// merging — rows are few, and the pick tables are narrowed per viewer.
    case changed
    case matchStatus(MatchStatus)
    case postGame(PostGameAction)
}
