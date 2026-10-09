import SwiftUI

/// The multiplayer wins board, hosted by `LeaderboardView` beside Ball Knower.
/// Mirrors the web's `GamerLeaderboard`: a board picker, a scope picker, a
/// window picker, the caller's own standing and the ranked list.
struct GamerLeaderboardView: View {
    @StateObject private var viewModel: GamerLeaderboardViewModel
    @Binding private var board: LeaderboardBoard

    init(
        board: Binding<LeaderboardBoard>,
        client: GamerLeaderboardClient = SupabaseGamerLeaderboardClient(client: SupabaseConfig.client)
    ) {
        _board = board
        _viewModel = StateObject(wrappedValue: GamerLeaderboardViewModel(source: .wins, client: client))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                eyebrow: "Leaderboard",
                title: LeaderboardBoard.gamer.title,
                description: LeaderboardBoard.gamer.description(for: viewModel.scope)
            )

            SegmentedChoice(
                selection: $board,
                options: LeaderboardBoard.allCases,
                title: { $0.label },
                accessibilityName: "Leaderboard"
            )

            SegmentedChoice(
                selection: $viewModel.scope,
                options: LeaderboardScope.allCases,
                title: { $0.label },
                accessibilityName: "Board"
            )

            SegmentedChoice(
                selection: $viewModel.window,
                options: LeaderboardWindow.allCases,
                title: { $0.label },
                accessibilityName: "Time window"
            )

            BoardContent(viewModel: viewModel, caption: caption, rule: rule)
        }
        // Restarts, and cancels the read in flight, whenever the selection changes.
        .task(id: viewModel.selection) { await viewModel.load() }
    }

    private var caption: String {
        switch viewModel.window {
        case .week: "Wins in the last 7 days"
        case .month: "Wins in the last 30 days"
        case .year: "Wins in the last 365 days"
        case .lifetime: "Every multiplayer win"
        }
    }

    private var rule: String {
        "A win is a first-place finish in a multiplayer game with at least two players. A tie for first counts as a win for everyone tied."
    }
}

/// One solo game's all-time best-run board, pushed from the game's card on the
/// Games tab. Mirrors the web's `/solo/<game>/leaderboard`: a scope picker, QB
/// Season Builder's Visible / Hidden picker, the caller's own standing and the
/// ranked list. There are no windows: a personal best is all-time.
struct SoloLeaderboardScreen: View {
    let board: SoloBoard
    @StateObject private var viewModel: GamerLeaderboardViewModel

    init(
        board: SoloBoard,
        mode: QbRatingMode = .visible,
        client: GamerLeaderboardClient = SupabaseGamerLeaderboardClient(client: SupabaseConfig.client)
    ) {
        self.board = board
        _viewModel = StateObject(wrappedValue: GamerLeaderboardViewModel(source: .solo(board), client: client, mode: mode))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    eyebrow: "Solo",
                    title: board.title,
                    description: board.description(for: viewModel.scope)
                )

                SegmentedChoice(
                    selection: $viewModel.scope,
                    options: LeaderboardScope.allCases,
                    title: { $0.label },
                    accessibilityName: "Board"
                )

                if board == .qbSeasonBuilder {
                    SegmentedChoice(
                        selection: $viewModel.mode,
                        options: QbRatingMode.allCases,
                        title: { $0.label },
                        accessibilityName: "Season mode"
                    )
                }

                BoardContent(viewModel: viewModel, caption: board.caption, rule: board.rule)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        // Restarts, and cancels the read in flight, whenever the selection changes.
        .task(id: viewModel.selection) { await viewModel.load() }
    }
}

/// The standing, the ranked list and the empty and failed states: the part of
/// the wins board and the solo boards that is the same.
private struct BoardContent: View {
    @ObservedObject var viewModel: GamerLeaderboardViewModel
    let caption: String
    let rule: String

    var body: some View {
        switch viewModel.phase {
        case .loading where viewModel.standing == nil:
            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
        case .failed:
            EmptyState(title: "Couldn't load the leaderboard", message: "Try again in a moment.") {
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.quiet)
            }
        default:
            if let standing = viewModel.standing {
                content(standing)
            }
        }
    }

    private func content(_ standing: BoardStanding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if standing.isRanked {
                PanelCard(edge: false) {
                    BoardYouRow(rank: standing.rank, detail: standing.detail, value: standing.value)
                }
            } else {
                BoardNotice(headline: standing.headline, detail: standing.detail)
            }

            HStack {
                Text(caption).monoLabel(10, tracking: 0.12)
                Spacer(minLength: 8)
                Text("\(standing.rankedCount.formatted()) ranked").monoLabel(10, tracking: 0.12)
            }

            if viewModel.friendsBoardIsEmpty {
                EmptyState(
                    title: "No friends on the board yet",
                    message: standing.floor.map { "Friends appear here after \($0) in this window." }
                        ?? "Add friends to see how you stack up against them."
                ) {
                    NavigationLink {
                        FriendsView(initialSection: .add)
                    } label: {
                        Text("Find friends")
                    }
                    .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                }
            }

            if viewModel.rows.isEmpty {
                if viewModel.scope == .all {
                    EmptyState(
                        title: "No one is ranked yet",
                        message: standing.floor.map { "Players appear after \($0) in this window." }
                            ?? "Finish a solo run to put the first score on this board."
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        BoardEntryRowView(row: row)
                    }
                }
            }

            Text(rule)
                .font(.sans(14))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}

// MARK: - Shared pieces
//
// Used by the Ball Knower screen as well, so the three kinds of board look
// the same.

/// One row of any board. The caller's own row sits on a panel; any other row
/// opens a profile only when the server gave a username for it.
struct BoardEntryRowView: View {
    let row: BoardEntry

    var body: some View {
        if row.isMe {
            PanelCard(edge: false) { content(onPanel: true).padding(.horizontal, 14).padding(.vertical, 12) }
        } else {
            VStack(spacing: 0) {
                LineRule()
                if let username = row.profileUsername {
                    NavigationLink {
                        OtherProfileView(username: username)
                    } label: {
                        content(onPanel: false).padding(.horizontal, 14).padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    content(onPanel: false).padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
        }
    }

    private func content(onPanel: Bool) -> some View {
        let primary = onPanel ? Theme.panelFg : Theme.fg
        let secondary = onPanel ? Theme.panelMuted : Theme.fgMuted
        let top = row.rank <= 3
        return HStack(spacing: 12) {
            Text("\(row.rank)")
                .slabTitle(top ? 30 : 24, color: top || onPanel ? primary : secondary)
                .frame(minWidth: 36, alignment: .leading)
            Avatar(name: row.displayName, url: row.avatarURL, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.isMe ? "\(row.displayName) · You" : row.displayName)
                    .font(.sans(16, weight: row.isMe ? .semibold : .medium))
                    .foregroundStyle(primary)
                    .lineLimit(1)
                if let detail = row.detail {
                    Text(detail).monoLabel(9, tracking: 0.1, color: secondary)
                }
            }
            Spacer(minLength: 8)
            Text(row.value).slabTitle(26, color: primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.spoken)
    }
}

/// The caller's own row at the top of a board, when they are ranked.
struct BoardYouRow: View {
    let rank: Int?
    let detail: String
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(rank.map(String.init) ?? "")
                .slabTitle(24, color: Theme.panelFg)
                .frame(minWidth: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("You").font(.sans(16, weight: .semibold)).foregroundStyle(Theme.panelFg)
                Text(detail).monoLabel(9, tracking: 0.1, color: Theme.panelMuted)
            }
            Spacer(minLength: 8)
            if let value {
                Text(value).slabTitle(26, color: Theme.panelFg)
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

/// Shown instead of a "you" row when the caller is not on the board, and why.
struct BoardNotice: View {
    let headline: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headline).monoLabel(11, weight: .bold, tracking: 0.12, color: Theme.fg)
            Text(detail)
                .font(.sans(15))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
        .accessibilityElement(children: .combine)
    }
}
