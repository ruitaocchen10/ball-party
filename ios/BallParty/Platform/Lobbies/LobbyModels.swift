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
/// have been pointed at a game iOS doesn't ship yet (the auction, the sabotage
/// draft) from the web, so an unrecognised value is a legitimate state to read
/// back rather than a decoding failure — see `selectedMatchGame`.
enum MatchGame: String, Sendable, Equatable, CaseIterable, Identifiable {
    case higherOrLower = "higher_or_lower"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .higherOrLower: "Higher or Lower"
        }
    }

    var tagline: String {
        switch self {
        case .higherOrLower: "Call the next card. Two to four players."
        }
    }
}

/// `public.lobbies` — the room itself.
struct Lobby: Equatable, Sendable, Decodable {
    let id: UUID
    /// The 5-character join code, from a mishear-resistant alphabet.
    let code: String
    let hostId: UUID
    /// Raw, so a game iOS can't start still reads back honestly.
    let selectedGame: String?
    let closedAt: Date?

    /// The selection, when it is one this app can actually start.
    var selectedMatchGame: MatchGame? { selectedGame.flatMap(MatchGame.init(rawValue:)) }

    var isClosed: Bool { closedAt != nil }

    init(id: UUID, code: String, hostId: UUID, selectedGame: String? = nil, closedAt: Date? = nil) {
        self.id = id
        self.code = code
        self.hostId = hostId
        self.selectedGame = selectedGame
        self.closedAt = closedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, code
        case hostId = "host_id"
        case selectedGame = "selected_game"
        case closedAt = "closed_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        hostId = try container.decode(UUID.self, forKey: .hostId)
        selectedGame = try container.decodeIfPresent(String.self, forKey: .selectedGame)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
            .map { try PostgresTimestamp.parse($0) }
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

    init(lobby: Lobby, members: [LobbyMember], run: LiveRun? = nil) {
        self.lobby = lobby
        self.members = members
        self.run = run
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
