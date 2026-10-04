import SwiftUI

/// Entry point for Huddle: owns the view model and shows the feed.
struct HuddleScreen: View {
    @StateObject private var viewModel: HuddleViewModel

    init(viewerId: UUID) {
        _viewModel = StateObject(
            wrappedValue: HuddleViewModel(
                client: SupabaseHuddleClient(client: SupabaseConfig.client),
                viewerId: viewerId
            )
        )
    }

    var body: some View {
        HuddleFeedView(viewModel: viewModel)
    }
}

struct HuddleFeedView: View {
    @ObservedObject var viewModel: HuddleViewModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                ProgressView {
                    Text("Loading the feed…").monoLabel(11, tracking: 0.15)
                }
            case .failed(let message):
                ScrollView {
                    EmptyState(title: "Couldn't load Huddle", message: message) {
                        Button("Try again") { Task { await viewModel.load() } }
                            .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                    }
                    .padding(16)
                }
            case .loaded:
                feed
            }
        }
        .screenBackground()
        .navigationTitle("Huddle")
        .navigationBarTitleDisplayMode(.inline)
        // Also runs on coming back from a prompt, which is when the feed is
        // most likely to be stale (a pick was just locked in).
        .task { await viewModel.load() }
        // Huddle has no live channel, so returning to the app is the moment to
        // look again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel.load() } }
        }
    }

    @ViewBuilder
    private var feed: some View {
        if viewModel.posts.isEmpty {
            ScrollView {
                EmptyState(
                    title: "No prompts yet",
                    message: "New prompts show up here. Pull down to check again."
                )
                .padding(16)
            }
            .refreshable { await viewModel.load() }
        } else {
            ScrollView {
                LazyVStack(spacing: 20) {
                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                    }
                    ForEach(viewModel.posts) { post in
                        NavigationLink {
                            PromptDetailView(viewModel: viewModel, postId: post.id)
                        } label: {
                            PostCard(post: post, actionLabel: viewModel.callToAction(for: post.id).label)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .refreshable { await viewModel.load() }
        }
    }
}

/// A prompt as the feed shows it: enough of the matchup to invite a response,
/// with the picks and the takes behind the tap.
///
/// Drawn the way the web's feed card is — a dark card with the game art on it
/// and a cream call to action — because the cream panel is for what a player
/// has earned, not for what is on offer. `aggregate` is nil until the viewer
/// has answered, so the crowd's headcount stays off the card until then.
private struct PostCard: View {
    let post: PromptPost
    let actionLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The badge gets its own row, above the title, instead of
            // sharing one with it — a long title otherwise loses its width
            // to whatever the badge needs that day.
            VStack(alignment: .leading, spacing: 8) {
                PostCardStatusBadge(post: post)
                Text(post.promptText)
                    .slabTitle(28)
                    .lineSpacing(0)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if !post.caption.isEmpty {
                Text(post.caption)
                    .font(.sans(14))
                    .foregroundStyle(Theme.fgMuted)
                    .padding(.horizontal, 16)
                    .padding(.top, 0)
            }
            if post.status == .void, let reason = post.voidReason {
                Text(reason)
                    .monoLabel(10, tracking: 0.08)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surface)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }

            if post.isUnsupported {
                UpdateAppNotice(compact: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            } else {
                teaser
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            if post.aggregate != nil {
                Text("\(post.responseCount) \(post.responseCount == 1 ? "person has" : "people have") answered")
                    .monoLabel(10, tracking: 0.1)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            Text(actionLabel)
                .font(.slab(18, relativeTo: .body))
                .tracking(0.72)
                .textCase(.uppercase)
                .foregroundStyle(Theme.panelFg)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.panel)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 10)
        .opacity(post.status == .void ? 0.45 : 1)
    }

    /// One game is a poster, a slate of them a pager of posters, Power Rankings
    /// its cover art, and anything else — players, a ranking — the faces of what
    /// is on offer.
    @ViewBuilder
    private var teaser: some View {
        if post.isPowerRankings {
            PowerRankingsCover(teamCodes: post.coverTeamCodes)
        } else if post.isMatchupPost {
            if post.slots.count == 1, let matchup = post.slots[0].matchup {
                MatchupPoster(away: matchup.away, home: matchup.home, game: post.slots[0].game)
            } else {
                MatchupCarousel(slots: post.slots)
            }
        } else {
            OptionStrip(options: post.slots.flatMap(\.options))
        }
    }
}

/// The feed's top marker is about this reader first: a submitted ticket is
/// complete even after results arrive. Otherwise it makes the prompt's
/// terminal lifecycle immediately scannable without repeating the timestamp.
private struct PostCardStatusBadge: View {
    let post: PromptPost

    var body: some View {
        if post.viewerAnswered {
            Label("Complete", systemImage: "checkmark")
                .monoLabel(9, weight: .bold, tracking: 0.1, color: Theme.panel)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.gradeElite)
                .accessibilityLabel("Complete")
        } else if post.status == .resolved {
            Text("Resolved")
                .monoLabel(9, weight: .bold, tracking: 0.1, color: Theme.panel)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.panel.opacity(0.1))
                .overlay(Rectangle().strokeBorder(Theme.panel.opacity(0.5), lineWidth: 1))
        } else if !post.isTakingPicks(at: Date()) {
            Label("Locked", systemImage: "lock.fill")
                .monoLabel(9, weight: .bold, tracking: 0.1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.surface)
                .overlay(Rectangle().strokeBorder(Theme.fgMuted.opacity(0.5), lineWidth: 1))
        } else {
            PostStatusLabel(post: post)
                .monoLabel(10, tracking: 0.14)
                .multilineTextAlignment(.leading)
        }
    }
}
