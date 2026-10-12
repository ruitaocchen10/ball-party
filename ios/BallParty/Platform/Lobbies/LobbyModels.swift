import Foundation

// Hand-maintained `Codable` mirrors of the lobby shapes in
// `docs/architecture/game-runtime.md` ("Getting into a match") and the three
// levels in `docs/architecture/lobbies/lobbies.md`. Same deal as
// `HigherOrLowerModels.swift`: there is no Postgres-to-Swift codegen, so a
// column added on the server has to be added here on purpose.

/// A failed lobby RPC, reduced to what a screen can act on: the raised message.
/// Separate from `HigherOrLowerServerError` because lobbies are their own module
/// with their own vocabulary of failures — the web keeps the same split between
/// `LOBBY_MESSAGES` and a game's own `CALL_MESSAGES`.
struct LobbyServerError: Error, Equatable, Sendable {
    let message: String
}

/// A game a room can be set to play.
///
/// `lobbies.selected_game` is free text on the server and the same room may
/// have been pointed at a game iOS doesn't ship yet from the web, so an unrecognised value is a legitimate state to read back rather
/// than a decoding failure — see `selectedMatchGame`.
enum MatchGame: String, Sendable, Equatable, CaseIterable, Identifiable {
    case higherOrLower = "higher_or_lower"
    case auctionTeamBuilder = "auction_team_builder"
    case wavelength = "wavelength_2v2"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .higherOrLower: "Higher or Lower"
        case .auctionTeamBuilder: "Auction Team Builder"
        case .wavelength: "2v2 Wavelength"
        }
    }

    /// The one-line pitch on the game's card.
    var tagline: String {
        switch self {
        case .higherOrLower: "Call the next card. Make the streak last."
        case .auctionTeamBuilder: "Bid on mystery fantasy lots to fill a roster."
        case .wavelength: "Give a one-shot clue and find the hidden target."
        }
    }

    /// How many people the game seats.
    var playersLabel: String {
        switch self {
        case .wavelength: "2 or 4 players"
        case .higherOrLower, .auctionTeamBuilder: "2–4 players"
        }
    }
}

/// `public.lobbies` — the room itself.
struct Lobby: Equatable, Sendable, Decodable {
    let id: UUID
    /// The room's link token: long and random, never shown or typed.
    let code: String
    let hostId: UUID
    /// Raw, so a game iOS can't start still reads back honestly.
    let selectedGame: String?
    let closedAt: Date?
    /// The host's saved settings for the games on offer, readable by everyone in
    /// the room. Empty until the host changes something.
    let gameFormat: LobbyGameFormat

    /// The selection, when it is one this app can actually start.
    var selectedMatchGame: MatchGame? { selectedGame.flatMap(MatchGame.init(rawValue:)) }

    var isClosed: Bool { closedAt != nil }

    init(
        id: UUID, code: String, hostId: UUID, selectedGame: String? = nil, closedAt: Date? = nil,
        gameFormat: LobbyGameFormat = LobbyGameFormat()
    ) {
        self.id = id
        self.code = code
        self.hostId = hostId
        self.selectedGame = selectedGame
        self.closedAt = closedAt
        self.gameFormat = gameFormat
    }

    private enum CodingKeys: String, CodingKey {
        case id, code
        case hostId = "host_id"
        case selectedGame = "selected_game"
        case closedAt = "closed_at"
        case gameFormat = "game_format"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        hostId = try container.decode(UUID.self, forKey: .hostId)
        selectedGame = try container.decodeIfPresent(String.self, forKey: .selectedGame)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
            .map { try PostgresTimestamp.parse($0) }
        // A room from before the column existed, or a read that didn't ask for
        // it, has no saved settings rather than being unreadable.
        gameFormat = (try? container.decodeIfPresent(LobbyGameFormat.self, forKey: .gameFormat)) ?? LobbyGameFormat()
    }
}

/// `public.lobbies.game_format`: the host's settings for each game the room
/// can play, kept on the room so everyone in it can see what is being set up.
///
/// An object keyed by game, each value that game's own settings. The platform
/// never reads it (it doesn't know what a game is); the clients write what the
/// host's pickers hold and read it back for everyone else. Values are raw
/// strings, not enums, so a setting a newer client wrote still decodes here and
/// is shown as written.
struct LobbyGameFormat: Equatable, Sendable, Codable {
    var higherOrLower: HigherOrLower?
    var auction: Auction?
    var wavelength: Wavelength?

    init(
        higherOrLower: HigherOrLower? = nil, auction: Auction? = nil,
        wavelength: Wavelength? = nil
    ) {
        self.higherOrLower = higherOrLower
        self.auction = auction
        self.wavelength = wavelength
    }

    private enum CodingKeys: String, CodingKey {
        case higherOrLower = "higher_or_lower"
        case auction = "auction_team_builder"
        case wavelength = "wavelength_2v2"
    }

    struct HigherOrLower: Equatable, Sendable, Codable {
        var scoringMode: String
        /// Nil is the whole pool.
        var seasonFrom: Int?
        var seasonTo: Int?

        private enum CodingKeys: String, CodingKey {
            case scoringMode = "scoring_mode"
            case seasonFrom = "season_from"
            case seasonTo = "season_to"
        }
    }

    struct Auction: Equatable, Sendable, Codable {
        var scoringMode: String
        var rosterPreset: String
        var tokenCount: Int
        var seasonFrom: Int?
        var seasonTo: Int?

        private enum CodingKeys: String, CodingKey {
            case scoringMode = "scoring_mode"
            case rosterPreset = "roster_preset"
            case tokenCount = "token_count"
            case seasonFrom = "season_from"
            case seasonTo = "season_to"
        }
    }

    struct Wavelength: Equatable, Sendable, Codable {
        var mode: String
        var preset: String
    }

    /// One row of the settings a card shows: "Scoring", "Season total".
    struct Line: Equatable, Sendable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    /// The settings for `game` as plain rows, falling back to the game's defaults
    /// for anything the host hasn't touched. Both the host's own pickers and
    /// everyone else's read-only card start from the same defaults, so an
    /// untouched room reads the same to all of them.
    func lines(for game: MatchGame) -> [Line] {
        func era(_ from: Int?, _ to: Int?) -> String {
            guard let from, let to else { return "All seasons" }
            return SeasonRange(from: from, to: to).label
        }
        func scoring(_ raw: String) -> String { ScoringMode(rawValue: raw)?.label ?? raw }

        switch game {
        case .higherOrLower:
            let f = higherOrLower
            return [
                Line(label: "Scoring", value: scoring(f?.scoringMode ?? ScoringMode.seasonTotal.rawValue)),
                Line(label: "Era", value: era(f?.seasonFrom, f?.seasonTo)),
            ]
        case .auctionTeamBuilder:
            let f = auction
            let preset = f?.rosterPreset ?? RosterPreset.standard.rawValue
            let tokens = f?.tokenCount ?? 1
            return [
                Line(label: "Scoring", value: scoring(f?.scoringMode ?? ScoringMode.weekly.rawValue)),
                Line(label: "Roster", value: RosterPreset(rawValue: preset)?.label ?? preset),
                Line(label: "Tokens", value: tokens == 0 ? "Off" : "\(tokens) per player"),
                Line(label: "Era", value: era(f?.seasonFrom, f?.seasonTo)),
            ]
        case .wavelength:
            let mode = wavelength?.mode ?? WavelengthMode.coop.rawValue
            let preset = wavelength?.preset ?? WavelengthPreset.short.rawValue
            var rows = [Line(label: "Mode", value: WavelengthMode(rawValue: mode)?.label ?? mode)]
            if mode == WavelengthMode.coop.rawValue {
                rows.append(Line(label: "Length", value: WavelengthPreset(rawValue: preset)?.label ?? preset))
            }
            return rows
        }
    }
}

/// One active row of `public.lobby_members`, with the profile identity the
/// roster shows joined in from `profiles`.
struct LobbyMember: Equatable, Sendable, Decodable, Identifiable {
    let userId: UUID
    let displayName: String
    let avatarURL: URL?
    /// A returning player keeps their original `joined_at` (`join_lobby` is an
    /// upsert), so this is a stable seat order rather than "most recent first".
    let joinedAt: Date

    var id: UUID { userId }

    init(userId: UUID, displayName: String, avatarURL: URL? = nil, joinedAt: Date) {
        self.userId = userId
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.joinedAt = joinedAt
    }

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case joinedAt = "joined_at"
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(UUID.self, forKey: .userId)
        joinedAt = try PostgresTimestamp.parse(try container.decode(String.self, forKey: .joinedAt))
        let profile = try container.decodeIfPresent(Profile.self, forKey: .profiles)
        displayName = profile?.displayName ?? "Unknown player"
        avatarURL = profile?.avatarURL.flatMap(URL.init(string:))
    }
}

/// One row of `public.matches`, as the lobby screen reads it.
struct RunMatch: Equatable, Sendable, Decodable {
    let id: UUID
    let status: MatchStatus
    /// Which game the match is, so the room can open the right screen. Raw, for
    /// the same reason `Lobby.selectedGame` is: a game iOS can't play still reads
    /// back honestly.
    let game: String?

    /// The game this app can play, when it is one. Every match before the
    /// auction shipped here was Higher or Lower, so a missing value reads as it.
    var matchGame: MatchGame { game.flatMap(MatchGame.init(rawValue:)) ?? .higherOrLower }

    init(id: UUID, status: MatchStatus, game: String? = nil) {
        self.id = id
        self.status = status
        self.game = game
    }
}

/// The lobby's one active `runs` row, with the roster it froze at start.
///
/// The two rosters are deliberately different things (see `lobbies.md`): who is
/// in the room is `LobbySnapshot.members`, who is playing this sitting is
/// `seatedUserIds`. Somebody who walked in after the freeze waits in the room
/// instead of being sent to a board they cannot act on.
struct LiveRun: Equatable, Sendable, Decodable {
    let matches: [RunMatch]
    let seatedUserIds: Set<UUID>

    var inFlightMatch: RunMatch? { matches.first { $0.status.isInFlight } }

    func seats(_ userId: UUID) -> Bool { seatedUserIds.contains(userId) }

    init(matches: [RunMatch], seatedUserIds: Set<UUID>) {
        self.matches = matches
        self.seatedUserIds = seatedUserIds
    }

    private enum CodingKeys: String, CodingKey {
        case matches
        case runParticipants = "run_participants"
    }

    private struct Participant: Decodable { let userId: UUID
        enum CodingKeys: String, CodingKey { case userId = "user_id" }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        matches = try container.decode([RunMatch].self, forKey: .matches)
        seatedUserIds = Set(
            try container.decode([Participant].self, forKey: .runParticipants).map(\.userId)
        )
    }
}

/// Everything the room screen needs at one moment, read as a set so it never
/// shows a roster from one moment beside a run from another.
struct LobbySnapshot: Equatable, Sendable {
    let lobby: Lobby
    /// Active members only, in join order.
    let members: [LobbyMember]
    /// The active run, if a game is under way or being dealt.
    let run: LiveRun?
    /// Matches each player has won in this room, for as long as it has been
    /// open. Absent means none. Not a stored stat: the web's `fetchLobbyWins`
    /// reads the same thing, `placement = 1` on the room's completed matches.
    let wins: [UUID: Int]

    init(lobby: Lobby, members: [LobbyMember], run: LiveRun? = nil, wins: [UUID: Int] = [:]) {
        self.lobby = lobby
        self.members = members
        self.run = run
        self.wins = wins
    }

    /// One row of `match_players` with `placement = 1`.
    struct WinRow: Decodable, Equatable, Sendable {
        let userId: UUID
        enum CodingKeys: String, CodingKey { case userId = "user_id" }
    }

    /// user id → win count.
    static func tallyWins(_ rows: [WinRow]) -> [UUID: Int] {
        rows.reduce(into: [:]) { $0[$1.userId, default: 0] += 1 }
    }
}

/// What arrives on the `lobby:${lobbyId}` channel.
///
/// The web applies no payloads here — every event triggers one full refresh —
/// and `realtime.md` calls that a deliberate difference in cost from a match
/// channel, not an oversight: a server round trip per lobby event is cheap, and
/// lobby membership changes rarely. So this stream carries the *fact* that
/// something changed rather than the row that changed.
enum LobbyEvent: Equatable, Sendable {
    /// The channel (re)subscribed — a first connect counts. The one condition
    /// only the subscription itself can know about (`realtime.md`), and the
    /// whole of iOS's reconnect contract: re-read everything.
    case subscribed
    /// A `lobby_members` / `lobbies` / `runs` / `matches` row changed.
    case changed
}

/// The link a room is shared by. The path must match the web's room route
/// (`/lobby/[code]`); the clients build it, SQL only owns the code.
enum RoomLink {
    static let pathPrefix = "lobby"

    static func url(code: String, base: URL = SiteLinks.home) -> URL {
        base.appendingPathComponent(pathPrefix).appendingPathComponent(code)
    }

    /// The room code in a link the app was opened with, or `nil` when the URL
    /// isn't a room link. Accepts `https://ballparty.social/lobby/<code>` (and
    /// `www.`), with or without a trailing slash. The code is only
    /// shape-checked; `join_lobby` decides whether the room exists.
    static func code(from url: URL, base: URL = SiteLinks.home) -> String? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              let baseHost = base.host?.lowercased(),
              host == baseHost || host == "www.\(baseHost)"
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == pathPrefix else { return nil }
        let code = parts[1]
        guard (1...64).contains(code.count),
              code.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) })
        else { return nil }
        return code.uppercased()
    }
}

// MARK: - Seat form

/// One row of `lobby_member_match_history` (migration 0080): a completed match
/// of someone currently seated in the room.
struct LobbyMatchHistoryRow: Decodable, Equatable, Sendable {
    let userId: UUID?
    let endedAt: Date?
    let placement: Int?

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id", endedAt = "ended_at", placement
    }

    init(userId: UUID?, endedAt: Date?, placement: Int?) {
        self.userId = userId
        self.endedAt = endedAt
        self.placement = placement
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decodeIfPresent(UUID.self, forKey: .userId)
        endedAt = try c.decodeTimestampIfPresent(forKey: .endedAt)
        placement = try c.decodeIfPresent(Int.self, forKey: .placement)
    }
}

/// What a player brings into the room, shown under their seat: win rate, best
/// streak and how their last few games went. The Swift counterpart of the web's
/// `summarizeProfile` as the lobby roster reads it (`MemberRoster`'s `PlayerForm`).
struct LobbyMemberForm: Equatable, Sendable {
    /// How many recent results the dots show — the web's `recentMatches` default.
    static let recentLimit = 3

    let gamesPlayed: Int
    /// Whole percent of games won.
    let winRate: Int
    /// The longest run of consecutive wins, over everything played.
    let bestStreak: Int
    /// Newest first: `true` for a win.
    let recent: [Bool]

    /// A player with no completed games yet reads "New".
    var isNew: Bool { gamesPlayed == 0 }

    /// Rows for several players at once, grouped by player.
    static func summaries(from rows: [LobbyMatchHistoryRow]) -> [UUID: LobbyMemberForm] {
        var byUser: [UUID: [LobbyMatchHistoryRow]] = [:]
        for row in rows {
            guard let userId = row.userId, row.endedAt != nil else { continue }
            byUser[userId, default: []].append(row)
        }
        return byUser.mapValues { summarize($0) }
    }

    static func summarize(_ rows: [LobbyMatchHistoryRow]) -> LobbyMemberForm {
        let oldestFirst = rows.sorted { ($0.endedAt ?? .distantPast) < ($1.endedAt ?? .distantPast) }
        let wins = oldestFirst.filter { $0.placement == 1 }.count
        var best = 0, run = 0
        for row in oldestFirst {
            if row.placement == 1 { run += 1; best = max(best, run) } else { run = 0 }
        }
        return LobbyMemberForm(
            gamesPlayed: oldestFirst.count,
            winRate: oldestFirst.isEmpty ? 0 : Int((Double(wins) / Double(oldestFirst.count) * 100).rounded()),
            bestStreak: best,
            recent: oldestFirst.reversed().prefix(recentLimit).map { $0.placement == 1 }
        )
    }
}
