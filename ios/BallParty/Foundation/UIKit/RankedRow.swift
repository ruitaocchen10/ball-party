import SwiftUI

// One ranked place — a team or a player at a number — drawn the same on a power
// rankings ballot, in the list editor, and in a saved list. It is a row, not a
// choice, but it wears the choice tiles' ticket cut and border so the two read
// as one family.

// MARK: - Movement

/// How an item moved against an earlier ranking. Not in the earlier one and
/// unchanged both read "—", like the web; a screen reader still hears which.
enum RankMovement: Equatable, Sendable {
    /// Ranked before, and by this many places higher now.
    case up(Int)
    case down(Int)
    case unchanged
    /// Not in the earlier ranking (or there is none).
    case new

    /// `previous` is the item's 1-based place last time, `current` its place now.
    init(previous: Int?, current: Int) {
        guard let previous else { self = .new; return }
        self.init(change: previous - current)
    }

    /// Places climbed (positive) or fallen (negative); nil for an item that was not there.
    init(change: Int?) {
        switch change {
        case .none: self = .new
        case .some(0): self = .unchanged
        case .some(let places): self = places > 0 ? .up(places) : .down(-places)
        }
    }

    /// What the movement tab prints under its arrow: how many places, or a dash.
    var text: String {
        switch self {
        case .up(let places), .down(let places): "\(places)"
        case .unchanged, .new: "—"
        }
    }

    /// The arrow over the number; none for an item that did not move.
    var arrow: String? {
        switch self {
        case .up: "chevron.up.2"
        case .down: "chevron.down.2"
        case .unchanged, .new: nil
        }
    }

    var spoken: String {
        switch self {
        case .up(let places): "Up \(places)"
        case .down(let places): "Down \(places)"
        case .unchanged: "No change"
        case .new: "New"
        }
    }

    var color: Color {
        switch self {
        case .up: Theme.gradeElite
        case .down: Theme.gradeRough
        case .unchanged, .new: Theme.panelMuted
        }
    }
}

// MARK: - Subject

/// What is ranked.
enum RankSubject: Equatable {
    case team(code: String, name: String)
    case player(name: String, position: String, team: String, headshotURL: URL?)

    /// The club whose colors fill the row: the team itself, or the player's.
    var teamCode: String {
        switch self {
        case .team(let code, _): code
        case .player(_, _, let team, _): team
        }
    }

    var name: String {
        switch self {
        case .team(_, let name): name
        case .player(let name, _, _, _): name
        }
    }

    /// The row's headline: a team's name, a player's surname.
    var title: String {
        switch self {
        case .team(_, let name): name
        case .player(let name, _, _, _): ListLogic.surname(name)
        }
    }

    /// The small line over a team's name: its city.
    var city: String? {
        if case .team(let code, _) = self { NFLTeams.city(for: code) } else { nil }
    }

    /// The small line under a player's surname.
    var detail: String? {
        guard case .player(_, let position, let team, _) = self, !position.isEmpty else { return nil }
        return "\(position) · \(team)"
    }
}

// MARK: - Row

/// One place in a ranking. `rank` is nil for an item not ranked yet (it shows a "+").
///
/// A team's logo sits at the left of the row, large, so the row reads as the club; a
/// full-width row names it too, and a half-width one has no room to. A quarter-width row
/// has the logo behind its whole width.
/// A player is a portrait and a surname. The movement tab at the end is always there
/// when there is something to compare against.
///
/// `onRemove` puts an X at the trailing edge (tapping the whole row instead, where a team
/// row is too narrow for one),
/// and `dragItem` lets a finger held on the row pick it up for a `.reorderSpace` board,
/// with the same row at compact density as the drag preview.
struct RankedRow: View {
    let rank: Int?
    let subject: RankSubject
    var density: RankDensity = .full
    var movement: RankMovement?
    var onRemove: (() -> Void)?
    var dragItem: String?

    private var height: CGFloat { density.rowHeight }
    private var tiny: Bool { density == .tiny }
    private var compact: Bool { density != .full }
    /// A half-width or quarter-width team row has no room for an X once it names the team,
    /// so tapping the row removes it. A player row keeps its X.
    private var removesByTap: Bool {
        if tiny { return true }
        if compact, case .team = subject { return true }
        return false
    }

    var body: some View {
        if let dragItem {
            row.reorderHandle(item: dragItem, preview: RankedRow(rank: rank, subject: subject, density: .compact))
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: 0) {
            Text(rank.map(String.init) ?? "+")
                .font(.slab(tiny ? 16 : compact ? 20 : 26))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: tiny ? 22 : compact ? 24 : 40, height: height)
                .background(Color.black.opacity(0.45))
            middle
            if !removesByTap, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: compact ? 28 : 36, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityHidden(true)
            }
            if let movement {
                // A slim tab: an arrow over the number of places, not a wide "+2".
                VStack(spacing: 1) {
                    if let arrow = movement.arrow {
                        Image(systemName: arrow).font(.system(size: tiny ? 8 : 10, weight: .black))
                    }
                    Text(movement.text)
                        .font(.mono(tiny || compact ? 11 : 13, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .foregroundStyle(movement.color)
                .frame(width: tiny ? 20 : compact ? 24 : 30, height: height)
                .background(Theme.fg)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background { fill }
        .clipShape(TicketShape.choice)
        .overlay { TicketShape.choice.stroke(Color.white.opacity(0.2), lineWidth: 1) }
        .contentShape(TicketShape.choice)
        .onTapGesture { if removesByTap { onRemove?() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityHint(removesByTap && onRemove != nil ? "Removes \(subject.name) from your ranking" : "")
        .accessibilityAddTraits(removesByTap && onRemove != nil ? .isButton : [])
        .accessibilityAction(named: "Remove \(subject.name)") { onRemove?() }
    }

    /// The club's colors, with its logo across them on a tiny team row, where a column is too
    /// narrow to put it anywhere else. The logo is bigger than the row and cropped by it.
    private var fill: some View {
        ZStack {
            teamFill(subject.teamCode)
            if case .team(let code, _) = subject, tiny {
                logo(code, size: 76)
            }
        }
    }

    @ViewBuilder private var middle: some View {
        switch subject {
        case .team(let code, let name) where !tiny:
            // The logo sits on the left and is bigger than the row, so it fills it and the
            // row's top and bottom crop it. A compact row's cell is as wide as its logo, so
            // nothing is cut off sideways and the name takes what is left.
            if compact {
                Color.clear
                    .frame(width: 60, height: height)
                    .overlay { logo(code, size: 60) }
                    .clipped()
                title(name)
            } else {
                Color.clear
                    .frame(width: 100, height: height)
                    .overlay { logo(code, size: 96) }
                    .clipped()
                title(name)
            }
        case .team:
            Color.clear.frame(maxWidth: .infinity)
        case .player(let name, _, _, let url):
            HStack(spacing: compact ? 4 : 8) {
                Portrait(name: name, url: url, size: compact ? 34 : 44)
                title(subject.title)
            }
            .padding(.leading, compact ? 5 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func logo(_ code: String, size: CGFloat) -> some View {
        TeamLogo(code: code, size: size).shadow(color: .black.opacity(0.5), radius: 4, y: 3)
    }

    /// A team's city in small type over its name in large; a player's surname over position and team.
    private func title(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let city = subject.city {
                Text(city)
                    .font(.mono(compact ? 8 : 10, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Text(text)
                .font(.slab(compact ? 16 : 26))
                .textCase(.uppercase)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let detail = subject.detail {
                Text(detail).font(.mono(9)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var spokenLabel: String {
        var parts = [rank.map(String.init) ?? "Not ranked", subject.name]
        if let movement { parts.append(movement.spoken) }
        return parts.joined(separator: ", ")
    }
}

#Preview("Ranked rows") {
    let kc = RankSubject.team(code: "KC", name: "Chiefs")
    let qb = RankSubject.player(name: "Patrick Mahomes", position: "QB", team: "KC", headshotURL: nil)
    return VStack(spacing: 6) {
        RankedRow(rank: 1, subject: kc, movement: .up(3), onRemove: {}, dragItem: "KC")
        RankedRow(rank: 2, subject: qb, movement: .down(1))
        RankedRow(rank: 3, subject: kc, density: .compact, movement: .new, onRemove: {}, dragItem: "KC")
        RankedRow(rank: nil, subject: qb, density: .compact)
        HStack(spacing: 6) {
            RankedRow(rank: 4, subject: kc, density: .tiny, movement: .unchanged, onRemove: {}, dragItem: "KC")
            RankedRow(rank: 5, subject: RankSubject.team(code: "BUF", name: "Bills"), density: .tiny)
        }
    }
    .padding(16)
    .background(Theme.surface)
}
