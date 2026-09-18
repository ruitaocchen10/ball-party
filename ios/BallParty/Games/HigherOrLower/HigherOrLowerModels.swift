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

    /// Sudden death is two phases, everywhere a caller only needs "is it live".
    var isSuddenDeath: Bool { self == .suddenDeathCall || self == .suddenDeathReveal }

    /// A phase in which the server will accept a call from somebody. Who
    /// exactly is a further question — in sudden death only the admitted field
    /// may call — see `LadderPlayer.canCall(in:)`.
    var acceptsCalls: Bool { self == .call || self == .suddenDeathCall }
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
    /// Set the moment this question reveals. The authoritative "this card is
    /// face up" — `points` is written in the same breath, but a screen asks
    /// this, because a reveal is also what makes other players' calls visible.
    let revealedAt: Date?

    var id: Int { ordinal }

    var isRevealed: Bool { revealedAt != nil }

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
            points: nil, revealedAt: nil
        )
    }

    init(
        ordinal: Int, playerId: String, displayName: String, position: String, season: Int,
        team: String, week: Int? = nil, opponent: String? = nil, headshotUrl: String? = nil,
        points: Double?, revealedAt: Date? = nil
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
        self.revealedAt = revealedAt
    }

    private enum CodingKeys: String, CodingKey {
        case ordinal
        case playerId = "player_id"
        case displayName = "display_name"
        case position, season, team, week, opponent
        case headshotUrl = "headshot_url"
        case points
        case revealedAt = "revealed_at"
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
        revealedAt = try container.decodeTimestampIfPresent(forKey: .revealedAt)
    }
}

/// One row of `higher_or_lower_players` — a seat's tallies, with the display
/// name the standings rail shows joined in from `profiles`.
struct LadderPlayer: Equatable, Sendable, Decodable, Identifiable {
    let userId: UUID
    /// Turn order as `start_run` froze it — random, and the last tiebreak in
    /// the live standings so two identical rows still order stably.
    let seat: Int
    /// Joined in from `profiles`, so a Realtime payload — which carries the
    /// bare row and no embed — has none. `nil` means "this payload didn't say",
    /// not "this player is nameless"; see `named(like:)`.
    let displayName: String?
    let currentStreak: Int
    let bestStreak: Int
    let correctCount: Int
    /// Latched at a question's reveal for a player who never called `tick`
    /// during it (`game-runtime.md`) — the app's only notion of "away".
    let absent: Bool
    /// Admitted to sudden death: tied on both total correct and best streak
    /// when the main ladder ended.
    let suddenDeath: Bool
    /// The sudden-death *question number* a player went out at — a smallint
    /// question index, not a timestamp (`0038`). `nil` while still alive.
    let eliminatedAt: Int?

    var id: UUID { userId }

    /// What to call this seat on screen.
    var name: String { displayName ?? "Unknown player" }

    /// This row, keeping the name an earlier read already established. A
    /// Realtime payload updates a streak or an absence without carrying the
    /// `profiles` embed, and a rail that blanked every name on each tick would
    /// be worse than one that remembers.
    func named(like previous: LadderPlayer?) -> LadderPlayer {
        guard displayName == nil, let previous, previous.userId == userId else { return self }
        return LadderPlayer(
            userId: userId, seat: seat, displayName: previous.displayName,
            currentStreak: currentStreak, bestStreak: bestStreak, correctCount: correctCount,
            absent: absent, suddenDeath: suddenDeath, eliminatedAt: eliminatedAt
        )
    }

    /// Whether this seat's two buttons should be live. The server is the actual
    /// rule (`higher_or_lower.call` rejects anything this disagrees with) —
    /// this only decides what the controls show.
    func canCall(in phase: HigherOrLowerPhase) -> Bool {
        switch phase {
        case .call: true
        case .suddenDeathCall: suddenDeath && eliminatedAt == nil
        default: false
        }
    }

    init(
        userId: UUID,
        seat: Int = 0,
        displayName: String? = nil,
        currentStreak: Int,
        bestStreak: Int,
        correctCount: Int,
        absent: Bool = false,
        suddenDeath: Bool = false,
        eliminatedAt: Int? = nil
    ) {
        self.userId = userId
        self.seat = seat
        self.displayName = displayName
        self.currentStreak = currentStreak
        self.bestStreak = bestStreak
        self.correctCount = correctCount
        self.absent = absent
        self.suddenDeath = suddenDeath
        self.eliminatedAt = eliminatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case seat
        case currentStreak = "current_streak"
        case bestStreak = "best_streak"
        case correctCount = "correct_count"
        case absent
        case suddenDeath = "sudden_death"
        case eliminatedAt = "eliminated_at"
        case profiles
    }

    private struct Profile: Decodable { let displayName: String?
        enum CodingKeys: String, CodingKey { case displayName = "display_name" }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        seat = try container.decodeIfPresent(Int.self, forKey: .seat) ?? 0
        currentStreak = try container.decode(Int.self, forKey: .currentStreak)
        bestStreak = try container.decode(Int.self, forKey: .bestStreak)
        correctCount = try container.decode(Int.self, forKey: .correctCount)
        absent = try container.decodeIfPresent(Bool.self, forKey: .absent) ?? false
        suddenDeath = try container.decodeIfPresent(Bool.self, forKey: .suddenDeath) ?? false
        eliminatedAt = try container.decodeIfPresent(Int.self, forKey: .eliminatedAt)
        displayName = try container.decodeIfPresent(Profile.self, forKey: .profiles)?.displayName
    }
}

/// One row of `higher_or_lower_call_statuses`, which deliberately carries no
/// columns beyond its key: its mere existence — visible to every match member,
/// unlike the call itself — is what lets the rail show a "locked in" dot
/// without revealing which way anyone called (`game-runtime.md`).
struct CallStatus: Equatable, Sendable, Decodable {
    let question: Int
    let userId: UUID

    private enum CodingKeys: String, CodingKey {
        case question
        case userId = "user_id"
    }
}

/// One row of `public.match_players` — the platform's per-match standings,
/// written once by `finish_match` at completion.
struct MatchStanding: Equatable, Sendable, Decodable, Identifiable {
    let userId: UUID
    /// 1-based, shared by a genuine tie.
    let placement: Int?
    /// The score `complete_match` composed: total correct plus best streak in
    /// the thousandths, or a sudden-death rank. Read only as the sort tiebreak
    /// behind `placement`, never shown.
    let rawScore: Double?

    var id: UUID { userId }

    init(userId: UUID, placement: Int?, rawScore: Double? = nil) {
        self.userId = userId
        self.placement = placement
        self.rawScore = rawScore
    }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case placement
        case rawScore = "raw_score"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        placement = try container.decodeIfPresent(Int.self, forKey: .placement)
        rawScore = try container.decodeNumericIfPresent(forKey: .rawScore)
    }
}

/// One payload from a live match, already decoded into the shape the screen
/// holds.
///
/// Unlike the lobby channel — which refreshes the whole page per event — a
/// match applies payloads directly, because a server round trip per move would
/// reintroduce exactly the latency the design avoids (`realtime.md`). So these
/// carry rows, not just the fact that something changed.
///
/// One stream, two channels: `higher-or-lower:${matchId}` for the game and
/// `post-game:${matchId}` for the host's "replay or back to the lobby" choice.
/// They stay separate topics on the wire, as the contract says, and are merged
/// here because one screen consumes both and a reconcile prompted by either is
/// correct.
enum MatchEvent: Equatable, Sendable {
    /// A channel (re)subscribed — a first connect counts too. The whole of the
    /// reconnect and mid-match-rejoin contract: re-read everything.
    case subscribed
    /// A `higher_or_lower_matches` row.
    case board(BoardPosition)
    /// A `higher_or_lower_cards` row — an update to a dealt card, or a brand
    /// new ordinal appended past the pre-dealt ladder.
    case card(LadderCard)
    /// A `higher_or_lower_players` row: somebody's streak, absence, or
    /// sudden-death standing changed.
    case player(LadderPlayer)
    /// A `higher_or_lower_calls` insert — only ever one RLS lets this viewer
    /// see, which is their own until the question reveals.
    case call(LadderCall)
    /// A `higher_or_lower_call_statuses` insert: a seat locked in.
    case callStatus(CallStatus)
    /// A `match_players` row, written once at completion.
    case standing(MatchStanding)
    /// `matches.status` changed — read for one thing only: pausing.
    case matchStatus(MatchStatus)
    /// The host chose what happens next.
    case postGame(PostGameAction)
}

/// `public.post_game_actions` — a finished match's one-time next destination.
struct PostGameAction: Equatable, Sendable, Decodable {
    enum Choice: String, Decodable, Sendable { case replay, lobby }

    let choice: Choice
    /// The already-dealt next match, for a `replay`.
    let nextMatchId: UUID?

    init(choice: Choice, nextMatchId: UUID?) {
        self.choice = choice
        self.nextMatchId = nextMatchId
    }

    private enum CodingKeys: String, CodingKey {
        case choice
        case nextMatchId = "next_match_id"
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

/// One `higher_or_lower_matches` row, as a Realtime payload delivers it.
///
/// Everything `HigherOrLowerBoard` has except `server_now`, which is `now()` at
/// *read* time and so exists only on an RPC response. A payload is applied over
/// the board with `HigherOrLowerBoard.applying(_:)`, which keeps the last
/// authoritative `serverNow` rather than substituting this device's clock.
struct BoardPosition: Equatable, Sendable, Decodable {
    let questionCount: Int
    let spareCount: Int
    let currentQuestion: Int
    let scoringMode: ScoringMode
    let seasonFrom: Int
    let seasonTo: Int
    let phase: HigherOrLowerPhase
    let phaseDeadline: Date?

    init(
        questionCount: Int,
        spareCount: Int,
        currentQuestion: Int,
        scoringMode: ScoringMode,
        seasonFrom: Int,
        seasonTo: Int,
        phase: HigherOrLowerPhase,
        phaseDeadline: Date?
    ) {
        self.questionCount = questionCount
        self.spareCount = spareCount
        self.currentQuestion = currentQuestion
        self.scoringMode = scoringMode
        self.seasonFrom = seasonFrom
        self.seasonTo = seasonTo
        self.phase = phase
        self.phaseDeadline = phaseDeadline
    }

    private enum CodingKeys: String, CodingKey {
        case questionCount = "question_count"
        case spareCount = "spare_count"
        case currentQuestion = "current_question"
        case scoringMode = "scoring_mode"
        case seasonFrom = "season_from"
        case seasonTo = "season_to"
        case phase
        case phaseDeadline = "phase_deadline"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questionCount = try container.decode(Int.self, forKey: .questionCount)
        spareCount = try container.decode(Int.self, forKey: .spareCount)
        currentQuestion = try container.decode(Int.self, forKey: .currentQuestion)
        scoringMode = try container.decode(ScoringMode.self, forKey: .scoringMode)
        seasonFrom = try container.decode(Int.self, forKey: .seasonFrom)
        seasonTo = try container.decode(Int.self, forKey: .seasonTo)
        phase = try container.decode(HigherOrLowerPhase.self, forKey: .phase)
        phaseDeadline = try container.decodeTimestampIfPresent(forKey: .phaseDeadline)
    }
}

extension HigherOrLowerBoard {
    /// This board moved to the position a Realtime payload just reported.
    ///
    /// `serverNow` is deliberately carried over: a row payload has no server
    /// timestamp, and substituting this device's clock would corrupt the offset
    /// the countdown is measured against. The next reconcile supplies a fresh
    /// authoritative one.
    func applying(_ position: BoardPosition) -> HigherOrLowerBoard {
        HigherOrLowerBoard(
            matchId: matchId,
            questionCount: position.questionCount,
            spareCount: position.spareCount,
            currentQuestion: position.currentQuestion,
            scoringMode: position.scoringMode,
            seasonFrom: position.seasonFrom,
            seasonTo: position.seasonTo,
            phase: position.phase,
            phaseDeadline: position.phaseDeadline,
            serverNow: serverNow
        )
    }
}

/// Everything a screen needs to render one moment of a match — the projection
/// the web's `refetch` assembles from six queries. Always read as a set, so a
/// screen never shows a board from one moment beside cards from another.
///
/// A solo match uses the same shape: `players` has one row, and
/// `statuses`/`standings` stay empty until there is anything to put in them.
///
/// Which room the match belongs to is deliberately absent — that is the
/// lobby's fact, not the game's, and reaches the screen from the room that
/// pushed it (`architecture.md`: a game may never import lobbies).
struct HigherOrLowerSnapshot: Equatable, Sendable {
    /// Every field is a `var` because a live screen merges payloads into the
    /// snapshot it already holds rather than re-reading the server for each
    /// one — see `MatchViewModel`.
    var board: HigherOrLowerBoard
    var cards: [LadderCard]
    var players: [LadderPlayer]
    var calls: [LadderCall]
    /// Who has locked in this question, without saying which way.
    var statuses: [CallStatus]
    /// Written once, at completion.
    var standings: [MatchStanding]
    /// Read for one thing only: whether the match is `paused`.
    var matchStatus: MatchStatus
    /// A choice already made for a finished match — so a screen opened after
    /// the host chose still follows everyone else.
    var postGame: PostGameAction?

    init(
        board: HigherOrLowerBoard,
        cards: [LadderCard],
        players: [LadderPlayer],
        calls: [LadderCall],
        statuses: [CallStatus] = [],
        standings: [MatchStanding] = [],
        matchStatus: MatchStatus = .playing,
        postGame: PostGameAction? = nil
    ) {
        self.board = board
        self.cards = cards
        self.players = players
        self.calls = calls
        self.statuses = statuses
        self.standings = standings
        self.matchStatus = matchStatus
        self.postGame = postGame
    }

    // MARK: The two cards a question puts side by side
    //
    // Card 0 is the seed anchor, so question k compares card k against card
    // k-1. Every card past the first is both a challenger and, once it
    // reveals, the anchor for the question after it — one row, two moments,
    // which is why this is one lookup rather than two tables. Solo and group
    // read it identically, so it lives on the snapshot they share rather than
    // once in each view model.

    /// The face-up card the challenger is priced against.
    var anchor: LadderCard? {
        cards.first { $0.ordinal == board.currentQuestion - 1 }
    }

    /// The card being called, with its points concealed until the *board*
    /// says the question revealed. The card and board rows commit together,
    /// but Realtime delivers them independently, and the phase is the
    /// authoritative permission to show an answer.
    var challenger: LadderCard? {
        guard let card = cards.first(where: { $0.ordinal == board.currentQuestion }) else { return nil }
        return board.phase.showsChallengerPoints ? card : card.concealingPoints()
    }

    /// One player's call on the question the table is on, if this viewer may
    /// see it.
    func call(at question: Int, by userId: UUID) -> LadderCall? {
        calls.first { $0.question == question && $0.userId == userId }
    }

    func currentCall(by userId: UUID) -> LadderCall? {
        call(at: board.currentQuestion, by: userId)
    }

    func player(_ userId: UUID) -> LadderPlayer? {
        players.first { $0.userId == userId }
    }
}

// `PostgresTimestamp` and the `numeric` decoding helper both moved to
// `Runtime/Contract/PostgresValues.swift` when the lobby models needed them
// too — a game may not be where the platform reads its timestamps from.
