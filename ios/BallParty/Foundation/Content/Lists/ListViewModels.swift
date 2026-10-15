import Foundation

/// Whose lists these are, as the editor's author line and the History links need them.
struct ListOwner: Equatable, Sendable {
    let username: String
    let displayName: String
    let avatarURL: URL?
}

/// A player's lists: the Lists tab (every kind, started or not), a Profile
/// tab's summaries, and another player's. Visitors are decided in SQL
/// (`get_ranking_lists` returns nothing for a profile the viewer may not see).
@MainActor
final class ListsViewModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded, failed }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var kinds: [ListKind] = []
    @Published private(set) var lists: [ListSummary] = []
    @Published private(set) var players: [String: ListPlayer] = [:]
    /// The faces on a position list's cover, until the player starts it.
    @Published private(set) var coverPlayers: [String: [ListPlayer]] = [:]
    @Published private(set) var owner: ListOwner?

    private let client: ListsClient
    private let ownerLoader: (() async -> ListOwner?)?
    private let wantsCovers: Bool

    /// Someone else's lists.
    init(client: ListsClient, username: String) {
        self.client = client
        self.owner = ListOwner(username: username, displayName: username, avatarURL: nil)
        self.ownerLoader = nil
        self.wantsCovers = false
    }

    /// The viewer's own lists; `owner` finds their username and name.
    init(client: ListsClient, owner: @escaping () async -> ListOwner?, showsCovers: Bool = false) {
        self.client = client
        self.ownerLoader = owner
        self.wantsCovers = showsCovers
    }

    var isOwn: Bool { ownerLoader != nil }

    func summary(for kind: ListKind) -> ListSummary? { lists.first { $0.kind == kind.id } }

    func load() async {
        do {
            if let ownerLoader {
                guard let found = await ownerLoader() else { throw ListsServerError(message: "no_profile", detail: nil) }
                owner = found
            }
            guard let username = owner?.username else { throw ListsServerError(message: "no_profile", detail: nil) }
            async let kindRows = client.kinds()
            async let listRows = client.lists(username: username)
            let (loadedKinds, loadedLists) = try await (kindRows, listRows)
            kinds = loadedKinds
            lists = loadedLists.sorted { $0.savedAt > $1.savedAt }
            phase = .loaded
            await loadFaces()
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            if phase != .loaded { phase = .failed }
        }
    }

    /// Best-effort, like the web: a failed face lookup leaves initials.
    private func loadFaces() async {
        var ids = lists.filter { $0.itemKind == .player }.flatMap { $0.items + ($0.previousItems ?? []) }
        var coverIds: [String: [String]] = [:]
        if wantsCovers {
            for kind in kinds where !kind.isTeams && summary(for: kind) == nil {
                coverIds[kind.id] = ListLogic.coverPlayerIds[kind.id] ?? []
                ids += coverIds[kind.id] ?? []
            }
        }
        guard let found = try? await client.players(ids: ids) else { return }
        players = found
        coverPlayers = coverIds.mapValues { $0.compactMap { found[$0] } }
    }
}

/// One list's page: its history (newest first) and, for the owner, whether a
/// ranking prompt is open, which hands the editing to the prompt.
@MainActor
final class ListDetailViewModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded, failed }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var versions: [ListVersion] = []
    @Published private(set) var players: [String: ListPlayer] = [:]
    @Published private(set) var openPromptId: UUID?

    let kind: ListKind
    let owner: ListOwner
    let isOwn: Bool
    private let client: ListsClient

    init(client: ListsClient, kind: ListKind, owner: ListOwner, isOwn: Bool) {
        self.client = client
        self.kind = kind
        self.owner = owner
        self.isOwn = isOwn
    }

    var current: ListVersion? { versions.first { $0.isCurrent } ?? versions.first }

    func load() async {
        do {
            let loaded = try await client.history(username: owner.username, kind: kind.id)
            versions = loaded
            phase = .loaded
            async let faces = kind.isTeams ? [:] : (try? await client.players(ids: loaded.flatMap(\.items))) ?? [:]
            async let prompt = isOwn ? (try? await client.openPrompt(kind: kind.id)) ?? nil : nil
            players = await faces
            openPromptId = await prompt
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            if phase != .loaded { phase = .failed }
        }
    }
}

/// Where a player builds a list. Moving is pick up, then place: tap a row to
/// pick it up, tap another row to put it there, or use the buttons. Nothing is
/// saved until Save, and the database decides whether a save is allowed (the
/// daily limit, a prompt that is open), so this only shows what it says.
///
/// Position lists start empty and fill by searching the player directory; team
/// lists start from all 32 teams in the saved order. Mirrors the web's `ListEditor`.
@MainActor
final class ListEditorViewModel: ObservableObject {
    let kind: ListKind
    /// The open prompt that feeds this list. While it is open the list is edited there.
    let openPromptId: UUID?

    @Published private(set) var baseline: [String]
    @Published private(set) var items: [String]
    @Published private(set) var size: Int
    @Published private(set) var players: [String: ListPlayer]
    @Published var note = ""
    @Published var share = true
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?
    @Published private(set) var saved = false

    private let client: ListsClient
    private let onSaved: () -> Void

    init(
        client: ListsClient, kind: ListKind, saved: [String], players: [String: ListPlayer],
        openPromptId: UUID?, onSaved: @escaping () -> Void = {}
    ) {
        self.client = client
        self.kind = kind
        self.baseline = saved
        self.size = kind.sizes.first { $0 == saved.count } ?? kind.sizes.last ?? saved.count
        self.items = kind.isTeams && saved.isEmpty ? ListLogic.resizeTeams([], to: kind.sizes.last ?? 32) : saved
        self.players = players
        self.openPromptId = openPromptId
        self.onSaved = onSaved
    }

    var isTeams: Bool { kind.isTeams }
    var readOnly: Bool { openPromptId != nil }
    var bench: [String] { isTeams && items.count < 32 ? ListLogic.benchTeams(items) : [] }
    var dirty: Bool { items.count != baseline.count || ListLogic.movedCount(previous: baseline, items: items) > 0 }
    var complete: Bool { items.count == size }
    /// How many places differ from the saved list; all of them when nothing is saved yet.
    var moves: Int { baseline.isEmpty ? items.count : ListLogic.movedCount(previous: baseline, items: items) }
    var canSave: Bool { !readOnly && dirty && complete && !isSaving }
    var title: String { String(ListLogic.title(kind: kind.id, itemKind: kind.itemKind, size: size).dropFirst(3)) }

    func name(of item: String) -> String {
        isTeams ? ListLogic.teamName(item) : (players[item]?.name ?? "Player")
    }

    /// How an item moved against the saved list; nil while nothing is saved.
    func change(at index: Int) -> ListMovement? {
        baseline.isEmpty ? nil : ListMovement(change: ListLogic.placeChange(previous: baseline, items: items, index: index))
    }

    /// The footer line beside Undo.
    var statusLine: String {
        if readOnly { return "Editing is paused until the prompt locks." }
        if !complete { return "\(items.count) of \(size) chosen. Finish the list to save it." }
        return dirty ? "\(moves) moved since your saved list." : "No changes yet."
    }

    // MARK: Moving

    /// An item dropped on a place: a ranked item moves there, shifting the ones between; a
    /// team from the bench takes the place, and whoever falls off the end goes to the bench.
    func drop(_ item: String, onto index: Int) {
        guard !readOnly, items.indices.contains(index) else { return }
        if let from = items.firstIndex(of: item) {
            items = ListLogic.moveItem(items, from: from, to: index)
        } else if isTeams, ListLogic.teamCodes.contains(item) {
            items = Array((items[..<index] + [item] + items[index...]).prefix(size))
        }
    }

    /// A step up or down, for VoiceOver's actions and anything that cannot drag.
    func nudge(_ index: Int, by step: Int) {
        guard !readOnly, items.indices.contains(index), items.indices.contains(index + step) else { return }
        items = ListLogic.moveItem(items, from: index, to: index + step)
    }

    func changeSize(_ next: Int) {
        guard !readOnly, kind.sizes.contains(next), isTeams else { return }
        size = next
        items = ListLogic.resizeTeams(items, to: next)
    }

    // MARK: Players

    /// Players from the directory at this list's position that are not in it yet.
    func search(_ query: String) async throws -> [NFLPlayer] {
        let found = try await client.searchPlayers(query: query)
        let position = kind.id.uppercased()
        return found.filter { $0.position == position && !items.contains($0.id) }
    }

    func add(_ player: NFLPlayer?) {
        guard let player, !readOnly, !items.contains(player.id), items.count < size else { return }
        players[player.id] = ListPlayer(player)
        items.append(player.id)
    }

    func remove(_ item: String) {
        guard !readOnly else { return }
        items.removeAll { $0 == item }
    }

    func undo() {
        items = isTeams ? ListLogic.resizeTeams(baseline, to: baseline.count) : baseline
        size = kind.sizes.first { $0 == baseline.count } ?? size
    }

    // MARK: Saving

    func save() async {
        guard canSave else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await client.save(kind: kind.id, items: items, note: note, publish: share)
            baseline = items
            note = ""
            saved = true
            onSaved()
        } catch {
            self.error = ListLogic.saveErrorMessage(error)
        }
    }

    var saveTitle: String { isSaving ? "Saving…" : share ? "Save and share" : "Save" }
}

/// An update card on its own page: the card, its replies and the box for yours.
@MainActor
final class ListUpdateViewModel: ObservableObject {
    enum Phase: Equatable { case loading, loaded, notFound, failed }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var update: ListUpdate?
    @Published private(set) var players: [String: ListPlayer] = [:]
    @Published private(set) var thread = ListThread(takeId: nil, replies: [])
    @Published var draft = ""
    @Published private(set) var isSending = false
    @Published private(set) var error: String?

    let postId: UUID
    let viewerId: UUID
    private let client: ListsClient

    init(client: ListsClient, postId: UUID, viewerId: UUID) {
        self.client = client
        self.postId = postId
        self.viewerId = viewerId
    }

    var canReply: Bool { thread.takeId != nil && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending }

    func load() async {
        do {
            guard let found = try await client.update(postId: postId) else {
                update = nil
                phase = .notFound
                return
            }
            update = found
            phase = .loaded
            if found.itemKind == .player {
                players = (try? await client.players(ids: found.items + (found.previousItems ?? []))) ?? [:]
            }
            thread = (try? await client.thread(postId: postId, viewerId: viewerId)) ?? thread
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { return }
            if phase != .loaded { phase = .failed }
        }
    }

    func sendReply() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canReply, let takeId = thread.takeId else { return }
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            try await client.reply(postId: postId, takeId: takeId, body: body)
            draft = ""
            thread = (try? await client.thread(postId: postId, viewerId: viewerId)) ?? thread
        } catch {
            self.error = HuddleServerError.describe(error)
        }
    }
}

/// The friends-only update cards on Home: the viewer's and their friends'
/// published edits, newest first, paged with `before`.
@MainActor
final class ListUpdatesViewModel: ObservableObject {
    static let pageSize = 20

    @Published private(set) var updates: [ListUpdate] = []
    @Published private(set) var players: [String: ListPlayer] = [:]
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreFailed = false

    let viewerId: UUID
    private let client: ListsClient

    init(client: ListsClient, viewerId: UUID) {
        self.client = client
        self.viewerId = viewerId
    }

    func load() async {
        // A failed read leaves the feed without update cards, as the web does.
        guard let page = try? await client.updates(limit: Self.pageSize, before: nil) else { return }
        updates = page
        hasMore = page.count >= Self.pageSize
        await loadFaces(for: page)
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, let oldest = updates.last?.savedAt else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await client.updates(limit: Self.pageSize, before: oldest)
            let known = Set(updates.map(\.postId))
            updates += page.filter { !known.contains($0.postId) }
            hasMore = page.count >= Self.pageSize
            await loadFaces(for: page)
        } catch {
            loadMoreFailed = true
        }
    }

    private func loadFaces(for page: [ListUpdate]) async {
        let ids = page.filter { $0.itemKind == .player }.flatMap { $0.items + ($0.previousItems ?? []) }
        guard let found = try? await client.players(ids: ids) else { return }
        players.merge(found) { _, new in new }
    }
}
