import Foundation

/// Reads the Huddle feed and shapes it for a screen — the Swift counterpart of
/// the web's `fetchPromptFeed` (`webapp/lib/foundation/content/prompts/feed.ts`):
/// flat rows in, joined and ordered `PromptPost`s out.
///
/// Everything a screen may or may not be shown is decided here, from the rows
/// alone: which posts are on the feed, whose picks are visible yet, and which
/// order things sit in. The rows come back in whatever order the server likes,
/// so nothing below depends on it.
enum PromptFeed {
    static func load(client: HuddleClient, viewerId: UUID, now: Date) async throws -> [PromptPost] {
        let rows = try await client.feedRows(viewerId: viewerId)
        let posts = rows.posts.filter(isShown)
        let answered = Set(rows.viewerResponses.map(\.postId))

        // A revealed view only ever shows once a post isn't open-and-unanswered
        // (`Post.aggregate` in `types.ts`) — and "open" means still taking
        // picks, not merely `status == 'open'` (`PostStatus.isTakingPicks`).
        // `post_aggregates` is the only sanctioned way to see anyone else's
        // pick, so it is asked for only the posts that actually need it.
        let needingAggregate = posts.filter { row in
            answered.contains(row.id) || !(row.postStatus?.isTakingPicks(lockAt: row.lockAt, now: now) ?? false)
        }
        let aggregates = try await gather(needingAggregate) {
            try await client.aggregates(postId: $0.id)
        }

        // A Power Rankings post's "most common top 5", revealed under the same
        // rule as the aggregates it sits beside. Like the web, a failure here
        // costs the post its consensus panel, not the player their feed.
        let powerTopFive = await gatherQuietly(needingAggregate.filter { $0.templateKind == PromptPost.powerRankingsKind }) {
            try await client.powerRankingTopFive(postId: $0.id)
        }

        // Individual calls become social content only after the board closes.
        // The RPC is `security definer` rather than a wider RLS policy, so an
        // open prompt never leaks a pick a later participant could copy — and
        // it is not asked for one at all. This phone's clock may run a little
        // behind the server's, in which case the server says `picks_not_revealed`
        // for a post the phone thought had locked: that is "nothing to show
        // yet", not a failed feed. Any other failure still fails it.
        let revealed = try await gather(posts.filter { $0.lockAt <= now || $0.postStatus == .resolved }) { post in
            do {
                return try await client.revealedResponses(postId: post.id)
            } catch let error as HuddleServerError where error.message == HuddleServerError.picksNotRevealed {
                return []
            }
        }

        return assemble(
            rows: rows, aggregates: aggregates, powerTopFive: powerTopFive, revealed: revealed, viewerId: viewerId
        )
    }

    /// The feed shows Picks and Power Rankings posts whose status this app
    /// knows. (`assemble` also leaves out a post with a slot shape it doesn't
    /// know.)
    private static func isShown(_ row: PromptPostRow) -> Bool {
        row.postStatus != nil && PromptPost.isFeedKind(row.templateKind)
    }

    /// Runs `fetch` for every post at once, keyed by post id.
    private static func gather<Row: Sendable>(
        _ posts: [PromptPostRow], _ fetch: @escaping @Sendable (PromptPostRow) async throws -> [Row]
    ) async throws -> [UUID: [Row]] {
        try await withThrowingTaskGroup(of: (UUID, [Row]).self) { group in
            for post in posts { group.addTask { (post.id, try await fetch(post)) } }
            var results: [UUID: [Row]] = [:]
            for try await (id, rows) in group { results[id] = rows }
            return results
        }
    }

    /// `gather` for reads that may fail without failing the feed: a post whose
    /// read throws is simply absent from the result.
    private static func gatherQuietly<Row: Sendable>(
        _ posts: [PromptPostRow], _ fetch: @escaping @Sendable (PromptPostRow) async throws -> [Row]
    ) async -> [UUID: [Row]] {
        await withTaskGroup(of: (UUID, [Row]?).self) { group in
            for post in posts { group.addTask { (post.id, try? await fetch(post)) } }
            var results: [UUID: [Row]] = [:]
            for await (id, rows) in group { if let rows { results[id] = rows } }
            return results
        }
    }

    static func assemble(
        rows: PromptFeedRows,
        aggregates: [UUID: [PromptAggregateRow]] = [:],
        powerTopFive: [UUID: [PromptPowerTopFiveRow]] = [:],
        revealed: [UUID: [PromptRevealedResponseRow]] = [:],
        viewerId: UUID
    ) -> [PromptPost] {
        let slotsByPost = Dictionary(grouping: rows.slots, by: \.postId)
        let optionsBySlot = Dictionary(grouping: rows.options, by: \.slotId)
        let commentsByPost = Dictionary(grouping: rows.comments, by: \.postId)
        let responsesByPost = Dictionary(grouping: rows.viewerResponses, by: \.postId)
        let nameById = Dictionary(rows.profiles.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        let gameById = Dictionary(rows.games.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let previousRanks = previousPowerRanks(rows: rows, responsesByPost: responsesByPost)

        return rows.posts
            .sorted { $0.createdAt > $1.createdAt }
            .compactMap { row -> PromptPost? in
                guard isShown(row), let status = row.postStatus else { return nil }
                let slotRows = (slotsByPost[row.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }
                // A slot shape this app has never heard of can't be answered
                // correctly, so the post is left out — the way an unknown status
                // is — rather than shown with a control that would send the
                // server the wrong thing.
                let shapes = slotRows.compactMap { SlotShape(rawValue: $0.shape) }
                guard shapes.count == slotRows.count else { return nil }
                let slots = zip(slotRows, shapes).map { slotRow, shape in
                    PromptSlot(
                        id: slotRow.id,
                        label: slotRow.label,
                        shape: shape,
                        pickCount: slotRow.pickCount,
                        points: slotRow.points,
                        correctOptionIds: slotRow.correctOptionIds,
                        options: (optionsBySlot[slotRow.id] ?? []).sorted { $0.sortOrder < $1.sortOrder }.map {
                            PromptOption(
                                id: $0.id, label: $0.label, sublabel: $0.sublabel, teamCode: $0.teamCode,
                                headshotURL: $0.headshotUrl.flatMap(URL.init(string:))
                            )
                        },
                        game: slotRow.sourceGameId.flatMap { gameById[$0] }
                    )
                }
                let mine = responsesByPost[row.id] ?? []
                var ticketsByAuthor: [UUID: [UUID: [UUID]]] = [:]
                for ticket in revealed[row.id] ?? [] {
                    ticketsByAuthor[ticket.profileId, default: [:]][ticket.slotId] = ticket.chosenOptionIds
                }
                var aggregate: [UUID: [UUID: Double]]?
                var responseCount = 0
                if let aggregateRows = aggregates[row.id] {
                    var bySlot = Dictionary(slots.map { ($0.id, [UUID: Double]()) }, uniquingKeysWith: { first, _ in first })
                    for aggregateRow in aggregateRows {
                        bySlot[aggregateRow.slotId, default: [:]][aggregateRow.optionId] = aggregateRow.pct ?? 0
                        responseCount = max(responseCount, aggregateRow.totalResponses ?? 0)
                    }
                    aggregate = bySlot
                }
                return PromptPost(
                    id: row.id,
                    templateKind: row.templateKind,
                    templateName: row.templateName,
                    author: nameById[row.authorId] ?? "Ball Party",
                    caption: row.caption,
                    createdAt: row.createdAt,
                    promptText: row.promptText,
                    resolutionCriteria: row.resolutionCriteria,
                    lockAt: row.lockAt,
                    status: status,
                    voidReason: row.voidReason,
                    isOpinion: row.isOpinion,
                    slots: slots,
                    comments: commentTree(
                        commentsByPost[row.id] ?? [], names: nameById, viewerId: viewerId, tickets: ticketsByAuthor
                    ),
                    responseCount: responseCount,
                    viewerResponse: mine.isEmpty ? nil : Dictionary(mine.map { ($0.slotId, $0.chosenOptionIds) }, uniquingKeysWith: { _, latest in latest }),
                    // Summed from what the server wrote, never recomputed from
                    // the scoring rules — those live in `resolve_post`.
                    viewerPointsAwarded: status == .resolved && !mine.isEmpty ? mine.reduce(0) { $0 + ($1.pointsEarned ?? 0) } : nil,
                    aggregate: aggregate,
                    coverTeamCodes: row.coverTeamCodes ?? [],
                    previousRankByTeam: previousRanks[row.id] ?? [:],
                    powerRankingTopFive: (powerTopFive[row.id] ?? []).map {
                        PowerRankingConsensusEntry(
                            optionId: $0.optionId, topFiveCount: $0.topFiveCount, averageRank: $0.averageRank
                        )
                    }
                )
            }
    }

    /// For each Power Rankings post, `{team code → place}` from the viewer's
    /// most recent *earlier* ballot. Option ids are unique to each weekly post,
    /// so weeks are compared through the NFL team code — from the viewer's own
    /// rows only, which exposes nobody else's history. A week the viewer sat
    /// out leaves the older ballot in force, as on the web.
    private static func previousPowerRanks(
        rows: PromptFeedRows, responsesByPost: [UUID: [PromptResponseRow]]
    ) -> [UUID: [String: Int]] {
        let teamCodeByOption = Dictionary(
            rows.options.compactMap { option in option.teamCode.map { (option.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        var previousByPost: [UUID: [String: Int]] = [:]
        var mostRecent: [String: Int] = [:]
        let powerPosts = rows.posts
            .filter { $0.templateKind == PromptPost.powerRankingsKind && isShown($0) }
            .sorted { $0.createdAt < $1.createdAt }
        for row in powerPosts {
            previousByPost[row.id] = mostRecent
            guard let ballot = responsesByPost[row.id]?.first else { continue }
            mostRecent = Dictionary(
                ballot.chosenOptionIds.enumerated().compactMap { index, optionId in
                    teamCodeByOption[optionId].map { ($0, index + 1) }
                },
                uniquingKeysWith: { first, _ in first }
            )
        }
        return previousByPost
    }

    /// The viewer's own top-level takes across every post, newest first — the
    /// Profile tab's "Your takes", mirroring the web's `takeHistory` join of
    /// `prompt_comments` (`parent_comment_id is null`) against the feed. A
    /// reply doesn't count: walking only `post.comments`, never a comment's
    /// `replies`, is what keeps a reply out, the same way the web's query does.
    static func myTakes(in posts: [PromptPost]) -> [ProfileTake] {
        posts
            .flatMap { post in post.comments.filter(\.isViewer).map { ProfileTake(post: post, comment: $0) } }
            .sorted { $0.comment.createdAt > $1.comment.createdAt }
    }

    /// Comments come back flat; this nests each reply under its take. A reply
    /// whose parent has gone missing (a stale read mid-request) stands as a
    /// take of its own rather than being silently dropped — the same call the
    /// web's `buildCommentTree` makes.
    private static func commentTree(
        _ rows: [PromptCommentRow], names: [UUID: String], viewerId: UUID, tickets: [UUID: [UUID: [UUID]]]
    ) -> [PromptComment] {
        let ids = Set(rows.map(\.id))
        var repliesByParent: [UUID: [PromptCommentRow]] = [:]
        for row in rows {
            if let parent = row.parentCommentId { repliesByParent[parent, default: []].append(row) }
        }

        func build(_ row: PromptCommentRow) -> PromptComment {
            PromptComment(
                id: row.id,
                author: names[row.authorId] ?? "Unknown",
                body: row.body,
                createdAt: row.createdAt,
                isViewer: row.authorId == viewerId,
                postedWithPick: row.postedWithPick,
                response: row.postedWithPick ? tickets[row.authorId] : nil,
                replies: (repliesByParent[row.id] ?? []).sorted { $0.createdAt < $1.createdAt }.map(build)
            )
        }

        return rows
            .filter { $0.parentCommentId.map { !ids.contains($0) } ?? true }
            .sorted { $0.createdAt < $1.createdAt }
            .map(build)
    }
}
