import SwiftUI

// Bold Predictions on iOS: the post whose answer is up to five written calls,
// each tagged with a game, a team or a player, locked in together — the web's
// `BoldPredictionsBoard.tsx`. Writing them is its own form; once they are in,
// the screen is the same as any prompt's: your take card, then everyone else's
// (`PromptDetailView`), with the predictions where other prompts show picks.
//
// Presentation only. The limits, what a draft may be and what locking in does
// are `HuddleViewModel`'s; who may read whose predictions is the server's.

// MARK: - A prediction

/// One prediction as a card in the shared ticket cut and border: the call in the heading
/// face over the tagged club's colors (both clubs' for a matchup), with the tag as art at
/// the right edge — both logos for a matchup, the logo for a team, the headshot over the
/// club's logo for a player — and named underneath.
struct BoldQuote<Actions: View>: View {
    let text: String
    let target: BoldTarget
    let board: BoldBoardData
    @ViewBuilder var actions: Actions

    var body: some View {
        let tag = BoldTargetDescription(target, board: board)
        ZStack(alignment: .trailing) {
            art(tag)
                .frame(width: 120)
                .clipped()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("“\(text)”")
                    .slabTitle(16, color: .white)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(target.type.title) · \(tag.label)").monoLabel(9, tracking: 0.1, color: .white.opacity(0.75))
                actions
            }
            .padding(.leading, 16)
            .padding(.trailing, 112)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        }
        .background(teamFill(codes: tag.player.map { [$0.team] } ?? tag.teamCodes))
        .clipShape(TicketShape.choice)
        .overlay { TicketShape.choice.stroke(Color.white.opacity(0.2), lineWidth: 1) }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func art(_ tag: BoldTargetDescription) -> some View {
        if target.type == .player {
            PlayerCell(name: tag.label, url: tag.player?.headshotURL, team: tag.player?.team ?? "", width: 120, height: 88)
        } else if tag.teamCodes.count > 1 {
            HStack(spacing: -22) {
                ForEach(tag.teamCodes, id: \.self) { logo($0, size: 64) }
            }
        } else if let code = tag.teamCodes.first {
            logo(code, size: 96)
        }
    }

    private func logo(_ code: String, size: CGFloat) -> some View {
        TeamLogo(code: code, size: size).shadow(color: .black.opacity(0.5), radius: 4, y: 3)
    }
}

extension BoldQuote where Actions == EmptyView {
    init(text: String, target: BoldTarget, board: BoldBoardData) {
        self.init(text: text, target: target, board: board) { EmptyView() }
    }
}

// MARK: - Writing

/// Drafts live on the phone until Lock in; only then does anything reach the server.
struct BoldComposer: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    @State private var editingIndex: Int?

    var body: some View {
        let drafts = viewModel.boldDraftList(for: post.id)
        let board = viewModel.boldBoard(for: post.id)
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Your predictions", trailing: "\(drafts.count) of \(BoldLimits.maxPredictions) used")

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(drafts.enumerated()), id: \.offset) { index, draft in
                    if editingIndex == index {
                        BoldForm(
                            viewModel: viewModel, postId: post.id, initial: draft, submitLabel: "Save changes",
                            onSubmit: { updated in
                                if viewModel.replacePrediction(at: index, with: updated, in: post.id) { editingIndex = nil }
                            },
                            onCancel: { editingIndex = nil }
                        )
                    } else {
                        BoldQuote(text: draft.body, target: draft.target, board: board) {
                            HStack(spacing: 16) {
                                Button("Edit") { editingIndex = index }
                                    .accessibilityLabel("Edit prediction: \(draft.body)")
                                Button("Remove") {
                                    viewModel.removePrediction(at: index, from: post.id)
                                    editingIndex = nil
                                }
                                .accessibilityLabel("Remove prediction: \(draft.body)")
                            }
                            .font(.mono(11, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(.white)
                            .buttonStyle(.plain)
                            .frame(minHeight: 32)
                        }
                    }
                }

                if drafts.count >= BoldLimits.maxPredictions {
                    Text("That's all five. Remove one to add another.").font(.sans(14)).foregroundStyle(Theme.fgMuted)
                } else if editingIndex == nil {
                    BoldForm(
                        viewModel: viewModel, postId: post.id, initial: nil, submitLabel: "Add prediction",
                        onSubmit: { viewModel.addPrediction($0, to: post.id) }
                    )
                }
            }

            Button {
                Task { await viewModel.lockInPredictions(post.id) }
            } label: {
                Text(viewModel.isSending ? "Locking in…" : "Lock in")
            }
            .buttonStyle(.solid)
            .disabled(!viewModel.canLockInPredictions(post.id) || editingIndex != nil)
        }
    }
}

/// The words, their counter and the tag picker — shared by adding a draft and
/// editing one.
private struct BoldForm: View {
    @ObservedObject var viewModel: HuddleViewModel
    let postId: UUID
    let initial: BoldDraft?
    let submitLabel: String
    let onSubmit: (BoldDraft) -> Void
    var onCancel: (() -> Void)?

    @State private var text: String
    @State private var target: BoldTarget?

    init(
        viewModel: HuddleViewModel, postId: UUID, initial: BoldDraft?, submitLabel: String,
        onSubmit: @escaping (BoldDraft) -> Void, onCancel: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel; self.postId = postId; self.initial = initial
        self.submitLabel = submitLabel; self.onSubmit = onSubmit; self.onCancel = onCancel
        _text = State(initialValue: initial?.body ?? "")
        _target = State(initialValue: initial?.target)
    }

    private var draft: BoldDraft? {
        guard let target else { return nil }
        let candidate = BoldDraft(body: text, target: target)
        return HuddleViewModel.isReadyPrediction(candidate) ? candidate : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            CountedTextArea(
                label: "Your prediction", placeholder: "Make your boldest call…",
                text: $text, limit: BoldLimits.bodyMax, lines: 3...6
            )
            VStack(alignment: .leading, spacing: 8) {
                Text("Tag — required").fieldLabel()
                BoldTagPicker(viewModel: viewModel, postId: postId, target: $target)
            }
            HStack(spacing: 8) {
                Button(submitLabel) {
                    guard let draft else { return }
                    onSubmit(draft)
                    if initial == nil { text = ""; target = nil }
                }
                .buttonStyle(initial == nil ? .ghost : .solid)
                .disabled(draft == nil)
                if let onCancel {
                    Button("Cancel", action: onCancel).buttonStyle(.ghost)
                }
            }
        }
    }
}

/// Chooses the single required tag on a prediction: a game from the week's
/// schedule, one of the thirty-two clubs, or a player found by search. Switching
/// kind drops a tag of the other kind, so a prediction can never hold two.
private struct BoldTagPicker: View {
    @ObservedObject var viewModel: HuddleViewModel
    let postId: UUID
    @Binding var target: BoldTarget?

    @State private var chosenType: BoldTargetType?

    private var type: BoldTargetType { target?.type ?? chosenType ?? .matchup }
    private let teamColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    private let gameColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PillChoice(
                selection: Binding(get: { type }, set: { switchType($0) }),
                options: BoldTargetType.allCases,
                // A closure, not `\.title`: the CI toolchain (Xcode 26.6, Swift 6.3.3)
                // crashes in IR generation on the key-path-to-function adapter.
                title: { $0.title },
                accessibilityName: "Tag type"
            )
            switch type {
            case .matchup: matchups
            case .team: teams
            case .player: player
            }
        }
    }

    private func switchType(_ next: BoldTargetType) {
        chosenType = next
        if let target, target.type != next { self.target = nil }
    }

    @ViewBuilder
    private var matchups: some View {
        if viewModel.boldBoards[postId] == nil {
            LoadingSpinner().frame(maxWidth: .infinity, minHeight: 44)
        } else if viewModel.boldBoard(for: postId).weekGames.isEmpty {
            Text("No games are scheduled for this week.").font(.sans(14)).foregroundStyle(Theme.fgMuted)
        } else {
            LazyVGrid(columns: gameColumns, spacing: 8) {
                ForEach(viewModel.boldBoard(for: postId).weekGames) { game in
                    AwardGameTile(away: game.away, home: game.home, label: game.label, state: state(of: .matchup, game.id)) {
                        target = BoldTarget(type: .matchup, id: game.id)
                    }
                }
            }
        }
    }

    private var teams: some View {
        LazyVGrid(columns: teamColumns, spacing: 6) {
            ForEach(NFLTeams.all, id: \.code) { team in
                TeamChoiceTile(code: team.code, name: team.name, state: state(of: .team, team.code)) {
                    target = BoldTarget(type: .team, id: team.code)
                }
            }
        }
    }

    private var player: some View {
        PlayerPickerView(
            label: "Player tag",
            selection: target.flatMap { $0.type == .player ? viewModel.foundPlayers[$0.id] : nil },
            search: { try await viewModel.searchPlayers($0) },
            onSelect: { player in
                if let player { viewModel.rememberPlayer(player) }
                target = player.map { BoldTarget(type: .player, id: $0.id) }
            }
        )
    }

    private func state(of type: BoldTargetType, _ id: String) -> ChoiceTileState {
        guard let target, target.type == type else { return .idle }
        return target.id == id ? .selected : .dimmed
    }
}
