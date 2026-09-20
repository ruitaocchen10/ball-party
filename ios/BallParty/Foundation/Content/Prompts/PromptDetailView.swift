import SwiftUI

/// One prompt: make your picks, or — once you have, or it has closed — see how
/// everyone answered, and read and reply to the takes.
struct PromptDetailView: View {
    @ObservedObject var viewModel: HuddleViewModel
    let postId: UUID

    var body: some View {
        Group {
            if let post = viewModel.post(postId) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(post)
                        if let message = viewModel.errorMessage {
                            ErrorBanner(message: message)
                        }
                        if viewModel.canAnswer(postId) {
                            AnswerForm(viewModel: viewModel, post: post)
                        } else {
                            results(post)
                            takes(post)
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await viewModel.load() }
            } else {
                ScrollView {
                    EmptyState(title: "This prompt is no longer available", message: "It may have been removed.")
                        .padding(16)
                }
            }
        }
        .screenBackground()
        .navigationTitle("Prompt")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ post: PromptPost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PostStatusLabel(post: post)
                .eyebrow()
            Text(post.promptText)
                .slabTitle(38)
                .lineSpacing(0)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !post.caption.isEmpty {
                Text(post.caption).font(.sans(16)).foregroundStyle(Theme.fgMuted)
            }
            if !post.resolutionCriteria.isEmpty {
                Text(post.resolutionCriteria).font(.sans(14)).foregroundStyle(Theme.fgMuted)
            }
            if post.status == .void, let reason = post.voidReason {
                Text(reason).monoLabel(11, tracking: 0.08, color: Theme.fg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { LineRule() }
    }

    // MARK: - After the picks

    /// Shown whenever picks can no longer be made — the viewer answered, or the
    /// prompt closed on them.
    @ViewBuilder
    private func results(_ post: PromptPost) -> some View {
        if !post.viewerAnswered {
            Text("You did not make picks for this prompt.")
                .monoLabel(11, tracking: 0.1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .overlay(Rectangle().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
        if let points = post.viewerPointsAwarded {
            // Points are a revealed thing, so a win is cream.
            if points > 0 {
                PanelCard(edge: false) {
                    Text("+\(points) points")
                        .slabTitle(32, color: Theme.panelFg)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("+\(points) points").monoLabel(12, weight: .bold, tracking: 0.1)
            }
        }
        if post.isMatchupPost {
            SectionTitle(text: post.viewerAnswered ? "Your calls" : "The games")
        }
        ForEach(post.slots) { slot in
            SlotResultsView(post: post, slot: slot)
        }
    }

    // MARK: - Takes

    @ViewBuilder
    private func takes(_ post: PromptPost) -> some View {
        if post.viewerAnswered {
            if let mine = viewModel.yourTake(on: post.id) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "Your take")
                    NavigationLink {
                        TakeThreadView(viewModel: viewModel, postId: post.id, takeId: mine.id)
                    } label: {
                        TakeCardView(post: post, comment: mine, showsReplyCount: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            let others = viewModel.otherTakes(on: post.id)
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionTitle(text: "Other takes")
                    ForEach(others) { take in
                        NavigationLink {
                            TakeThreadView(viewModel: viewModel, postId: post.id, takeId: take.id)
                        } label: {
                            TakeCardView(post: post, comment: take, showsReplyCount: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Making picks

/// The picks, the optional take, and Lock in.
private struct AnswerForm: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if post.isMatchupPost {
                MatchupPicks(viewModel: viewModel, post: post)
            } else {
                ForEach(post.slots) { slot in
                    SlotPicker(viewModel: viewModel, post: post, slot: slot)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Add a take (optional)").fieldLabel()
                TextField(
                    "Share your reasoning…",
                    text: Binding(
                        get: { viewModel.takeDraft(for: post.id) },
                        set: { viewModel.setTakeDraft($0, for: post.id) }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .padding(.vertical, 10)
                .fieldStyle()
                Text("\(viewModel.takeDraft(for: post.id).count)/\(HuddleViewModel.commentMax)")
                    .monoLabel(10, tracking: 0.08)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Button {
                Task { await viewModel.submitAnswer(post.id) }
            } label: {
                Text(viewModel.isSending ? "Locking in…" : "Lock in")
            }
            .buttonStyle(.solid)
            .disabled(!viewModel.canSubmit(post.id) || viewModel.isSending)
        }
    }
}

/// The picks of a post made only of games: a single game is a full poster to
/// tap a side of, a slate a column of compact strips to work down.
private struct MatchupPicks: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    var body: some View {
        if post.slots.count == 1, let slot = post.slots.first, let matchup = slot.matchup {
            MatchupPoster(
                away: matchup.away, home: matchup.home, game: slot.game,
                selected: viewModel.selection(in: slot.id, of: post.id).first,
                onSelect: { viewModel.toggle($0, in: slot.id, of: post.id) }
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Make each call").monoLabel(10, tracking: 0.1)
                    Spacer()
                    Text("\(picked)/\(post.slots.count) picked").monoLabel(10, tracking: 0.08)
                }
                ForEach(post.slots) { slot in
                    if let matchup = slot.matchup {
                        MatchupTile(
                            away: matchup.away, home: matchup.home,
                            selected: viewModel.selection(in: slot.id, of: post.id).first,
                            onSelect: { viewModel.toggle($0, in: slot.id, of: post.id) }
                        )
                    }
                }
            }
        }
    }

    private var picked: Int {
        post.slots.filter { !viewModel.selection(in: $0.id, of: post.id).isEmpty }.count
    }
}

private struct SlotPicker: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost
    let slot: PromptSlot

    var body: some View {
        let chosen = viewModel.selection(in: slot.id, of: post.id)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(
                text: slot.label,
                trailing: slot.shape != .pick ? "\(chosen.count)/\(slot.requiredCount)" : nil
            )
            ForEach(slot.options) { option in
                let position = chosen.firstIndex(of: option.id)
                let isChosen = position != nil
                Button {
                    viewModel.toggle(option.id, in: slot.id, of: post.id)
                } label: {
                    HStack(spacing: 12) {
                        OptionBadge(option: option, onPanel: isChosen)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                                .font(.sans(17, weight: .semibold))
                                .foregroundStyle(isChosen ? Theme.panelFg : Theme.fg)
                            if let sublabel = option.sublabel {
                                Text(sublabel)
                                    .font(.sans(13))
                                    .foregroundStyle(isChosen ? Theme.panelMuted : Theme.fgMuted)
                            }
                        }
                        Spacer()
                        if let position {
                            // A ranking's order is the point, so it shows.
                            if slot.shape == .rank {
                                Text("\(position + 1)").slabTitle(28, color: Theme.panelFg)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.panelFg)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    // A chosen option is a known thing, so it is lit like a
                    // panel; the rest stay in the well.
                    .background(isChosen ? Theme.panel : Theme.surfaceRaised)
                    .overlay(Rectangle().strokeBorder(isChosen ? Color.clear : Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isChosen ? .isSelected : [])
            }
        }
    }
}

// MARK: - Results

/// How one slot went: each option's share of the crowd, the viewer's pick, and
/// — once resolved — the right answer.
private struct SlotResultsView: View {
    let post: PromptPost
    let slot: PromptSlot

    var body: some View {
        if let matchup = slot.matchup {
            matchupResult(matchup)
        } else {
            optionResults
        }
    }

    /// A game: the strip with the viewer's call on it, and how the crowd split.
    private func matchupResult(_ matchup: (away: PromptOption, home: PromptOption)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MatchupTile(
                away: matchup.away, home: matchup.home,
                selected: post.viewerResponse?[slot.id]?.first, winner: slot.winnerId
            )
            crowd(matchup)
        }
    }

    @ViewBuilder
    private func crowd(_ matchup: (away: PromptOption, home: PromptOption)) -> some View {
        let split = post.aggregate?[slot.id]
        if let away = split?[matchup.away.id], let home = split?[matchup.home.id] {
            VStack(spacing: 6) {
                HStack {
                    Text("\(matchup.away.label) \(Int(away.rounded()))%")
                    Spacer()
                    Text("\(Int(home.rounded()))% \(matchup.home.label)")
                }
                .monoLabel(10, tracking: 0.08)
                MeterBar(fraction: min(max(away, 0), 100) / 100, fill: Theme.fgMuted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var optionResults: some View {
        let mine = post.viewerResponse?[slot.id] ?? []
        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: slot.label)
            ForEach(slot.options) { option in
                let pct = post.aggregate?[slot.id]?[option.id]
                let position = mine.firstIndex(of: option.id)
                let isRight = slot.isCorrect(option.id) == true
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        OptionBadge(option: option, size: 30)
                        Text(option.label)
                            .font(.sans(17, weight: position == nil ? .regular : .bold))
                            .foregroundStyle(Theme.fg)
                        if position != nil { Text("your pick").monoLabel(10, tracking: 0.08) }
                        Spacer()
                        if isRight { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.panel) }
                        if let pct {
                            Text("\(Int(pct.rounded()))%")
                                .font(.mono(14, weight: .bold))
                                .foregroundStyle(Theme.fg)
                        }
                    }
                    if let pct {
                        MeterBar(fraction: min(max(pct, 0), 100) / 100, fill: position == nil ? Theme.fgMuted : Theme.panel)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
