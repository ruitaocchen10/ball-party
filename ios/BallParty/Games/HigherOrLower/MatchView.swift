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
                ProgressView("Dealing…")
            } else if viewModel.isComplete {
                MatchFinalView(viewModel: viewModel)
            } else {
                MatchPlayView(viewModel: viewModel)
            }
        }
        .navigationTitle("Higher or Lower")
        .navigationBarTitleDisplayMode(.inline)
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
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }

                if let phase = viewModel.phase {
                    CountdownView(clock: viewModel.clock, phase: phase)
                }

                if let anchor = viewModel.anchor, let challenger = viewModel.challenger {
                    LadderCardView(label: "Anchor", card: anchor)
                    LadderCardView(label: "Challenger", card: challenger)
                } else {
                    Text("Waiting for the next card…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 40)
                }

                callArea
                StandingsRail(viewModel: viewModel)

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(viewModel.questionLabel.uppercased())
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(viewModel.formatLabel.uppercased())
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var callArea: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.call(.higher) }
                } label: {
                    Label("Higher", systemImage: "arrow.up").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    Task { await viewModel.call(.lower) }
                } label: {
                    Label("Lower", systemImage: "arrow.down").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .disabled(!viewModel.canCall)

            // A row with no direction is the miss the server wrote when the
            // deadline passed. It scores exactly as a wrong call — that is the
            // point of writing it — so this line is the only place the
            // difference shows.
            if let call = viewModel.myCall {
                Text(call.timedOut ? "You ran out of time." : "You called \(call.direction?.rawValue ?? "").")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Who is at the table, where they stand, and what each of them is doing.
private struct StandingsRail: View {
    @ObservedObject var viewModel: MatchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("STANDINGS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("CORRECT · BEST")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.standings) { standing in
                let player = standing.player
                HStack(spacing: 10) {
                    Text("\(standing.tied ? "T-" : "#")\(standing.rank)")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(standing.rank == 1 ? Color.accentColor : Color.secondary)
                        .frame(width: 32, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(player.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if player.userId == viewModel.viewerId {
                                Text("YOU")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.tint)
                            }
                        }
                        Text(viewModel.status(of: player))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(player.correctCount) correct")
                            .font(.caption.weight(.bold))
                            .monospacedDigit()
                        Text("\(player.bestStreak) best")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - The ending

private struct MatchFinalView: View {
    @ObservedObject var viewModel: MatchViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FINAL")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.headline)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .accessibilityAddTraits(.isHeader)
                }

                ForEach(viewModel.finalStandings) { row in
                    HStack(spacing: 12) {
                        Text("#\(row.rank)")
                            .font(.headline.monospaced())
                            .foregroundStyle(row.rank == 1 ? Color.accentColor : Color.secondary)
                            .frame(width: 34, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(row.name).font(.headline).lineLimit(1)
                                if row.isViewer {
                                    Text("YOU")
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.tint)
                                }
                            }
                            Text(row.statLine)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
                }

                if let message = viewModel.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }

                postGameControls
            }
            .padding()
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
                    HStack {
                        if viewModel.isBusy { ProgressView().tint(.white) }
                        Text("Play again").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canChoosePostGame)

                Button("Back to the room") {
                    Task { await viewModel.choosePostGame(.lobby) }
                }
                .disabled(!viewModel.canChoosePostGame)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                Text("Waiting for the host to choose what's next.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Back to the room") { dismiss() }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
