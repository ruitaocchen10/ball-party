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
    private var revealedByPost: [UUID: [PromptRevealedResponseRow]] = [:]
    private var clock = 0

    private var _holdNextFeedRead = false
    private var _heldReads: [CheckedContinuation<Void, Never>] = []

    // What the app asked for.
    private var _feedReads = 0
    private var _aggregateRequests: [UUID] = []
    private var _revealedRequests: [UUID] = []
    private var _submissions: [Submission] = []
    private var _comments: [PostedComment] = []

    struct Submission: Equatable {
        let postId: UUID
        let choices: [UUID: [UUID]]
        let comment: String?
    }

    struct PostedComment: Equatable {
        let postId: UUID
        let body: String
        let parentCommentId: UUID?
    }

    var feedReads: Int { lock.withLock { _feedReads } }
    var aggregateRequests: [UUID] { lock.withLock { _aggregateRequests } }
    var revealedRequests: [UUID] { lock.withLock { _revealedRequests } }
    var submissions: [Submission] { lock.withLock { _submissions } }
    var postedComments: [PostedComment] { lock.withLock { _comments } }

    /// Scripted failures, keyed by RPC name (`feed_rows`, `submit_response`,
    /// `post_comment`, `revealed_responses`). Cleared by the test that set it.
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

    func addProfile(_ id: UUID = UUID(), named name: String) -> UUID {
        lock.withLock { rows.profiles.append(PromptProfileRow(id: id, displayName: name)) }
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

    func revealedResponses(postId: UUID) async throws -> [PromptRevealedResponseRow] {
        try lock.withLock {
            _revealedRequests.append(postId)
            if let failure = _failures["revealed_responses"] { throw failure }
            return revealedByPost[postId] ?? []
        }
    }

    func submitResponse(postId: UUID, choices: [UUID: [UUID]], comment: String?) async throws {
        try lock.withLock {
            if let failure = _failures["submit_response"] { throw failure }
            _submissions.append(Submission(postId: postId, choices: choices, comment: comment))
            for (slotId, optionIds) in choices {
                rows.viewerResponses.append(PromptResponseRow(
                    postId: postId, slotId: slotId, chosenOptionIds: optionIds, pointsEarned: nil
                ))
            }
            if let comment, !comment.isEmpty {
                rows.comments.append(nextComment(
                    postId: postId, author: viewerId, body: comment, withPick: true, parent: nil
                ))
            }
        }
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
