import SwiftUI

/// The Ball Knower leaderboard, pushed from the Profile tab's stats card.
/// Mirrors the web's `/leaderboard`: a window picker, the ranked list, and the
/// caller's own standing above it, which is also highlighted in place when
/// they are on the list.
struct LeaderboardView: View {
    @StateObject private var viewModel: LeaderboardViewModel

    init(
        initialWindow: LeaderboardWindow = .week,
        client: LeaderboardClient = SupabaseLeaderboardClient(client: SupabaseConfig.client)
    ) {
        _viewModel = StateObject(wrappedValue: LeaderboardViewModel(client: client, window: initialWindow))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(
                    eyebrow: "Leaderboard",
                    title: "Ball Knower",
                    description: "Points from your resolved picks, ranked against everyone who plays the weekly prompts."
                )

                SegmentedChoice(
                    selection: $viewModel.window,
                    options: LeaderboardWindow.allCases,
                    title: { $0.label },
                    accessibilityName: "Time window"
                )

                content
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        // Restarts, and cancels the read in flight, whenever the window changes.
        .task(id: viewModel.window) { await viewModel.load() }
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
                PanelCard(edge: false) { standingRow(standing) }
            } else {
                StandingNotice(standing: standing)
            }

            HStack {
                Text(viewModel.window.caption).monoLabel(10, tracking: 0.12)
                Spacer(minLength: 8)
                Text("\(standing.rankedCount.formatted()) ranked").monoLabel(10, tracking: 0.12)
            }

            if viewModel.rows.isEmpty {
                EmptyState(
                    title: "No one is ranked yet",
                    message: "Players appear after \(standing.minPicks) scored picks in this window."
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        LeaderboardRowView(row: row)
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

    private func standingRow(_ standing: LeaderboardStanding) -> some View {
        HStack(spacing: 12) {
            Text(standing.rank.map(String.init) ?? "")
                .slabTitle(24, color: Theme.panelFg)
                .frame(minWidth: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("You").font(.sans(16, weight: .semibold)).foregroundStyle(Theme.panelFg)
                Text(standing.copy.detail).monoLabel(9, tracking: 0.1, color: Theme.panelMuted)
            }
            Spacer(minLength: 8)
            Text(standing.totalPoints.formatted()).slabTitle(26, color: Theme.panelFg)
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}

private struct LeaderboardRowView: View {
    let row: LeaderboardRow

    var body: some View {
        if row.isMe {
            PanelCard(edge: false) { content(onPanel: true).padding(.horizontal, 14).padding(.vertical, 12) }
        } else {
            VStack(spacing: 0) {
                LineRule()
                content(onPanel: false).padding(.horizontal, 14).padding(.vertical, 12)
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
                Text("\(row.scoredPicks) picks").monoLabel(9, tracking: 0.1, color: secondary)
            }
            Spacer(minLength: 8)
            Text(row.totalPoints.formatted()).slabTitle(26, color: primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Rank \(row.rank), \(row.displayName)\(row.isMe ? ", you" : ""), \(row.totalPoints) points, \(row.scoredPicks) picks")
    }
}

/// Shown instead of a "you" row when the caller is not on the board, and why.
private struct StandingNotice: View {
    let standing: LeaderboardStanding

    var body: some View {
        let copy = standing.copy
        VStack(alignment: .leading, spacing: 6) {
            Text(copy.headline).monoLabel(11, weight: .bold, tracking: 0.12, color: Theme.fg)
            Text(copy.detail)
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
