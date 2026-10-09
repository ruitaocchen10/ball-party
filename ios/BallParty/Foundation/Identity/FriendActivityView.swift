import SwiftUI

/// The Friends tab on Home: what friends have been up to over the last 30
/// days. A pick shows that a friend answered a prompt, never what they picked.
struct FriendActivityFeedView: View {
    @ObservedObject var viewModel: FriendActivityViewModel
    let client: FriendsClient

    var body: some View {
        ScrollView {
            content
                .padding(16)
        }
        .refreshable { await viewModel.load() }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        case .failed:
            EmptyState(title: "Couldn’t load activity", message: "Try again in a moment.") {
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.quiet)
            }
        case .loaded:
            if viewModel.events.isEmpty {
                if viewModel.hasFriends {
                    EmptyState(
                        title: "No recent activity",
                        message: "Picks and finished games from your friends in the last 30 days show up here."
                    )
                } else {
                    EmptyState(
                        title: "No friends yet",
                        message: "Add friends from your profile to see their picks and results here."
                    )
                }
            } else {
                feed
            }
        }
    }

    private var feed: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.events) { event in
                VStack(spacing: 0) {
                    LineRule()
                    NavigationLink {
                        OtherProfileView(username: event.actor.username, client: client)
                    } label: {
                        ActivityRow(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
            if viewModel.hasMore {
                VStack(spacing: 8) {
                    LineRule()
                    if viewModel.loadMoreFailed {
                        Text("Couldn’t load more.").font(.sans(14)).foregroundStyle(Theme.hiddenText)
                    }
                    Button(viewModel.isLoadingMore ? "Loading…" : "Load more") {
                        Task { await viewModel.loadMore() }
                    }
                    .buttonStyle(.ghost)
                    .disabled(viewModel.isLoadingMore)
                    .padding(.top, 8)
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let event: FriendActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(name: event.actor.displayName, url: event.actor.avatarURL, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.actor.displayName)
                    .font(.sans(16, weight: .semibold))
                    .foregroundStyle(Theme.fg)
                    .lineLimit(1)
                Text(event.summary)
                    .font(.sans(15))
                    .foregroundStyle(Theme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.occurredAt.formatted(.relative(presentation: .named)))
                    .monoLabel(9, tracking: 0.1)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
