import SwiftUI

/// Another player's profile, opened from the friends list, a search result or
/// a request. Four states, all decided by the server: open (public, or a
/// private one that is yours to see), private and closed (header and a note,
/// with the add-friend button), and not found, which is the same neutral
/// screen for a missing, blocked or unknown player.
struct OtherProfileView: View {
    @StateObject private var viewModel: OtherProfileViewModel
    /// Asks before an action that is awkward to take back.
    @State private var confirming: RelationshipAction?
    @State private var tab: ProfileTab = .stats
    private let username: String

    init(
        username: String,
        client: FriendsClient = SupabaseFriendsClient(client: SupabaseConfig.client)
    ) {
        self.username = username
        _viewModel = StateObject(wrappedValue: OtherProfileViewModel(client: client, username: username))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("@\(viewModel.username)")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .confirmationDialog(
            confirming == .block ? "Block this player?" : "Remove this friend?",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible
        ) {
            if let action = confirming {
                Button(action == .block ? "Block" : "Remove", role: .destructive) {
                    Task { await viewModel.perform(action) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirming == .block
                ? "They won’t be able to find you or see your profile, and any friendship ends."
                : "You’ll stop seeing each other’s friends rankings.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            LoadingSpinner().frame(maxWidth: .infinity, minHeight: 160)
        case .notFound:
            EmptyState(title: "Player not found", message: OtherProfileViewModel.notFoundMessage)
        case .failed:
            EmptyState(title: "Couldn’t load this profile", message: "Try again in a moment.") {
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.quiet)
            }
        case .loaded:
            if let player = viewModel.player {
                header(player)
                actions
                if let notice = viewModel.notice {
                    Text(notice).font(.sans(14)).foregroundStyle(Theme.fgMuted)
                }
                if viewModel.isClosed {
                    EmptyState(title: "Private profile", message: OtherProfileViewModel.privateNote)
                } else {
                    ProfileTabBar(selection: $tab, tabs: [.stats, .lists])
                        .padding(.top, -8)
                    if tab == .lists, let viewerId = SupabaseConfig.client.auth.currentSession?.user.id {
                        ProfileListsTab(username: username, viewerId: viewerId)
                    } else {
                        StatsCard(
                            statsView: $viewModel.statsView,
                            statsRange: $viewModel.statsRange,
                            knower: viewModel.selectedKnowerHighlight,
                            status: viewModel.knowerStatus,
                            statusDetail: viewModel.knowerStatusDetail,
                            gamer: viewModel.gamerHighlight
                        ) { EmptyView() }
                    }
                }
            }
        }
    }

    private func header(_ player: PlayerIdentity) -> some View {
        HStack(spacing: 16) {
            Avatar(name: player.displayName, url: player.avatarURL)
            VStack(alignment: .leading, spacing: 0) {
                Text(player.displayName)
                    .slabTitle(38)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, -6)
                    .accessibilityAddTraits(.isHeader)
                Text(player.handle)
                    .font(.sans(15))
                    .foregroundStyle(Theme.fgMuted)
                if let joined = viewModel.joinedLabel {
                    Text(joined).monoLabel(10, tracking: 0.12)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { LineRule() }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if let primary = viewModel.primaryAction {
                Button(primary.title) { Task { await viewModel.perform(primary.action) } }
                    .buttonStyle(.solid)
            }
            ForEach(viewModel.secondaryActions, id: \.title) { secondary in
                Button(secondary.title) {
                    switch secondary.action {
                    case .block, .remove: confirming = secondary.action
                    default: Task { await viewModel.perform(secondary.action) }
                    }
                }
                .buttonStyle(.ghost)
            }
        }
        .disabled(viewModel.isActing)
    }
}
