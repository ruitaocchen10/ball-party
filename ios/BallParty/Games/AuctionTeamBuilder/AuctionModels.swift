import Foundation

// Hand-maintained `Codable` mirrors of the `auction` schema's rows and RPC
// results, and the pure board rules the screen derives from them. Same deal as
// `HigherOrLowerModels.swift`: there is no Postgres-to-Swift codegen, so a
// column added on the server has to be added here on purpose.
//
// Everything derived here is *display*, never a rule. The database decides each
// question again when a move arrives (`webapp/lib/games/auction/board.ts` makes
// the same split); the point of computing them on the client is that a disabled
// button can say why.

/// A failed auction RPC, reduced to what a screen can act on: the raised message.
struct AuctionServerError: Error, Equatable, Sendable {
    let message: String

    /// The raised message as a sentence for the player, the way the web's
    /// `MESSAGES` map does it. Anything unmapped surfaces raw rather than being
    /// flattened into a friendly lie — an unrecognised failure is a bug to
    /// notice, not a state to paper over.
    static func describe(_ error: Error) -> String {
        guard let server = error as? AuctionServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        return messages[server.message] ?? server.message
    }

    static let messages: [String: String] = [
        "not_your_turn": "It isn't your turn.",
        "already_passed": "You already passed on this lot.",
        "not_eligible": "You have no open slot for this lot.",
        "insufficient_budget": "That's more than you have left.",
        "bid_not_whole": "Bids are in whole dollars.",
        "bid_not_increasing": "Your bid must be higher than the current price.",
        "bidding_not_open": "Bidding has not opened yet.",
        "no_pass_tokens": "You're out of pass tokens, so this one's yours.",
        "no_scout_tokens": "You're out of scouting tokens.",
        "lot_already_resolved": "This lot's points are already revealed.",
        "no_seal_tokens": "You're out of sealed-bid tokens.",
        "sealing_not_available": "This lot can't be sealed right now.",
        "bidding_already_underway": "Someone's already bid on this lot, so it can't be sealed.",
        "seal_needs_two_bidders": "Nobody else can bid on this lot, so sealing it wouldn't change anything.",
        "sealed_bidding_not_open": "Sealed bidding on this lot has already closed.",
        "already_submitted": "You've already submitted your sealed bid.",
        "match_not_playing": "This game isn't accepting moves right now.",
        "not_a_participant": "You're not in this game.",
        "not_authenticated": "Sign in first.",
        "not_host": "Only the host can choose what's next.",
        "match_not_complete": "This game is still in progress.",
        "post_game_choice_already_made": "The next game has already been chosen.",
        "invalid_scoring_mode": "Choose a valid scoring mode.",
        "invalid_roster_preset": "Choose a valid roster.",
        "invalid_token_count": "Tokens can be zero to three per player.",
        "invalid_season_range": "The last season has to come after the first.",
        "season_out_of_range": "That season isn't in the player pool.",
        "season_range_too_narrow": "Pick a span of at least four seasons.",
        "pool_exhausted": "Couldn't deal a full board. Try a wider era.",
    ]
}

// MARK: - Format

/// `auction_matches.roster_preset`. The slot counts and purse are resolved by
/// the server and stored on the match; this only names the host's choice.
enum RosterPreset: String, Sendable, CaseIterable, Identifiable {
    case standard, full, deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard · 20 lots"
        case .full: "Full · 28 lots"
        case .deep: "Deep · 40 lots"
        }
    }

    var shortLabel: String {
        switch self {
        case .standard: "Standard"
        case .full: "Full"
        case .deep: "Deep"
        }
    }
}

/// The era the host may deal from, as `auction.season_bounds()` reports it —
/// the pool's own extent plus the dealer's minimum window, read rather than
/// restated so the picker can never offer a range the server would refuse.
struct AuctionEra: Equatable, Sendable, Decodable {
    let seasonMin: Int
    let seasonMax: Int
    let minSpan: Int

    private enum CodingKeys: String, CodingKey {
        case seasonMin = "season_min"
        case seasonMax = "season_max"
        case minSpan = "min_span"
    }
}

/// A dealt match's immutable format snapshot, loaded once beside the board.
struct AuctionFormat: Equatable, Sendable, Decodable {
    let scoringMode: String
    let rosterPreset: String
    let qbSlots: Int
    let rbSlots: Int
    let wrSlots: Int
    let teSlots: Int
    let flexSlots: Int
    let purse: Int
    let seasonFrom: Int
    let seasonTo: Int
    /// How many of Pass/Scout/Seal a player may invoke this match, total.
    let tokenCount: Int

    private enum CodingKeys: String, CodingKey {
        case scoringMode = "scoring_mode"
        case rosterPreset = "roster_preset"
        case qbSlots = "qb_slots"
        case rbSlots = "rb_slots"
        case wrSlots = "wr_slots"
        case teSlots = "te_slots"
        case flexSlots = "flex_slots"
        case purse
        case seasonFrom = "season_from"
        case seasonTo = "season_to"
        case tokenCount = "token_count"
    }

    var eraLabel: String { "\(seasonFrom)-\(seasonTo)" }

    var scoringLabel: String {
        ScoringMode(rawValue: scoringMode)?.label ?? scoringMode
    }

    var limits: [Slot: Int] {
        [.qb: qbSlots, .rb: rbSlots, .wr: wrSlots, .te: teSlots, .flex: flexSlots]
    }
}

/// A roster position. FLEX is never a lot's own position — it is where an
/// RB/WR/TE lands once its natural slots are full.
enum Slot: String, Sendable, CaseIterable, Hashable {
    case qb = "QB", rb = "RB", wr = "WR", te = "TE", flex = "FLEX"
}

/// One visible roster position, including an independently readable repeat.
struct RosterSlot: Equatable, Sendable, Identifiable {
    let slot: Slot
    /// 1-based within its own position.
    let index: Int
    let label: String

    var id: String { "\(slot.rawValue)-\(index)" }
}

// MARK: - Rows

/// `auction.turn` — the board's pointer. Arrives from the RPCs (with
/// `server_now`) and from the `auction_matches` channel (without).
struct AuctionTurn: Equatable, Sendable, Decodable {
    enum Phase: String, Decodable, Sendable {
        case lotPreview = "lot_preview"
        case bidding
        case sold
        case sealed

        /// The length of the phase on the server, so the bar can show a
        /// fraction. Mirrors the web's `DURATION_MS`, which mirrors the
        /// intervals in the migrations.
        var durationMs: Int {
            switch self {
            case .lotPreview, .sold: 5_000
            case .bidding, .sealed: 20_000
            }
        }
    }

    let lotCount: Int
    let currentLot: Int
    let turnSeat: Int?
    let openerSeat: Int
    /// The broke opener's seat: the board hands the lot to them free unless
    /// they pass it back.
    let freeFallbackSeat: Int?
    /// The one eligible bidder left on a lot nobody else can bid on. They get a
    /// real turn — take it free, or spend a Pass token to let it go unsold.
    let stuckSeat: Int?
    let turnDeadline: Date?
    let phase: Phase
    let phaseDeadline: Date?
    /// Only on an RPC result; a replicated row carries none, and the screen
    /// keeps the last one it saw.
    let serverNow: Date?

    private enum CodingKeys: String, CodingKey {
        case lotCount = "lot_count"
        case currentLot = "current_lot"
        case turnSeat = "turn_seat"
        case openerSeat = "opener_seat"
        case freeFallbackSeat = "free_fallback_seat"
        case stuckSeat = "stuck_seat"
        case turnDeadline = "turn_deadline"
        case phase
        case phaseDeadline = "phase_deadline"
        case serverNow = "server_now"
    }

    init(
        lotCount: Int, currentLot: Int, turnSeat: Int?, openerSeat: Int = 0,
        freeFallbackSeat: Int? = nil, stuckSeat: Int? = nil, turnDeadline: Date? = nil,
        phase: Phase, phaseDeadline: Date? = nil, serverNow: Date? = nil
    ) {
        self.lotCount = lotCount
        self.currentLot = currentLot
        self.turnSeat = turnSeat
        self.openerSeat = openerSeat
        self.freeFallbackSeat = freeFallbackSeat
        self.stuckSeat = stuckSeat
        self.turnDeadline = turnDeadline
        self.phase = phase
        self.phaseDeadline = phaseDeadline
        self.serverNow = serverNow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lotCount = try container.decodeIfPresent(Int.self, forKey: .lotCount) ?? 0
        currentLot = try container.decodeIfPresent(Int.self, forKey: .currentLot) ?? 1
        turnSeat = try container.decodeIfPresent(Int.self, forKey: .turnSeat)
        openerSeat = try container.decodeIfPresent(Int.self, forKey: .openerSeat) ?? 0
        freeFallbackSeat = try container.decodeIfPresent(Int.self, forKey: .freeFallbackSeat)
        stuckSeat = try container.decodeIfPresent(Int.self, forKey: .stuckSeat)
        turnDeadline = try container.decodeTimestampIfPresent(forKey: .turnDeadline)
        phase = try container.decodeIfPresent(Phase.self, forKey: .phase) ?? .lotPreview
        phaseDeadline = try container.decodeTimestampIfPresent(forKey: .phaseDeadline)
        serverNow = try container.decodeTimestampIfPresent(forKey: .serverNow)
    }

    /// Exactly one of the two deadlines is ever set at a time — the server sets
    /// the turn's during bidding and the phase's otherwise.
    var activeDeadline: Date? { turnDeadline ?? phaseDeadline }
}

/// `auction_lots` — one player-week or player-season on the board. Points are
/// `nil` until the lot resolves; they are withheld server-side, not hidden here.
struct AuctionLot: Equatable, Sendable, Decodable, Identifiable {
    let seq: Int
    let displayName: String
    let headshotURL: URL?
    let position: String
    let season: Int
    let team: String
    /// `nil` on a season-total lot.
    let week: Int?
    let opponent: String?
    let points: Double?
    let price: Int?
    let slot: String?
    let winnerId: UUID?
    /// Stamped by `resolve` on every lot it settles, sold or not.
    let resolvedAt: Date?

    var id: Int { seq }

    /// Whether the lot was actually put up for bidding. A lot behind the table
    /// with no `resolved_at` is a spare the dealer skipped as unusable: nobody
    /// ever saw it, so its player must not appear in the board's history.
    var wasPresented: Bool { resolvedAt != nil }

    var isWeekly: Bool { week != nil && opponent != nil }

    private enum CodingKeys: String, CodingKey {
        case seq
        case displayName = "display_name"
        case headshotURL = "headshot_url"
        case position, season, team, week, opponent, points, price, slot
        case winnerId = "winner_id"
        case resolvedAt = "resolved_at"
    }

    init(
        seq: Int, displayName: String, headshotURL: URL? = nil, position: String, season: Int,
        team: String, week: Int? = nil, opponent: String? = nil, points: Double? = nil,
        price: Int? = nil, slot: String? = nil, winnerId: UUID? = nil, resolvedAt: Date? = nil
    ) {
        self.seq = seq
        self.displayName = displayName
        self.headshotURL = headshotURL
        self.position = position
        self.season = season
        self.team = team
        self.week = week
        self.opponent = opponent
        self.points = points
        self.price = price
        self.slot = slot
        self.winnerId = winnerId
        self.resolvedAt = resolvedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(Int.self, forKey: .seq)
        displayName = try container.decode(String.self, forKey: .displayName)
        headshotURL = try container.decodeIfPresent(String.self, forKey: .headshotURL).flatMap(URL.init(string:))
        position = try container.decode(String.self, forKey: .position)
        season = try container.decode(Int.self, forKey: .season)
        team = try container.decode(String.self, forKey: .team)
        week = try container.decodeIfPresent(Int.self, forKey: .week)
        opponent = try container.decodeIfPresent(String.self, forKey: .opponent)
        points = try container.decodeNumericIfPresent(forKey: .points)
        price = try container.decodeIfPresent(Int.self, forKey: .price)
        slot = try container.decodeIfPresent(String.self, forKey: .slot)
        winnerId = try container.decodeIfPresent(UUID.self, forKey: .winnerId)
        resolvedAt = try container.decodeTimestampIfPresent(forKey: .resolvedAt)
    }

    /// Weekly cards name the player's team before their opponent; season cards
    /// show the stable player-season identity.
    var identityLine: String {
        guard let week, let opponent else { return "\(season) · \(team)" }
        return "\(season) · Week \(week) · \(team) vs. \(opponent)"
    }

    /// A weekly result is only impressive relative to its position: a 12-point
    /// quarterback day disappoints, a 12-point tight end day is useful. Season
    /// lots deliberately have none — their equivalent needs a server-computed
    /// percentile, not a client guess from one total.
    var revealTier: RevealTier? {
        guard isWeekly, let points else { return nil }
        let (rough, great): (Double, Double) = switch position {
        case "QB": (15, 25)
        case "TE": (8, 16)
        default: (10, 20)
        }
        return points < rough ? .rough : points >= great ? .great : .solid
    }

    enum RevealTier: Sendable {
        case rough, solid, great

        var copy: String {
            switch self {
            case .rough: "Rough outing"
            case .solid: "Solid game"
            case .great: "Big game"
            }
        }
    }
}

/// `auction_players` — one seat, with the profile identity joined in.
struct AuctionSeat: Equatable, Sendable, Decodable, Identifiable {
    let userId: UUID
    let seat: Int
    let budget: Int
    let usedPassToken: Bool
    let usedScoutToken: Bool
    let usedSealToken: Bool
    let name: String
    let avatarURL: URL?

    var id: UUID { userId }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case seat, budget
        case usedPassToken = "used_pass_token"
        case usedScoutToken = "used_scout_token"
        case usedSealToken = "used_seal_token"
        case profiles
    }

    private struct Profile: Decodable {
        let displayName: String?
        let avatarURL: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case avatarURL = "avatar_url"
        }
    }

    init(
        userId: UUID, seat: Int, budget: Int, usedPassToken: Bool = false, usedScoutToken: Bool = false,
        usedSealToken: Bool = false, name: String = "Unknown player", avatarURL: URL? = nil
    ) {
        self.userId = userId
        self.seat = seat
        self.budget = budget
        self.usedPassToken = usedPassToken
        self.usedScoutToken = usedScoutToken
        self.usedSealToken = usedSealToken
        self.name = name
        self.avatarURL = avatarURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        seat = try container.decode(Int.self, forKey: .seat)
        budget = try container.decode(Int.self, forKey: .budget)
        usedPassToken = try container.decodeIfPresent(Bool.self, forKey: .usedPassToken) ?? false
        usedScoutToken = try container.decodeIfPresent(Bool.self, forKey: .usedScoutToken) ?? false
        usedSealToken = try container.decodeIfPresent(Bool.self, forKey: .usedSealToken) ?? false
        let profile = try container.decodeIfPresent(Profile.self, forKey: .profiles)
        name = profile?.displayName ?? "Unknown player"
        avatarURL = profile?.avatarURL.flatMap(URL.init(string:))
    }

    /// A replicated seat row carries no profile, so it takes the identity of
    /// the row it replaces.
    func named(like existing: AuctionSeat) -> AuctionSeat {
        AuctionSeat(
            userId: userId, seat: seat, budget: budget, usedPassToken: usedPassToken,
            usedScoutToken: usedScoutToken, usedSealToken: usedSealToken,
            name: existing.name, avatarURL: existing.avatarURL
        )
    }
}

/// `auction_bids` — append-only; a raise or a pass.
struct AuctionBid: Equatable, Sendable, Decodable {
    enum Action: String, Decodable, Sendable { case raise, pass }

    let seq: Int
    let bidSeq: Int
    let userId: UUID
    let action: Action
    let price: Int?

    private enum CodingKeys: String, CodingKey {
        case seq
        case bidSeq = "bid_seq"
        case userId = "user_id"
        case action, price
    }
}

/// A scouted tier — RLS-scoped to its own owner, so the rows this client ever
/// receives are only the viewer's own.
struct ScoutHint: Equatable, Sendable, Decodable {
    let seq: Int
    let userId: UUID
    let tier: String

    private enum CodingKeys: String, CodingKey {
        case seq
        case userId = "user_id"
        case tier
    }
}

/// A sealed-round bid amount, RLS-scoped the same way: an opponent's amount
/// never reaches this client, win or lose.
struct SealedBid: Equatable, Sendable, Decodable {
    let seq: Int
    let userId: UUID
    let amount: Int

    private enum CodingKeys: String, CodingKey {
        case seq
        case userId = "user_id"
        case amount
    }
}

/// Presence, not value: readable by any match member, so "waiting on Tasha" is
/// renderable without the amount leaking.
struct SealedBidStatus: Equatable, Sendable, Decodable {
    let seq: Int
    let userId: UUID
    let submitted: Bool

    private enum CodingKeys: String, CodingKey {
        case seq
        case userId = "user_id"
        case submitted
    }
}

// MARK: - Snapshot and events

/// Everything the screen holds, as one value: a full re-read produces one, and
/// payloads are merged into it.
struct AuctionSnapshot: Equatable, Sendable {
    var turn: AuctionTurn
    /// The server's clock as of the most recently applied state.
    var serverNow: Date
    var lots: [AuctionLot]
    var seats: [AuctionSeat]
    var bids: [AuctionBid]
    var standings: [MatchStanding]
    /// `nil` for a match dealt before roster formats existed.
    var format: AuctionFormat?
    var scoutHints: [ScoutHint]
    var sealedBids: [SealedBid]
    var sealedStatuses: [SealedBidStatus]
    var matchStatus: MatchStatus
    var postGame: PostGameAction?

    init(
        turn: AuctionTurn, serverNow: Date, lots: [AuctionLot] = [], seats: [AuctionSeat] = [],
        bids: [AuctionBid] = [], standings: [MatchStanding] = [], format: AuctionFormat? = nil,
        scoutHints: [ScoutHint] = [], sealedBids: [SealedBid] = [],
        sealedStatuses: [SealedBidStatus] = [], matchStatus: MatchStatus = .playing,
        postGame: PostGameAction? = nil
    ) {
        self.turn = turn
        self.serverNow = serverNow
        self.lots = lots
        self.seats = seats
        self.bids = bids
        self.standings = standings
        self.format = format
        self.scoutHints = scoutHints
        self.sealedBids = sealedBids
        self.sealedStatuses = sealedStatuses
        self.matchStatus = matchStatus
        self.postGame = postGame
    }
}

/// One payload from a live auction, already decoded into the shape the screen
/// holds. See `MatchEvent` for why a match applies rows rather than refreshing.
enum AuctionEvent: Equatable, Sendable {
    /// A channel (re)subscribed — a first connect counts. The one condition
    /// only the subscription itself can know about.
    case subscribed
    case turn(AuctionTurn)
    case lot(AuctionLot)
    case seat(AuctionSeat)
    case bid(AuctionBid)
    case scoutHint(ScoutHint)
    case sealedBid(SealedBid)
    case sealedStatus(SealedBidStatus)
    case standing(MatchStanding)
    case matchStatus(MatchStatus)
    case postGame(PostGameAction)
}

// MARK: - Board rules (display only)

/// Which of the viewer's three states the controls are in. "Sealed" is its own
/// case — every live player acts in the same window, so there is no single seat
/// whose turn it is.
enum ViewerPhase: Equatable, Sendable {
    case lotPreview, biddingSelf, biddingOther, sold, sealed
}

/// Why the controls are off. `nil` means they are on.
enum Blocked: Equatable, Sendable {
    case notYourTurn, noSlot, flexWouldStrand, passed, cannotAfford

    func text(position: String) -> String {
        switch self {
        case .notYourTurn: "Waiting on another player"
        case .noSlot: "Your \(position) slots are full."
        case .flexWouldStrand: "Someone else still needs this position"
        case .passed: "You passed on this lot"
        case .cannotAfford: "You can't afford the next raise"
        }
    }
}

/// A token's state in the tray: usable right now, used up for the rest of the
/// match, or not applicable to this moment.
enum TokenState: Equatable, Sendable {
    case usable, inactive, used
}

enum AuctionRules {
    /// How many lots the strip should show: the ones already behind the table,
    /// the one on the block, and however many more roster slots are still open.
    ///
    /// The dealt `lotCount` includes spare RB/WR/TE lots that exist only so FLEX
    /// can never strand anybody, and the match ends the moment every roster is
    /// full, so showing it leaves empty cells at the end that look like lots
    /// nobody played. Every lot that is actually put up sells (an eligible
    /// player can always take it for $0) and fills exactly one slot, so what is
    /// left to play is the open slots across the table, less the current lot if
    /// it is still unsold.
    ///
    /// An estimate that tracks the real board: a lot skipped as unusable moves
    /// `currentLot` on without filling anything, and a Pass-token decline redraws
    /// a replacement, so the count can grow by one at those moments. It never
    /// exceeds `lotCount`, which stays the server's hard cap. Mirrors the web's
    /// `playableLotCount`.
    static func playableLotCount(
        turn: AuctionTurn, lots: [AuctionLot], seats: [AuctionSeat], format: AuctionFormat?
    ) -> Int {
        let perPlayer = rosterSlots(format).count
        let open = seats.reduce(0) { sum, seat in
            let won = lots.filter { $0.winnerId == seat.userId && $0.slot != nil }.count
            return sum + max(0, perPlayer - won)
        }
        let current = Self.lot(lots, at: turn.currentLot)
        let onTheBlock = current != nil && current?.winnerId == nil && turn.phase != .sold ? 1 : 0
        return min(turn.lotCount, turn.currentLot + max(0, open - onTheBlock))
    }

    /// The two raises the rules allow. Anything else is refused, not clamped.
    static let increments = [1, 5]

    /// A match may predate roster formats; those boards retain the original shape.
    static func limits(_ format: AuctionFormat?) -> [Slot: Int] {
        format?.limits ?? [.qb: 1, .rb: 1, .wr: 1, .te: 1, .flex: 1]
    }

    /// Every visible roster position, in QB/RB/WR/TE/FLEX order.
    static func rosterSlots(_ format: AuctionFormat?) -> [RosterSlot] {
        let limits = limits(format)
        return Slot.allCases.flatMap { slot -> [RosterSlot] in
            let count = limits[slot] ?? 0
            return (0..<count).map { offset in
                RosterSlot(slot: slot, index: offset + 1, label: count == 1 ? slot.rawValue : "\(slot.rawValue) \(offset + 1)")
            }
        }
    }

    static func lot(_ lots: [AuctionLot], at seq: Int) -> AuctionLot? {
        lots.first { $0.seq == seq }
    }

    /// Replaces the lot with the same seq, or appends it (a redrawn lot after a
    /// Pass token), keeping seq order.
    static func upserting(_ lot: AuctionLot, into lots: [AuctionLot]) -> [AuctionLot] {
        if lots.contains(where: { $0.seq == lot.seq }) {
            return lots.map { $0.seq == lot.seq ? lot : $0 }
        }
        return (lots + [lot]).sorted { $0.seq < $1.seq }
    }

    /// The opening price is $0, and an uncontested lot goes for it.
    static func standingPrice(_ bids: [AuctionBid], seq: Int) -> Int {
        bids.filter { $0.seq == seq && $0.action == .raise }.map { $0.price ?? 0 }.max() ?? 0
    }

    static func highBidder(_ bids: [AuctionBid], seq: Int) -> UUID? {
        bids.filter { $0.seq == seq && $0.action == .raise }.max { $0.bidSeq < $1.bidSeq }?.userId
    }

    static func hasPassed(_ bids: [AuctionBid], seq: Int, userId: UUID) -> Bool {
        bids.contains { $0.seq == seq && $0.userId == userId && $0.action == .pass }
    }

    /// A player's roster is the slots on the lots they won — there is no roster table.
    static func filledSlots(_ lots: [AuctionLot], userId: UUID) -> [Slot: Int] {
        var filled: [Slot: Int] = Dictionary(uniqueKeysWithValues: Slot.allCases.map { ($0, 0) })
        for lot in lots where lot.winnerId == userId {
            if let slot = lot.slot.flatMap(Slot.init(rawValue:)) { filled[slot, default: 0] += 1 }
        }
        return filled
    }

    /// What a win on this lot would fill: the natural slot if still open,
    /// otherwise FLEX. There is no "choose a slot" step.
    static func targetSlot(for lot: AuctionLot, filled: [Slot: Int], format: AuctionFormat?) -> Slot {
        guard let position = Slot(rawValue: lot.position) else { return .flex }
        return (filled[position] ?? 0) < (limits(format)[position] ?? 0) ? position : .flex
    }

    enum Eligibility: Equatable { case eligible, noSlot, flexWouldStrand }

    /// A lot may be bid on by a player whose natural slot for it is still open.
    /// Once that slot is full, a flex-eligible position (never QB) may still be
    /// bid on for FLEX, but only if enough of this exact position remains
    /// undealt to cover every *other* player who still needs it naturally,
    /// counted in remaining slot units rather than a headcount.
    static func eligibility(
        of lot: AuctionLot, lots: [AuctionLot], seats: [AuctionSeat], userId: UUID, format: AuctionFormat?
    ) -> Eligibility {
        guard let position = Slot(rawValue: lot.position) else { return .noSlot }
        let limits = limits(format)
        let mine = filledSlots(lots, userId: userId)
        if (mine[position] ?? 0) < (limits[position] ?? 0) { return .eligible }
        if position == .qb || (mine[.flex] ?? 0) >= (limits[.flex] ?? 0) { return .noSlot }

        let remaining = lots.filter { $0.position == lot.position && $0.seq >= lot.seq && $0.winnerId == nil }.count - 1
        let othersStillNeeding = seats
            .filter { $0.userId != userId }
            .reduce(0) { sum, seat in
                sum + max(0, (limits[position] ?? 0) - (filledSlots(lots, userId: seat.userId)[position] ?? 0))
            }
        return remaining >= othersStillNeeding ? .eligible : .flexWouldStrand
    }

    static func isEligible(
        _ lot: AuctionLot, lots: [AuctionLot], seats: [AuctionSeat], userId: UUID, format: AuctionFormat?
    ) -> Bool {
        eligibility(of: lot, lots: lots, seats: seats, userId: userId, format: format) == .eligible
    }

    /// Points revealed so far on the lots a player has won.
    static func revealedTotal(_ lots: [AuctionLot], userId: UUID) -> Double {
        lots.filter { $0.winnerId == userId }.reduce(0) { $0 + ($1.points ?? 0) }
    }

    static func canAfford(price: Int, budget: Int, increment: Int) -> Bool {
        price + increment <= budget
    }

    static func viewerPhase(_ turn: AuctionTurn, viewerSeat: Int?) -> ViewerPhase {
        switch turn.phase {
        case .lotPreview: .lotPreview
        case .sold: .sold
        case .sealed: .sealed
        case .bidding: turn.turnSeat == viewerSeat ? .biddingSelf : .biddingOther
        }
    }

    static func blockedReason(
        lot: AuctionLot, me: AuctionSeat?, lots: [AuctionLot], seats: [AuctionSeat],
        turnSeat: Int?, format: AuctionFormat?, passed: Bool, price: Int
    ) -> Blocked? {
        guard let me else { return .notYourTurn }
        switch eligibility(of: lot, lots: lots, seats: seats, userId: me.userId, format: format) {
        case .noSlot: return .noSlot
        case .flexWouldStrand: return .flexWouldStrand
        case .eligible: break
        }
        if passed { return .passed }
        if turnSeat != me.seat { return .notYourTurn }
        // Not a block on its own: a player with nothing left can still take an
        // uncontested lot for $0, so an empty wallet costs contested lots and
        // never costs slots. It only closes the raise buttons.
        if price + (increments.min() ?? 1) > me.budget { return .cannotAfford }
        return nil
    }

    /// How many of a player's three single-use abilities they have left to
    /// spend this match, total — not per ability. A match dealt before tokens
    /// existed has no format, so every ability stays unavailable.
    static func tokensRemaining(format: AuctionFormat?, seat: AuctionSeat?) -> Int {
        guard let format, let seat else { return 0 }
        let used = [seat.usedPassToken, seat.usedScoutToken, seat.usedSealToken].filter { $0 }.count
        return max(0, format.tokenCount - used)
    }
}
