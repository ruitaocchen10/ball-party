import Foundation

// Hand-maintained mirrors of the `prompts` (Huddle) shapes in
// `docs/architecture/game-runtime.md` ("Huddle's write API", "Huddle's
// tables"), and of the domain types in
// `webapp/lib/foundation/content/prompts/types.ts`. Same deal as the other
// models: there is no Postgres-to-Swift codegen, so a column added on the
// server has to be added here on purpose.
//
// Two layers, on purpose. The `*Row` types are what PostgREST prints — flat,
// one per table, and all `HuddleClient` ever hands back. The `Prompt*` types
// are what a screen reads — joined, ordered, and gated by who is looking.
// `PromptFeed` is the only thing that turns one into the other.

/// `slot.shape` — how many options a slot takes and whether their order counts.
enum SlotShape: String, Sendable, Equatable {
    case pick
    case pickSet = "pick_set"
    case rank
}

/// `prompt_posts.status`.
enum PostStatus: String, Sendable, Equatable {
    case open, locked, resolved, void

    /// Whether picks are still being taken. `status` alone is not enough:
    /// nothing on the server ever writes `'locked'` (`0096`) — `lock_at` is
    /// checked live against `now()` — so a post stays `open` past its lock time
    /// until it is resolved, which is the ordinary state of every game in
    /// progress.
    func isTakingPicks(lockAt: Date, now: Date) -> Bool { self == .open && lockAt > now }
}

struct PromptOption: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let sublabel: String?
    let teamCode: String?
    let headshotURL: URL?
}

/// One game on the schedule the web and this app share (`public.nfl_games`,
/// migration 0119) — the venue, the kickoff and the Primetime flag a matchup
/// cover shows. The database fills it from nflverse and does the Eastern-time
/// conversion, so `kickoff` is already a real instant. Decoded straight from
/// the row: there is nothing to join or gate, so no separate row type.
struct NFLGame: Identifiable, Decodable, Equatable, Sendable {
    /// nflverse's game id — the value a slot keeps in `source_game_id`.
    let id: String
    let stadium: String
    let kickoff: Date
    let primetime: Bool

    init(id: String, stadium: String = "", kickoff: Date, primetime: Bool = false) {
        self.id = id; self.stadium = stadium; self.kickoff = kickoff; self.primetime = primetime
    }

    private enum CodingKeys: String, CodingKey { case id, stadium, kickoff, primetime }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        stadium = try c.decode(String.self, forKey: .stadium)
        kickoff = try c.decodeTimestamp(forKey: .kickoff)
        primetime = try c.decode(Bool.self, forKey: .primetime)
    }
}

struct PromptSlot: Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    let shape: SlotShape
    /// How many options the viewer must choose (`pick_set`) or order (`rank`).
    /// `nil` means "one" for a `pick` and "all of them" otherwise.
    let pickCount: Int?
    let points: Int
    /// Ground truth — `nil` until the post resolves. Order counts for `rank`.
    let correctOptionIds: [UUID]?
    let options: [PromptOption]
    /// The schedule entry this slot is about — set on a game pick, `nil` on
    /// anything else, and on a game the schedule doesn't know (yet).
    var game: NFLGame? = nil

    /// The two teams of a game pick, away first and home second — the order the
    /// composer writes them, and the order a matchup cover draws them in. `nil`
    /// for anything that isn't a head-to-head between two teams (a ranking, a
    /// pick of players), which is what keeps those on the plain option list.
    var matchup: (away: PromptOption, home: PromptOption)? {
        guard shape == .pick, options.count == 2,
              options.allSatisfy({ $0.teamCode != nil && $0.headshotURL == nil })
        else { return nil }
        return (options[0], options[1])
    }

    /// Whether `optionId` is one of the right answers — `nil` until the post
    /// resolves. The server did the grading (`resolve_post`); this only reads
    /// what it wrote.
    func isCorrect(_ optionId: UUID) -> Bool? {
        correctOptionIds.flatMap { $0.isEmpty ? nil : $0.contains(optionId) }
    }

    /// How many options a complete answer to this slot holds.
    var requiredCount: Int {
        switch shape {
        case .pick: 1
        case .pickSet, .rank: pickCount ?? options.count
        }
    }
}

/// A take (top-level comment) or a reply to one.
struct PromptComment: Identifiable, Equatable, Sendable {
    let id: UUID
    let author: String
    /// The author's profile picture; without one the card draws their initial.
    var authorAvatarURL: URL? = nil
    let body: String
    let createdAt: Date
    let isViewer: Bool
    /// Whether the take was submitted together with the author's picks.
    let postedWithPick: Bool
    /// The author's full ticket, `{slot → chosen options}` — present only once
    /// the post has locked, and only for a take posted with a pick.
    let response: [UUID: [UUID]]?
    /// One level deep: `post_comment` refuses a reply to a reply.
    let replies: [PromptComment]
}

/// One of the viewer's own takes, paired with the post it was left on — what
/// `PromptFeed.myTakes` hands the Profile tab, mirroring the web profile's
/// `{ post, comment }` pairing of `takeHistory`.
struct ProfileTake: Identifiable, Equatable, Sendable {
    let post: PromptPost
    let comment: PromptComment

    var id: UUID { comment.id }
}

struct PromptPost: Identifiable, Equatable, Sendable {
    let id: UUID
    let templateKind: String
    let templateName: String
    let author: String
    let caption: String
    let createdAt: Date
    let promptText: String
    let resolutionCriteria: String
    let lockAt: Date
    let status: PostStatus
    let voidReason: String?
    /// No correct answer, ever — the server refuses to grade it.
    let isOpinion: Bool
    let slots: [PromptSlot]
    /// Top-level takes, oldest first, each with its replies.
    let comments: [PromptComment]
    /// Known only once `post_aggregates` has been asked for (see `PromptFeed`);
    /// 0 otherwise, which is not the same as "nobody has answered".
    let responseCount: Int
    /// The viewer's own ticket, `{slot → chosen options}`; `nil` if they haven't answered.
    let viewerResponse: [UUID: [UUID]]?
    /// What the server paid the viewer — resolved posts only.
    let viewerPointsAwarded: Int?
    /// `{slot → {option → percent of that slot's respondents who chose it}}`.
    /// `nil` until the post is past open or the viewer has answered.
    let aggregate: [UUID: [UUID: Double]]?
    /// Power Rankings only: the six teams the admin chose for the cover art, in
    /// placement order.
    var coverTeamCodes: [String] = []
    /// Power Rankings only: `{team code → position}` from the viewer's most
    /// recent *earlier* Power Rankings ballot. Option ids are unique to each
    /// weekly post, so the team code is what ties one week to the next.
    var previousRankByTeam: [String: Int] = [:]
    /// Power Rankings only: the teams most often placed in a ballot's top
    /// five, best first. Empty until `aggregate` is (same reveal rule).
    var powerRankingTopFive: [PowerRankingConsensusEntry] = []

    var viewerAnswered: Bool { viewerResponse != nil }

    /// Power Rankings: an opinion-only, weekly ranking of the league where the
    /// respondent — not the composer — chooses to rank 5, 10 or all 32 teams.
    var isPowerRankings: Bool { templateKind == Self.powerRankingsKind }

    static let powerRankingsKind = "power_rankings"
    /// How many teams a Power Rankings ballot may hold (`submit_response`).
    static let powerRankingDepths = [5, 10, 32]

    /// Whether every slot is a head-to-head between two teams, which is when
    /// the post is drawn as matchup covers instead of an option list.
    var isMatchupPost: Bool { !slots.isEmpty && slots.allSatisfy { $0.matchup != nil } }

    func isTakingPicks(at now: Date) -> Bool { status.isTakingPicks(lockAt: lockAt, now: now) }

    /// Whether this viewer can still make picks on it.
    func canBeAnswered(at now: Date) -> Bool { isTakingPicks(at: now) && !viewerAnswered }

    /// Picks posts. `game_pick` and `weekly_picks` remain readable for posts
    /// written before Picks unified them.
    static let picksKinds = ["picks", "game_pick", "weekly_picks"]

    static func isPicksKind(_ kind: String) -> Bool { picksKinds.contains(kind) }

    /// What the web home shows (`isHomePrompt` in `webapp/app/page.tsx`): Picks
    /// plus Power Rankings. The other kinds stay with the admin tooling.
    static let feedKinds = picksKinds + [powerRankingsKind]

    static func isFeedKind(_ kind: String) -> Bool { feedKinds.contains(kind) }
}

/// One team of a Power Rankings post's "most common top 5"
/// (`prompts.power_ranking_top_five`).
struct PowerRankingConsensusEntry: Equatable, Sendable {
    let optionId: UUID
    /// How many ballots put the team in their top five.
    let topFiveCount: Int
    /// The team's average position across the ballots that ranked it.
    let averageRank: Double
}

/// How a team moved between the viewer's last two Power Rankings ballots.
enum PowerRankingMovement: Equatable, Sendable {
    /// Ranked before, and by this many places higher now.
    case up(Int)
    case down(Int)
    case unchanged
    /// Not on the viewer's previous ballot (or they have none).
    case new

    /// `previous` is the team's 1-based place last time, `current` its place now.
    init(previous: Int?, current: Int) {
        guard let previous else { self = .new; return }
        let places = previous - current
        self = places > 0 ? .up(places) : places < 0 ? .down(-places) : .unchanged
    }
}

// MARK: - Rows

struct PromptPostRow: Decodable, Equatable, Sendable {
    let id: UUID
    let templateKind: String
    let templateName: String
    let authorId: UUID
    let caption: String
    let promptText: String
    let resolutionCriteria: String
    let lockAt: Date
    let createdAt: Date
    /// Raw, so a status the app doesn't know is a post it leaves out rather
    /// than a decoding failure that takes the whole feed with it.
    let status: String
    let voidReason: String?
    let isOpinion: Bool
    /// Power Rankings only (`cover_team_codes`, 0118); `nil` on every other kind.
    let coverTeamCodes: [String]?

    /// `nil` for a status this app doesn't know.
    var postStatus: PostStatus? { PostStatus(rawValue: status) }

    init(
        id: UUID, templateKind: String = "picks", templateName: String = "Picks", authorId: UUID,
        caption: String = "", promptText: String, resolutionCriteria: String = "", lockAt: Date,
        createdAt: Date, status: String = "open", voidReason: String? = nil, isOpinion: Bool = false,
        coverTeamCodes: [String]? = nil
    ) {
        self.id = id; self.templateKind = templateKind; self.templateName = templateName
        self.authorId = authorId; self.caption = caption; self.promptText = promptText
        self.resolutionCriteria = resolutionCriteria; self.lockAt = lockAt; self.createdAt = createdAt
        self.status = status; self.voidReason = voidReason; self.isOpinion = isOpinion
        self.coverTeamCodes = coverTeamCodes
    }

    private enum CodingKeys: String, CodingKey {
        case id, caption, status
        case templateKind = "template_kind"
        case templateName = "template_name"
        case authorId = "author_id"
        case promptText = "prompt_text"
        case resolutionCriteria = "resolution_criteria"
        case lockAt = "lock_at"
        case createdAt = "created_at"
        case voidReason = "void_reason"
        case isOpinion = "is_opinion"
        case coverTeamCodes = "cover_team_codes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        templateKind = try c.decode(String.self, forKey: .templateKind)
        templateName = try c.decode(String.self, forKey: .templateName)
        authorId = try c.decode(UUID.self, forKey: .authorId)
        caption = try c.decode(String.self, forKey: .caption)
        promptText = try c.decode(String.self, forKey: .promptText)
        resolutionCriteria = try c.decode(String.self, forKey: .resolutionCriteria)
        lockAt = try c.decodeTimestamp(forKey: .lockAt)
        createdAt = try c.decodeTimestamp(forKey: .createdAt)
        status = try c.decode(String.self, forKey: .status)
        voidReason = try c.decodeIfPresent(String.self, forKey: .voidReason)
        isOpinion = try c.decode(Bool.self, forKey: .isOpinion)
        coverTeamCodes = try c.decodeIfPresent([String].self, forKey: .coverTeamCodes)
    }
}

struct PromptSlotRow: Decodable, Equatable, Sendable {
    let id: UUID
    let postId: UUID
    let label: String
    let shape: String
    let pickCount: Int?
    let points: Int
    let sortOrder: Int
    let correctOptionIds: [UUID]?
    /// The nflverse game id of a game pick (`prompt_slots.source_game_id`, 0097).
    let sourceGameId: String?

    init(
        id: UUID, postId: UUID, label: String, shape: String = "pick", pickCount: Int? = nil,
        points: Int = 10, sortOrder: Int = 0, correctOptionIds: [UUID]? = nil, sourceGameId: String? = nil
    ) {
        self.id = id; self.postId = postId; self.label = label; self.shape = shape
        self.pickCount = pickCount; self.points = points; self.sortOrder = sortOrder
        self.correctOptionIds = correctOptionIds; self.sourceGameId = sourceGameId
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, shape, points
        case postId = "post_id"
        case pickCount = "pick_count"
        case sortOrder = "sort_order"
        case correctOptionIds = "correct_option_ids"
        case sourceGameId = "source_game_id"
    }
}

struct PromptOptionRow: Decodable, Equatable, Sendable {
    let id: UUID
    let slotId: UUID
    let label: String
    let sublabel: String?
    let teamCode: String?
    let headshotUrl: String?
    let sortOrder: Int

    init(
        id: UUID, slotId: UUID, label: String, sublabel: String? = nil, teamCode: String? = nil,
        headshotUrl: String? = nil, sortOrder: Int = 0
    ) {
        self.id = id; self.slotId = slotId; self.label = label; self.sublabel = sublabel
        self.teamCode = teamCode; self.headshotUrl = headshotUrl; self.sortOrder = sortOrder
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, sublabel
        case slotId = "slot_id"
        case teamCode = "team_code"
        case headshotUrl = "headshot_url"
        case sortOrder = "sort_order"
    }
}

/// One of the *viewer's own* `prompt_responses` — the table is own-rows-only at
/// the database, whatever the client filters for.
struct PromptResponseRow: Decodable, Equatable, Sendable {
    let postId: UUID
    let slotId: UUID
    let chosenOptionIds: [UUID]
    let pointsEarned: Int?

    private enum CodingKeys: String, CodingKey {
        case postId = "post_id"
        case slotId = "slot_id"
        case chosenOptionIds = "chosen_option_ids"
        case pointsEarned = "points_earned"
    }
}

struct PromptCommentRow: Decodable, Equatable, Sendable {
    let id: UUID
    let postId: UUID
    let authorId: UUID
    let body: String
    let postedWithPick: Bool
    let parentCommentId: UUID?
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, body
        case postId = "post_id"
        case authorId = "author_id"
        case postedWithPick = "posted_with_pick"
        case parentCommentId = "parent_comment_id"
        case createdAt = "created_at"
    }

    init(
        id: UUID, postId: UUID, authorId: UUID, body: String, postedWithPick: Bool = false,
        parentCommentId: UUID? = nil, createdAt: Date
    ) {
        self.id = id; self.postId = postId; self.authorId = authorId; self.body = body
        self.postedWithPick = postedWithPick; self.parentCommentId = parentCommentId
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        postId = try c.decode(UUID.self, forKey: .postId)
        authorId = try c.decode(UUID.self, forKey: .authorId)
        body = try c.decode(String.self, forKey: .body)
        postedWithPick = try c.decode(Bool.self, forKey: .postedWithPick)
        parentCommentId = try c.decodeIfPresent(UUID.self, forKey: .parentCommentId)
        createdAt = try c.decodeTimestamp(forKey: .createdAt)
    }
}

/// `profiles` rows read for who wrote a post or take — their name and picture.
struct PromptProfileRow: Decodable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    var avatarUrl: String? = nil

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

/// Everything `HuddleClient.feedRows` reads in one go: the flat tables the web's
/// `fetchPromptFeed` joins in JS (`webapp/lib/foundation/content/prompts/feed.ts`).
struct PromptFeedRows: Equatable, Sendable {
    var posts: [PromptPostRow] = []
    var slots: [PromptSlotRow] = []
    var options: [PromptOptionRow] = []
    var viewerResponses: [PromptResponseRow] = []
    var comments: [PromptCommentRow] = []
    var profiles: [PromptProfileRow] = []
    /// The schedule entries the slots point at. May come back empty — the
    /// schedule is garnish for a cover, never a reason to lose the feed.
    var games: [NFLGame] = []
}

/// One row of `prompts.post_aggregates`.
struct PromptAggregateRow: Decodable, Equatable, Sendable {
    let slotId: UUID
    let optionId: UUID
    /// Rounded percent of the slot's responses that chose the option; `nil` if
    /// the slot has none yet.
    let pct: Double?
    let totalResponses: Int?

    init(slotId: UUID, optionId: UUID, pct: Double?, totalResponses: Int?) {
        self.slotId = slotId; self.optionId = optionId; self.pct = pct
        self.totalResponses = totalResponses
    }

    private enum CodingKeys: String, CodingKey {
        case slotId = "slot_id"
        case optionId = "option_id"
        case pct
        case totalResponses = "total_responses"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slotId = try c.decode(UUID.self, forKey: .slotId)
        optionId = try c.decode(UUID.self, forKey: .optionId)
        pct = try c.decodeNumericIfPresent(forKey: .pct)
        totalResponses = try c.decodeNumericIfPresent(forKey: .totalResponses).map { Int($0) }
    }
}

/// One row of `prompts.power_ranking_top_five` — a team's showing in the
/// ballots' top fives. Team-level only; never an individual ballot.
struct PromptPowerTopFiveRow: Decodable, Equatable, Sendable {
    let optionId: UUID
    let topFiveCount: Int
    let averageRank: Double

    init(optionId: UUID, topFiveCount: Int, averageRank: Double) {
        self.optionId = optionId; self.topFiveCount = topFiveCount; self.averageRank = averageRank
    }

    private enum CodingKeys: String, CodingKey {
        case optionId = "option_id"
        case topFiveCount = "top_five_count"
        case averageRank = "average_rank"
    }

    /// `bigint` and `numeric` arrive as a number or a string depending on the
    /// path PostgREST takes, like `post_aggregates`' columns.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        optionId = try c.decode(UUID.self, forKey: .optionId)
        topFiveCount = try c.decodeNumericIfPresent(forKey: .topFiveCount).map { Int($0) } ?? 0
        averageRank = try c.decodeNumericIfPresent(forKey: .averageRank) ?? 0
    }
}

/// One row of `prompts.revealed_responses` — a whole ticket for one slot.
struct PromptRevealedResponseRow: Decodable, Equatable, Sendable {
    let profileId: UUID
    let slotId: UUID
    let chosenOptionIds: [UUID]

    private enum CodingKeys: String, CodingKey {
        case profileId = "profile_id"
        case slotId = "slot_id"
        case chosenOptionIds = "chosen_option_ids"
    }
}
