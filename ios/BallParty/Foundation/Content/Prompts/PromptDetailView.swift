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
                        if post.isUnsupported {
                            UpdateAppNotice(compact: false)
                        } else if post.isBoldPredictions {
                            BoldPredictionsView(viewModel: viewModel, post: post)
                        } else if viewModel.canAnswer(postId) {
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
        VStack(alignment: .leading, spacing: 0) {
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
    /// prompt closed on them. As on the web, what the viewer picked (and said,
    /// and scored) is one card; what the crowd did sits with it or below it.
    @ViewBuilder
    private func results(_ post: PromptPost) -> some View {
        if post.viewerAnswered {
            YourCard(viewModel: viewModel, post: post, take: viewModel.yourTake(on: post.id))
        } else {
            Text("You did not make picks for this prompt.")
                .monoLabel(11, tracking: 0.1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
            if post.isMatchupPost {
                SectionTitle(text: "The games")
                MatchupCalls(post: post)
            } else if !post.isPowerRankings && !post.isWeeklyAwards {
                ForEach(post.slots) { slot in
                    SlotResultsView(post: post, slot: slot)
                }
            }
        }
        if post.isPowerRankings {
            PowerRankingsResults(post: post)
        }
        if post.isWeeklyAwards {
            WeeklyAwardsResults(post: post)
        }
    }

    // MARK: - Takes

    /// Everybody else's takes. The viewer's own is in their card.
    @ViewBuilder
    private func takes(_ post: PromptPost) -> some View {
        takeSection("Friend takes", post: post, takes: viewModel.friendTakes(on: post.id))
        takeSection("Other takes", post: post, takes: viewModel.otherTakes(on: post.id))
    }

    @ViewBuilder
    private func takeSection(_ title: String, post: PromptPost, takes: [PromptComment]) -> some View {
        if !takes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(text: title)
                ForEach(takes) { take in
                    TakeCardView(
                        post: post, comment: take, showsReplyCount: true,
                        collapsesPicks: true,
                        threadDestination: { AnyView(TakeThreadView(viewModel: viewModel, postId: post.id, takeId: take.id)) }
                    )
                }
            }
        }
    }
}

// MARK: - The viewer's card

/// What the viewer locked in: their take, their picks — each game marked right
/// or wrong once it is graded, a ballot with how each team moved — and the
/// points it earned. The card the web's thread opens with.
private struct YourCard: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost
    /// Their take, when they left one with their picks.
    let take: PromptComment?

    /// Your own ticket folds away too, same as everyone else's, so a long
    /// slate doesn't force a scroll past it to reach the other takes.
    @State private var picksShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let take {
                    Avatar(name: take.author, url: take.authorAvatarURL, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(take.author).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                        if let username = take.authorUsername {
                            Text("@\(username)").font(.sans(12)).foregroundStyle(Theme.fgMuted)
                        }
                    }
                }
                Text("You").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText)
                Spacer()
                if let take {
                    Text(take.createdAt, style: .relative).font(.mono(10)).foregroundStyle(Theme.fgMuted)
                }
            }
            if let take, !take.body.isEmpty {
                Text(take.body).font(.sans(16)).foregroundStyle(Theme.fg)
            }
            if picksShown { picks }
            HStack(spacing: 12) {
                Label("Picks locked in", systemImage: "lock.fill").monoLabel(10, tracking: 0.08)
                if let points = post.viewerPointsAwarded {
                    ResultBadge(text: "+\(points)", tone: points > 0 ? .good : .bad)
                }
                Spacer(minLength: 0)
                Button { picksShown.toggle() } label: {
                    Text(picksShown ? "Hide take" : "View take")
                        .monoLabel(10, weight: .semibold, tracking: 0.08)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
                if let take { replyLink(take) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var picks: some View {
        if post.isPowerRankings {
            PowerRankingsBoard(post: post)
        } else if post.isWeeklyAwards {
            WeeklyAwardsBallot(post: post, response: post.viewerResponse ?? [:])
        } else if post.isMatchupPost {
            MatchupCalls(post: post)
        } else {
            ForEach(post.slots) { slot in
                SlotResultsView(post: post, slot: slot)
            }
        }
    }

    private func replyLink(_ take: PromptComment) -> some View {
        NavigationLink {
            TakeThreadView(viewModel: viewModel, postId: post.id, takeId: take.id)
        } label: {
            Label(
                take.replies.isEmpty ? "Reply" : "\(take.replies.count) \(take.replies.count == 1 ? "reply" : "replies")",
                systemImage: "bubble.left"
            )
            .monoLabel(10, weight: .semibold, tracking: 0.1)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A post made only of games, as the web's "Your calls": the compact strips two
/// to a row — one, for one game — each with the viewer's call on it and, once
/// they have answered and so may see it, how the crowd split.
private struct MatchupCalls: View {
    let post: PromptPost

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: post.hasMarginGames ? 1 : min(2, post.slots.count)),
            spacing: 10
        ) {
            ForEach(post.slots) { slot in
                SlotResultsView(post: post, slot: slot)
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
            if post.isPowerRankings {
                PowerRankingsPicker(viewModel: viewModel, post: post)
            } else if post.isWeeklyAwards {
                WeeklyAwardsPicker(viewModel: viewModel, post: post)
            } else if post.isMatchupPost {
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
/// tap a side of, a slate compact strips two to a row to work down.
private struct MatchupPicks: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    var body: some View {
        if post.slots.count == 1, let slot = post.slots.first, let game = slot.marginGame {
            // Winner and margin: the cover is just the game; the call is one of the four below it.
            VStack(alignment: .leading, spacing: 12) {
                MatchupPoster(away: game.cover.away, home: game.cover.home, game: slot.game)
                Text("Pick the winner and margin").monoLabel(10, tracking: 0.1)
                MarginChoices(
                    slot: slot, game: game, selected: viewModel.selection(in: slot.id, of: post.id).first,
                    onSelect: { viewModel.toggle($0, in: slot.id, of: post.id) }
                )
            }
        } else if post.slots.count == 1, let slot = post.slots.first, let matchup = slot.matchup {
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
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: post.hasMarginGames ? 1 : 2),
                    spacing: 10
                ) {
                    ForEach(post.slots) { slot in
                        if let game = slot.marginGame {
                            MarginChoices(
                                slot: slot, game: game, selected: viewModel.selection(in: slot.id, of: post.id).first,
                                onSelect: { viewModel.toggle($0, in: slot.id, of: post.id) }
                            )
                        } else if let matchup = slot.matchup {
                            MatchupTile(
                                away: matchup.away, home: matchup.home,
                                selected: viewModel.selection(in: slot.id, of: post.id).first,
                                onSelect: { viewModel.toggle($0, in: slot.id, of: post.id) },
                                logoSize: 80
                            )
                        }
                    }
                }
            }
        }
    }

    private var picked: Int {
        post.slots.filter { !viewModel.selection(in: $0.id, of: post.id).isEmpty }.count
    }
}

struct SlotPicker: View {
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
                    // A chosen option is filled red; the rest stay in the well.
                    .background(isChosen ? Theme.hidden : Theme.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(isChosen ? Color.clear : Theme.line, lineWidth: 1))
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
            if let game = slot.marginGame {
                MarginChoices(
                    slot: slot, game: game, selected: post.viewerResponse?[slot.id]?.first,
                    reveals: slot.correctOptionIds != nil
                )
            } else {
                MatchupTile(
                    away: matchup.away, home: matchup.home,
                    selected: post.viewerResponse?[slot.id]?.first, winner: slot.winnerId
                )
            }
            crowd(matchup)
        }
    }

    /// How the crowd split between the two clubs. On a winner-and-margin game a
    /// club's share is both of its margin choices together.
    private var crowdSplit: (away: Double, home: Double)? {
        guard let split = post.aggregate?[slot.id] else { return nil }
        if let game = slot.marginGame {
            return (
                (split[game.awayShort.id] ?? 0) + (split[game.awayLong.id] ?? 0),
                (split[game.homeShort.id] ?? 0) + (split[game.homeLong.id] ?? 0)
            )
        }
        guard let matchup = slot.matchup, let away = split[matchup.away.id], let home = split[matchup.home.id] else { return nil }
        return (away, home)
    }

    @ViewBuilder
    private func crowd(_ matchup: (away: PromptOption, home: PromptOption)) -> some View {
        if let (away, home) = crowdSplit {
            VStack(spacing: 6) {
                HStack {
                    Text("\(matchup.away.teamCode ?? matchup.away.label) \(Int(away.rounded()))%")
                    Spacer()
                    Text("\(Int(home.rounded()))% \(matchup.home.teamCode ?? matchup.home.label)")
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
                        if isRight { Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.fg) }
                        if let pct {
                            Text("\(Int(pct.rounded()))%")
                                .font(.mono(14, weight: .bold))
                                .foregroundStyle(Theme.fg)
                        }
                    }
                    if let pct {
                        MeterBar(fraction: min(max(pct, 0), 100) / 100, fill: position == nil ? Theme.fgMuted : Theme.fg)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
