import Foundation

// Ranking lists on iOS: a player's living, versioned lists (Power Rankings and
// the position lists). The Swift counterpart of `webapp/lib/foundation/lists/`;
// the rules live in the database (`docs/architecture/ranking-lists.md`), so
// these types only carry what the RPCs return and the pure helpers a screen
// needs (movement marks, titles, moving an item).

/// A kind of list a player can keep (`ranking_list_kinds`).
struct ListKind: Identifiable, Equatable, Sendable, Decodable {
    enum ItemKind: String, Sendable { case team, player }

    let id: String
    let label: String
    /// Teams are keyed by nflverse code, players by player id.
    let itemKind: ItemKind
    /// The lengths the list may have, ascending.
    let sizes: [Int]

    init(id: String, label: String, itemKind: ItemKind, sizes: [Int]) {
        self.id = id; self.label = label; self.itemKind = itemKind; self.sizes = sizes.sorted()
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, sizes
        case itemKind = "item_kind"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            label: try c.decode(String.self, forKey: .label),
            itemKind: ItemKind(rawValue: try c.decode(String.self, forKey: .itemKind)) ?? .team,
            sizes: try c.decode([Int].self, forKey: .sizes)
        )
    }

    var isTeams: Bool { itemKind == .team }
}

/// A player's list as the Lists tab shows it: the newest version of one kind
/// (`get_ranking_lists`).
struct ListSummary: Identifiable, Equatable, Sendable, Decodable {
    let kind: String
    let label: String
    let itemKind: ListKind.ItemKind
    let versionId: UUID
    let versionNo: Int
    let savedAt: Date
    let versionCount: Int
    let items: [String]
    /// The newest version's note. Only the owner and their friends get it.
    let note: String?
    /// The version it replaced, for movement marks. Nil on a first version.
    let previousItems: [String]?

    var id: String { kind }

    private enum CodingKeys: String, CodingKey {
        case kind, label, items, note
        case itemKind = "item_kind"
        case versionId = "version_id"
        case versionNo = "version_no"
        case savedAt = "created_at"
        case versionCount = "version_count"
        case previousItems = "prev_items"
    }

    init(
        kind: String, label: String, itemKind: ListKind.ItemKind, versionId: UUID = UUID(), versionNo: Int,
        savedAt: Date, versionCount: Int, items: [String], note: String? = nil, previousItems: [String]? = nil
    ) {
        self.kind = kind; self.label = label; self.itemKind = itemKind; self.versionId = versionId
        self.versionNo = versionNo; self.savedAt = savedAt; self.versionCount = versionCount
        self.items = items; self.note = note; self.previousItems = previousItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(String.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        itemKind = ListKind.ItemKind(rawValue: try c.decode(String.self, forKey: .itemKind)) ?? .team
        versionId = try c.decode(UUID.self, forKey: .versionId)
        versionNo = try c.decode(Int.self, forKey: .versionNo)
        savedAt = try c.decodeTimestamp(forKey: .savedAt)
        versionCount = try c.decode(Int.self, forKey: .versionCount)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
        previousItems = try c.decodeIfPresent([String].self, forKey: .previousItems)
    }
}

/// One saved version in a list's history (`get_ranking_list`).
struct ListVersion: Identifiable, Equatable, Sendable, Decodable {
    enum Source: String, Sendable { case edit, prompt }

    let id: UUID
    let versionNo: Int
    /// `prompt` when it came from answering a ranking prompt, `edit` when the player saved it.
    let source: Source
    let promptPostId: UUID?
    /// The friends-only card, once the player posted this version.
    let updatePostId: UUID?
    let note: String?
    let savedAt: Date
    let isCurrent: Bool
    let items: [String]

    private enum CodingKeys: String, CodingKey {
        case source, note, items
        case id = "version_id"
        case versionNo = "version_no"
        case promptPostId = "post_id"
        case updatePostId = "update_post_id"
        case savedAt = "created_at"
        case isCurrent = "is_current"
    }

    init(
        id: UUID = UUID(), versionNo: Int, source: Source = .edit, promptPostId: UUID? = nil, updatePostId: UUID? = nil,
        note: String? = nil, savedAt: Date, isCurrent: Bool = false, items: [String]
    ) {
        self.id = id; self.versionNo = versionNo; self.source = source; self.promptPostId = promptPostId
        self.updatePostId = updatePostId; self.note = note; self.savedAt = savedAt; self.isCurrent = isCurrent; self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        versionNo = try c.decode(Int.self, forKey: .versionNo)
        source = Source(rawValue: try c.decode(String.self, forKey: .source)) ?? .edit
        promptPostId = try c.decodeIfPresent(UUID.self, forKey: .promptPostId)
        updatePostId = try c.decodeIfPresent(UUID.self, forKey: .updatePostId)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        savedAt = try c.decodeTimestamp(forKey: .savedAt)
        isCurrent = try c.decode(Bool.self, forKey: .isCurrent)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
    }
}

/// A player in a list: identity only (`ranking_players`).
struct ListPlayer: Equatable, Sendable, Decodable {
    let id: String
    let name: String
    let position: String
    let team: String
    let headshotURL: URL?

    private enum CodingKeys: String, CodingKey {
        case position, team
        case id = "player_id"
        case name = "display_name"
        case headshotURL = "headshot_url"
    }

    init(id: String, name: String, position: String, team: String, headshotURL: URL? = nil) {
        self.id = id; self.name = name; self.position = position; self.team = team; self.headshotURL = headshotURL
    }

    init(_ player: NFLPlayer) {
        self.init(id: player.id, name: player.name, position: player.position, team: player.team, headshotURL: player.headshotURL)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        position = try c.decode(String.self, forKey: .position)
        team = try c.decode(String.self, forKey: .team)
        headshotURL = try c.decodeIfPresent(String.self, forKey: .headshotURL).flatMap(URL.init(string:))
    }
}

/// A published edit in the home feed, with the list it replaced
/// (`friend_list_updates`).
/// The take behind an update card and what the viewer can do with its balls.
struct ListBall: Equatable, Sendable {
    let takeId: UUID
    let reaction: TakeReaction
}

struct ListUpdate: Identifiable, Equatable, Sendable, Decodable {
    let postId: UUID
    let authorId: UUID
    let username: String?
    let displayName: String
    let avatarURL: URL?
    let kind: String
    let label: String
    let itemKind: ListKind.ItemKind
    let versionNo: Int
    let note: String?
    let savedAt: Date
    let items: [String]
    let previousItems: [String]?
    /// The take the note is, with its balls. Balls hang on the take, not on the post.
    /// Not part of the RPC: the client fills it in from `take_reaction_summary`.
    var ball: ListBall?

    var id: UUID { postId }

    private enum CodingKeys: String, CodingKey {
        case username, kind, label, note, items
        case postId = "post_id"
        case authorId = "author_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case itemKind = "item_kind"
        case versionNo = "version_no"
        case savedAt = "created_at"
        case previousItems = "prev_items"
    }

    init(
        postId: UUID = UUID(), authorId: UUID = UUID(), username: String? = nil, displayName: String = "Player", avatarURL: URL? = nil,
        kind: String, label: String, itemKind: ListKind.ItemKind, versionNo: Int, note: String? = nil,
        savedAt: Date, items: [String], previousItems: [String]? = nil
    ) {
        self.postId = postId; self.authorId = authorId; self.username = username; self.displayName = displayName
        self.avatarURL = avatarURL; self.kind = kind; self.label = label; self.itemKind = itemKind
        self.versionNo = versionNo; self.note = note; self.savedAt = savedAt; self.items = items; self.previousItems = previousItems
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postId = try c.decode(UUID.self, forKey: .postId)
        authorId = try c.decode(UUID.self, forKey: .authorId)
        username = try c.decodeIfPresent(String.self, forKey: .username)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarURL = try c.decodeIfPresent(String.self, forKey: .avatarURL).flatMap(URL.init(string:))
        kind = try c.decode(String.self, forKey: .kind)
        label = try c.decode(String.self, forKey: .label)
        itemKind = ListKind.ItemKind(rawValue: try c.decode(String.self, forKey: .itemKind)) ?? .team
        versionNo = try c.decode(Int.self, forKey: .versionNo)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        savedAt = try c.decodeTimestamp(forKey: .savedAt)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        previousItems = try c.decodeIfPresent([String].self, forKey: .previousItems)
    }
}

/// A reply under an update card.
struct ListReply: Identifiable, Equatable, Sendable {
    let id: UUID
    let authorName: String
    let authorUsername: String?
    let avatarURL: URL?
    let body: String
    let createdAt: Date
    let isViewer: Bool
}

/// What a card's thread needs: the id of the take the replies hang on (the
/// card's note) and the replies themselves.
struct ListThread: Equatable, Sendable {
    var takeId: UUID?
    var replies: [ListReply]
}

/// A refusal from `save_ranking_list`: the raised message, and for
/// `edit_limit` / `prompt_open` the extra detail (when the next save opens,
/// the prompt's id).
struct ListsServerError: Error, Equatable, Sendable {
    let message: String
    let detail: String?
}

// MARK: - Logic

/// The pure rules a list screen needs. Mirrors `webapp/lib/foundation/lists/lists.ts`
/// and `messages.ts`; when one changes there, change it here.
enum ListLogic {
    /// The 32 teams a team list can hold (nflverse codes). The database checks
    /// the same set on save; this is only the pool the editor offers.
    static let teamCodes = [
        "ARI", "ATL", "BAL", "BUF", "CAR", "CHI", "CIN", "CLE", "DAL", "DEN", "DET", "GB", "HOU", "IND", "JAX", "KC",
        "LAC", "LAR", "LV", "MIA", "MIN", "NE", "NO", "NYG", "NYJ", "PHI", "PIT", "SEA", "SF", "TB", "TEN", "WAS",
    ]

    /// Whose faces stand on a position list's cover before the player has
    /// started it, by nflverse player id (the web's `COVER_PLAYER_IDS`).
    static let coverPlayerIds: [String: [String]] = [
        "qb": ["00-0036389", "00-0034796", "00-0033873", "00-0034857", "00-0036442"],
        "rb": ["00-0038542", "00-0032764", "00-0034844", "00-0033280", "00-0039139"],
        "wr": ["00-0036963", "00-0036358", "00-0036322", "00-0036900", "00-0039075"],
    ]

    /// The order the Lists tab shows the kinds in.
    static let kindOrder = ["power_rankings", "qb", "rb", "wr"]

    /// Moves one item to another place, shifting the ones between.
    static func moveItem<T>(_ items: [T], from: Int, to: Int) -> [T] {
        guard from != to, items.indices.contains(from), items.indices.contains(to) else { return items }
        var next = items
        let item = next.remove(at: from)
        next.insert(item, at: to)
        return next
    }

    /// How far an item moved against an earlier list: positive when it climbed,
    /// negative when it fell, 0 when it stayed, and nil when it was not in the
    /// earlier list (or there is no earlier list).
    static func placeChange(previous: [String]?, items: [String], index: Int) -> Int? {
        guard let previous, items.indices.contains(index), let was = previous.firstIndex(of: items[index]) else { return nil }
        return was - index
    }

    /// How many places hold a different item than the earlier list did.
    static func movedCount(previous: [String]?, items: [String]) -> Int {
        guard let previous else { return items.count }
        return items.indices.filter { index in previous.indices.contains(index) ? previous[index] != items[index] : true }.count
    }

    /// The teams not in a list, in alphabetical order, for the editor's bench.
    static func benchTeams(_ items: [String]) -> [String] {
        teamCodes.filter { !items.contains($0) }
    }

    /// A list after its size changes: cut from the bottom, or filled from the bench.
    static func resizeTeams(_ items: [String], to size: Int) -> [String] {
        items.count >= size ? Array(items.prefix(size)) : Array((items + benchTeams(items)).prefix(size))
    }

    /// "Top 10", "All 32".
    static func sizeLabel(_ size: Int, itemKind: ListKind.ItemKind) -> String {
        itemKind == .team && size == 32 ? "All 32" : "Top \(size)"
    }

    /// A list's heading on a card: "My power rankings - V3", "My top 10 QBs - V3".
    /// Without a version (a list not started yet) it is just the name.
    static func title(kind: String, itemKind: ListKind.ItemKind, size: Int, versionNo: Int? = nil) -> String {
        let name = itemKind == .team ? "My power rankings" : "My top \(size) \(kind.uppercased())s"
        return versionNo.map { "\(name) - V\($0)" } ?? name
    }

    /// "Buffalo Bills" → "Bills". A team's logo already says the city.
    static func teamName(_ code: String) -> String { NFLTeams.name(for: code) }

    /// "Amon-Ra St. Brown" → "St. Brown".
    static func surname(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace)
        return parts.count > 1 ? parts.dropFirst().joined(separator: " ") : name
    }

    /// The words under an update card's author line.
    static func updateContext(_ update: ListUpdate) -> String {
        let name = update.itemKind == .team ? "power rankings" : "top \(update.items.count) \(update.kind.uppercased())s"
        return "Updated their \(name) · V\(update.versionNo)"
    }

    // MARK: Refusals

    /// The most a list's note may say (`ranking_list_versions.note`).
    static let noteLimit = 280

    private static let messages: [String: String] = [
        "not_authenticated": "Sign in with an account to keep lists.",
        "no_change": "That's the same as your saved list. Move something first.",
        "note_too_long": "Keep the note to 280 characters.",
        "invalid_ranking_size": "That list can't be that long.",
        "invalid_ranking_items": "One of those picks isn't valid. Refresh and try again.",
        "unknown_ranking_kind": "That list doesn't exist.",
    ]

    /// When the next save opens, in the player's own words, or nil when the detail is not a time.
    static func nextSaveLabel(detail: String?, now: Date = Date()) -> String? {
        guard let detail, let at = try? PostgresTimestamp.parse(detail) else { return nil }
        let minutes = max(1, Int((at.timeIntervalSince(now) / 60).rounded()))
        if minutes < 60 { return "in \(minutes) minute\(minutes == 1 ? "" : "s")" }
        let hours = Int((Double(minutes) / 60).rounded())
        return "in \(hours) hour\(hours == 1 ? "" : "s")"
    }

    static func saveErrorMessage(_ error: Error, now: Date = Date()) -> String {
        guard let server = error as? ListsServerError else {
            return "Something went wrong. Check your connection and try again."
        }
        if server.message == "edit_limit" {
            if let when = nextSaveLabel(detail: server.detail, now: now) {
                return "You saved this list in the last 24 hours. You can save again \(when)."
            }
            return "You saved this list in the last 24 hours. Try again later."
        }
        if server.message == "prompt_open" { return "This week's prompt for this list is open. Answer it to update your list." }
        return messages[server.message] ?? server.message
    }
}
