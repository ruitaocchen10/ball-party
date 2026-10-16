import SwiftUI

// The list screens: the Lists tab, a list's own page, the Lists section of a
// profile, and an update card with its replies.

private func makeOwnerLoader() -> () async -> ListOwner? {
    { @Sendable in
        guard let userId = SupabaseConfig.client.auth.currentSession?.user.id,
              let summary = try? await SupabaseProfileClient(client: SupabaseConfig.client).profile(userId: userId),
              let username = summary.username
        else { return nil }
        return ListOwner(username: username, displayName: summary.displayName ?? username, avatarURL: summary.avatarURL)
    }
}

// MARK: - The Lists tab

/// The Lists tab, where a player builds their lists: every kind there is, the ones
/// they keep as a short preview and the rest inviting them to start.
struct ListsScreen: View {
    let viewerId: UUID
    @StateObject private var viewModel: ListsViewModel
    private let client: ListsClient

    init(viewerId: UUID) {
        self.viewerId = viewerId
        let client = SupabaseListsClient(client: SupabaseConfig.client)
        self.client = client
        _viewModel = StateObject(wrappedValue: ListsViewModel(client: client, owner: makeOwnerLoader(), showsCovers: true))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.phase {
                case .loading:
                    LoadingSpinner().frame(maxWidth: .infinity, minHeight: 160)
                case .failed:
                    EmptyState(title: "Couldn’t load your lists", message: "Try again in a moment.") {
                        Button("Try again") { Task { await viewModel.load() } }.buttonStyle(.quiet)
                    }
                case .loaded:
                    ForEach(viewModel.kinds) { kind in
                        if let list = viewModel.summary(for: kind) {
                            ListBuilderCard(kind: kind, list: list, players: viewModel.players, detail: { detail(kind) })
                        } else {
                            ListStartCard(kind: kind, players: viewModel.coverPlayers[kind.id] ?? [], detail: { detail(kind) })
                        }
                    }
                }
            }
            .padding(16)
        }
        .refreshable { await viewModel.load() }
        .screenBackground()
        .screenHeader("Lists") { RootBell() }
        .task { await viewModel.load() }
    }

    private func detail(_ kind: ListKind) -> ListDetailScreen {
        ListDetailScreen(client: client, kind: kind, owner: viewModel.owner, isOwn: true, viewerId: viewerId)
    }
}

// MARK: - A list's page

/// One list: for its owner the editor on top and every saved version below it,
/// for a visitor the history alone.
struct ListDetailScreen: View {
    @StateObject private var viewModel: ListDetailViewModel
    private let client: ListsClient
    private let viewerId: UUID

    init(client: ListsClient, kind: ListKind, owner: ListOwner?, isOwn: Bool, viewerId: UUID) {
        self.client = client
        self.viewerId = viewerId
        _viewModel = StateObject(wrappedValue: ListDetailViewModel(
            client: client, kind: kind,
            owner: owner ?? ListOwner(username: "", displayName: "You", avatarURL: nil), isOwn: isOwn
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: viewModel.isOwn ? "Lists" : "@\(viewModel.owner.username)",
                    title: viewModel.isOwn
                        ? "Update " + ListLogic.title(kind: viewModel.kind.id, itemKind: viewModel.kind.itemKind, size: viewModel.current?.items.count ?? viewModel.kind.sizes.first ?? 10).replacingOccurrences(of: "My ", with: "your ")
                        : viewModel.kind.label,
                    description: viewModel.isOwn
                        ? "Your list is a living record. Change it any time, and every version stays in your history."
                        : "Every saved version, newest first."
                )
                switch viewModel.phase {
                case .loading:
                    LoadingSpinner().frame(maxWidth: .infinity, minHeight: 160)
                case .failed:
                    EmptyState(title: "Couldn’t load this list", message: "Try again in a moment.") {
                        Button("Try again") { Task { await viewModel.load() } }.buttonStyle(.quiet)
                    }
                case .loaded:
                    if viewModel.isOwn {
                        ListEditorView(
                            client: client, kind: viewModel.kind, saved: viewModel.current?.items ?? [], players: viewModel.players,
                            openPromptId: viewModel.openPromptId, viewerId: viewerId,
                            onSaved: { Task { await viewModel.load() } }
                        )
                        .id(viewModel.current?.id)
                    }
                    history
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await viewModel.load() }
        .screenBackground()
        .navigationTitle(viewModel.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "History")
            if viewModel.versions.isEmpty {
                EmptyState(
                    title: "No versions yet",
                    message: viewModel.isOwn ? "Save your first version and it starts your history." : "Nothing here to show."
                )
            } else {
                ListHistoryView(
                    versions: viewModel.versions, itemKind: viewModel.kind.itemKind, players: viewModel.players,
                    isOwn: viewModel.isOwn, viewerId: viewerId
                )
            }
        }
    }
}

// MARK: - On a profile

/// The Lists tab of a profile: the viewer's own (with Edit) or another player's.
struct ProfileListsTab: View {
    @StateObject private var viewModel: ListsViewModel
    private let client: ListsClient
    private let viewerId: UUID
    private let isOwn: Bool

    /// Your own lists.
    init(viewerId: UUID) {
        let client = SupabaseListsClient(client: SupabaseConfig.client)
        self.client = client
        self.viewerId = viewerId
        self.isOwn = true
        _viewModel = StateObject(wrappedValue: ListsViewModel(client: client, owner: makeOwnerLoader()))
    }

    /// Another player's lists.
    init(username: String, viewerId: UUID) {
        let client = SupabaseListsClient(client: SupabaseConfig.client)
        self.client = client
        self.viewerId = viewerId
        self.isOwn = false
        _viewModel = StateObject(wrappedValue: ListsViewModel(client: client, username: username))
    }

    var body: some View {
        ListSummariesView(
            viewModel: viewModel,
            emptyText: isOwn ? "Build your first list from the Lists tab." : "They haven’t shared any lists yet.",
            detail: { kind in
                ListDetailScreen(client: client, kind: kind, owner: viewModel.owner, isOwn: isOwn, viewerId: viewerId)
            }
        )
        .task { await viewModel.load() }
    }
}

// MARK: - Update card

/// A friend's published edit, drawn as a take card like every other post: who, when, the
/// note as the take, and under it the whole new list with how far each item moved against
/// the list it replaced (a first version has nothing to compare, so no marks).
struct ListUpdateCardView: View {
    let update: ListUpdate
    let players: [String: ListPlayer]
    let viewerId: UUID
    /// On the card's own page: no link to itself, and the history link instead.
    var full = false
    var client: FriendsClient = SupabaseFriendsClient(client: SupabaseConfig.client)

    private var isYou: Bool { update.authorId == viewerId }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            author
            Text(ListLogic.updateContext(update)).monoLabel(10, tracking: 0.1)
            if let note = update.note, !note.isEmpty {
                Text(note).font(.sans(16)).foregroundStyle(Theme.fg)
            }
            ListRowsView(items: update.items, itemKind: update.itemKind, players: players, previous: update.previousItems)
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var author: some View {
        let label = HStack(spacing: 8) {
            Avatar(name: update.displayName, url: update.avatarURL, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(update.displayName).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                if let username = update.username { Text("@\(username)").font(.sans(12)).foregroundStyle(Theme.fgMuted) }
            }
            if isYou { Text("You").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText) }
            Spacer()
            Text(update.savedAt, style: .relative).font(.mono(10)).foregroundStyle(Theme.fgMuted)
        }
        if let username = update.username, !isYou {
            NavigationLink { OtherProfileView(username: username, client: client) } label: { label }.buttonStyle(.plain)
        } else {
            label
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let ball = update.ball { TakeBallVoteView(takeId: ball.takeId, initial: ball.reaction) }
            if !full {
                NavigationLink { ListUpdateScreen(postId: update.postId, viewerId: viewerId) } label: {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.fgMuted)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle().inset(by: -8))
                        .accessibilityLabel("Reply")
                }
                .buttonStyle(.plain)
            }
            Text("Friends only").monoLabel(9, weight: .bold, tracking: 0.06, color: Theme.fg)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.line, lineWidth: 1))
            Spacer(minLength: 0)
            if full, let username = isYou ? nil : update.username {
                NavigationLink { ProfileListHistory(update: update, username: username, viewerId: viewerId) } label: {
                    Text("See the whole history").monoLabel(10, tracking: 0.08).underline().frame(minHeight: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// An update card's author's history for that list, opened from the card's page.
private struct ProfileListHistory: View {
    let update: ListUpdate
    let username: String
    let viewerId: UUID

    var body: some View {
        ListDetailScreen(
            client: SupabaseListsClient(client: SupabaseConfig.client),
            kind: ListKind(id: update.kind, label: update.label, itemKind: update.itemKind, sizes: [update.items.count]),
            owner: ListOwner(username: username, displayName: update.displayName, avatarURL: update.avatarURL),
            isOwn: false, viewerId: viewerId
        )
    }
}

/// An update card on its own page, with its replies and the box for yours.
struct ListUpdateScreen: View {
    @StateObject private var viewModel: ListUpdateViewModel
    private let viewerId: UUID

    init(postId: UUID, viewerId: UUID) {
        self.viewerId = viewerId
        _viewModel = StateObject(wrappedValue: ListUpdateViewModel(
            client: SupabaseListsClient(client: SupabaseConfig.client), postId: postId, viewerId: viewerId
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch viewModel.phase {
                case .loading:
                    LoadingSpinner().frame(maxWidth: .infinity, minHeight: 160)
                case .notFound:
                    EmptyState(title: "This update is no longer available", message: "It may have been removed, or it isn’t shared with you.")
                case .failed:
                    EmptyState(title: "Couldn’t load this update", message: "Try again in a moment.") {
                        Button("Try again") { Task { await viewModel.load() } }.buttonStyle(.quiet)
                    }
                case .loaded:
                    if let update = viewModel.update {
                        ListUpdateCardView(update: update, players: viewModel.players, viewerId: viewerId, full: true)
                        replies
                    }
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await viewModel.load() }
        .screenBackground()
        .navigationTitle("Update")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    @ViewBuilder private var replies: some View {
        VStack(alignment: .leading, spacing: 12) {
            let count = viewModel.thread.replies.count
            Text(count == 0 ? "Replies" : "\(count) \(count == 1 ? "reply" : "replies")").monoLabel(11, weight: .bold, tracking: 0.14)
            if viewModel.thread.takeId != nil { replyBox }
            if let error = viewModel.error { ErrorBanner(message: error) }
            if viewModel.thread.replies.isEmpty {
                Text("No replies yet.").font(.sans(14)).foregroundStyle(Theme.fgMuted)
            } else {
                ForEach(viewModel.thread.replies) { reply in
                    HStack(alignment: .top, spacing: 10) {
                        Avatar(name: reply.authorName, url: reply.avatarURL, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(reply.isViewer ? "You" : reply.authorName).font(.sans(14, weight: .bold)).foregroundStyle(Theme.fg)
                                Text(reply.createdAt, style: .relative).font(.mono(10)).foregroundStyle(Theme.fgMuted)
                            }
                            Text(reply.body).font(.sans(15)).foregroundStyle(Theme.fg)
                        }
                    }
                }
            }
        }
    }

    private var replyBox: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Post your reply", text: $viewModel.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.vertical, 10)
                .fieldStyle()
            Button(viewModel.isSending ? "Sending…" : "Reply") { Task { await viewModel.sendReply() } }
                .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                .disabled(!viewModel.canReply)
        }
    }
}
