import Foundation

// Home's friend-driven types: the game moments of `friend_activity` (migrations
// 0188, 0194 and 0209) and `friends_who_answered` (0209), plus the merge of both
// with the prompts into the one feed. Which friends, which 30 days and what is
// left out (a pick's chosen options never come down the wire) are the server's
// calls; nothing here filters except dropping event types this build doesn't know.

/// What happened: only game moments, a multiplayer win or a new solo best. A
/// friend's answer to a prompt is not an event; it is a line on the prompt's card.
enum FriendActivityKind: Equatable, Sendable {
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
        case .win(let matchId, _, _, _, _, _): "win-\(actor.profileId)-\(matchId)"
        case .highScore(let game, _, let mode, _, _): "high_score-\(actor.profileId)-\(game)-\(mode ?? "")"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type", occurredAt = "occurred_at", actorId = "actor_id"
        case username, displayName = "display_name", avatarURL = "avatar_url"
        case mode
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
    /// win and high-score cards draw their own bodies; this is what a screen
    /// reader hears.
    var summary: String {
        switch kind {
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


/// A friend who answered a prompt: the fact only, never the pick.
struct FriendAnswerer: Decodable, Equatable, Sendable, Identifiable {
    let postId: UUID
    let identity: PlayerIdentity
    let answeredAt: Date

    var id: String { "\(postId)-\(identity.profileId)" }

    init(postId: UUID, identity: PlayerIdentity, answeredAt: Date) {
        self.postId = postId
        self.identity = identity
        self.answeredAt = answeredAt
    }

    private enum CodingKeys: String, CodingKey {
        case postId = "post_id", actorId = "actor_id", username
        case displayName = "display_name", avatarURL = "avatar_url", answeredAt = "answered_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postId = try c.decode(UUID.self, forKey: .postId)
        identity = PlayerIdentity(
            profileId: try c.decode(UUID.self, forKey: .actorId),
            username: try c.decodeIfPresent(String.self, forKey: .username) ?? "",
            displayName: try c.decode(String.self, forKey: .displayName),
            avatarURL: try c.decodeIfPresent(String.self, forKey: .avatarURL).flatMap(URL.init(string:))
        )
        answeredAt = try PostgresTimestamp.parse(try c.decode(String.self, forKey: .answeredAt))
    }

    /// Who answered, friends first. With the prompt's total: "Sam and 5 others have
    /// answered", "Sam and Jo have answered". Without it (the headcount is hidden until
    /// the viewer answers): "Sam answered", "Sam & Jo answered", "Sam, Jo & 2 other friends answered".
    static func line(_ answerers: [FriendAnswerer], total: Int? = nil) -> String? {
        let names = answerers.map(\.identity.displayName)
        guard !names.isEmpty else { return nil }
        if let total {
            let shown = Array(names.prefix(2))
            let rest = max(0, total - shown.count)
            let list = shown.count == 2 && rest == 0 ? "\(shown[0]) and \(shown[1])" : shown.joined(separator: ", ")
            if rest > 0 { return "\(list) and \(rest) \(rest == 1 ? "other has" : "others have") answered" }
            return "\(list) \(shown.count == 1 ? "has" : "have") answered"
        }
        switch names.count {
        case 1: return "\(names[0]) answered"
        case 2: return "\(names[0]) & \(names[1]) answered"
        default:
            let others = names.count - 2
            return "\(names[0]), \(names[1]) & \(others) other \(others == 1 ? "friend" : "friends") answered"
        }
    }
}

/// The pills over Home's one feed. Friends is the prompts a friend answered
/// plus their game moments. Lists is the shared list updates alone.
enum HomeFilter: Hashable, CaseIterable {
    case all, prompts, friends, lists

    var title: String {
        switch self {
        case .all: "All"
        case .prompts: "Prompts"
        case .friends: "Friends"
        case .lists: "Lists"
        }
    }
}

enum HomeFeedEntry: Equatable, Identifiable {
    case prompt(PromptPost, answerers: [FriendAnswerer])
    case moment(FriendActivityItem)
    case listUpdate(ListUpdate)

    var id: String {
        switch self {
        case .prompt(let post, _): "prompt-\(post.id)"
        case .moment(let item): item.id
        case .listUpdate(let update): "list-\(update.postId)"
        }
    }

    var date: Date {
        switch self {
        case .prompt(let post, _): post.createdAt
        case .moment(let item): item.event.occurredAt
        case .listUpdate(let update): update.savedAt
        }
    }
}

enum HomeFeed {
    /// Prompts and game moments, newest first. Under Friends a prompt is dated by
    /// its newest friend answer and only prompts a friend answered stay. Moments
    /// page, so while more remain the feed stops at the oldest one loaded and
    /// "Load more" moves that line back. Mirrors `buildHomeFeed` on the web.
    static func build(
        posts: [PromptPost],
        answerers: [UUID: [FriendAnswerer]],
        moments: [FriendActivityEvent],
        filter: HomeFilter,
        hasMoreMoments: Bool,
        listUpdates: [ListUpdate] = []
    ) -> [HomeFeedEntry] {
        if filter == .prompts {
            return posts.map { .prompt($0, answerers: []) }
        }
        if filter == .lists {
            return listUpdates.sorted { $0.savedAt > $1.savedAt }.map { .listUpdate($0) }
        }
        let prompts: [(entry: HomeFeedEntry, date: Date)] = posts.compactMap { post in
            let who = (answerers[post.id] ?? []).sorted { $0.answeredAt > $1.answeredAt }
            if filter == .friends {
                guard let newest = who.first else { return nil }
                return (.prompt(post, answerers: who), newest.answeredAt)
            }
            return (.prompt(post, answerers: who), post.createdAt)
        }
        let games: [(entry: HomeFeedEntry, date: Date)] = FriendActivityItem.grouped(moments).map { (.moment($0), $0.event.occurredAt) }
        let updates: [(entry: HomeFeedEntry, date: Date)] = listUpdates.map { (.listUpdate($0), $0.savedAt) }
        let floor = hasMoreMoments ? moments.last?.occurredAt : nil
        return (prompts + games + updates)
            .filter { floor == nil || $0.date >= floor! }
            .sorted { $0.date > $1.date }
            .map(\.entry)
    }
}
