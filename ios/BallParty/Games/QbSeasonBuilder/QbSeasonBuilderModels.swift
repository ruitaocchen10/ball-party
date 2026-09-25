import Foundation

// Hand-maintained `Decodable` mirrors of what `qb_season_builder.state`, `pick`,
// `respin`, `finish` and `result` return — see `docs/games/qb_season_builder.md`.
// The web's equivalents are `webapp/lib/games/qb-season-builder/board.ts` and
// `result.ts`. The server decides whether a grade is shown at all: every
// grade in a hidden run is `null` until the run is finished, so a `nil` here
// is an honest rendering of an absent grade, never something to fill in. The
// number behind a grade never leaves the server (migration `0154`).

/// Whether grades show while the player picks. Chosen when the run starts and
/// locked for its whole length.
enum QbRatingMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case visible
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .visible: "Visible"
        case .hidden: "Hidden"
        }
    }

    var summary: String {
        switch self {
        case .visible: "Letter grades show while you pick."
        case .hidden: "No grades until the run is over. Pick on what you know."
        }
    }
}

/// The pool of team-seasons a run deals from. Chosen when the run starts and
/// locked for its whole length, like `QbRatingMode`. Three fixed presets a
/// client hardcodes rather than a free range — see migration `0153`'s header
/// for why — so there is nothing to read from the server about them beyond
/// which one a run picked.
enum QbEra: String, Codable, Sendable, CaseIterable, Identifiable {
    case all
    case classic
    case modern

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All Years"
        case .classic: "Classic"
        case .modern: "Modern"
        }
    }

    var summary: String {
        switch self {
        case .all: "Every team-season, 2006-2025."
        case .classic: "2006-2015."
        case .modern: "2016-2025."
        }
    }
}

/// The six things a season is built from: five qualities of a quarterback, and
/// the team around him.
enum QbSlot: String, Codable, Sendable, CaseIterable, Identifiable {
    case accuracy
    case armTalent = "arm_talent"
    case mobility
    case iq
    case build
    case supportingCast = "supporting_cast"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accuracy: "Accuracy"
        case .armTalent: "Arm Talent"
        case .mobility: "Mobility"
        case .iq: "IQ"
        case .build: "Build"
        case .supportingCast: "Supporting Cast"
        }
    }

    /// The five things a quarterback is rated on; the sixth slot is the team.
    static let qualities: [QbSlot] = [.accuracy, .armTalent, .mobility, .iq, .build]

    /// A three-to-five letter code for the compact grid and build track,
    /// where a full label wouldn't fit.
    var shortLabel: String {
        switch self {
        case .accuracy: "ACC"
        case .armTalent: "ARM"
        case .mobility: "MOB"
        case .iq: "IQ"
        case .build: "BLD"
        case .supportingCast: "TEAM"
        }
    }

    var systemImage: String {
        switch self {
        case .accuracy: "scope"
        case .armTalent: "bolt.fill"
        case .mobility: "figure.run"
        case .iq: "brain"
        case .build: "shield.fill"
        case .supportingCast: "person.3.fill"
        }
    }
}

enum QbPhase: String, Decodable, Sendable {
    case picking
    case readyToFinish = "ready_to_finish"
    case complete
}

/// How good a quality or a Supporting Cast is, best first. The server maps the
/// blended value to one of these and sends only the letter — `webapp`'s `GRADES`
/// in `board.ts` is the same list.
enum QbGrade: String, Codable, Sendable, CaseIterable {
    case aPlus = "A+", a = "A", aMinus = "A-"
    case bPlus = "B+", b = "B", bMinus = "B-"
    case cPlus = "C+", c = "C", cMinus = "C-"
    case dPlus = "D+", d = "D", dMinus = "D-"
    case f = "F"

    var label: String { rawValue }

    /// What VoiceOver should say: "A-" is otherwise read as a letter and a dash.
    var spoken: String {
        rawValue.replacingOccurrences(of: "+", with: " plus").replacingOccurrences(of: "-", with: " minus")
    }
}

/// Score points, drawn as a whole number when they are one.
enum QbPoints {
    static func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

struct QbQuarterback: Equatable, Identifiable, Sendable, Decodable {
    let playerId: String
    let displayName: String
    let headshotURL: URL?
    /// Nil while the run is hidden and not yet finished.
    let grades: [QbSlot: QbGrade]?

    var id: String { playerId }

    init(playerId: String, displayName: String, headshotURL: URL? = nil, grades: [QbSlot: QbGrade]? = nil) {
        self.playerId = playerId
        self.displayName = displayName
        self.headshotURL = headshotURL
        self.grades = grades
    }

    private enum CodingKeys: String, CodingKey {
        case playerId = "player_id", displayName = "display_name", headshotURL = "headshot_url", grades
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playerId = try container.decode(String.self, forKey: .playerId)
        displayName = try container.decode(String.self, forKey: .displayName)
        headshotURL = try container.decodeIfPresent(String.self, forKey: .headshotURL).flatMap(URL.init(string:))
        // All five, or none: a run never shows half a quarterback.
        if let raw = try container.decodeIfPresent([String: String?].self, forKey: .grades) {
            var grades: [QbSlot: QbGrade] = [:]
            for slot in QbSlot.qualities {
                guard let letter = raw[slot.rawValue] ?? nil, let grade = QbGrade(rawValue: letter) else { break }
                grades[slot] = grade
            }
            self.grades = grades.count == QbSlot.qualities.count ? grades : nil
        } else {
            grades = nil
        }
    }
}

/// One team-season the player is dealt, with everything it offers.
struct QbSpin: Equatable, Sendable, Decodable {
    let quarterbacks: [QbQuarterback]
    /// The team's Supporting Cast grade; nil when hidden.
    let supportingCastGrade: QbGrade?

    init(quarterbacks: [QbQuarterback], supportingCastGrade: QbGrade? = nil) {
        self.quarterbacks = quarterbacks
        self.supportingCastGrade = supportingCastGrade
    }

    private enum CodingKeys: String, CodingKey {
        case quarterbacks, supportingCast = "supporting_cast"
    }

    private struct Cast: Decodable { let grade: String? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quarterbacks = try container.decode([QbQuarterback].self, forKey: .quarterbacks)
        supportingCastGrade = try container.decode(Cast.self, forKey: .supportingCast).grade.flatMap(QbGrade.init(rawValue:))
    }
}

struct QbDeal: Equatable, Sendable {
    /// Pro Football Reference's franchise code (`crd`, `rav`, …), the one the
    /// `team-logos` bucket is keyed on.
    let franchiseCode: String
    let season: Int
    let spin: QbSpin
}

struct QbPick: Equatable, Identifiable, Sendable, Decodable {
    let round: Int
    let slot: QbSlot
    let franchiseCode: String
    let season: Int
    /// Nil for the Supporting Cast, whose source is the team.
    let playerId: String?
    let displayName: String?
    let headshotURL: URL?
    let grade: QbGrade?

    var id: Int { round }

    init(
        round: Int, slot: QbSlot, franchiseCode: String, season: Int,
        playerId: String? = nil, displayName: String? = nil, headshotURL: URL? = nil, grade: QbGrade? = nil
    ) {
        self.round = round
        self.slot = slot
        self.franchiseCode = franchiseCode
        self.season = season
        self.playerId = playerId
        self.displayName = displayName
        self.headshotURL = headshotURL
        self.grade = grade
    }

    private enum CodingKeys: String, CodingKey {
        case round, slot, season, grade
        case franchiseCode = "franchise_code", playerId = "player_id", displayName = "display_name"
        case headshotURL = "headshot_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        round = try container.decode(Int.self, forKey: .round)
        slot = try container.decode(QbSlot.self, forKey: .slot)
        franchiseCode = try container.decode(String.self, forKey: .franchiseCode)
        season = try container.decode(Int.self, forKey: .season)
        playerId = try container.decodeIfPresent(String.self, forKey: .playerId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        headshotURL = try container.decodeIfPresent(String.self, forKey: .headshotURL).flatMap(URL.init(string:))
        grade = try container.decodeIfPresent(String.self, forKey: .grade).flatMap(QbGrade.init(rawValue:))
    }
}

/// A spin the player was dealt, kept for the reveal: once a run is finished the
/// server returns every spin it showed with every grade, whichever mode it was.
/// `attempt` 2 of a round means attempt 1 was respun away.
struct QbShownSpin: Equatable, Identifiable, Sendable, Decodable {
    let round: Int
    let attempt: Int
    let franchiseCode: String
    let season: Int
    let spin: QbSpin

    var id: String { "\(round)-\(attempt)" }

    init(round: Int, attempt: Int, franchiseCode: String, season: Int, spin: QbSpin) {
        self.round = round
        self.attempt = attempt
        self.franchiseCode = franchiseCode
        self.season = season
        self.spin = spin
    }

    private enum CodingKeys: String, CodingKey {
        case round, attempt, season, options
        case franchiseCode = "franchise_code"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        round = try container.decode(Int.self, forKey: .round)
        attempt = try container.decode(Int.self, forKey: .attempt)
        franchiseCode = try container.decode(String.self, forKey: .franchiseCode)
        season = try container.decode(Int.self, forKey: .season)
        spin = try container.decode(QbSpin.self, forKey: .options)
    }
}

/// A pick with every grade the run showed for where it came from: the taken
/// slot always, and — when the finished board's spins are to hand — the rest of
/// that quarterback's grades and his team's Supporting Cast.
struct QbPickedPlayer: Equatable, Identifiable, Sendable {
    let pick: QbPick
    let grades: [QbSlot: QbGrade]

    var id: Int { pick.round }

    /// The grades in card order, the picked slot flagged.
    var gradeLines: [(slot: QbSlot, grade: QbGrade, isPicked: Bool)] {
        QbSlot.allCases.compactMap { slot in
            grades[slot].map { (slot, $0, slot == pick.slot) }
        }
    }

    /// The Supporting Cast pick is the team, not a quarterback.
    var title: String { pick.displayName ?? QbFranchises.name(for: pick.franchiseCode) }
}

/// A run, as `state`, `pick` and `respin` all hand it over.
struct QbBoard: Equatable, Sendable, Decodable {
    let matchId: UUID
    let mode: QbRatingMode
    /// `picking` while a round is open; `ready_to_finish` once all six slots are filled.
    let phase: QbPhase
    let roundCount: Int
    let currentRound: Int
    let respinUsed: Bool
    /// The current round's spin; nil once no round is open.
    let deal: QbDeal?
    let picks: [QbPick]
    /// Every spin the player saw, grades revealed; nil until the run is complete.
    let shown: [QbShownSpin]?
    /// The pool this run deals from. Absent on a run dealt before migration
    /// `0153` fell out of any fixture that predates it — `.all` is what every
    /// one of those was, so it is the truth here too, not a default standing in
    /// for one.
    let era: QbEra

    init(
        matchId: UUID, mode: QbRatingMode, phase: QbPhase, roundCount: Int = 6, currentRound: Int,
        respinUsed: Bool = false, deal: QbDeal? = nil, picks: [QbPick] = [], shown: [QbShownSpin]? = nil,
        era: QbEra = .all
    ) {
        self.matchId = matchId
        self.mode = mode
        self.phase = phase
        self.roundCount = roundCount
        self.currentRound = currentRound
        self.respinUsed = respinUsed
        self.deal = deal
        self.picks = picks
        self.shown = shown
        self.era = era
    }

    private enum CodingKeys: String, CodingKey {
        case mode, phase, season, options, picks, shown, era
        case matchId = "match_id", roundCount = "round_count", currentRound = "current_round"
        case respinUsed = "respin_used", franchiseCode = "franchise_code"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try container.decode(UUID.self, forKey: .matchId)
        mode = try container.decode(QbRatingMode.self, forKey: .mode)
        phase = try container.decode(QbPhase.self, forKey: .phase)
        roundCount = try container.decode(Int.self, forKey: .roundCount)
        currentRound = try container.decode(Int.self, forKey: .currentRound)
        respinUsed = try container.decode(Bool.self, forKey: .respinUsed)
        picks = try container.decodeIfPresent([QbPick].self, forKey: .picks) ?? []
        shown = try container.decodeIfPresent([QbShownSpin].self, forKey: .shown)
        era = try container.decodeIfPresent(QbEra.self, forKey: .era) ?? .all

        if let franchiseCode = try container.decodeIfPresent(String.self, forKey: .franchiseCode),
           let season = try container.decodeIfPresent(Int.self, forKey: .season),
           let spin = try container.decodeIfPresent(QbSpin.self, forKey: .options) {
            deal = QbDeal(franchiseCode: franchiseCode, season: season, spin: spin)
        } else {
            deal = nil
        }
    }

    func pick(for slot: QbSlot) -> QbPick? {
        picks.first { $0.slot == slot }
    }

    func isTaken(_ slot: QbSlot) -> Bool {
        pick(for: slot) != nil
    }
}

// MARK: - The season

enum QbAward: String, CaseIterable, Sendable {
    case mvp
    case opoy
    case allPro = "all_pro"
    case proBowl = "pro_bowl"
    case sbMvp = "sb_mvp"

    var label: String {
        switch self {
        case .mvp: "MVP"
        case .opoy: "Offensive Player of the Year"
        case .allPro: "First-Team All-Pro"
        case .proBowl: "Pro Bowl"
        case .sbMvp: "Super Bowl MVP"
        }
    }
}

enum QbPlayoffResult: String, Decodable, Sendable {
    case missedPlayoffs = "missed_playoffs"
    case lostWildCard = "lost_wild_card"
    case lostDivisional = "lost_divisional"
    case lostConference = "lost_conference"
    case lostSuperBowl = "lost_super_bowl"
    case wonSuperBowl = "won_super_bowl"

    var label: String {
        switch self {
        case .missedPlayoffs: "Missed the playoffs"
        case .lostWildCard: "Lost in the wild card round"
        case .lostDivisional: "Lost in the divisional round"
        case .lostConference: "Lost the conference championship"
        case .lostSuperBowl: "Lost the Super Bowl"
        case .wonSuperBowl: "Won the Super Bowl"
        }
    }
}

struct QbStatLine: Equatable, Sendable, Decodable {
    let attempts: Int
    let completions: Int
    let passYards: Int
    let passTds: Int
    let interceptions: Int
    let rating: Double
    let rushYards: Int
    let rushTds: Int

    private enum CodingKeys: String, CodingKey {
        case attempts, completions, interceptions, rating
        case passYards = "pass_yards", passTds = "pass_tds", rushYards = "rush_yards", rushTds = "rush_tds"
    }
}

struct QbScoreComponent: Equatable, Sendable, Decodable {
    let component: String
    /// Relative to the other components, not a percentage.
    let weight: Double
    /// 0–1: the share of real seasons this one beat.
    let percentile: Double
    /// What the component added to the score.
    let points: Double

    var label: String {
        switch component {
        case "stat_line": "Stat line"
        case "team_success": "Team success"
        case "awards": "Awards"
        default: component
        }
    }
}

/// A finished run's saved season, as `finish` and `result` return it.
struct QbSeasonResult: Equatable, Sendable, Decodable {
    struct Record: Equatable, Sendable, Decodable {
        let wins: Int
        let losses: Int
    }

    struct Playoffs: Equatable, Sendable, Decodable {
        let depth: Int
        let result: QbPlayoffResult
    }

    let matchId: UUID
    let mode: QbRatingMode
    let statLine: QbStatLine
    let record: Record
    let playoffs: Playoffs
    /// The awards won, in the order the web lists them.
    let awards: [QbAward]
    let score: Double
    let breakdown: [QbScoreComponent]
    let picks: [QbPick]

    init(
        matchId: UUID, mode: QbRatingMode, statLine: QbStatLine, record: Record, playoffs: Playoffs,
        awards: [QbAward], score: Double, breakdown: [QbScoreComponent], picks: [QbPick]
    ) {
        self.matchId = matchId
        self.mode = mode
        self.statLine = statLine
        self.record = record
        self.playoffs = playoffs
        self.awards = awards
        self.score = score
        self.breakdown = breakdown
        self.picks = picks
    }

    private enum CodingKeys: String, CodingKey {
        case mode, record, playoffs, awards, score, breakdown, picks
        case matchId = "match_id", statLine = "stat_line"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try container.decode(UUID.self, forKey: .matchId)
        mode = try container.decode(QbRatingMode.self, forKey: .mode)
        statLine = try container.decode(QbStatLine.self, forKey: .statLine)
        record = try container.decode(Record.self, forKey: .record)
        playoffs = try container.decode(Playoffs.self, forKey: .playoffs)
        let won = try container.decode([String: Bool].self, forKey: .awards)
        awards = QbAward.allCases.filter { won[$0.rawValue] == true }
        score = try container.decode(Double.self, forKey: .score)
        breakdown = try container.decode([QbScoreComponent].self, forKey: .breakdown)
        picks = try container.decode([QbPick].self, forKey: .picks)
    }

    /// The share of the score a component is worth, as a whole percent.
    func weightPercent(of part: QbScoreComponent) -> Int {
        let total = breakdown.reduce(0) { $0 + $1.weight }
        return total > 0 ? Int((100 * part.weight / total).rounded()) : 0
    }
}

// MARK: - Franchise names

/// Pro Football Reference's franchise codes and each franchise's current name —
/// `webapp/lib/foundation/content/nfl/franchises.ts` verbatim. A spin stores the
/// code because it is stable across a franchise's whole history, which is why
/// several read nothing like the team (`oti`, `crd`, `rav`).
enum QbFranchises {
    private static let names: [String: String] = [
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
    static func name(for code: String) -> String {
        names[code] ?? code
    }

    /// Every known code, sorted so the order is stable across runs — a
    /// `Dictionary`'s own iteration order is not.
    static let allCodes: [String] = names.keys.sorted()

    /// A stable run of decoy codes for a spin reel, picked deterministically
    /// from `key` rather than randomly. Mirrors the web's `stableReelDecoys`
    /// (`webapp/lib/foundation/ui-kit/reel.ts`) so a reel's decoys don't
    /// jitter if this view is ever asked to render the same key twice.
    static func reelDecoys(excluding code: String, key: String, count: Int) -> [String] {
        let pool = allCodes.filter { $0 != code }
        guard count > 0, !pool.isEmpty else { return [] }

        var hash: UInt32 = 0
        for scalar in key.unicodeScalars { hash = hash &* 31 &+ scalar.value }
        let start = Int(hash % UInt32(pool.count))
        let length = min(count, pool.count)
        return (0..<length).map { pool[(start + $0) % pool.count] }
    }
}
