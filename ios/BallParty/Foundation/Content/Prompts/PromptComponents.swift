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
            .background(onPanel ? Theme.panelRule : Theme.panelShade, in: Circle())
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
}

/// One take — or one reply — with its author, its age and, on a take that was
/// posted with picks, the author's ticket (once the post has locked).
struct TakeCardView: View {
    let post: PromptPost
    let comment: PromptComment
    var showsReplyCount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(comment.author).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                if comment.isViewer {
                    Text("You").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText)
                }
                Spacer()
                Text(comment.createdAt, style: .relative)
                    .font(.mono(10))
                    .foregroundStyle(Theme.fgMuted)
            }
            if !comment.body.isEmpty {
                Text(comment.body)
                    .font(.sans(16))
                    .foregroundStyle(Theme.fg)
            }
            if let response = comment.response {
                TicketView(post: post, response: response)
            }
            if showsReplyCount {
                Label(
                    comment.replies.isEmpty ? "Reply" : "\(comment.replies.count) \(comment.replies.count == 1 ? "reply" : "replies")",
                    systemImage: "bubble.left"
                )
                .monoLabel(10, weight: .semibold, tracking: 0.1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
        .accessibilityElement(children: .combine)
    }
}

/// A compact list of what somebody picked, marked right or wrong once the post resolves.
///
/// Right is cream — a revealed thing turns cream — and wrong is quiet, not red:
/// red means concealed, and by now nothing here is.
struct TicketView: View {
    let post: PromptPost
    let response: [UUID: [UUID]]

    var body: some View {
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
                            case .some(true): Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.panel)
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
