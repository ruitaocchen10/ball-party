import Foundation

// The friends activity feed's types: the rows of `friend_activity`
// (migration 0188) and the sentence each one reads as. Which friends, which
// 30 days and what is left out (a pick's chosen options never come down the
// wire) are the server's calls; nothing here filters.

/// What happened. A pick event carries the prompt but, by design, never the
/// option chosen.
enum FriendActivityKind: Equatable, Sendable {
    case pickMade(postId: UUID, caption: String?)
    case pickResult(postId: UUID, caption: String?, points: Int)
    case matchResult(matchId: UUID, game: String, placement: Int?, score: Double?, mode: RunMode?)
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
        case .pickMade(let postId, _): "pick_made-\(actor.profileId)-\(postId)"
        case .pickResult(let postId, _, _): "pick_result-\(actor.profileId)-\(postId)"
        case .matchResult(let matchId, _, _, _, _): "match_result-\(actor.profileId)-\(matchId)"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type", occurredAt = "occurred_at", actorId = "actor_id"
        case username, displayName = "display_name", avatarURL = "avatar_url"
        case postId = "post_id", postCaption = "post_caption", points
        case matchId = "match_id", game, placement, rawScore = "raw_score", runMode = "run_mode"
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
        case "pick_made":
            kind = .pickMade(
                postId: try c.decode(UUID.self, forKey: .postId),
                caption: try c.decodeIfPresent(String.self, forKey: .postCaption)
            )
        case "pick_result":
            kind = .pickResult(
                postId: try c.decode(UUID.self, forKey: .postId),
                caption: try c.decodeIfPresent(String.self, forKey: .postCaption),
                points: try c.decodeIfPresent(Int.self, forKey: .points) ?? 0
            )
        case "match_result":
            kind = .matchResult(
                matchId: try c.decode(UUID.self, forKey: .matchId),
                game: try c.decode(String.self, forKey: .game),
                placement: try c.decodeIfPresent(Int.self, forKey: .placement),
                score: try c.decodeNumericIfPresent(forKey: .rawScore),
                mode: try c.decodeIfPresent(String.self, forKey: .runMode).flatMap(RunMode.init(rawValue:))
            )
        default:
            throw UnknownEvent(type: type)
        }
    }

    /// The line the feed shows, without the actor's name (the row leads with it).
    var summary: String {
        switch kind {
        case .pickMade(_, let caption):
            return "made a pick" + Self.onPrompt(caption)
        case .pickResult(_, let caption, let points):
            let noun = abs(points) == 1 ? "point" : "points"
            let signed = points > 0 ? "+\(points)" : "\(points)"
            return "scored \(signed) \(noun)" + Self.onPrompt(caption)
        case .matchResult(_, let game, let placement, let score, let mode):
            let name = MatchGame(rawValue: game)?.label ?? Self.humanized(game)
            var line: String
            if let placement, mode != .solo {
                line = "finished \(placement.ordinal) in \(name)"
            } else {
                line = "played \(name)" + (mode == .solo ? " solo" : "")
            }
            if let score {
                line += " · \(Self.formatScore(score))"
            }
            return line
        }
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
