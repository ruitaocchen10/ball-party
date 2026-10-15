import SwiftUI

/// Entry point for Home: one feed of prompts and friends' game moments,
/// interleaved by time, with pills (All, Prompts, Friends) to narrow it. The app
/// is only reachable with a real account, so the pills are always shown.
struct HuddleScreen: View {
    @StateObject private var viewModel: HuddleViewModel
    @StateObject private var activity: FriendActivityViewModel
    @State private var filter: HomeFilter = .all
    private let friendsClient: FriendsClient

    init(viewerId: UUID) {
        _viewModel = StateObject(
            wrappedValue: HuddleViewModel(
                client: SupabaseHuddleClient(client: SupabaseConfig.client),
                viewerId: viewerId
            )
        )
        let friends = SupabaseFriendsClient(client: SupabaseConfig.client)
        friendsClient = friends
        _activity = StateObject(
            wrappedValue: FriendActivityViewModel(
                client: SupabaseFriendActivityClient(client: SupabaseConfig.client),
                friendsClient: friends
            )
        )
    }

    var body: some View {
        HuddleFeedView(viewModel: viewModel, activity: activity, filter: $filter, client: friendsClient)
            .screenBackground()
            .screenHeader("Home") { RootBell() }
    }
}

struct HuddleFeedView: View {
    @ObservedObject var viewModel: HuddleViewModel
    @ObservedObject var activity: FriendActivityViewModel
    @Binding var filter: HomeFilter
    let client: FriendsClient
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PillChoice(selection: $filter, options: HomeFilter.allCases, title: \.title, accessibilityName: "Filter the feed")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                switch viewModel.phase {
                case .loading:
                    LoadingState(label: "Loading the feed…")
                    .frame(maxWidth: .infinity, minHeight: 160)
                case .failed(let message):
                    EmptyState(title: "Couldn't load Huddle", message: message) {
                        Button("Try again") { Task { await reload() } }
                            .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                    }
                    .padding(16)
                case .loaded:
                    feed
                }
            }
        }
        .refreshable { await reload() }
        .screenBackground()
        // Also runs on coming back from a prompt, which is when the feed is
        // most likely to be stale (a pick was just locked in).
        .task { await reload() }
        // Huddle has no live channel, so returning to the app is the moment to
        // look again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reload() } }
        }
    }

    /// The prompts first, then who answered them and the game moments, which don't depend on each other.
    private func reload() async {
        await viewModel.load()
        async let moments: Void = activity.load()
        async let answered: Void = activity.loadAnswerers(postIds: viewModel.posts.map(\.id))
        _ = await (moments, answered)
    }

    private var entries: [HomeFeedEntry] {
        HomeFeed.build(
            posts: viewModel.posts,
            answerers: activity.answerers,
            moments: activity.events,
            filter: filter,
            hasMoreMoments: activity.hasMore
        )
    }

    @ViewBuilder
    private var feed: some View {
        let entries = entries
        if entries.isEmpty {
            emptyState.padding(16)
        } else {
            LazyVStack(spacing: 20) {
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
                ForEach(entries) { entry in
                    switch entry {
                    case .prompt(let post, let answerers):
                        NavigationLink {
                            PromptDetailView(viewModel: viewModel, postId: post.id)
                        } label: {
                            PostCard(post: post, actionLabel: viewModel.callToAction(for: post.id).label, friendsAnswered: answerers)
                        }
                        .buttonStyle(.plain)
                    case .moment(let item):
                        GameMomentCard(item: item, client: client)
                    }
                }
                if filter != .prompts && activity.hasMore {
                    VStack(spacing: 8) {
                        if activity.loadMoreFailed {
                            Text("Couldn’t load more.").font(.sans(14)).foregroundStyle(Theme.hiddenText)
                        }
                        Button(activity.isLoadingMore ? "Loading…" : "Load more") {
                            Task { await activity.loadMore() }
                        }
                        .buttonStyle(.ghost)
                        .disabled(activity.isLoadingMore)
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if filter == .friends {
            if activity.hasFriends {
                EmptyState(
                    title: "No recent activity",
                    message: "Prompts your friends answer, their wins and new high scores from the last 30 days show up here."
                )
            } else {
                EmptyState(
                    title: "No friends yet",
                    message: "Add friends from your profile to see which prompts they answer and their wins here."
                )
            }
        } else {
            EmptyState(
                title: "No prompts yet",
                message: "New prompts show up here. Pull down to check again."
            )
        }
    }
}

/// A prompt as the feed shows it: its art across the top with the timer (or the
/// state) in a chip on the art's corner, then the title and subtitle, who has
/// answered, and the button to make a pick. The picks and the takes are behind
/// the tap.
///
/// Drawn the way the web's feed card is — a dark card with the art bleeding off
/// its top edge and a cream call to action — because the cream panel is for what
/// a player has earned, not for what is on offer. The art is short on purpose, so
/// a phone fits a couple of these at once instead of one and a half. `aggregate`
/// is nil until the viewer has answered, so the crowd's headcount stays off the
/// card until then.
private struct PostCard: View {
    let post: PromptPost
    let actionLabel: String
    /// Friends who answered, as a line of avatars and names; never their picks.
    var friendsAnswered: [FriendAnswerer] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if post.isUnsupported {
                UpdateAppNotice(compact: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else {
                teaser
                    .overlay(alignment: .topTrailing) { PostCardStatusBadge(post: post).padding(8) }
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(post.promptText)
                    .slabTitle(24)
                    .lineSpacing(0)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !post.caption.isEmpty {
                    Text(post.caption)
                        .font(.sans(13))
                        .foregroundStyle(Theme.fgMuted)
                        .padding(.top, 2)
                }
                if post.status == .void, let reason = post.voidReason {
                    Text(reason)
                        .monoLabel(10, tracking: 0.08)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
                        .padding(.top, 12)
                }

                if post.isBoldPredictions {
                    let count = post.predictionCount ?? 0
                    Text("\(count) \(count == 1 ? "prediction" : "predictions") made")
                        .monoLabel(10, tracking: 0.1)
                        .padding(.top, 10)
                } else if post.aggregate != nil && friendsAnswered.isEmpty {
                    Text("\(post.responseCount) \(post.responseCount == 1 ? "person has" : "people have") answered")
                        .monoLabel(10, tracking: 0.1)
                        .padding(.top, 10)
                }

                if let line = FriendAnswerer.line(friendsAnswered, total: post.aggregate == nil ? nil : post.isBoldPredictions ? post.predictorCount : post.responseCount) {
                    HStack(spacing: 8) {
                        HStack(spacing: -8) {
                            ForEach(friendsAnswered.prefix(3)) { answerer in
                                Avatar(name: answerer.identity.displayName, url: answerer.identity.avatarURL, size: 24)
                                    .overlay(Circle().strokeBorder(Theme.surfaceRaised, lineWidth: 2))
                            }
                        }
                        .accessibilityHidden(true)
                        Text(line)
                            .font(.sans(13))
                            .foregroundStyle(Theme.fgMuted)
                            .lineLimit(1)
                    }
                    .padding(.top, 10)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Text(actionLabel)
                .font(.slab(18, relativeTo: .body))
                .tracking(0.72)
                .textCase(.uppercase)
                .foregroundStyle(Theme.surface)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.fg, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 10)
        .opacity(post.status == .void ? 0.45 : 1)
    }

    /// One game is a banner, a slate of them one banner of small pairs, Power
    /// Rankings its cover art, and anything else — players, a ranking — the
    /// faces of what is on offer.
    @ViewBuilder
    private var teaser: some View {
        if post.isPowerRankings {
            PowerRankingsCover(teamCodes: post.coverTeamCodes)
        } else if post.isWeeklyAwards {
            WeeklyAwardsCover()
        } else if post.isBoldPredictions {
            BoldPredictionsCover()
        } else if post.isMatchupPost {
            if post.slots.count == 1, let matchup = post.slots[0].matchup {
                MatchupBanner(away: matchup.away, home: matchup.home, game: post.slots[0].game)
            } else {
                SlateBanner(slots: post.slots)
            }
        } else {
            OptionBanner(options: post.slots.flatMap(\.options), pickCount: post.slots.count)
        }
    }
}

/// The chip in the art's top-right corner. About this reader first: a submitted
/// ticket is Completed even after results arrive. Otherwise it counts down to the
/// deadline while the prompt is open, and says what became of it once it isn't.
private struct PostCardStatusBadge: View {
    let post: PromptPost

    var body: some View {
        if post.viewerAnswered {
            ArtChip("Completed", tone: .success, systemImage: "checkmark")
        } else if post.status == .void {
            ArtChip("Void")
        } else if post.status == .resolved {
            ArtChip("Resolved")
        } else if !post.isTakingPicks(at: Date()) {
            ArtChip("Locked", systemImage: "lock.fill")
        } else {
            ArtChip("Closes \(PostStatusLabel.countdown(to: post.lockAt, now: Date()))")
        }
    }
}
