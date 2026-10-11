import SwiftUI

/// The Friends tab on Home: what friends have been up to over the last 30
/// days, as a feed of cards. A friend's answer to a locked prompt is the same
/// take card the Huddle uses (their take, then their picks); a multiplayer win
/// or a new solo best is a lighter game card. An open prompt only shows that a
/// friend answered.
struct FriendActivityFeedView: View {
    @ObservedObject var viewModel: FriendActivityViewModel
    /// Where take cards get the prompt (slots and options) their picks are drawn from.
    @ObservedObject var huddle: HuddleViewModel
    let client: FriendsClient

    var body: some View {
        ScrollView {
            content
                .padding(16)
        }
        .refreshable { await viewModel.load() }
        .task {
            await viewModel.load()
            if huddle.posts.isEmpty { await huddle.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            LoadingSpinner().frame(maxWidth: .infinity, minHeight: 160)
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
                        message: "Answers, wins and new high scores from your friends in the last 30 days show up here."
                    )
                } else {
                    EmptyState(
                        title: "No friends yet",
                        message: "Add friends from your profile to see their answers and wins here."
                    )
                }
            } else {
                feed
            }
        }
    }

    private var feed: some View {
        VStack(spacing: 16) {
            ForEach(FriendActivityItem.grouped(viewModel.events)) { item in
                card(for: item)
            }
            if viewModel.hasMore {
                VStack(spacing: 8) {
                    if viewModel.loadMoreFailed {
                        Text("Couldn’t load more.").font(.sans(14)).foregroundStyle(Theme.hiddenText)
                    }
                    Button(viewModel.isLoadingMore ? "Loading…" : "Load more") {
                        Task { await viewModel.loadMore() }
                    }
                    .buttonStyle(.ghost)
                    .disabled(viewModel.isLoadingMore)
                }
            }
        }
    }

    @ViewBuilder
    private func card(for item: FriendActivityItem) -> some View {
        let event = item.event
        switch event.kind {
        case .take(let take):
            FriendTakeCard(event: event, take: take, post: huddle.post(take.postId), huddle: huddle)
        case .pickMade:
            OpenPickRow(event: event)
        case .win, .highScore:
            GameMomentCard(item: item, client: client)
        }
    }
}

/// A friend's answer to a locked prompt: the Huddle's take card with the prompt as a
/// quoted strip inside it, picks folded behind "View take". Its reply row opens the
/// take's thread (or the prompt, when the friend posted no take). With the prompt not in the Huddle feed it shows the take alone.
private struct FriendTakeCard: View {
    let event: FriendActivityEvent
    let take: FriendTake
    let post: PromptPost?
    @ObservedObject var huddle: HuddleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let post {
                // The reply row opens the thread; "View take" folds the picks. A card-wide link
                // would fight that button for the tap, as in the prompt screen.
                TakeCardView(
                    post: post,
                    comment: comment(in: post),
                    showsReplyCount: true,
                    collapsesPicks: true,
                    threadDestination: {
                        if let commentId = take.commentId, post.comments.contains(where: { $0.id == commentId }) {
                            return AnyView(TakeThreadView(viewModel: huddle, postId: post.id, takeId: commentId))
                        }
                        return AnyView(PromptDetailView(viewModel: huddle, postId: post.id))
                    },
                    contextTitle: take.caption?.trimmingCharacters(in: .whitespaces).nonEmpty ?? "a prompt",
                    contextDestination: { AnyView(PromptDetailView(viewModel: huddle, postId: post.id)) }
                )
            } else {
                Text(take.body ?? event.summary)
                    .font(.sans(16))
                    .foregroundStyle(Theme.fg)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .well()
            }
        }
    }

    private func realComment(in post: PromptPost) -> PromptComment? {
        take.commentId.flatMap { id in post.comments.first { $0.id == id } }
    }

    /// The friend's take with the answer from the feed (the Huddle copy only
    /// carries it once that post has been re-read since the lock).
    private func comment(in post: PromptPost) -> PromptComment {
        let real = realComment(in: post)
        return PromptComment(
            id: take.commentId ?? event.actor.profileId,
            author: event.actor.displayName,
            authorAvatarURL: event.actor.avatarURL,
            authorUsername: event.actor.username,
            body: take.body ?? "",
            createdAt: event.occurredAt,
            isViewer: false,
            postedWithPick: true,
            response: take.response.isEmpty ? nil : take.response,
            replies: real?.replies ?? []
        )
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// A friend who answered a prompt that hasn't locked: the fact, never the answer.
private struct OpenPickRow: View {
    let event: FriendActivityEvent

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Avatar(name: event.actor.displayName, url: event.actor.avatarURL, size: 28)
            (Text(event.actor.displayName).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                + Text(" " + event.summary).font(.sans(15)).foregroundStyle(Theme.fgMuted))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(event.occurredAt.formatted(.relative(presentation: .named)))
                .monoLabel(9, tracking: 0.1)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A multiplayer win or a new solo best, lighter than a take card so answers
/// stay the main thing. A high score leads with the number and where it puts
/// the friend among the viewer's circle and opens that game's board; a win
/// names who it was over and opens the friend's profile. Several wins on one
/// day arrive folded into one card.
private struct GameMomentCard: View {
    let item: FriendActivityItem
    let client: FriendsClient

    private var event: FriendActivityEvent { item.event }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                OtherProfileView(username: event.actor.username, client: client)
            } label: {
                HStack(spacing: 8) {
                    Avatar(name: event.actor.displayName, url: event.actor.avatarURL, size: 28)
                    Text(event.actor.displayName).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                    Spacer()
                    Text(event.occurredAt, style: .relative).font(.mono(10)).foregroundStyle(Theme.fgMuted)
                }
            }
            .buttonStyle(.plain)

            switch event.kind {
            case .highScore(let game, let score, let mode, let rank, let count):
                highScore(game: game, score: score, mode: mode, rank: rank, count: count)
            case .win(_, let game, let score, let opponents, let you, let count):
                win(game: game, score: score, opponents: opponents, you: you, count: count)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func highScore(game: String, score: Double, mode: String?, rank: Int?, count: Int?) -> some View {
        let board: SoloBoard? = game == "higher_or_lower" ? .higherOrLower : game == "qb_season_builder" ? .qbSeasonBuilder : nil
        let qb = board == .qbSeasonBuilder
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("New best").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.surface)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.fg, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
                Text("in " + FriendActivityEvent.gameName(game) + (qb ? mode.map { " · \($0)" } ?? "" : ""))
                    .monoLabel(10, tracking: 0.08)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(board.map { BoardEntry.formatScore(score, board: $0) } ?? "—")
                    .font(.slab(44))
                    .foregroundStyle(Theme.fg)
                Text(qb ? "season score" : "in a row").monoLabel(10, tracking: 0.08)
            }
            if let rank, let count, count > 1 {
                Text("#\(rank) of \(count) among you and your friends")
                    .font(.sans(15))
                    .foregroundStyle(Theme.fgMuted)
            }
            if let board {
                NavigationLink {
                    SoloLeaderboardScreen(board: board, mode: mode == "hidden" ? .hidden : .visible)
                } label: {
                    Text("Beat it")
                        .monoLabel(10, weight: .semibold, tracking: 0.08)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func win(game: String, score: Double?, opponents: [String], you: Bool, count: Int) -> some View {
        let wins = [event] + item.more
        VStack(alignment: .leading, spacing: 6) {
            Text(wins.count == 1 ? "Win" : "\(wins.count) wins")
                .monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.surface)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.fg, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
            if wins.count == 1 {
                Text("Won \(FriendActivityEvent.gameName(game))")
                    .font(.sans(18, weight: .medium))
                    .foregroundStyle(Theme.fg)
                let beat = FriendActivityEvent.beatLine(opponents: opponents, you: you, count: count)
                let scoreText = score.map { "Score \(FriendActivityEvent.formatScore($0))" }
                if beat != nil || scoreText != nil {
                    Text([beat.map { "Beat \($0)" }, scoreText].compactMap { $0 }.joined(separator: " · "))
                        .font(.sans(15))
                        .foregroundStyle(Theme.fgMuted)
                }
            } else {
                let games = wins.compactMap { win -> String? in
                    if case .win(_, let game, _, _, _, _) = win.kind { return FriendActivityEvent.gameName(game) }
                    return nil
                }
                let distinct = Array(NSOrderedSet(array: games)).compactMap { $0 as? String }
                Text(distinct.count == 1 ? "Won \(wins.count) \(distinct[0]) games" : "Won \(wins.count) games: \(distinct.joined(separator: ", "))")
                    .font(.sans(18, weight: .medium))
                    .foregroundStyle(Theme.fg)
            }
        }
    }
}
