import SwiftUI

// Every tile a player chooses from — a team, a whole game, a side of a game, a
// margin — shares one look: the same ticket cut, height and border, and the same
// way of saying "this one" and "that was right". The tiles differ only in what
// they show. Build a new choice from `.choiceTile(mark:)`, not from its own
// shape and ring.

/// How a tile in a group of choices looks: nothing chosen yet, this one chosen,
/// or another one chosen.
enum ChoiceTileState {
    case idle, selected, dimmed

    init(chosen: UUID?, option: UUID) {
        self = chosen == nil ? .idle : chosen == option ? .selected : .dimmed
    }
}

/// What a tile says about itself once chosen: just chosen, or graded right or wrong.
enum ChoiceMark: Equatable {
    case selected, right, wrong

    init?(selected: Bool, verdict: Bool? = nil) {
        if let verdict { self = verdict ? .right : .wrong } else if selected { self = .selected } else { return nil }
    }

    fileprivate var color: Color {
        switch self {
        case .selected: Theme.fg
        case .right: Theme.gradeElite
        case .wrong: Theme.gradeRough
        }
    }
}

enum ChoiceTile {
    static let height: CGFloat = 64
    /// The mark is cropped large by the tile, so it is far bigger than the tile is tall.
    static let logoSize: CGFloat = 80
}

extension TicketShape {
    /// The cut every choosable tile shares.
    static let choice = TicketShape(cutX: 12, cutY: 8)
}

/// The fill behind a team: its primary color, deepening toward the far corner to a
/// darker shade of itself, so the color runs the whole width. A team's color is
/// data, not a design token, so it comes from `NFLTeams`; a code with none falls
/// back to the raised surface fading into the surface.
func teamFill(_ code: String?) -> LinearGradient {
    guard let primary = code.flatMap(NFLTeams.primaryColor(for:)) else {
        return LinearGradient(colors: [Theme.surfaceRaised, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    return LinearGradient(colors: [primary, primary.deepened(by: 0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private extension Color {
    /// The same hue with its brightness scaled by `factor`.
    func deepened(by factor: CGFloat) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }
        return Color(hue: hue, saturation: saturation, brightness: brightness * factor, opacity: alpha)
    }
}

/// The corner badge of a marked tile: a check when chosen, a filled check or
/// cross once graded (a filled badge, because a grade color alone vanishes into
/// a dark or team-colored face).
struct ChoiceBadge: View {
    let mark: ChoiceMark

    var body: some View {
        switch mark {
        case .selected:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Theme.fg)
                .shadow(radius: 1)
                .padding(5)
                .accessibilityHidden(true)
        case .right, .wrong:
            Image(systemName: mark == .right ? "checkmark" : "xmark")
                .font(.system(size: 9, weight: .black))
                .foregroundStyle(Theme.fg)
                .frame(width: 16, height: 16)
                .background(mark.color, in: Circle())
                .padding(5)
                .accessibilityHidden(true)
        }
    }
}

private struct ChoiceSurface: ViewModifier {
    let mark: ChoiceMark?
    let badge: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: ChoiceTile.height)
            .clipShape(TicketShape.choice)
            .overlay {
                TicketShape.choice.stroke(mark?.color ?? Color.white.opacity(0.2), lineWidth: mark == nil ? 1 : 2)
            }
            .overlay(alignment: .topTrailing) {
                if badge, let mark { ChoiceBadge(mark: mark) }
            }
            .contentShape(TicketShape.choice)
    }
}

extension View {
    /// Makes this view a choice tile: the shared height, ticket cut and border, in the
    /// color of `mark`, with its badge in the corner. A tile whose halves carry their
    /// own marks (a side of a game) passes `badge: false`.
    func choiceTile(mark: ChoiceMark? = nil, badge: Bool = true) -> some View {
        modifier(ChoiceSurface(mark: mark, badge: badge))
    }
}

// MARK: - Two-sided tiles

/// One side of a game: the club's color floods it when chosen, and a side passed
/// over recedes to a gray, faded logo. A side that carries a mark gets its own ring
/// and badge, since the tile around it holds two.
struct ChoiceHalf: View {
    let code: String?
    var flooded = false
    var receded = false
    var mark: ChoiceMark?

    var body: some View {
        // The logo sits in an overlay, not in the layout: it is far bigger than
        // the tile and cropped by it, so it must not set the side's width.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: ChoiceTile.height)
            .background {
                if flooded { teamFill(code) } else { Theme.surface.opacity(0.85) }
            }
            .overlay {
                if let code {
                    TeamLogo(code: code, size: ChoiceTile.logoSize)
                        .grayscale(receded ? 1 : 0)
                        .opacity(receded ? 0.4 : 1)
                }
            }
            .overlay { if let mark { Rectangle().strokeBorder(mark.color, lineWidth: 2) } }
            .overlay(alignment: .topTrailing) { if let mark { ChoiceBadge(mark: mark) } }
            .clipped()
    }
}

/// Two sides of a game, away then home, with the "@" between them. Wrap it in
/// `.choiceTile` for the tile around it.
struct TwoSidedFace<Away: View, Home: View>: View {
    @ViewBuilder let away: Away
    @ViewBuilder let home: Home

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                away
                Theme.line.frame(width: 1)
                home
            }
            Text("@")
                .font(.mono(10, weight: .bold))
                .foregroundStyle(Theme.fgMuted)
                .frame(width: 24, height: 24)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Team

/// A club as a choice: its colors behind an oversized, cropped logo. The club is
/// named for VoiceOver only; the mark says it for everyone else.
///
/// One tile for every place a team is chosen. Picking one of several (Weekly
/// Awards, a Bold Predictions tag) passes a `state` and gets a ring and a check
/// when chosen. Adding to a ranking (the Power Rankings pool) sets `adds`, which
/// draws a "+"; the tile leaves the pool once ranked, so it is never selected.
/// A tile under `.disabled(true)` reads like a dimmed one but cannot be tapped.
struct TeamChoiceTile: View {
    let code: String
    let name: String
    var state: ChoiceTileState = .idle
    var adds = false
    /// Nil for a tile that is only picked up and dragged (the list editor's bench), not tapped.
    var action: (() -> Void)?

    @Environment(\.isEnabled) private var isEnabled

    private var selected: Bool { state == .selected }

    var body: some View {
        if let action {
            Button(action: action) { face }
                .buttonStyle(.plain)
                .accessibilityLabel(adds ? "Add \(name)" : name)
                .accessibilityAddTraits(selected ? .isSelected : [])
        } else {
            face
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
        }
    }

    private var face: some View {
        Color.clear
            .frame(height: ChoiceTile.height)
            .background(teamFill(code))
            .overlay { TeamLogo(code: code, size: ChoiceTile.logoSize).shadow(color: .black.opacity(0.5), radius: 4, y: 3) }
            .overlay(alignment: .bottomTrailing) {
                if adds {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(Theme.fg.opacity(0.85))
                        .padding(.trailing, 10)
                        .padding(.bottom, 4)
                }
            }
            .choiceTile(mark: ChoiceMark(selected: selected))
            .opacity(state == .dimmed || !isEnabled ? 0.45 : 1)
    }
}

#Preview("Choice tiles") {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    return VStack(spacing: 12) {
        LazyVGrid(columns: columns, spacing: 6) {
            TeamChoiceTile(code: "KC", name: "Chiefs") {}
            TeamChoiceTile(code: "BUF", name: "Bills", state: .selected) {}
            TeamChoiceTile(code: "DET", name: "Lions", state: .dimmed) {}
            TeamChoiceTile(code: "PHI", name: "Eagles", adds: true) {}
            TeamChoiceTile(code: "SF", name: "49ers", adds: true) {}.disabled(true)
            TeamChoiceTile(code: "ZZZ", name: "Unknown") {}
        }
        HStack(spacing: 8) {
            TwoSidedFace {
                ChoiceHalf(code: "KC", flooded: true, mark: .right)
            } home: {
                ChoiceHalf(code: "BUF", receded: true)
            }
            .choiceTile(badge: false)
            TwoSidedFace {
                ChoiceHalf(code: "DET", flooded: true)
            } home: {
                ChoiceHalf(code: "GB", flooded: true)
            }
            .choiceTile(mark: .selected)
        }
    }
    .padding(16)
    .background(Theme.surface)
}
