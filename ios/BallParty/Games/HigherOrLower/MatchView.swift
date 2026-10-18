import SwiftUI

/// Entry point for one live match: owns the view model and shows the board
/// until it ends, then the final table.
///
/// It dismisses itself once a post-game choice exists. Where that leads is the
/// room's business, not the game's: the room is already following its own run,
/// so a replay appears there as a new match to carry everybody into, and
/// "back to the lobby" is simply this screen going away.
struct MatchScreen: View {
    @StateObject private var viewModel: MatchViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// `roomCode` and `isHost` come from the room that pushed this screen —
    /// a game may not read the lobby itself (`architecture.md`), the same
    /// reason the web's match page passes them in as props.
    init(matchId: UUID, viewerId: UUID, roomCode: String?, isHost: Bool) {
        _viewModel = StateObject(
            wrappedValue: MatchViewModel(
                client: SupabaseHigherOrLowerClient(client: SupabaseConfig.client),
                matchId: matchId,
                viewerId: viewerId,
                roomCode: roomCode,
                isHost: isHost
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.board == nil {
                LoadingState(label: "Dealing…")
            } else if viewModel.isComplete {
                MatchFinalView(viewModel: viewModel)
            } else {
                MatchPlayView(viewModel: viewModel)
            }
        }
        .screenBackground()
        .winnerMoment(viewModel.winnerMoment, ready: viewModel.board != nil, complete: viewModel.isComplete)
        .matchStartCountdown(game: .higherOrLower, matchId: viewModel.matchId)
        .navigationTitle("Higher or Lower")
        .navigationBarTitleDisplayMode(.inline)
        // A live match is not somewhere to tab away from by accident.
        .toolbar(.hidden, for: .tabBar)
        .task { await viewModel.load() }
        // Coming back from the background is when a screen is most likely to
        // be wrong: the countdown may barely have run, and the match may have
        // moved on several questions.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.appReturnedToForeground() }
        }
        .onChange(of: viewModel.postGameAction) { _, action in
            if action != nil { dismiss() }
        }
        .onDisappear { viewModel.stopObserving() }
    }
}

// MARK: - Playing

private struct MatchPlayView: View {
    @ObservedObject var viewModel: MatchViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if viewModel.isPaused {
                    Label("The host paused the game.", systemImage: "pause.circle.fill")
                        .monoLabel(11, weight: .semibold, tracking: 0.13, color: Theme.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .well()
                }

                if let phase = viewModel.phase {
                    CountdownView(clock: viewModel.clock, phase: phase)
                }

                if let anchor = viewModel.anchor, let challenger = viewModel.challenger {
                    LadderCardsView(anchor: anchor, challenger: challenger)
                } else {
                    Text("Waiting for the next card…")
                        .monoLabel(11, tracking: 0.13)
                        .padding(.vertical, 40)
                }

                callArea
                StandingsRail(viewModel: viewModel)

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(16)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(viewModel.questionLabel).monoLabel(11, weight: .semibold, tracking: 0.15)
            Spacer()
            Text(viewModel.formatLabel).monoLabel(11, tracking: 0.13)
        }
    }

    @ViewBuilder
    private var callArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.call(.higher) }
                } label: {
                    Label("Higher", systemImage: "arrow.up")
                }
                .buttonStyle(.solid)
                Button {
                    Task { await viewModel.call(.lower) }
                } label: {
                    Label("Lower", systemImage: "arrow.down")
                }
                .buttonStyle(.ghost)
            }
            .disabled(!viewModel.canCall)

            // A row with no direction is the miss the server wrote when the
            // deadline passed. It scores exactly as a wrong call — that is the
            // point of writing it — so this line is the only place the
            // difference shows.
            if let call = viewModel.myCall {
                Text(call.timedOut ? "You ran out of time." : "You called \(call.direction?.rawValue ?? "").")
                    .monoLabel(11, tracking: 0.13)
            }
        }
    }
}

/// Who is at the table, where they stand, and what each of them is doing.
private struct StandingsRail: View {
    @ObservedObject var viewModel: MatchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Standings").monoLabel(10, weight: .bold, tracking: 0.15)
                Spacer()
                Text("Correct · best").monoLabel(9, tracking: 0.08)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            ForEach(viewModel.standings) { standing in
                let player = standing.player
                LineRule()
                HStack(spacing: 10) {
                    Text("\(standing.tied ? "T-" : "#")\(standing.rank)")
                        .font(.mono(12, weight: .bold))
                        .foregroundStyle(standing.rank == 1 ? Theme.hiddenText : Theme.fgMuted)
                        .frame(width: 34, alignment: .leading)
                    Avatar(
                        name: player.name,
                        url: player.avatarURL,
                        size: 28,
                        isMine: player.userId == viewModel.viewerId
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(player.name).slabTitle(18).lineLimit(1)
                            if player.userId == viewModel.viewerId {
                                Text("You").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText)
                            }
                        }
                        Text(viewModel.status(of: player)).monoLabel(10, tracking: 0.07)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(player.correctCount) correct")
                            .monoLabel(10, weight: .bold, tracking: 0.05, color: Theme.fg)
                            .monospacedDigit()
                        Text("\(player.bestStreak) best").monoLabel(10, tracking: 0.05)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(standing.rank == 1 ? Theme.fg.opacity(0.05) : .clear)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity)
        .well()
    }
}

// MARK: - The ending

private struct MatchFinalView: View {
    @ObservedObject var viewModel: MatchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Final").eyebrow()

                ForEach(viewModel.finalStandings) { row in
                    // The winner is the thing that matters, so the winner is a panel.
                    if row.rank == 1 {
                        PanelCard {
                            finalRow(row, onPanel: true).padding(14)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        finalRow(row, onPanel: false)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .well()
                            .accessibilityElement(children: .combine)
                    }
                }

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }

                postGameControls
            }
            .padding(16)
        }
    }

    private func finalRow(_ row: MatchViewModel.FinalStanding, onPanel: Bool) -> some View {
        HStack(spacing: 12) {
            Text("#\(row.rank)")
                .font(.mono(16, weight: .bold))
                .foregroundStyle(row.rank == 1 ? (onPanel ? Theme.hiddenInk : Theme.hiddenText) : Theme.fgMuted)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .slabTitle(24, color: onPanel ? Theme.panelFg : Theme.fg)
                        .lineLimit(1)
                    if row.isViewer {
                        Text("You")
                            .monoLabel(9, weight: .bold, tracking: 0.08, color: onPanel ? Theme.hiddenInk : Theme.hiddenText)
                    }
                }
                Text(row.statLine)
                    .monoLabel(11, tracking: 0.08, color: onPanel ? Theme.panelMuted : Theme.fgMuted)
            }
            Spacer()
        }
    }

    /// The host advances the whole room; everybody else can keep reading the
    /// result until they do.
    @ViewBuilder
    private var postGameControls: some View {
        if viewModel.roomCode == nil {
            EmptyView()
        } else if viewModel.isHost {
            VStack(spacing: 8) {
                Button {
                    Task { await viewModel.choosePostGame(.replay) }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isBusy { LoadingSpinner(size: 16) }
                        Text("Play again")
                    }
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canChoosePostGame)

                Button("Back to the room") {
                    Task { await viewModel.choosePostGame(.lobby) }
                }
                .buttonStyle(.ghost)
                .disabled(!viewModel.canChoosePostGame)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                Text("Waiting for the host to choose what's next.")
                    .monoLabel(11, tracking: 0.13)
                Button("Back to the room") { dismiss() }
                    .buttonStyle(.ghost)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
