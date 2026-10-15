import SwiftUI

extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// A multiplayer win or a new solo best, lighter than a prompt card so prompts
/// stay the main thing. A high score leads with the number and where it puts
/// the friend among the viewer's circle and opens that game's board; a win
/// names who it was over and opens the friend's profile. Several wins on one
/// day arrive folded into one card.
struct GameMomentCard: View {
    let item: FriendActivityItem
    let client: FriendsClient

    @Environment(\.openParty) private var openParty

    private var event: FriendActivityEvent { item.event }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                OtherProfileView(username: event.actor.username, client: client)
            } label: {
                HStack(spacing: 8) {
                    Avatar(name: event.actor.displayName, url: event.actor.avatarURL, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.actor.displayName).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                        if let username = event.actor.username.nonEmpty {
                            Text("@" + username).font(.mono(10)).foregroundStyle(Theme.fgMuted)
                        }
                    }
                    Spacer()
                    Text(event.occurredAt, style: .relative).font(.mono(10)).foregroundStyle(Theme.fgMuted)
                }
            }
            .buttonStyle(.plain)

            switch event.kind {
            case .highScore(let game, let score, let mode, let rank, let count):
                highScore(game: game, score: score, mode: mode, rank: rank, count: count)
            case .win(_, let game, let score, let opponents, let you, let count):
                win(game: game, score: score, opponents: opponents, you: you, count: count)
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func highScore(game: String, score: Double, mode: String?, rank: Int?, count: Int?) -> some View {
        let board: SoloBoard? = game == "higher_or_lower" ? .higherOrLower : game == "qb_season_builder" ? .qbSeasonBuilder : nil
        let qb = board == .qbSeasonBuilder
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("New best").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.surface)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Theme.fg, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
                Text("in " + FriendActivityEvent.gameName(game) + (qb ? mode.map { " · \($0)" } ?? "" : ""))
                    .monoLabel(10, tracking: 0.08)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(board.map { BoardEntry.formatScore(score, board: $0) } ?? "—")
                    .font(.slab(44))
                    .foregroundStyle(Theme.fg)
                Text(qb ? "season score" : "in a row").monoLabel(10, tracking: 0.08)
            }
            if let rank, let count, count > 1 {
                Text("#\(rank) of \(count) among you and your friends")
                    .font(.sans(15))
                    .foregroundStyle(Theme.fgMuted)
            }
            if let board {
                NavigationLink {
                    SoloLeaderboardScreen(board: board, mode: mode == "hidden" ? .hidden : .visible)
                } label: {
                    CardLinkLabel(title: "Beat it")
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func win(game: String, score: Double?, opponents: [String], you: Bool, count: Int) -> some View {
        let wins = [event] + item.more
        VStack(alignment: .leading, spacing: 6) {
            Text(wins.count == 1 ? "Win" : "\(wins.count) wins")
                .monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.surface)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Theme.fg, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
            if wins.count == 1 {
                Text("Won \(FriendActivityEvent.gameName(game))")
                    .font(.sans(18, weight: .medium))
                    .foregroundStyle(Theme.fg)
                let beat = FriendActivityEvent.beatLine(opponents: opponents, you: you, count: count)
                let scoreText = score.map { "Score \(FriendActivityEvent.formatScore($0))" }
                if beat != nil || scoreText != nil {
                    Text([beat.map { "Beat \($0)" }, scoreText].compactMap { $0 }.joined(separator: " · "))
                        .font(.sans(15))
                        .foregroundStyle(Theme.fgMuted)
                }
            } else {
                let games = wins.compactMap { win -> String? in
                    if case .win(_, let game, _, _, _, _) = win.kind { return FriendActivityEvent.gameName(game) }
                    return nil
                }
                let distinct = Array(NSOrderedSet(array: games)).compactMap { $0 as? String }
                Text(distinct.count == 1 ? "Won \(wins.count) \(distinct[0]) games" : "Won \(wins.count) games: \(distinct.joined(separator: ", "))")
                    .font(.sans(18, weight: .medium))
                    .foregroundStyle(Theme.fg)
            }
            Button(action: openParty) {
                CardLinkLabel(title: "Play")
            }
            .buttonStyle(.plain)
        }
    }
}

/// A game card's out-link: bordered like the web's small ghost button, label
/// underlined, with an arrow to say it leaves the feed.
private struct CardLinkLabel: View {
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Text(title).monoLabel(10, weight: .semibold, tracking: 0.08).underline()
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .semibold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.fg)
        .padding(.horizontal, 12)
        .frame(minHeight: 36)
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}
