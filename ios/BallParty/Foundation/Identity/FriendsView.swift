import SwiftUI

/// The Friends screen, reached from the Profile menu: your friends, the
/// requests waiting on you (and yours waiting on others), and a way to add
/// someone, by exact username or by sharing your invite link. Mirrors the
/// web's friends page; every rule is the server's.
struct FriendsView: View {
    /// The screen's sections.
    enum Section: Hashable {
        case friends, requests, add
    }

    @StateObject private var viewModel: FriendsViewModel
    @State private var section: Section
    /// A removal or block waiting on the player's say-so.
    @State private var confirming: PendingConfirmation?
    @State private var resettingInvite = false

    private let client: FriendsClient

    init(
        initialSection: Section = .friends,
        client: FriendsClient = SupabaseFriendsClient(client: SupabaseConfig.client)
    ) {
        self.client = client
        _section = State(initialValue: initialSection)
        _viewModel = StateObject(wrappedValue: FriendsViewModel(client: client))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    eyebrow: "Friends",
                    title: "Your people",
                    description: "Add friends to see how you rank against them."
                )

                SegmentedChoice(
                    selection: $section,
                    options: [.friends, .requests, .add],
                    title: title(for:),
                    accessibilityName: "Friends section"
                )

                if let notice = viewModel.notice {
                    Text(notice).font(.sans(14)).foregroundStyle(Theme.fgMuted)
                }

                content
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .confirmationDialog(
            confirming?.title ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { pending in
            Button(pending.buttonTitle, role: .destructive) {
                Task { await viewModel.perform(pending.action, on: pending.player) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    private func title(for section: Section) -> String {
        switch section {
        case .friends: "Friends"
        case .requests: viewModel.incoming.isEmpty ? "Requests" : "Requests (\(viewModel.incoming.count))"
        case .add: "Add"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading where section == .friends || section == .requests:
            LoadingSpinner().frame(maxWidth: .infinity, minHeight: 160)
        case .failed where section == .friends || section == .requests:
            EmptyState(title: "Couldn’t load your friends", message: "Try again in a moment.") {
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.quiet)
            }
        default:
            switch section {
            case .friends: friendsList
            case .requests: requestsList
            case .add: addSection
            }
        }
    }

    // MARK: Friends

    @ViewBuilder
    private var friendsList: some View {
        if viewModel.friends.isEmpty {
            EmptyState(title: "No friends yet", message: "Find people by username, or share your invite link.") {
                Button("Add friends") { section = .add }
                    .buttonStyle(.quiet)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.friends) { friend in
                    VStack(spacing: 0) {
                        LineRule()
                        HStack(spacing: 8) {
                            NavigationLink {
                                OtherProfileView(username: friend.player.username, client: client)
                            } label: {
                                PersonRow(player: friend.player)
                            }
                            .buttonStyle(.plain)
                            Menu {
                                Button("Remove friend", systemImage: "person.badge.minus") {
                                    confirming = .remove(friend.player)
                                }
                                Button("Block", systemImage: "hand.raised", role: .destructive) {
                                    confirming = .block(friend.player)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(Theme.fgMuted)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("More options for \(friend.player.displayName)")
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }

        if !viewModel.blocked.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Blocked")
                ForEach(viewModel.blocked) { blocked in
                    VStack(spacing: 0) {
                        LineRule()
                        HStack(spacing: 8) {
                            PersonRow(player: blocked.player)
                            Button("Unblock") {
                                Task { await viewModel.perform(.unblock, on: blocked.player) }
                            }
                            .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: Requests

    @ViewBuilder
    private var requestsList: some View {
        if viewModel.requests.isEmpty {
            EmptyState(title: "No requests", message: "Requests you send and receive will show up here.")
        }
        if !viewModel.incoming.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Received")
                ForEach(viewModel.incoming) { request in
                    requestRow(request) {
                        Button("Accept") { Task { await viewModel.perform(.accept, on: request.player) } }
                            .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                        Button("Decline") { Task { await viewModel.perform(.decline, on: request.player) } }
                            .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                    }
                }
            }
        }
        if !viewModel.outgoing.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: "Sent")
                ForEach(viewModel.outgoing) { request in
                    requestRow(request) {
                        Button("Cancel") { Task { await viewModel.perform(.cancel, on: request.player) } }
                            .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                    }
                }
            }
            .padding(.top, 12)
        }
    }

    private func requestRow<Buttons: View>(
        _ request: FriendRequest, @ViewBuilder buttons: () -> Buttons
    ) -> some View {
        VStack(spacing: 0) {
            LineRule()
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink {
                    OtherProfileView(username: request.player.username, client: client)
                } label: {
                    PersonRow(player: request.player)
                }
                .buttonStyle(.plain)
                HStack(spacing: 8) { buttons() }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: Add

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "Find by username")
                HStack(spacing: 8) {
                    TextField("Start typing a username", text: $viewModel.query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await viewModel.search() } }
                        .onChange(of: viewModel.query) { viewModel.queryChanged() }
                        .fieldStyle()
                }
                searchResult
            }
            inviteLink
        }
    }

    @ViewBuilder
    private var searchResult: some View {
        switch viewModel.searchPhase {
        case .idle:
            EmptyView()
        case .searching:
            LoadingSpinner().frame(maxWidth: .infinity)
        case .invalid(let message):
            Text(message).font(.sans(14)).foregroundStyle(Theme.hiddenText)
        case .failed:
            Text(FriendsViewModel.genericFailure).font(.sans(14)).foregroundStyle(Theme.hiddenText)
        case .notFound:
            Text("No players found.")
                .font(.sans(14)).foregroundStyle(Theme.fgMuted)
        case .results(let rows):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { result in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink {
                            OtherProfileView(username: result.player.username, client: client)
                        } label: {
                            PersonRow(player: result.player)
                        }
                        .buttonStyle(.plain)
                        if let primary = RelationshipAction.primary(for: result.relationship) {
                            Button(primary.title) { Task { await viewModel.perform(primary.action, on: result.player) } }
                                .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                        } else if result.relationship == .friends {
                            Text("You’re already friends.").monoLabel(10, tracking: 0.12)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if result.id != rows.last?.id { Divider() }
                }
            }
            .well()
        }
    }

    private var inviteLink: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Invite link")
            Text("Anyone with this link can ask to be your friend. You still choose whether to accept.")
                .font(.sans(14))
                .foregroundStyle(Theme.fgMuted)
            if let url = viewModel.inviteURL {
                Text(url.absoluteString)
                    .font(.mono(12))
                    .foregroundStyle(Theme.fg)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .well()
                HStack(spacing: 8) {
                    ShareLink(item: url, message: Text("Add me on Ball Party.")) {
                        Text("Share link")
                    }
                    .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                    Button("Reset link") {
                        resettingInvite = true
                    }
                    .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                }
            } else {
                LoadingSpinner().frame(maxWidth: .infinity)
            }
        }
        .task { await viewModel.loadInviteCode() }
        .confirmationDialog(
            "Reset your invite link?", isPresented: Binding(
                get: { resettingInvite }, set: { resettingInvite = $0 }
            ), titleVisibility: .visible
        ) {
            Button("Reset link", role: .destructive) { Task { await viewModel.resetInviteCode() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Links you already shared will stop working.")
        }
    }
}

/// A removal or block waiting for confirmation.
private enum PendingConfirmation: Equatable, Identifiable {
    case remove(PlayerIdentity)
    case block(PlayerIdentity)

    var id: String {
        switch self {
        case .remove(let player): "remove-\(player.profileId)"
        case .block(let player): "block-\(player.profileId)"
        }
    }

    var action: RelationshipAction {
        switch self {
        case .remove: .remove
        case .block: .block
        }
    }

    var player: PlayerIdentity {
        switch self {
        case .remove(let player), .block(let player): player
        }
    }

    var title: String {
        switch self {
        case .remove(let player): "Remove \(player.displayName)?"
        case .block(let player): "Block \(player.displayName)?"
        }
    }

    var buttonTitle: String {
        switch self {
        case .remove: "Remove friend"
        case .block: "Block"
        }
    }

    var message: String {
        switch self {
        case .remove: "You’ll stop seeing each other’s friends rankings."
        case .block: "They won’t be able to find you or see your profile, and any friendship ends."
        }
    }
}

/// A player in a list: avatar, name and @username.
struct PersonRow: View {
    let player: PlayerIdentity

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: player.displayName, url: player.avatarURL, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName)
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Text(player.handle)
                    .font(.sans(14))
                    .foregroundStyle(Theme.fgMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
