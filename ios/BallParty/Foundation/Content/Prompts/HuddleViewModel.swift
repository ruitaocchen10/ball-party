import Foundation

/// Huddle's screens' shared state: the feed, the picks a player is in the
/// middle of making, and the takes and replies they are in the middle of
/// writing. A prompt's detail screen reads the very same read model as the
/// feed does, as it does on the web, so a post is looked up by id from
/// `posts` rather than held separately — a card and its detail screen cannot
/// disagree about picks, takes, or which response is the viewer's.
///
/// Every rule that is the server's to enforce (locking, one answer per post,
/// the reply depth limit) is still the server's. What is here is only the
/// guard that keeps a screen from offering a control the server would refuse.
@MainActor
final class HuddleViewModel: ObservableObject {
    enum Phase: Equatable {
        /// Nothing has been read yet.
        case loading
        case loaded
        /// The first read failed, so there is nothing to show.
        case failed(String)
    }

    /// What a prompt's card in the feed invites the viewer to do — the same
    /// three calls to action the web's card makes, plus one for a prompt that
    /// has closed on somebody who never answered.
    enum CardAction: Equatable {
        case makePicks, viewPicks, seeTakes, seeResults, updateApp
        /// Bold Predictions' own pair: the web labels them by whether the post is
        /// still open, not by whether the viewer has answered.
        case makePredictions, seePredictions

        var label: String {
            switch self {
            case .makePicks: "Make your picks"
            case .viewPicks: "View your picks"
            case .seeTakes: "See takes"
            case .seeResults: "See results"
            case .updateApp: "Update to play"
            case .makePredictions: "Make your predictions"
            case .seePredictions: "See predictions"
            }
        }
    }

    /// The most a take or a reply may say — `prompt_comments.body`'s check.
    static let commentMax = 280

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var posts: [PromptPost] = []
    /// The reason the last action or refresh failed, for a banner.
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSending = false

    /// `{post → {slot → chosen options}}` — picks not yet locked in.
    @Published private(set) var pickDrafts: [UUID: [UUID: [UUID]]] = [:]
    /// `{post → how many teams}` — the depth a Power Rankings ballot is being
    /// composed to (5, 10 or 32). Absent means the shallowest.
    @Published private(set) var rankDepths: [UUID: Int] = [:]
    /// `{post → {slot → player}}` — the players chosen for a Weekly Awards post's
    /// search slots. A player is not an option, so it is kept apart from
    /// `pickDrafts` and sent as a directory id.
    @Published private(set) var playerDrafts: [UUID: [UUID: NFLPlayer]] = [:]
    /// `{post → predictions}` — Bold Predictions not yet locked in.
    @Published private(set) var boldDrafts: [UUID: [BoldDraft]] = [:]
    /// `{post → the games and players its tags are drawn from}`.
    @Published private(set) var boldBoards: [UUID: BoldBoardData] = [:]
    /// Players this session has found, so a tag the viewer just chose keeps its
    /// name and headshot.
    @Published private(set) var foundPlayers: [String: NFLPlayer] = [:]
    /// `{post → take}` — the optional take that goes with the picks.
    @Published private(set) var takeDrafts: [UUID: String] = [:]
    /// `{take → reply}`.
    @Published private(set) var replyDrafts: [UUID: String] = [:]

    /// The viewer's accepted friends, whose takes are read before everyone else's.
    @Published private(set) var friendIds: Set<UUID> = []

    private let client: HuddleClient
    private let viewerId: UUID
    private let now: () -> Date
    /// Reads are numbered as they start, so a slow one that finishes after a
    /// newer one has already answered can be told apart from it and dropped.
    private var loadsStarted = 0
    private var lastAppliedLoad = 0

    init(client: HuddleClient, viewerId: UUID, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.viewerId = viewerId
        self.now = now
    }

    // MARK: - Reading

    /// A full re-read of the feed. Also what pull-to-refresh calls.
    ///
    /// A refresh that fails after the feed has already shown keeps what is on
    /// screen and reports the reason; only a *first* read that fails leaves the
    /// screen with nothing to show.
    func load() async {
        loadsStarted += 1
        let mine = loadsStarted
        do {
            let loaded = try await PromptFeed.load(client: client, viewerId: viewerId, now: now())
            // Loads overlap — appearing, foregrounding, pulling to refresh, and
            // a pick landing can all start one — and a read that began before a
            // pick landed can finish after the read that began after it.
            guard mine > lastAppliedLoad else { return }
            lastAppliedLoad = mine
            posts = loaded
            phase = .loaded
            errorMessage = nil
            // Like the web, a failure here costs the friends section, not the feed.
            if let friends = try? await client.friendIds() { friendIds = friends }
        } catch {
            // A read abandoned by the screen (leaving it, or letting go of a
            // pull-to-refresh) is not a failure to report.
            if Self.isCancellation(error) || mine < lastAppliedLoad { return }
            if phase == .loaded {
                errorMessage = HuddleServerError.describe(error)
            } else {
                phase = .failed(HuddleServerError.describe(error))
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    func post(_ id: UUID) -> PromptPost? { posts.first { $0.id == id } }

    // MARK: - Takes on screen

    /// The viewer's own take on a post, if they left one with their picks.
    func yourTake(on postId: UUID) -> PromptComment? {
        post(postId)?.comments.first { $0.isViewer && $0.postedWithPick }
    }

    /// Whether the viewer may read other players' takes and answers: once they
    /// have answered, or once the prompt has stopped taking picks. Before that,
    /// making a pick is what unlocks the discussion, on the web too
    /// (`PromptThread`), so a take is never a way to learn what a crowd
    /// thinks before committing; after it, there is nothing left to copy.
    private func canReadOthers(_ post: PromptPost) -> Bool {
        post.viewerAnswered || !post.isTakingPicks(at: now())
    }

    /// Everybody else's takes, gated by `canReadOthers`.
    private func comments(on postId: UUID, friends: Bool) -> [PromptComment] {
        guard let post = post(postId), canReadOthers(post) else { return [] }
        return post.comments.filter { !$0.isViewer && isFriend($0.authorId) == friends }
    }

    func otherTakes(on postId: UUID) -> [PromptComment] {
        comments(on: postId, friends: false).filter(\.hasWords)
    }

    /// The viewer's friends' takes, which lead the discussion; gated like
    /// `otherTakes`.
    func friendTakes(on postId: UUID) -> [PromptComment] {
        comments(on: postId, friends: true).filter(\.hasWords)
    }

    /// Every answer is a take, empty when the player wrote nothing. The lists
    /// run friends first, then takes with words, then bare answers.
    func friendAnswers(on postId: UUID) -> [PromptComment] {
        comments(on: postId, friends: true).filter { !$0.hasWords }
    }

    func otherAnswers(on postId: UUID) -> [PromptComment] {
        comments(on: postId, friends: false).filter { !$0.hasWords }
    }

    func isFriend(_ authorId: UUID?) -> Bool {
        authorId.map(friendIds.contains) ?? false
    }

    // MARK: - Making picks

    /// Whether the viewer can still make picks on this post.
    func canAnswer(_ postId: UUID) -> Bool {
        post(postId)?.canBeAnswered(at: now()) ?? false
    }

    func callToAction(for postId: UUID) -> CardAction {
        guard let post = post(postId) else { return .seeResults }
        if post.isUnsupported { return .updateApp }
        if post.isBoldPredictions { return post.isTakingPicks(at: now()) ? .makePredictions : .seePredictions }
        if canAnswer(postId) { return .makePicks }
        if post.viewerAnswered { return post.isTakingPicks(at: now()) ? .viewPicks : .seeTakes }
        return .seeResults
    }

    func selection(in slotId: UUID, of postId: UUID) -> [UUID] {
        pickDrafts[postId]?[slotId] ?? []
    }

    /// How many teams a Power Rankings ballot is being composed to.
    func rankDepth(for postId: UUID) -> Int {
        rankDepths[postId] ?? PromptPost.powerRankingDepths[0]
    }

    /// Chooses how deep a Power Rankings ballot goes. Going shallower drops the
    /// teams that no longer fit, lowest-ranked first, like the web's board.
    func setRankDepth(_ depth: Int, for postId: UUID) {
        guard canAnswer(postId), let post = post(postId), post.isPowerRankings,
              PromptPost.powerRankingDepths.contains(depth)
        else { return }
        rankDepths[postId] = depth
        for slot in post.slots {
            if let chosen = pickDrafts[postId]?[slot.id], chosen.count > depth {
                pickDrafts[postId]?[slot.id] = Array(chosen.prefix(depth))
            }
        }
    }

    /// How many options a complete answer to `slot` holds. A Power Rankings
    /// ballot's is the depth the player chose; every other slot's is the
    /// composer's.
    func requiredCount(for slot: PromptSlot, in post: PromptPost) -> Int {
        post.isPowerRankings ? rankDepth(for: post.id) : slot.requiredCount
    }

    /// One tap on an option. A `pick` slot holds one option, and a second tap
    /// elsewhere replaces it; a set or a ranking fills up to its count, in the
    /// order tapped (which is the ranking), and a tap on a chosen option
    /// removes it.
    func toggle(_ optionId: UUID, in slotId: UUID, of postId: UUID) {
        guard canAnswer(postId), let post = post(postId),
              let slot = post.slots.first(where: { $0.id == slotId }), !slot.playerSearch
        else { return }
        var chosen = selection(in: slotId, of: postId)
        if let index = chosen.firstIndex(of: optionId) {
            chosen.remove(at: index)
        } else if slot.shape == .pick {
            chosen = [optionId]
        } else if chosen.count < requiredCount(for: slot, in: post) {
            chosen.append(optionId)
        }
        pickDrafts[postId, default: [:]][slotId] = chosen
    }

    /// Moves one ranked option to a new place in a ranking, the way a drag on
    /// the board does. `destination` is the place it ends up in, not the gap it
    /// is dropped into. Only the order of what is already chosen changes.
    func moveRanked(from source: Int, to destination: Int, in slotId: UUID, of postId: UUID) {
        guard canAnswer(postId) else { return }
        var chosen = selection(in: slotId, of: postId)
        guard chosen.indices.contains(source), chosen.indices.contains(destination), source != destination
        else { return }
        chosen.insert(chosen.remove(at: source), at: destination)
        pickDrafts[postId, default: [:]][slotId] = chosen
    }

    func takeDraft(for postId: UUID) -> String { takeDrafts[postId] ?? "" }

    func setTakeDraft(_ text: String, for postId: UUID) {
        takeDrafts[postId] = String(text.prefix(Self.commentMax))
    }

    /// The player chosen for one of a Weekly Awards post's search slots.
    func player(in slotId: UUID, of postId: UUID) -> NFLPlayer? {
        playerDrafts[postId]?[slotId]
    }

    /// Chooses (or, with `nil`, clears) the player for a search slot.
    func setPlayer(_ player: NFLPlayer?, in slotId: UUID, of postId: UUID) {
        guard canAnswer(postId), let slot = post(postId)?.slots.first(where: { $0.id == slotId }), slot.playerSearch
        else { return }
        playerDrafts[postId, default: [:]][slotId] = player
        if let player { foundPlayers[player.id] = player }
    }

    /// Searches the player directory for a Weekly Awards slot or a prediction tag.
    func searchPlayers(_ query: String) async throws -> [NFLPlayer] {
        try await client.searchPlayers(query: query)
    }

    /// Whether every slot has a complete answer.
    func canSubmit(_ postId: UUID) -> Bool {
        guard canAnswer(postId), let post = post(postId), !post.isBoldPredictions else { return false }
        return post.slots.allSatisfy { slot in
            slot.playerSearch
                ? player(in: slot.id, of: postId) != nil
                : selection(in: slot.id, of: postId).count == requiredCount(for: slot, in: post)
        }
    }

    /// Locks in the picks — and the take, in the same call — then re-reads,
    /// because answering is what turns on the crowd's percentages and the
    /// other players' takes. On a refusal nothing is thrown away: the picks and
    /// the take stay where they were, and the reason shows.
    func submitAnswer(_ postId: UUID) async {
        guard canSubmit(postId), !isSending else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        let take = takeDraft(for: postId).trimmed
        let players = (playerDrafts[postId] ?? [:]).mapValues(\.id)
        // A search slot is answered by its player, so whatever option a stale
        // draft might hold for it is not sent.
        let choices = (pickDrafts[postId] ?? [:]).filter { players[$0.key] == nil }
        do {
            try await client.submitResponse(
                postId: postId, choices: choices, players: players, comment: take.isEmpty ? nil : take
            )
        } catch {
            errorMessage = HuddleServerError.describe(error)
            return
        }
        pickDrafts[postId] = nil
        playerDrafts[postId] = nil
        rankDepths[postId] = nil
        takeDrafts[postId] = nil
        await load()
        await PushCoordinator.shared.meaningfulActionCompleted()
    }

    // MARK: - Bold Predictions

    func boldDraftList(for postId: UUID) -> [BoldDraft] { boldDrafts[postId] ?? [] }

    /// Whether `draft` is a prediction worth keeping: some words (trimmed, at most
    /// 280 characters) and a tag. The server checks the tag itself.
    static func isReadyPrediction(_ draft: BoldDraft) -> Bool {
        let body = draft.body.trimmed
        return !body.isEmpty && body.count <= BoldLimits.bodyMax
    }

    func canAddPrediction(to postId: UUID) -> Bool {
        canAnswer(postId) && boldDraftList(for: postId).count < BoldLimits.maxPredictions
    }

    /// Adds a prediction to the response being written. Returns whether it was
    /// kept — not when the response is full or the words are missing or too long.
    @discardableResult
    func addPrediction(_ draft: BoldDraft, to postId: UUID) -> Bool {
        guard canAddPrediction(to: postId), Self.isReadyPrediction(draft) else { return false }
        boldDrafts[postId, default: []].append(BoldDraft(body: draft.body.trimmed, target: draft.target))
        return true
    }

    /// Replaces the prediction at `index`. Returns whether it was kept.
    @discardableResult
    func replacePrediction(at index: Int, with draft: BoldDraft, in postId: UUID) -> Bool {
        guard canAnswer(postId), boldDraftList(for: postId).indices.contains(index), Self.isReadyPrediction(draft)
        else { return false }
        boldDrafts[postId]?[index] = BoldDraft(body: draft.body.trimmed, target: draft.target)
        return true
    }

    func removePrediction(at index: Int, from postId: UUID) {
        guard canAnswer(postId), boldDraftList(for: postId).indices.contains(index) else { return }
        boldDrafts[postId]?.remove(at: index)
    }

    func canLockInPredictions(_ postId: UUID) -> Bool {
        canAnswer(postId) && !boldDraftList(for: postId).isEmpty && !isSending
    }

    /// Locks in the whole response — final: there is no editing or deleting
    /// afterwards — then re-reads, because answering is what unlocks everyone
    /// else's predictions. On a refusal the drafts stay where they were.
    func lockInPredictions(_ postId: UUID) async {
        guard canLockInPredictions(postId) else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            try await client.submitBoldPredictions(postId: postId, predictions: boldDraftList(for: postId))
        } catch {
            errorMessage = HuddleServerError.describe(error)
            return
        }
        boldDrafts[postId] = nil
        await load()
        await loadBoldBoard(postId)
    }

    /// Reads what a post's tags are drawn from: the week's games for a matchup
    /// tag, and the directory rows of whichever players its predictions name.
    /// Like the web, a failure costs the tags their art, never the post.
    func loadBoldBoard(_ postId: UUID) async {
        guard let post = post(postId), post.isBoldPredictions else { return }
        async let games: [NFLScheduleGame] = (try? await client.weekGames(after: post.lockAt)) ?? []
        let tagged = Set(post.boldPredictions.filter { $0.target.type == .player }.map(\.target.id))
        let missing = tagged.subtracting(foundPlayers.keys)
        async let players: [NFLPlayer] = missing.isEmpty ? [] : ((try? await client.players(ids: Array(missing))) ?? [])
        let (weekGames, found) = await (games, players)
        for player in found { foundPlayers[player.id] = player }
        boldBoards[postId] = BoldBoardData(weekGames: weekGames, players: foundPlayers)
    }

    /// The tag data for a post, with every player found so far.
    func boldBoard(for postId: UUID) -> BoldBoardData {
        BoldBoardData(weekGames: boldBoards[postId]?.weekGames ?? [], players: foundPlayers)
    }

    /// Remembers a player the viewer chose for a tag.
    func rememberPlayer(_ player: NFLPlayer) {
        foundPlayers[player.id] = player
    }

    // MARK: - Replying

    func replyDraft(for takeId: UUID) -> String { replyDrafts[takeId] ?? "" }

    func setReplyDraft(_ text: String, for takeId: UUID) {
        replyDrafts[takeId] = String(text.prefix(Self.commentMax))
    }

    func canReply(to takeId: UUID) -> Bool {
        !replyDraft(for: takeId).trimmed.isEmpty && !isSending
    }

    /// Posts a reply under a take. Only ever offered on a top-level take —
    /// the server refuses a reply to a reply (`nested_reply`).
    func sendReply(to takeId: UUID, on postId: UUID) async {
        guard canReply(to: takeId) else { return }
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            try await client.postComment(
                postId: postId,
                body: replyDraft(for: takeId).trimmed,
                parentCommentId: takeId
            )
        } catch {
            errorMessage = HuddleServerError.describe(error)
            return
        }
        replyDrafts[takeId] = nil
        await load()
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
