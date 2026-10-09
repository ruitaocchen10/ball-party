import Foundation

// What Weekly Awards and Bold Predictions need beyond the slot-and-option model
// every other prompt kind fits: the player directory (an award's answer is a
// player id, and a prediction can be tagged with one), the week's games (a
// prediction can be tagged with one), and the predictions themselves.
//
// Mirrors `webapp/lib/foundation/content/prompts/players.ts` and
// `boldPredictions.ts`, which are the source of truth for the rules; the limits
// below only keep the form honest, and the server enforces them again (0171).

// MARK: - Players

/// One row of the player directory, as `prompts.search_players` and
/// `prompts.players_by_ids` return it: identity fields only, no scoring data.
struct NFLPlayer: Identifiable, Decodable, Equatable, Sendable {
    /// The nflverse gsis id — what an award's answer is made of.
    let id: String
    let name: String
    let position: String
    let team: String
    let headshotURL: URL?
    /// nflverse roster status: ACT, DEV, RES, INA or EXE.
    let status: String

    init(id: String, name: String, position: String, team: String, headshotURL: URL? = nil, status: String = "ACT") {
        self.id = id; self.name = name; self.position = position; self.team = team
        self.headshotURL = headshotURL; self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case id = "player_id"
        case name = "display_name"
        case position, team, status
        case headshotURL = "headshot_url"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        position = try c.decode(String.self, forKey: .position)
        team = try c.decode(String.self, forKey: .team)
        status = try c.decode(String.self, forKey: .status)
        headshotURL = try c.decodeIfPresent(String.self, forKey: .headshotURL).flatMap(URL.init(string:))
    }

    /// "QB · KC".
    var summary: String { "\(position) · \(team)" }

    /// The label for a player who isn't on the active roster; `nil` for one who is.
    var statusLabel: String? {
        switch status {
        case "DEV": "Practice squad"
        case "RES": "Reserve list"
        case "INA": "Inactive"
        case "EXE": "Exempt list"
        default: nil
        }
    }
}

// MARK: - The week's games

/// A game on the schedule, as far as a prediction's matchup tag needs one.
/// Read from `public.nfl_games`, the table the web reads for the same tag.
struct NFLScheduleGame: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let away: String
    let home: String
    let kickoff: Date

    init(id: String, away: String, home: String, kickoff: Date = Date(timeIntervalSince1970: 0)) {
        self.id = id; self.away = away; self.home = home; self.kickoff = kickoff
    }

    /// "Chiefs @ Bills".
    var label: String { "\(NFLTeams.name(for: away)) @ \(NFLTeams.name(for: home))" }

    private enum CodingKeys: String, CodingKey {
        case id, kickoff
        case away = "away_team"
        case home = "home_team"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        away = try c.decode(String.self, forKey: .away)
        home = try c.decode(String.self, forKey: .home)
        kickoff = try c.decodeTimestamp(forKey: .kickoff)
    }
}

// MARK: - Bold Predictions

enum BoldTargetType: String, Sendable, Equatable, CaseIterable {
    case matchup, team, player

    var title: String {
        switch self {
        case .matchup: "Matchup"
        case .team: "Team"
        case .player: "Player"
        }
    }
}

/// The one required tag on a prediction: a game id, a team code or a player id,
/// by `type`.
struct BoldTarget: Equatable, Sendable {
    let type: BoldTargetType
    let id: String
}

/// A prediction the viewer is still writing. Nothing reaches the server until
/// the whole set is locked in.
struct BoldDraft: Equatable, Sendable {
    var body: String
    var target: BoldTarget
}

struct BoldPrediction: Identifiable, Equatable, Sendable {
    let id: UUID
    let authorId: UUID
    let author: String
    var authorUsername: String? = nil
    var authorAvatarURL: URL? = nil
    let isViewer: Bool
    let body: String
    let target: BoldTarget
    let createdAt: Date
}

/// Everything the board needs to draw a tag: the week's games for matchup
/// tags, and the directory rows for whichever players are tagged. Teams need no
/// lookup — their names and art come from the code alone.
struct BoldBoardData: Equatable, Sendable {
    var weekGames: [NFLScheduleGame] = []
    var players: [String: NFLPlayer] = [:]
}

/// What a tag looks like on a prediction: a label and the art to draw. A target
/// that can't be resolved still gets a label rather than vanishing.
struct BoldTargetDescription: Equatable {
    let label: String
    let teamCodes: [String]
    let player: NFLPlayer?

    init(_ target: BoldTarget, board: BoldBoardData) {
        switch target.type {
        case .team:
            self.init(label: NFLTeams.name(for: target.id), teamCodes: [target.id], player: nil)
        case .matchup:
            if let game = board.weekGames.first(where: { $0.id == target.id }) {
                self.init(label: game.label, teamCodes: [game.away, game.home], player: nil)
            } else {
                self.init(label: "Matchup", teamCodes: [], player: nil)
            }
        case .player:
            let player = board.players[target.id]
            self.init(label: player?.name ?? "Player", teamCodes: [], player: player)
        }
    }

    private init(label: String, teamCodes: [String], player: NFLPlayer?) {
        self.label = label; self.teamCodes = teamCodes; self.player = player
    }
}

enum BoldLimits {
    static let maxPredictions = 5
    static let bodyMax = 280
}

// MARK: - Rows

/// One row of `public.bold_predictions`, read through
/// `prompts.bold_predictions_for_post` — the only sanctioned read of other
/// people's predictions.
struct BoldPredictionRow: Decodable, Equatable, Sendable {
    let id: UUID
    let postId: UUID
    let authorId: UUID
    let body: String
    let targetType: String
    let targetId: String
    let createdAt: Date

    init(id: UUID = UUID(), postId: UUID, authorId: UUID, body: String, targetType: String, targetId: String, createdAt: Date) {
        self.id = id; self.postId = postId; self.authorId = authorId; self.body = body
        self.targetType = targetType; self.targetId = targetId; self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, body
        case postId = "post_id"
        case authorId = "author_id"
        case targetType = "target_type"
        case targetId = "target_id"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        postId = try c.decode(UUID.self, forKey: .postId)
        authorId = try c.decode(UUID.self, forKey: .authorId)
        body = try c.decode(String.self, forKey: .body)
        targetType = try c.decode(String.self, forKey: .targetType)
        targetId = try c.decode(String.self, forKey: .targetId)
        createdAt = try c.decodeTimestamp(forKey: .createdAt)
    }
}

/// A post's predictions as the server will show this viewer, with the profiles
/// of the people who wrote them.
struct BoldPredictionRows: Equatable, Sendable {
    var predictions: [BoldPredictionRow] = []
    var profiles: [PromptProfileRow] = []
}

/// One row of `prompts.bold_prediction_counts`.
struct BoldPredictionCountRow: Decodable, Equatable, Sendable {
    let postId: UUID
    let predictionCount: Int

    init(postId: UUID, predictionCount: Int) {
        self.postId = postId; self.predictionCount = predictionCount
    }

    private enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case predictionCount = "prediction_count"
    }

    /// `bigint` arrives as a number or a string, like the other aggregate columns.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postId = try c.decode(UUID.self, forKey: .postId)
        predictionCount = try c.decodeNumericIfPresent(forKey: .predictionCount).map { Int($0) } ?? 0
    }
}
