import SwiftUI

// Bold Predictions on iOS: the post whose answer is up to five written calls,
// each tagged with a game, a team or a player, locked in together — the web's
// `BoldPredictionsBoard.tsx`. Its board is the whole detail screen: there are
// no picks to make and no takes to unlock.
//
// Presentation only. The limits, what a draft may be and what locking in does
// are `HuddleViewModel`'s; who may read whose predictions is the server's.

// MARK: - The screen

struct BoldPredictionsView: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    var body: some View {
        Group {
            if viewModel.canAnswer(post.id) {
                BoldComposer(viewModel: viewModel, post: post)
            } else {
                BoldRevealed(viewModel: viewModel, post: post)
            }
        }
        .task { await viewModel.loadBoldBoard(post.id) }
    }
}

// MARK: - A prediction

/// One prediction as a poster line: the call in the heading face, with its tag
/// as faded art behind the right edge — both clubs for a matchup, the logo for a
/// team, the headshot for a player — and named underneath.
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
                .opacity(0.2)
                .clipped()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("“\(text)”")
                    .slabTitle(24)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(target.type.title) · \(tag.label)").monoLabel(9, tracking: 0.1)
                actions
            }
            .padding(.leading, 16)
            .padding(.trailing, 112)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .clipped()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func art(_ tag: BoldTargetDescription) -> some View {
        if target.type == .player {
            Portrait(name: tag.label, url: tag.player?.headshotURL, size: 96)
        } else if tag.teamCodes.count > 1 {
            HStack(spacing: -22) {
                ForEach(tag.teamCodes, id: \.self) { TeamLogo(code: $0, size: 64) }
            }
        } else if let code = tag.teamCodes.first {
            TeamLogo(code: code, size: 96)
        }
    }
}

extension BoldQuote where Actions == EmptyView {
    init(text: String, target: BoldTarget, board: BoldBoardData) {
        self.init(text: text, target: target, board: board) { EmptyView() }
    }
}

// MARK: - Writing

/// Drafts live on the phone until Lock in; only then does anything reach the server.
private struct BoldComposer: View {
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
                                .foregroundStyle(Theme.hiddenText)
                                .accessibilityLabel("Remove prediction: \(draft.body)")
                            }
                            .font(.mono(11, weight: .semibold))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.fg)
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Your prediction").fieldLabel()
                TextField("Make your boldest call…", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(.vertical, 10)
                    .fieldStyle()
                    .onChange(of: text) { _, value in
                        if value.count > BoldLimits.bodyMax { text = String(value.prefix(BoldLimits.bodyMax)) }
                    }
                Text("\(text.count)/\(BoldLimits.bodyMax)")
                    .monoLabel(10, tracking: 0.08)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
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
                AwardTeamTile(code: team.code, name: team.name, state: state(of: .team, team.code)) {
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

// MARK: - Reading

/// Everyone's predictions once they can be read: your own response first, then
/// the other takes, each person's together on one card.
private struct BoldRevealed: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    private struct AuthorGroup: Identifiable {
        let id: UUID
        let author: String
        let username: String?
        let avatarURL: URL?
        let isViewer: Bool
        var predictions: [BoldPrediction]
    }

    /// One response per person, in the order the first of their predictions was
    /// written; the viewer's own leads, like their take does on a pick prompt.
    private var groups: [AuthorGroup] {
        var order: [UUID] = []
        var byAuthor: [UUID: AuthorGroup] = [:]
        for prediction in post.boldPredictions {
            if byAuthor[prediction.authorId] == nil {
                order.append(prediction.authorId)
                byAuthor[prediction.authorId] = AuthorGroup(
                    id: prediction.authorId, author: prediction.author, username: prediction.authorUsername,
                    avatarURL: prediction.authorAvatarURL, isViewer: prediction.isViewer, predictions: []
                )
            }
            byAuthor[prediction.authorId]?.predictions.append(prediction)
        }
        let all = order.compactMap { byAuthor[$0] }
        return all.filter(\.isViewer) + all.filter { !$0.isViewer }
    }

    var body: some View {
        let groups = groups
        let board = viewModel.boldBoard(for: post.id)
        if groups.isEmpty {
            Text(post.status == .void ? "This post was voided." : "Nobody made a prediction before this locked.")
                .font(.sans(14))
                .foregroundStyle(Theme.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groups.filter(\.isViewer)) { card($0, board: board) }
                section("Friend takes", groups.filter { !$0.isViewer && viewModel.isFriend($0.id) }, board: board)
                section("Other takes", groups.filter { !$0.isViewer && !viewModel.isFriend($0.id) }, board: board)
            }
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ groups: [AuthorGroup], board: BoldBoardData) -> some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: title)
                ForEach(groups) { card($0, board: board) }
            }
        }
    }

    /// Every answer is a take (migration 0208), so each person's predictions hang
    /// on theirs: a reply row into its thread and the predictions behind View take.
    @ViewBuilder
    private func card(_ group: AuthorGroup, board: BoldBoardData) -> some View {
        if let take = post.comments.first(where: { $0.authorId == group.id && $0.postedWithPick }) {
            VStack(alignment: .leading, spacing: 8) {
                TakeCardView(
                    post: post, comment: take, showsReplyCount: true, collapsesPicks: true,
                    threadDestination: { AnyView(TakeThreadView(viewModel: viewModel, postId: post.id, takeId: take.id)) },
                    boldPredictions: group.predictions, boldBoard: board
                )
                if group.isViewer, post.isTakingPicks(at: Date()) {
                    Label("Predictions locked in", systemImage: "lock.fill").monoLabel(10, tracking: 0.08)
                }
            }
        } else {
            legacyCard(group, board: board)
        }
    }

    /// A person whose predictions predate their take (a read racing the answer landing).
    private func legacyCard(_ group: AuthorGroup, board: BoldBoardData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Avatar(name: group.author, url: group.avatarURL, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.author).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                    if let username = group.username {
                        Text("@\(username)").font(.sans(12)).foregroundStyle(Theme.fgMuted)
                    }
                }
                if group.isViewer {
                    Text("You").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText)
                }
                Spacer()
            }
            ForEach(group.predictions) { prediction in
                BoldQuote(text: prediction.body, target: prediction.target, board: board)
            }
            if group.isViewer, post.isTakingPicks(at: Date()) {
                Label("Predictions locked in", systemImage: "lock.fill").monoLabel(10, tracking: 0.08)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(group.author)'s predictions")
    }
}
