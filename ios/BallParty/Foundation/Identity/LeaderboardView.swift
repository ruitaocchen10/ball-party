import SwiftUI

/// The leaderboards, pushed from the Profile tab's stats card. Mirrors the
/// web's `/leaderboard`: a board picker (Ball Knower and multiplayer wins),
/// then for each the ranked list with the caller's own standing above it,
/// which is also highlighted in place when they are on the list. This view
/// hosts Ball Knower; the wins board is `GamerLeaderboardView`. The solo games'
/// boards live with the games (`SoloLeaderboardScreen`).
struct LeaderboardView: View {
    @StateObject private var viewModel: LeaderboardViewModel
    /// Which board is showing. The Profile card opens on Ball Knower; the other
    /// boards are one tap away on the picker.
    @State private var board: LeaderboardBoard

    init(
        initialBoard: LeaderboardBoard = .ballKnower,
        initialWindow: LeaderboardWindow = .week,
        initialScope: LeaderboardScope = .all,
        client: LeaderboardClient = SupabaseLeaderboardClient(client: SupabaseConfig.client)
    ) {
        _board = State(initialValue: initialBoard)
        _viewModel = StateObject(
            wrappedValue: LeaderboardViewModel(client: client, window: initialWindow, scope: initialScope)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if board == .ballKnower {
                    ballKnower
                } else {
                    // A new identity per board, so switching boards starts the
                    // new one on its own defaults, as the web does.
                    GamerLeaderboardView(board: $board)
                        .id(board)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var ballKnower: some View {
        VStack(alignment: .leading, spacing: 16) {
            PageHeader(
                eyebrow: "Leaderboard",
                title: "Ball Knower",
                description: viewModel.scope.description
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

            content
        }
        // Restarts, and cancels the read in flight, whenever the window or scope changes.
        .task(id: viewModel.selection) { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
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
                board(standing)
            }
        }
    }

    private func board(_ standing: LeaderboardStanding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // The caller's own standing leads, in every state, so it never
            // depends on scrolling to find. Someone on the list is also
            // highlighted in place below.
            if standing.status == .ranked {
                PanelCard(edge: false) {
                    BoardYouRow(
                        rank: standing.rank,
                        detail: standing.copy(for: viewModel.scope).detail,
                        value: standing.totalPoints.formatted()
                    )
                }
            } else {
                let copy = standing.copy(for: viewModel.scope)
                BoardNotice(headline: copy.headline, detail: copy.detail)
            }

            HStack {
                Text(viewModel.window.caption).monoLabel(10, tracking: 0.12)
                Spacer(minLength: 8)
                Text("\(standing.rankedCount.formatted()) ranked").monoLabel(10, tracking: 0.12)
            }

            if viewModel.friendsBoardIsEmpty {
                EmptyState(
                    title: "No friends on the board yet",
                    message: "Friends appear here after \(standing.minPicks) scored picks in this window."
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
                        message: "Players appear after \(standing.minPicks) scored picks in this window."
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        BoardEntryRowView(row: BoardEntry(row))
                    }
                }
            }

            Text("You need at least \(standing.minPicks) scored picks in a window to be ranked.")
                .font(.sans(14))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }
}
