import Foundation

// The friends activity feed's types: the rows of `friend_activity`
// (migrations 0188 and 0194) and the sentence each one reads as. Which friends, which
// 30 days and what is left out (a pick's chosen options never come down the
// wire) are the server's calls; nothing here filters.

/// A take's thread and answer, as `friend_activity` returns them.
struct FriendTake: Equatable, Sendable {
    let postId: UUID
    let caption: String?
    /// The take posted with the answer; nil when the friend answered without one.
    let body: String?
    let commentId: UUID?
    let replyCount: Int
    /// `{slot → chosen options}`, in the order chosen.
    let response: [UUID: [UUID]]
    let points: Int?
}

/// What happened. A `take` is an answer to a prompt that has locked, so it
/// carries the answer and the take posted with it; while a prompt is open
/// the feed only says a friend answered (`pickMade`) and the server leaves the
/// choice out. Game results are only multiplayer wins and new solo bests.
enum FriendActivityKind: Equatable, Sendable {
    case take(FriendTake)
    case pickMade(postId: UUID, caption: String?)
    /// `opponents` are the beaten players who are the caller's friends,
    /// `opponentYou` says the caller was one, `opponentCount` is everyone beaten.
    case win(matchId: UUID, game: String, score: Double?, opponents: [String], opponentYou: Bool, opponentCount: Int)
    /// `friendRank` of `friendCount` places the best among the caller and their friends.
    case highScore(game: String, score: Double, mode: String?, friendRank: Int?, friendCount: Int?)
}

struct FriendActivityEvent: Decodable, Equatable, Sendable, Identifiable {
    let kind: FriendActivityKind
    let occurredAt: Date
    /// `occurred_at` exactly as the server printed it. Paging sends this back
    /// as `p_before`, since a parsed `Date` would round off microseconds and
    /// skip events that fall inside the rounding.
    let occurredAtRaw: String
    let actor: PlayerIdentity

    var id: String {
        switch kind {
        case .take(let take): "take-\(actor.profileId)-\(take.postId)"
        case .pickMade(let postId, _): "pick_made-\(actor.profileId)-\(postId)"
        case .win(let matchId, _, _, _, _, _): "win-\(actor.profileId)-\(matchId)"
        case .highScore(let game, _, let mode, _, _): "high_score-\(actor.profileId)-\(game)-\(mode ?? "")"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type", occurredAt = "occurred_at", actorId = "actor_id"
        case username, displayName = "display_name", avatarURL = "avatar_url"
        case postId = "post_id", postCaption = "post_caption", takeBody = "take_body", commentId = "comment_id", replyCount = "reply_count", response, mode, points
        case matchId = "match_id", game, placement, rawScore = "raw_score", runMode = "run_mode"
        case opponents, opponentYou = "opponent_you", opponentCount = "opponent_count"
        case friendRank = "friend_rank", friendCount = "friend_count"
    }

    init(kind: FriendActivityKind, occurredAt: Date, occurredAtRaw: String? = nil, actor: PlayerIdentity) {
        self.kind = kind
        self.occurredAt = occurredAt
        self.occurredAtRaw = occurredAtRaw ?? ISO8601DateFormatter().string(from: occurredAt)
        self.actor = actor
    }

    /// Thrown for an event type this build doesn't know; the client drops
    /// those rather than failing the whole page.
    struct UnknownEvent: Error { let type: String }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .eventType)
        occurredAtRaw = try c.decode(String.self, forKey: .occurredAt)
        occurredAt = try PostgresTimestamp.parse(occurredAtRaw)
        actor = PlayerIdentity(
            profileId: try c.decode(UUID.self, forKey: .actorId),
            username: try c.decode(String.self, forKey: .username),
            displayName: try c.decode(String.self, forKey: .displayName),
            avatarURL: try c.decodeIfPresent(String.self, forKey: .avatarURL).flatMap(URL.init(string:))
        )
        switch type {
        case "take":
            // `{slot id: [option ids]}`; ids that aren't UUIDs would be a server bug, so they are dropped.
            let raw = try c.decodeIfPresent([String: [UUID]].self, forKey: .response) ?? [:]
            kind = .take(FriendTake(
                postId: try c.decode(UUID.self, forKey: .postId),
                caption: try c.decodeIfPresent(String.self, forKey: .postCaption),
                body: try c.decodeIfPresent(String.self, forKey: .takeBody),
                commentId: try c.decodeIfPresent(UUID.self, forKey: .commentId),
                replyCount: try c.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0,
                response: Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in UUID(uuidString: key).map { ($0, value) } }),
                points: try c.decodeIfPresent(Int.self, forKey: .points)
            ))
        case "pick_made":
            kind = .pickMade(
                postId: try c.decode(UUID.self, forKey: .postId),
                caption: try c.decodeIfPresent(String.self, forKey: .postCaption)
            )
        case "win":
            kind = .win(
                matchId: try c.decode(UUID.self, forKey: .matchId),
                game: try c.decode(String.self, forKey: .game),
                score: try c.decodeNumericIfPresent(forKey: .rawScore),
                opponents: try c.decodeIfPresent([String].self, forKey: .opponents) ?? [],
                opponentYou: try c.decodeIfPresent(Bool.self, forKey: .opponentYou) ?? false,
                opponentCount: try c.decodeIfPresent(Int.self, forKey: .opponentCount) ?? 0
            )
        case "high_score":
            kind = .highScore(
                game: try c.decode(String.self, forKey: .game),
                score: try c.decodeNumericIfPresent(forKey: .rawScore) ?? 0,
                mode: try c.decodeIfPresent(String.self, forKey: .mode),
                friendRank: try c.decodeIfPresent(Int.self, forKey: .friendRank),
                friendCount: try c.decodeIfPresent(Int.self, forKey: .friendCount)
            )
        default:
            throw UnknownEvent(type: type)
        }
    }

    /// The one-line description of the event, without the actor's name. The
    /// take, win and high-score cards draw their own bodies; this is what a
    /// screen reader hears and what an open pick shows.
    var summary: String {
        switch kind {
        case .take(let take):
            var line = "answered" + Self.onPrompt(take.caption)
            if let points = take.points, points > 0 { line += " · +\(points)" }
            return line
        case .pickMade(_, let caption):
            return "answered" + Self.onPrompt(caption) + ". Their picks show when it locks."
        case .win(_, let game, let score, _, _, _):
            var line = "won \(Self.gameName(game))"
            if let score { line += " · score \(Self.formatScore(score))" }
            return line
        case .highScore(let game, let score, let mode, _, _):
            let name = Self.gameName(game)
            if game == "qb_season_builder" {
                let board = mode.map { " (\($0))" } ?? ""
                return "set a new high score in \(name)\(board): \(score.formatted(.number.precision(.fractionLength(1))))"
            }
            return "set a new high score in \(name): \(Self.formatScore(score)) in a row"
        }
    }

    /// "you", "you and Ava", "Ava, Ben and 2 others": who a win was over. Only
    /// the caller and their friends are named.
    static func beatLine(opponents: [String], you: Bool, count: Int) -> String? {
        guard count > 0 else { return nil }
        let names = (you ? ["you"] : []) + opponents
        if names.isEmpty { return "\(count) \(count == 1 ? "player" : "players")" }
        let others = count - names.count
        let shown = others > 0 ? names + ["\(others) \(others == 1 ? "other" : "others")"] : names
        guard shown.count > 1 else { return shown[0] }
        return shown.dropLast().joined(separator: ", ") + " and " + shown[shown.count - 1]
    }

    static func gameName(_ game: String) -> String {
        if game == "qb_season_builder" { return SoloBoard.qbSeasonBuilder.title }
        return MatchGame(rawValue: game)?.label ?? humanized(game)
    }

    private static func onPrompt(_ caption: String?) -> String {
        guard let caption, !caption.isEmpty else { return "" }
        return " on “\(caption)”"
    }

    private static func humanized(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "_", with: " ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func formatScore(_ score: Double) -> String {
        score == score.rounded() ? Int(score).formatted() : score.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// One feed entry. A friend's wins on the same (UTC) day fold into one entry
/// led by the newest; `more` holds the rest.
struct FriendActivityItem: Equatable, Sendable, Identifiable {
    let event: FriendActivityEvent
    var more: [FriendActivityEvent] = []

    var id: String { event.id }

    /// Folds back-to-back wins by the same friend on one day, so a busy player doesn't fill the feed.
    static func grouped(_ events: [FriendActivityEvent]) -> [FriendActivityItem] {
        var items: [FriendActivityItem] = []
        for event in events {
            if var last = items.last,
               case .win = last.event.kind, case .win = event.kind,
               last.event.actor.profileId == event.actor.profileId,
               last.event.occurredAtRaw.prefix(10) == event.occurredAtRaw.prefix(10) {
                last.more.append(event)
                items[items.count - 1] = last
            } else {
                items.append(FriendActivityItem(event: event))
            }
        }
        return items
    }
}

/// A page of `friend_activity`, with the events this build can't read dropped.
struct FriendActivityPage: Decodable, Sendable {
    let events: [FriendActivityEvent]

    private struct Lossy: Decodable {
        let event: FriendActivityEvent?
        init(from decoder: Decoder) throws {
            event = try? FriendActivityEvent(from: decoder)
        }
    }

    init(events: [FriendActivityEvent]) { self.events = events }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var events: [FriendActivityEvent] = []
        while !container.isAtEnd {
            if let event = try container.decode(Lossy.self).event { events.append(event) }
        }
        self.events = events
    }
}
