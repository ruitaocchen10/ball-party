import SwiftUI

// The shared pieces of every list screen: the ticket-style tile, the column
// grid, a saved list's card, the start card for a list not begun, and a list's
// version history. The Swift counterpart of the web's `ListRows`,
// `ListSummaries`, `ListStartCard` and `ListHistory`.

/// How far an item moved against an earlier list, as the tile's mark. Not in
/// the earlier list and unchanged both read "–", like the prompt boards; a
/// screen reader still hears which.
enum ListMovement: Equatable {
    case up(Int), down(Int), same, new

    init(change: Int?) {
        switch change {
        case .none: self = .new
        case .some(0): self = .same
        case .some(let places): self = places > 0 ? .up(places) : .down(-places)
        }
    }

    var text: String {
        switch self {
        case .up(let places): "+\(places)"
        case .down(let places): "−\(places)"
        case .same, .new: "–"
        }
    }

    var spoken: String {
        switch self {
        case .up(let places): "Up \(places)"
        case .down(let places): "Down \(places)"
        case .same: "Did not move"
        case .new: "New"
        }
    }

    var color: Color {
        switch self {
        case .up: Theme.gradeElite
        case .down: Theme.gradeRough
        case .same, .new: Theme.panelMuted
        }
    }
}

/// One item in a list, drawn like the Power Rankings board's ticket: its rank,
/// the team's logo or the player's face, a short name, and (against an earlier
/// list) how far it moved. `rank` is nil for a team on the bench.
struct ListTile: View {
    let item: String
    let itemKind: ListKind.ItemKind
    let players: [String: ListPlayer]
    var rank: Int?
    var movement: ListMovement?
    var picked = false
    /// A player's remove glyph in the trailing cell (the editor); the tap itself is the caller's.
    var removable = false
    var compact = false
    /// A four-column board's tile: no name, since a column is under 80 points wide.
    var tiny = false

    private var player: ListPlayer? { itemKind == .player ? players[item] : nil }
    private var team: String? { itemKind == .team ? item : player?.team }
    private var height: CGFloat { tiny || compact ? 48 : 56 }
    private var markSize: CGFloat { tiny ? 34 : compact ? 30 : 36 }

    var body: some View {
        if tiny { tinyBody } else { fullBody }
    }

    private var tinyBody: some View {
        HStack(spacing: 0) {
            Text(rank.map(String.init) ?? "+")
                .font(.slab(16))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: 22, height: height)
                .background(Color.black.opacity(0.45))
            mark
                .frame(maxWidth: .infinity)
                .clipped()
            if let movement {
                Text(movement.text)
                    .font(.mono(10, weight: .bold))
                    .foregroundStyle(movement.color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(width: 22, height: height)
                    .background(Theme.fg)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: height)
        .background(picked ? AnyShapeStyle(Theme.hidden) : AnyShapeStyle(gradient))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(picked ? Color.white : Color.white.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var fullBody: some View {
        HStack(spacing: 0) {
            Text(rank.map(String.init) ?? "+")
                .font(.slab(compact ? 20 : 24))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: compact ? 28 : 34, height: height)
                .background(Color.black.opacity(0.45))
            HStack(spacing: compact ? 5 : 8) {
                mark
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.slab(compact ? 16 : 19))
                        .textCase(.uppercase)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let player {
                        Text("\(player.position) · \(player.team)")
                            .font(.mono(9))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 5 : 8)
            if let movement {
                Text(movement.text)
                    .font(.mono(11, weight: .bold))
                    .foregroundStyle(movement.color)
                    .frame(width: compact ? 30 : 36, height: height)
                    .background(Theme.fg)
                    .accessibilityHidden(true)
            } else if removable {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.surface)
                    .frame(width: 34, height: height)
                    .background(Theme.fg)
                    .accessibilityHidden(true)
            }
        }
        .frame(height: height)
        .background(picked ? AnyShapeStyle(Theme.hidden) : AnyShapeStyle(gradient))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(picked ? Color.white : Color.white.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var title: String {
        itemKind == .team ? ListLogic.teamName(item) : ListLogic.surname(player?.name ?? "Unknown")
    }

    private var spokenLabel: String {
        var parts = [rank.map(String.init) ?? "Not ranked", itemKind == .team ? ListLogic.teamName(item) : (player?.name ?? "Unknown")]
        if let movement { parts.append(movement.spoken) }
        if picked { parts.append("picked up") }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder private var mark: some View {
        if itemKind == .team {
            TeamLogo(code: item, size: markSize)
                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 3)
        } else {
            Portrait(name: player?.name ?? "Player", url: player?.headshotURL, size: markSize)
        }
    }

    // A team's primary color is data, not a design token, as on the prompt boards.
    private var gradient: LinearGradient {
        let primary = team.flatMap(NFLTeams.primaryColor(for:)) ?? Color(hex: 0x252722)
        return LinearGradient(colors: [primary, Color(hex: 0x171914)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.72, y: 1))
    }
}

/// A list laid out as the web lays it out: one column up to 5, two columns
/// of 5 for a top 10, four of 8 for all 32. It fills down each column first.
struct ListGrid<Tile: View>: View {
    let count: Int
    /// The size the list is laid out for, when it shows only part of itself.
    let size: Int
    @ViewBuilder let tile: (Int) -> Tile

    init(count: Int, size: Int? = nil, @ViewBuilder tile: @escaping (Int) -> Tile) {
        self.count = count
        self.size = size ?? count
        self.tile = tile
    }

    static func columns(for size: Int) -> Int { size > 10 ? 4 : size > 5 ? 2 : 1 }

    var body: some View {
        let columns = Self.columns(for: size)
        let rows = Int((Double(max(size, 1)) / Double(columns)).rounded(.up))
        HStack(alignment: .top, spacing: 6) {
            ForEach(0..<columns, id: \.self) { column in
                VStack(spacing: 6) {
                    ForEach(Array(stride(from: column * rows, to: min(count, (column + 1) * rows), by: 1)), id: \.self) { index in
                        tile(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

/// A saved list in order as tiles, optionally with movement against the version it replaced.
struct ListRowsView: View {
    let items: [String]
    let itemKind: ListKind.ItemKind
    let players: [String: ListPlayer]
    var previous: [String]?
    var size: Int?

    var body: some View {
        ListGrid(count: items.count, size: size) { index in
            ListTile(
                item: items[index], itemKind: itemKind, players: players, rank: index + 1,
                movement: previous.map { ListMovement(change: ListLogic.placeChange(previous: $0, items: items, index: index)) },
                compact: (size ?? items.count) > 5, tiny: (size ?? items.count) > 10
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
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .background(Theme.surface)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
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
                .padding(.top, 8)
            }
            .padding(16)
        }
    }

    @ViewBuilder private var art: some View {
        if kind.isTeams {
            HStack(spacing: -8) {
                ForEach(Array(Self.coverTeams.enumerated()), id: \.offset) { index, code in
                    TeamLogo(code: code, size: 56)
                        .rotationEffect(.degrees(index.isMultiple(of: 2) ? -6 : 6))
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 4)
                }
            }
        } else if players.count >= 3 {
            HStack(spacing: 0) {
                ForEach(players, id: \.id) { player in
                    ZStack(alignment: .bottom) {
                        (NFLTeams.primaryColor(for: player.team) ?? Theme.panelShade).opacity(0.55)
                        Portrait(name: player.name, url: player.headshotURL, size: 76)
                    }
                }
            }
        } else {
            Text("1  2  3").font(.slab(44)).foregroundStyle(Theme.fgMuted.opacity(0.5))
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
