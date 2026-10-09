import Foundation
@testable import BallParty

/// An in-memory stand-in for the `prompts` half of the server, behind the same
/// `HuddleClient` seam the app uses. It plays only the rules a screen's
/// behavior depends on — an answer becomes the viewer's own response row plus
/// their take, a reply becomes a comment under its parent, a post's picks stay
/// hidden until it locks — so view-model tests can drive Huddle without a
/// network.
final class FakeHuddleClient: HuddleClient, @unchecked Sendable {
    /// One post the test added, with the ids a test needs to act on it.
    struct AddedPost {
        let id: UUID
        let slotIds: [UUID]
        /// `optionIds[slot][option]`, in display order.
        let optionIds: [[UUID]]

        var slotId: UUID { slotIds[0] }
        var options: [UUID] { optionIds[0] }
    }

    let viewerId: UUID
    let epoch = Date(timeIntervalSince1970: 1_786_795_200)

    // Server-side state.
    private let lock = NSLock()
    private var rows = PromptFeedRows()
    private var aggregatesByPost: [UUID: [PromptAggregateRow]] = [:]
    private var powerTopFiveByPost: [UUID: [PromptPowerTopFiveRow]] = [:]
    private var revealedByPost: [UUID: [PromptRevealedResponseRow]] = [:]
    private var clock = 0

    private var _holdNextFeedRead = false
    private var _heldReads: [CheckedContinuation<Void, Never>] = []

    // What the app asked for.
    private var _feedReads = 0
    private var _aggregateRequests: [UUID] = []
    private var _powerTopFiveRequests: [UUID] = []
    private var _revealedRequests: [UUID] = []
    private var _submissions: [Submission] = []
    private var _comments: [PostedComment] = []
    private var _boldSubmissions: [BoldSubmission] = []
    private var _playerSearches: [String] = []

    // The player directory, the week's schedule and the predictions the server holds.
    private var directory: [NFLPlayer] = []
    private var schedule: [NFLScheduleGame] = []
    private var boldRows: [BoldPredictionRow] = []

    struct Submission: Equatable {
        let postId: UUID
        let choices: [UUID: [UUID]]
        var players: [UUID: String] = [:]
        let comment: String?
    }

    struct BoldSubmission: Equatable {
        let postId: UUID
        let predictions: [BoldDraft]
    }

    struct PostedComment: Equatable {
        let postId: UUID
        let body: String
        let parentCommentId: UUID?
    }

    var feedReads: Int { lock.withLock { _feedReads } }
    var aggregateRequests: [UUID] { lock.withLock { _aggregateRequests } }
    var powerTopFiveRequests: [UUID] { lock.withLock { _powerTopFiveRequests } }
    var revealedRequests: [UUID] { lock.withLock { _revealedRequests } }
    var submissions: [Submission] { lock.withLock { _submissions } }
    var postedComments: [PostedComment] { lock.withLock { _comments } }
    var boldSubmissions: [BoldSubmission] { lock.withLock { _boldSubmissions } }
    var playerSearches: [String] { lock.withLock { _playerSearches } }

    /// Scripted failures, keyed by RPC name (`feed_rows`, `submit_response`,
    /// `post_comment`, `revealed_responses`, `power_ranking_top_five`). Cleared
    /// by the test that set it.
    var failures: [String: Error] {
        get { lock.withLock { _failures } }
        set { lock.withLock { _failures = newValue } }
    }
    private var _failures: [String: Error] = [:]

    init(viewerId: UUID) {
        self.viewerId = viewerId
        rows.profiles.append(PromptProfileRow(id: viewerId, displayName: "Me"))
    }

    // MARK: - Test controls

    func addProfile(_ id: UUID = UUID(), named name: String, username: String? = nil) -> UUID {
        lock.withLock { rows.profiles.append(PromptProfileRow(id: id, displayName: name, username: username)) }
        return id
    }

    /// A post with one `pick` slot per entry of `matchups`, each offering the
    /// labels given. `age` is how long ago it was posted; `locksIn` is
    /// relative to `epoch` (negative → already past `lock_at`).
    @discardableResult
    func addPost(
        _ promptText: String,
        kind: String = "picks",
        status: String = "open",
        by author: UUID? = nil,
        age: TimeInterval = 0,
        locksIn: TimeInterval = 3600,
        slots matchups: [[String]] = [["Chiefs", "Bills"]],
        shape: String = "pick",
        pickCount: Int? = nil
    ) -> AddedPost {
        lock.withLock {
            let postId = UUID()
            let authorId = author ?? UUID()
            if !rows.profiles.contains(where: { $0.id == authorId }) {
                rows.profiles.append(PromptProfileRow(id: authorId, displayName: "Ball Party"))
            }
            rows.posts.append(PromptPostRow(
                id: postId, templateKind: kind, authorId: authorId, promptText: promptText,
                lockAt: epoch.addingTimeInterval(locksIn), createdAt: epoch.addingTimeInterval(-age),
                status: status
            ))
            var slotIds: [UUID] = [], optionIds: [[UUID]] = []
            for (slotIndex, labels) in matchups.enumerated() {
                let slotId = UUID()
                slotIds.append(slotId)
                rows.slots.append(PromptSlotRow(
                    id: slotId, postId: postId, label: "Game \(slotIndex + 1)", shape: shape,
                    pickCount: pickCount, sortOrder: slotIndex
                ))
                var ids: [UUID] = []
                for (optionIndex, label) in labels.enumerated() {
                    let optionId = UUID()
                    ids.append(optionId)
                    rows.options.append(PromptOptionRow(
                        id: optionId, slotId: slotId, label: label, sortOrder: optionIndex
                    ))
                }
                optionIds.append(ids)
            }
            return AddedPost(id: postId, slotIds: slotIds, optionIds: optionIds)
        }
    }

    /// A Game Picks / Weekly Picks post: one slot per `(away, home)` game, each with
    /// four options in the composer's order — away <7, away 7+, home <7, home 7+ —
    /// like `0174` writes them. `optionIds[game]` is in that order.
    @discardableResult
    func addMarginPost(
        _ promptText: String,
        games: [(away: (name: String, code: String), home: (name: String, code: String))] = [(("Chiefs", "KC"), ("Bills", "BUF"))],
        status: String = "open",
        locksIn: TimeInterval = 3600
    ) -> AddedPost {
        lock.withLock {
            let postId = UUID(), authorId = UUID()
            rows.profiles.append(PromptProfileRow(id: authorId, displayName: "Ball Party"))
            rows.posts.append(PromptPostRow(
                id: postId, templateKind: games.count == 1 ? "game_pick" : "weekly_picks", authorId: authorId,
                promptText: promptText, lockAt: epoch.addingTimeInterval(locksIn), createdAt: epoch, status: status
            ))
            var slotIds: [UUID] = [], optionIds: [[UUID]] = []
            for (index, game) in games.enumerated() {
                let slotId = UUID()
                slotIds.append(slotId)
                rows.slots.append(PromptSlotRow(id: slotId, postId: postId, label: "Game \(index + 1)", sortOrder: index))
                let spec: [(String, String, String)] = [
                    (game.away.name, game.away.code, "under_7"), (game.away.name, game.away.code, "7_plus"),
                    (game.home.name, game.home.code, "under_7"), (game.home.name, game.home.code, "7_plus"),
                ]
                var ids: [UUID] = []
                for (position, option) in spec.enumerated() {
                    let optionId = UUID()
                    ids.append(optionId)
                    rows.options.append(PromptOptionRow(
                        id: optionId, slotId: slotId, label: "\(option.0) by \(option.2 == "under_7" ? "<7" : "7+")",
                        sublabel: option.2 == "under_7" ? "Wins by 1–6" : "Wins by 7 or more",
                        teamCode: option.1, sortOrder: position, margin: option.2
                    ))
                }
                optionIds.append(ids)
            }
            return AddedPost(id: postId, slotIds: slotIds, optionIds: optionIds)
        }
    }

    /// A Power Rankings post: one `rank` slot over the given teams (label and
    /// team code both the code), best-known order first, with the cover art the
    /// admin chose. `option(_:)` finds a team's option id.
    @discardableResult
    func addPowerRankingsPost(
        _ promptText: String,
        teams: [String],
        cover: [String] = [],
        status: String = "open",
        age: TimeInterval = 0,
        locksIn: TimeInterval = 3600
    ) -> AddedPost {
        lock.withLock {
            let postId = UUID(), slotId = UUID(), authorId = UUID()
            rows.profiles.append(PromptProfileRow(id: authorId, displayName: "Ball Party"))
            rows.posts.append(PromptPostRow(
                id: postId, templateKind: "power_rankings", authorId: authorId, promptText: promptText,
                lockAt: epoch.addingTimeInterval(locksIn), createdAt: epoch.addingTimeInterval(-age),
                status: status, isOpinion: true, coverTeamCodes: cover
            ))
            rows.slots.append(PromptSlotRow(
                id: slotId, postId: postId, label: "Your power rankings", shape: "rank", pickCount: 32
            ))
            let optionIds = teams.enumerated().map { index, code -> UUID in
                let optionId = UUID()
                rows.options.append(PromptOptionRow(
                    id: optionId, slotId: slotId, label: code, teamCode: code, sortOrder: index
                ))
                return optionId
            }
            return AddedPost(id: postId, slotIds: [slotId], optionIds: [optionIds])
        }
    }

    /// A Weekly Awards post, laid out as the composer writes it: two teams slots
    /// (three clubs each, enough to tell them apart), a best-game slot whose
    /// options keep their clubs as `AWAY @ HOME` in the sublabel, and three
    /// player-search slots that start with no options at all.
    @discardableResult
    func addWeeklyAwardsPost(
        _ promptText: String = "Weekly awards",
        status: String = "open",
        age: TimeInterval = 0,
        locksIn: TimeInterval = 3600
    ) -> AddedPost {
        lock.withLock {
            let postId = UUID(), authorId = UUID()
            rows.profiles.append(PromptProfileRow(id: authorId, displayName: "Ball Party"))
            rows.posts.append(PromptPostRow(
                id: postId, templateKind: "weekly_awards", authorId: authorId, promptText: promptText,
                lockAt: epoch.addingTimeInterval(locksIn), createdAt: epoch.addingTimeInterval(-age),
                status: status, isOpinion: true
            ))
            let labels = ["Biggest winner", "Biggest loser", "Best game", "Offensive player", "Defensive player", "LVP"]
            var slotIds: [UUID] = [], optionIds: [[UUID]] = []
            for (index, label) in labels.enumerated() {
                let slotId = UUID()
                slotIds.append(slotId)
                rows.slots.append(PromptSlotRow(
                    id: slotId, postId: postId, label: label, sortOrder: index, playerSearch: index > 2
                ))
                var ids: [UUID] = []
                let options: [(label: String, sublabel: String?, team: String?)] = switch index {
                case 0, 1: [("Chiefs", nil, "KC"), ("Bills", nil, "BUF"), ("Eagles", nil, "PHI")]
                case 2: [("Chiefs @ Bills", "KC @ BUF", nil), ("Eagles @ Cowboys", "PHI @ DAL", nil)]
                default: []
                }
                for (optionIndex, option) in options.enumerated() {
                    let optionId = UUID()
                    ids.append(optionId)
                    rows.options.append(PromptOptionRow(
                        id: optionId, slotId: slotId, label: option.label, sublabel: option.sublabel,
                        teamCode: option.team, sortOrder: optionIndex
                    ))
                }
                optionIds.append(ids)
            }
            return AddedPost(id: postId, slotIds: slotIds, optionIds: optionIds)
        }
    }

    /// A Bold Predictions post: no slots, opinion only.
    @discardableResult
    func addBoldPredictionsPost(
        _ promptText: String = "Bold predictions",
        status: String = "open",
        age: TimeInterval = 0,
        locksIn: TimeInterval = 3600
    ) -> AddedPost {
        lock.withLock {
            let postId = UUID(), authorId = UUID()
            rows.profiles.append(PromptProfileRow(id: authorId, displayName: "Ball Party"))
            rows.posts.append(PromptPostRow(
                id: postId, templateKind: "bold_predictions", authorId: authorId, promptText: promptText,
                lockAt: epoch.addingTimeInterval(locksIn), createdAt: epoch.addingTimeInterval(-age),
                status: status, isOpinion: true
            ))
            return AddedPost(id: postId, slotIds: [], optionIds: [])
        }
    }

    func addPlayers(_ players: [NFLPlayer]) { lock.withLock { directory += players } }

    func setWeekGames(_ games: [NFLScheduleGame]) { lock.withLock { schedule = games } }

    /// Somebody else's prediction, as if written while the viewer wasn't looking.
    func anotherPlayerPredicts(
        _ body: String, on post: AddedPost, by author: UUID, tagging target: BoldTarget, secondsAfterEpoch offset: TimeInterval = 0
    ) {
        lock.withLock {
            boldRows.append(BoldPredictionRow(
                postId: post.id, authorId: author, body: body, targetType: target.type.rawValue,
                targetId: target.id, createdAt: epoch.addingTimeInterval(offset)
            ))
        }
    }

    func setPowerTopFive(for post: AddedPost, _ rowsForPost: [PromptPowerTopFiveRow]) {
        lock.withLock { powerTopFiveByPost[post.id] = rowsForPost }
    }

    /// The server locks the slot in the same way `resolve_post` does: correct
    /// answer written, status flipped.
    func resolve(_ post: AddedPost, correct: [UUID], pointsAwarded: Int) {
        lock.withLock {
            rows.posts = rows.posts.map { row in
                guard row.id == post.id else { return row }
                return PromptPostRow(
                    id: row.id, templateKind: row.templateKind, authorId: row.authorId,
                    promptText: row.promptText, lockAt: row.lockAt, createdAt: row.createdAt,
                    status: "resolved"
                )
            }
            rows.slots = rows.slots.map { row in
                guard row.postId == post.id else { return row }
                return PromptSlotRow(
                    id: row.id, postId: row.postId, label: row.label, shape: row.shape,
                    pickCount: row.pickCount, points: row.points, sortOrder: row.sortOrder,
                    correctOptionIds: correct
                )
            }
            rows.viewerResponses = rows.viewerResponses.map { row in
                guard row.postId == post.id else { return row }
                return PromptResponseRow(
                    postId: row.postId, slotId: row.slotId, chosenOptionIds: row.chosenOptionIds,
                    pointsEarned: pointsAwarded
                )
            }
        }
    }

    /// The next `feedRows` call reads the server as it is now but answers late.
    func holdNextFeedRead() { lock.withLock { _holdNextFeedRead = true } }

    var heldFeedReads: Int { lock.withLock { _heldReads.count } }

    func releaseHeldFeedReads() {
        let held = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            defer { _heldReads = [] }
            return _heldReads
        }
        held.forEach { $0.resume() }
    }

    func setAggregate(for post: AddedPost, _ rowsForPost: [PromptAggregateRow]) {
        lock.withLock { aggregatesByPost[post.id] = rowsForPost }
    }

    func setRevealed(for post: AddedPost, _ rowsForPost: [PromptRevealedResponseRow]) {
        lock.withLock { revealedByPost[post.id] = rowsForPost }
    }

    /// Somebody else's take, posted while the viewer wasn't looking.
    @discardableResult
    func anotherPlayerPosts(
        _ body: String, on post: AddedPost, by author: UUID, withPick: Bool = true, replyingTo parent: UUID? = nil
    ) -> UUID {
        lock.withLock {
            let comment = nextComment(postId: post.id, author: author, body: body, withPick: withPick, parent: parent)
            rows.comments.append(comment)
            return comment.id
        }
    }

    /// A post's viewer response row, as if answered from another device.
    func viewerAlreadyAnswered(_ post: AddedPost, choosing choices: [UUID: [UUID]]) {
        lock.withLock {
            for (slotId, optionIds) in choices {
                rows.viewerResponses.append(PromptResponseRow(
                    postId: post.id, slotId: slotId, chosenOptionIds: optionIds, pointsEarned: nil
                ))
            }
        }
    }

    // MARK: - HuddleClient

    func feedRows(viewerId: UUID) async throws -> PromptFeedRows {
        let (snapshot, hold): (PromptFeedRows, Bool) = try lock.withLock {
            _feedReads += 1
            if let failure = _failures["feed_rows"] { throw failure }
            defer { _holdNextFeedRead = false }
            return (rows, _holdNextFeedRead)
        }
        // A slow response: the rows are read *now*, but only handed back once
        // the test says so — by which time the server may have moved on.
        if hold {
            await withCheckedContinuation { continuation in
                lock.withLock { _heldReads.append(continuation) }
            }
        }
        return snapshot
    }

    func aggregates(postId: UUID) async throws -> [PromptAggregateRow] {
        lock.withLock {
            _aggregateRequests.append(postId)
            return aggregatesByPost[postId] ?? []
        }
    }

    func powerRankingTopFive(postId: UUID) async throws -> [PromptPowerTopFiveRow] {
        try lock.withLock {
            _powerTopFiveRequests.append(postId)
            if let failure = _failures["power_ranking_top_five"] { throw failure }
            return powerTopFiveByPost[postId] ?? []
        }
    }

    func revealedResponses(postId: UUID) async throws -> [PromptRevealedResponseRow] {
        try lock.withLock {
            _revealedRequests.append(postId)
            if let failure = _failures["revealed_responses"] { throw failure }
            return revealedByPost[postId] ?? []
        }
    }

    func submitResponse(postId: UUID, choices: [UUID: [UUID]], players: [UUID: String], comment: String?) async throws {
        try lock.withLock {
            if let failure = _failures["submit_response"] { throw failure }
            _submissions.append(Submission(postId: postId, choices: choices, players: players, comment: comment))
            for (slotId, optionIds) in choices {
                rows.viewerResponses.append(PromptResponseRow(
                    postId: postId, slotId: slotId, chosenOptionIds: optionIds, pointsEarned: nil
                ))
            }
            // The server makes an option for a player the first time anyone picks them.
            for (slotId, playerId) in players {
                guard let player = directory.first(where: { $0.id == playerId }) else {
                    throw HuddleServerError(message: "invalid_option")
                }
                let existing = rows.options.first { $0.slotId == slotId && $0.sublabel == player.summary && $0.label == player.name }
                let optionId = existing?.id ?? UUID()
                if existing == nil {
                    rows.options.append(PromptOptionRow(
                        id: optionId, slotId: slotId, label: player.name, sublabel: player.summary,
                        teamCode: player.team, headshotUrl: player.headshotURL?.absoluteString
                    ))
                }
                rows.viewerResponses.append(PromptResponseRow(
                    postId: postId, slotId: slotId, chosenOptionIds: [optionId], pointsEarned: nil
                ))
            }
            if let comment, !comment.isEmpty {
                rows.comments.append(nextComment(
                    postId: postId, author: viewerId, body: comment, withPick: true, parent: nil
                ))
            }
        }
    }

    func boldPredictions(postId: UUID) async throws -> BoldPredictionRows {
        try lock.withLock {
            if let failure = _failures["bold_predictions"] { throw failure }
            let post = rows.posts.first { $0.id == postId }
            let mine = boldRows.contains { $0.postId == postId && $0.authorId == viewerId }
            let revealed = mine || (post.map { $0.lockAt <= epoch } ?? false)
            let visible = boldRows.filter { $0.postId == postId && (revealed || $0.authorId == viewerId) }
            let authors = Set(visible.map(\.authorId))
            return BoldPredictionRows(
                predictions: visible, profiles: rows.profiles.filter { authors.contains($0.id) }
            )
        }
    }

    func boldPredictionCounts(postIds: [UUID]) async throws -> [UUID: Int] {
        lock.withLock {
            Dictionary(postIds.map { id in (id, boldRows.filter { $0.postId == id }.count) }, uniquingKeysWith: { first, _ in first })
        }
    }

    func submitBoldPredictions(postId: UUID, predictions: [BoldDraft]) async throws {
        try lock.withLock {
            if let failure = _failures["submit_bold_predictions"] { throw failure }
            if boldRows.contains(where: { $0.postId == postId && $0.authorId == viewerId }) {
                throw HuddleServerError(message: "already_answered")
            }
            _boldSubmissions.append(BoldSubmission(postId: postId, predictions: predictions))
            for (index, prediction) in predictions.enumerated() {
                boldRows.append(BoldPredictionRow(
                    postId: postId, authorId: viewerId, body: prediction.body, targetType: prediction.target.type.rawValue,
                    targetId: prediction.target.id, createdAt: epoch.addingTimeInterval(Double(index))
                ))
            }
        }
    }

    func weekGames(after lockAt: Date) async throws -> [NFLScheduleGame] {
        try lock.withLock {
            if let failure = _failures["week_games"] { throw failure }
            return schedule
        }
    }

    func searchPlayers(query: String) async throws -> [NFLPlayer] {
        try lock.withLock {
            _playerSearches.append(query)
            if let failure = _failures["search_players"] { throw failure }
            let needle = query.lowercased()
            return directory.filter { $0.name.lowercased().contains(needle) }
        }
    }

    func players(ids: [String]) async throws -> [NFLPlayer] {
        lock.withLock { directory.filter { ids.contains($0.id) } }
    }

    func postComment(postId: UUID, body: String, parentCommentId: UUID?) async throws {
        try lock.withLock {
            if let failure = _failures["post_comment"] { throw failure }
            _comments.append(PostedComment(postId: postId, body: body, parentCommentId: parentCommentId))
            rows.comments.append(nextComment(
                postId: postId, author: viewerId, body: body, withPick: false, parent: parentCommentId
            ))
        }
    }

    // MARK: - Private

    /// Comments are ordered by `created_at`, so each one lands a minute after
    /// the last.
    private func nextComment(postId: UUID, author: UUID, body: String, withPick: Bool, parent: UUID?) -> PromptCommentRow {
        clock += 1
        return PromptCommentRow(
            id: UUID(), postId: postId, authorId: author, body: body, postedWithPick: withPick,
            parentCommentId: parent, createdAt: epoch.addingTimeInterval(Double(clock) * 60)
        )
    }
}
