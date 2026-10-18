import SwiftUI

// The shared pieces of every list screen: the ranked row's subject, the column
// grid, a saved list's card, the start card for a list not begun, and a list's
// version history. The Swift counterpart of the web's `ListRows`,
// `ListSummaries`, `ListStartCard` and `ListHistory`.

extension ListLogic {
    /// What a saved list draws for `item`: the team, or the player the list knows by that id.
    static func rankSubject(item: String, itemKind: ListKind.ItemKind, players: [String: ListPlayer]) -> RankSubject {
        switch itemKind {
        case .team: .team(code: item, name: teamName(item))
        case .player:
            players[item].map { .player(name: $0.name, position: $0.position, team: $0.team, headshotURL: $0.headshotURL) }
                ?? .player(name: "Unknown", position: "", team: "", headshotURL: nil)
        }
    }
}

/// A saved list in order as rows, optionally with movement against the version it replaced.
struct ListRowsView: View {
    let items: [String]
    let itemKind: ListKind.ItemKind
    let players: [String: ListPlayer]
    var previous: [String]?
    var size: Int?

    var body: some View {
        RankBoard(size: size ?? items.count, places: items.count) { index, density in
            RankedRow(
                rank: index + 1, subject: ListLogic.rankSubject(item: items[index], itemKind: itemKind, players: players),
                density: density,
                movement: previous.map { RankMovement(change: ListLogic.placeChange(previous: $0, items: items, index: index)) }
            )
        }
    }
}

// MARK: - Cards

/// A card on the Lists tab and the profile tabs: the shape of the web's `Card`
/// with its title row, note, tiles and footer links.
private struct ListCardShell<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 8)
    }
}

private struct ListCardHeader: View {
    let title: String
    let savedAt: Date
    var sizeBadge: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).slabTitle(24, color: Theme.panelFg).lineSpacing(0).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let sizeBadge {
                Text(sizeBadge).monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.panelFg)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.panelLine, lineWidth: 1))
            }
            Text(savedAt, style: .relative).font(.mono(10)).foregroundStyle(Theme.panelMuted)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
    }
}

private struct ListNote: View {
    let note: String

    var body: some View {
        Text("“\(note)”")
            .font(.sans(18, weight: .medium))
            .foregroundStyle(Theme.panelFg)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.bottom, 12)
    }
}

/// A started list on the Lists tab: its heading, note, the first ten tiles and
/// the History and Edit links.
struct ListBuilderCard: View {
    let kind: ListKind
    let list: ListSummary
    let players: [String: ListPlayer]
    let detail: () -> ListDetailScreen

    var body: some View {
        ListCardShell {
            ListCardHeader(
                title: ListLogic.title(kind: kind.id, itemKind: kind.itemKind, size: list.items.count, versionNo: list.versionNo),
                savedAt: list.savedAt
            )
            if let note = list.note { ListNote(note: note) }
            ListRowsView(
                items: Array(list.items.prefix(10)), itemKind: list.itemKind, players: players,
                previous: list.previousItems, size: min(list.items.count, 10)
            )
            .padding(.horizontal, 16).padding(.bottom, 16)
            if list.items.count > 10 {
                Text("+ \(list.items.count - 10) more · \(ListLogic.sizeLabel(list.items.count, itemKind: list.itemKind))")
                    .monoLabel(10, tracking: 0.1, color: Theme.panelMuted)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
            HStack {
                Text("History · \(list.versionCount) \(list.versionCount == 1 ? "version" : "versions")")
                    .monoLabel(10, tracking: 0.1, color: Theme.panelMuted)
                Spacer()
                Text("Edit").monoLabel(10, weight: .bold, tracking: 0.1, color: Theme.panelFg)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)
        }
        .overlay { NavigationLink { detail() } label: { Color.clear }.accessibilityLabel("Edit \(kind.label)") }
    }
}

/// The empty state for a list not started: teams show a row of logos, positions the faces
/// of five of the best at the position, then the title, a line and the way in.
struct ListStartCard: View {
    let kind: ListKind
    var players: [ListPlayer] = []
    let detail: () -> ListDetailScreen

    private static let coverTeams = ["BUF", "KC", "DET", "PHI", "BAL", "SF"]

    var body: some View {
        ListCardShell {
            art
                .frame(maxWidth: .infinity)
                .frame(height: PromptArt.height)
                .background(Theme.surface)
                .clipped()
            VStack(alignment: .leading, spacing: 1) {
                Text(ListLogic.title(kind: kind.id, itemKind: kind.itemKind, size: kind.sizes.first ?? 10))
                    .slabTitle(24, color: Theme.panelFg).lineSpacing(0)
                Text(kind.isTeams
                    ? "Rank the teams. Friends can see it and reply when you change it."
                    : "Rank your top \(kind.sizes.first ?? 10). Friends can see it and reply when you change it.")
                    .font(.sans(15)).foregroundStyle(Theme.panelMuted)
                    .fixedSize(horizontal: false, vertical: true)
                NavigationLink { detail() } label: {
                    Text("Start your list")
                }
                .buttonStyle(.solid)
                .padding(.top, 13)
            }
            .padding(16)
        }
    }

    /// Tilts alternate so a row of six reads as a spread, not a table
    /// (`LOGO_TILTS` and `RankNumerals` in the web's `PromptCover` and `ListStartCard`).
    private static let logoTilts: [Double] = [-10, 8, -6, 10, -8, 6]
    private static let numeralTilts: [Double] = [-8, 6, -5, 9, -7, 5]

    /// The web's cover for the card: a glow on each side, then the teams' logos,
    /// a lineup of the position's best, or tilted rank numerals when their
    /// photos are not available.
    @ViewBuilder private var art: some View {
        let lineup = players.filter { $0.headshotURL != nil }
        ZStack {
            if kind.isTeams {
                PromptGlow(left: PromptArt.greenBase, right: PromptArt.red, leftOpacity: 0.22, rightOpacity: 0.22)
                spread(tilts: Self.logoTilts) { index in
                    TeamLogo(code: Self.coverTeams[index], size: 48)
                        .shadow(color: .black.opacity(0.8), radius: 4, x: 0, y: 6)
                }
                .padding(.top, 16)
            } else {
                PromptGlow(leftOpacity: 0.22, rightOpacity: 0.22)
                if lineup.count >= 3 {
                    ListPlayerLineup(players: lineup)
                } else {
                    spread(tilts: Self.numeralTilts) { index in
                        Text("\(index + 1)").font(.slab(60)).foregroundStyle(Theme.fg.opacity(0.8))
                            .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 6)
                    }
                }
            }
        }
    }

    /// One tilted mark per tilt, each centered in an equal share of the width (`justify-around`).
    private func spread<Mark: View>(tilts: [Double], @ViewBuilder mark: @escaping (Int) -> Mark) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(tilts.enumerated()), id: \.offset) { index, tilt in
                mark(index).rotationEffect(.degrees(tilt)).frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .accessibilityHidden(true)
    }
}

/// Each player's headshot standing on a column of their team's color, side by
/// side across the cover (`PlayerLineup` on the web). Each column crops the
/// photo to its middle, so the face stays centered at any width.
private struct ListPlayerLineup: View {
    let players: [ListPlayer]

    /// NFL.com headshots are all 3400 x 2450: head and shoulders on a transparent background.
    private static let aspect: CGFloat = 3400 / 2450

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                column(player)
                    .overlay(alignment: .trailing) {
                        if index < players.count - 1 { Rectangle().fill(.white.opacity(0.1)).frame(width: 1) }
                    }
            }
        }
        .accessibilityHidden(true)
    }

    private func column(_ player: ListPlayer) -> some View {
        // A team's primary color is data, not a token, as on the prompt boards.
        let color = NFLTeams.primaryColor(for: player.team) ?? Color(hex: 0x30332E)
        return GeometryReader { proxy in
            let height = proxy.size.height * 0.92
            ZStack(alignment: .bottom) {
                LinearGradient(colors: [color, .clear], startPoint: .bottom, endPoint: UnitPoint(x: 0.5, y: 0.15))
                AsyncImage(url: player.headshotURL.map { NFLHeadshot.resized($0, width: 400) }) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(Self.aspect, contentMode: .fit)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: height * Self.aspect, height: height)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 6)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }
}

/// A player's lists on a Profile tab: only the lists they keep, each at its full size,
/// newest first, with History. `isOwn` adds the Edit link.
struct ListSummariesView: View {
    @ObservedObject var viewModel: ListsViewModel
    let emptyText: String
    let detail: (ListKind) -> ListDetailScreen

    var body: some View {
        switch viewModel.phase {
        case .loading:
            LoadingSpinner().frame(maxWidth: .infinity, minHeight: 120)
        case .failed:
            EmptyState(title: "Couldn’t load lists", message: "Try again in a moment.") {
                Button("Retry") { Task { await viewModel.load() } }.buttonStyle(.quiet)
            }
        case .loaded:
            if viewModel.lists.isEmpty {
                EmptyState(title: "No lists yet", message: emptyText)
            } else {
                VStack(spacing: 16) {
                    ForEach(viewModel.lists) { list in
                        if let kind = viewModel.kinds.first(where: { $0.id == list.kind }) {
                            ListSummaryCard(list: list, kind: kind, players: viewModel.players, isOwn: viewModel.isOwn, detail: { detail(kind) })
                        }
                    }
                }
            }
        }
    }
}

struct ListSummaryCard: View {
    let list: ListSummary
    let kind: ListKind
    let players: [String: ListPlayer]
    let isOwn: Bool
    let detail: () -> ListDetailScreen

    var body: some View {
        ListCardShell {
            ListCardHeader(
                title: ListLogic.title(kind: kind.id, itemKind: kind.itemKind, size: list.items.count, versionNo: list.versionNo),
                savedAt: list.savedAt,
                sizeBadge: ListLogic.sizeLabel(list.items.count, itemKind: list.itemKind)
            )
            if let note = list.note { ListNote(note: note) }
            ListRowsView(items: list.items, itemKind: list.itemKind, players: players, previous: list.previousItems)
                .padding(.horizontal, 16).padding(.bottom, 16)
            NavigationLink { detail() } label: {
                HStack {
                    Text("History · \(list.versionCount) \(list.versionCount == 1 ? "version" : "versions")")
                        .monoLabel(10, tracking: 0.1, color: Theme.panelMuted)
                    Spacer()
                    if isOwn { Text("Edit").monoLabel(10, weight: .bold, tracking: 0.1, color: Theme.panelFg) }
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
    }
}

// MARK: - History

/// Every saved version of one list, newest first: when, what moved, the note, and how it got
/// there. The list itself folds open under "Show the list".
struct ListHistoryView: View {
    let versions: [ListVersion]
    let itemKind: ListKind.ItemKind
    let players: [String: ListPlayer]
    /// The owner also sees which versions were saved quietly.
    let isOwn: Bool
    let viewerId: UUID

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Array(versions.enumerated()), id: \.element.id) { index, version in
                HistoryVersionCard(
                    version: version, previous: versions.indices.contains(index + 1) ? versions[index + 1].items : nil,
                    itemKind: itemKind, players: players, isOwn: isOwn, viewerId: viewerId
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Version history")
    }
}

private struct HistoryVersionCard: View {
    let version: ListVersion
    let previous: [String]?
    let itemKind: ListKind.ItemKind
    let players: [String: ListPlayer]
    let isOwn: Bool
    let viewerId: UUID

    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Version \(version.versionNo)\(version.isCurrent ? " · Now" : "")")
                    .slabTitle(21, color: Theme.panelFg).lineSpacing(0)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(version.savedAt, style: .relative).font(.mono(10)).foregroundStyle(Theme.panelMuted)
            }
            if let note = version.note {
                Text("“\(note)”").font(.sans(15)).foregroundStyle(Theme.panelSoft)
            }
            Text(movesLine).monoLabel(10, tracking: 0.08, color: Theme.panelMuted)
            HStack(spacing: 6) {
                if version.source == .prompt { badge("Prompt answer") }
                if version.source == .edit {
                    if version.updatePostId != nil { badge("Shared with friends", filled: true) }
                    else if isOwn { badge("Saved quietly") }
                }
                if let post = version.updatePostId {
                    NavigationLink { ListUpdateScreen(postId: post, viewerId: viewerId) } label: {
                        Text("Replies").monoLabel(9, tracking: 0.08, color: Theme.panelMuted).underline()
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                Text(open ? "Hide the list" : "Show the list")
                    .monoLabel(10, tracking: 0.1, color: Theme.panelMuted)
                    .frame(minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(open ? "Expanded" : "Collapsed")
            if open {
                ListRowsView(items: version.items, itemKind: itemKind, players: players, previous: previous)
                    .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(version.isCurrent ? Theme.hidden : Theme.line, lineWidth: 1))
    }

    private func badge(_ text: String, filled: Bool = false) -> some View {
        Text(text)
            .monoLabel(9, weight: .bold, tracking: 0.06, color: filled ? Theme.surface : Theme.panelFg)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(filled ? Theme.panelFg : .clear, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.panelLine, lineWidth: filled ? 0 : 1))
    }

    /// "DET ▲3 · SF ▼2" against the version before it.
    private var movesLine: String {
        guard let previous else { return "First version" }
        let moves = version.items.indices
            .map { (item: version.items[$0], change: ListLogic.placeChange(previous: previous, items: version.items, index: $0)) }
            .filter { $0.change != 0 }
            .sorted { abs($0.change ?? .max) > abs($1.change ?? .max) }
        guard !moves.isEmpty else { return "No change in order" }
        let named = moves.prefix(3).map { move -> String in
            let name = itemKind == .team ? move.item : (players[move.item]?.name ?? "A player")
            switch move.change {
            case .none: return "\(name) new"
            case .some(let places): return "\(name) \(places > 0 ? "▲\(places)" : "▼\(-places)")"
            }
        }
        let rest = ListLogic.movedCount(previous: previous, items: version.items) - named.count
        return rest > 0 ? "\(named.joined(separator: " · ")) · \(rest) more" : named.joined(separator: " · ")
    }
}
