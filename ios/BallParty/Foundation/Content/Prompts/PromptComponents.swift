import SwiftUI

// Small pieces the Huddle screens share. Presentation only — anything a screen
// *decides* (what is answerable, whose takes show, what a card invites) lives
// in `HuddleViewModel`, and what a slot's answer was graded as is the server's.

extension PromptPost {
    /// The viewer's picks resolved against the slots they belong to, in slot order.
    func choices(in response: [UUID: [UUID]]) -> [(slot: PromptSlot, options: [PromptOption])] {
        slots.compactMap { slot in
            guard let chosen = response[slot.id], !chosen.isEmpty else { return nil }
            let byId = Dictionary(slot.options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return (slot, chosen.compactMap { byId[$0] })
        }
    }
}

/// A headshot when there is one, otherwise the team's code, otherwise the
/// option's first letter.
struct OptionBadge: View {
    let option: PromptOption
    var size: CGFloat = 36
    /// True when the badge sits on a cream panel, which flips its ink.
    var onPanel = false

    var body: some View {
        Group {
            if let url = option.headshotURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    fallback
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Text(option.teamCode ?? String(option.label.prefix(1)).uppercased())
            .font(.mono(max(10, size * 0.32), weight: .bold))
            .foregroundStyle(Theme.panelFg)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(onPanel ? Theme.panelLine : Theme.panelShade, in: Circle())
    }
}

/// Where a prompt stands, in a few words. Text only: the caller sets the
/// colour, since the same words sit on both a panel and the background.
struct PostStatusLabel: View {
    let post: PromptPost

    var body: some View {
        switch post.status {
        case .open where post.isTakingPicks(at: Date()): Text("Closes ") + Text(post.lockAt, style: .relative)
        case .open, .locked: Text("Locked")
        case .resolved: Text("Resolved")
        case .void: Text("Void")
        }
    }

    /// `in 2d`, the way the web's `relativeTime` says it: whole hours under a day,
    /// whole days after, and "a few min" in the last hour. Short, because the
    /// feed card's chip shares the art's corner with a team logo.
    nonisolated static func countdown(to date: Date, now: Date) -> String {
        let hours = Int((abs(date.timeIntervalSince(now)) / 3600).rounded())
        if hours < 1 { return "in a few min" }
        if hours < 24 { return "in \(hours)h" }
        return "in \(Int((Double(hours) / 24).rounded()))d"
    }
}

/// One take — or one reply — with its author, its age and, on a take that was
/// posted with picks, the author's ticket (once the post has locked).
struct TakeCardView: View {
    let post: PromptPost
    let comment: PromptComment
    var showsReplyCount = false
    /// Somebody else's ticket stays folded away until the reader asks for it,
    /// so a page of takes on a sixteen-game slate can be skimmed.
    var collapsesPicks = false
    /// Where the reply row leads. Without it the row is a plain label: a reply,
    /// or a take already open on its own screen, has nowhere further to go.
    var threadDestination: (() -> AnyView)?
    /// What the take is answering, drawn as a quoted strip between the author line and the
    /// take (the friends feed). `contextDestination` opens that prompt.
    var contextTitle: String?
    var contextDestination: (() -> AnyView)?
    /// A Bold Predictions take's picks are its author's predictions (read from
    /// the board), not a ticket. They sit behind View take like any other.
    var boldPredictions: [BoldPrediction]?
    var boldBoard: BoldBoardData?
    /// Replaces the default ticket behind View take: the viewer's own card draws
    /// their picks graded, and a ballot with how each team moved.
    var picksContent: (() -> AnyView)?
    /// Sits between the reply row and View take (the viewer's points).
    var footer: (() -> AnyView)?

    /// Foldable like any other, but starts open: the viewer's own take on the prompt screen.
    var startsOpen = false

    @State private var toggled = false

    private var picksShown: Bool { startsOpen != toggled }

    private var hasPicks: Bool { comment.response != nil || boldPredictions != nil || picksContent != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Avatar(name: comment.author, url: comment.authorAvatarURL, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(comment.author).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                    if let username = comment.authorUsername {
                        Text("@\(username)").font(.sans(12)).foregroundStyle(Theme.fgMuted)
                    }
                }
                if comment.isViewer {
                    Text("You").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText)
                }
                Spacer()
                Text(comment.createdAt, style: .relative)
                    .font(.mono(10))
                    .foregroundStyle(Theme.fgMuted)
            }
            if let contextTitle { contextStrip(contextTitle) }
            if !comment.body.isEmpty {
                Text(comment.body)
                    .font(.sans(16))
                    .foregroundStyle(Theme.fg)
            }
            if !collapsesPicks || picksShown {
                if let picksContent {
                    picksContent()
                } else if let boldPredictions, let boldBoard {
                    ForEach(boldPredictions) { prediction in
                        BoldQuote(text: prediction.body, target: prediction.target, board: boldBoard)
                    }
                } else if let response = comment.response {
                    // `collapsesPicks` already gates this whole ticket behind "View
                    // take" above; a second, inner fold would make the reader tap
                    // twice to see a matchup slate in full.
                    TicketView(post: post, response: response)
                }
            }
            if showsReplyCount || footer != nil || (collapsesPicks && hasPicks) {
                HStack(spacing: 12) {
                    if showsReplyCount { replyRow }
                    if let footer { footer() }
                    Spacer(minLength: 0)
                    if collapsesPicks, hasPicks {
                        Button { toggled.toggle() } label: {
                            Text(picksShown ? "Hide take" : "View take")
                                .monoLabel(10, weight: .semibold, tracking: 0.08)
                                .frame(minHeight: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
        // A link and a button inside it would fight for the same tap, so the
        // card is only ever combined into one element when it has neither.
        .accessibilityElement(children: threadDestination == nil && !collapsesPicks ? .combine : .contain)
    }

    @ViewBuilder
    private func contextStrip(_ title: String) -> some View {
        let strip = VStack(alignment: .leading, spacing: 2) {
            Text("Answering").monoLabel(9, tracking: 0.1)
            Text(title)
                .font(.sans(15, weight: .medium))
                .foregroundStyle(Theme.fg)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.line, lineWidth: 1))
        if let contextDestination {
            NavigationLink { contextDestination() } label: { strip }
                .buttonStyle(.plain)
        } else {
            strip
        }
    }

    @ViewBuilder
    private var replyRow: some View {
        let label = Label(
            comment.replies.isEmpty ? "Reply" : "\(comment.replies.count) \(comment.replies.count == 1 ? "reply" : "replies")",
            systemImage: "bubble.left"
        )
        .monoLabel(10, weight: .semibold, tracking: 0.1)
        if let threadDestination {
            NavigationLink { threadDestination() } label: {
                label.frame(minHeight: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            label
        }
    }
}

/// What somebody picked, marked right or wrong once the post resolves: a strip
/// per game when the post is a set of matchups, a short list otherwise.
///
/// Right is cream — a revealed thing turns cream — and wrong is quiet, not red:
/// red means concealed, and by now nothing here is.
struct TicketView: View {
    let post: PromptPost
    let response: [UUID: [UUID]]
    /// A long slate starts at its first few games, with "View all N picks" for
    /// the rest, as the web's take cards do.
    var collapsible = false

    @State private var showsAll = false

    /// The games a collapsed slate shows before "View all".
    private static let collapsedGames = 4

    var body: some View {
        if post.isPowerRankings {
            PowerRankingTicket(post: post, response: response)
        } else if post.isWeeklyAwards {
            WeeklyAwardsBallot(post: post, response: response)
        } else if post.isMatchupPost {
            matchups
        } else {
            list
        }
    }

    private var matchups: some View {
        let folds = collapsible && post.slots.count > Self.collapsedGames
        let shown = folds && !showsAll ? Array(post.slots.prefix(Self.collapsedGames)) : post.slots
        return VStack(alignment: .leading, spacing: 8) {
            // Two to a row, like the web's "Your calls" grid — or one, for one game.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: post.hasMarginGames ? 1 : min(2, post.slots.count)), spacing: 8) {
                ForEach(shown) { slot in
                    if let game = slot.marginGame {
                        MarginChoices(slot: slot, game: game, selected: response[slot.id]?.first, reveals: slot.correctOptionIds != nil)
                    } else if let matchup = slot.matchup {
                        MatchupTile(away: matchup.away, home: matchup.home, selected: response[slot.id]?.first, winner: slot.winnerId)
                    }
                }
            }
            if folds {
                Button { showsAll.toggle() } label: {
                    Label(
                        showsAll ? "Show fewer picks" : "View all \(post.slots.count) picks",
                        systemImage: showsAll ? "chevron.up" : "chevron.down"
                    )
                    .monoLabel(10, tracking: 0.08)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(post.choices(in: response), id: \.slot.id) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if post.slots.count > 1 {
                        Text(entry.slot.label).monoLabel(10, tracking: 0.08)
                    }
                    ForEach(entry.options) { option in
                        HStack(spacing: 4) {
                            Text(option.label).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                            switch entry.slot.isCorrect(option.id) {
                            case .some(true): Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.fg)
                            case .some(false): Image(systemName: "xmark.circle").foregroundStyle(Theme.fgMuted)
                            case .none: EmptyView()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Unsupported kinds

/// What a prompt of a kind this build doesn't know shows in place of its
/// picks: a note to update. Plain copy only — no App Store listing is
/// configured to link to.
struct UpdateAppNotice: View {
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Update the app to play this", systemImage: "arrow.down.app")
                .monoLabel(compact ? 10 : 11, weight: .bold, tracking: 0.1, color: Theme.fg)
            Text("This prompt needs a newer version of Ball Party. Update the app from the App Store to see it and make your picks.")
                .font(.sans(compact ? 13 : 15))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
        .accessibilityElement(children: .combine)
    }
}
