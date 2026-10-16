import SwiftUI

let rankRowHeight: CGFloat = 56

/// How dense a ranking board is, as on the web: five places are one column of
/// full rows, ten are two columns of five, all thirty-two are four columns of
/// eight — each column filled top to bottom before the next.
enum RankDensity {
    case full, compact, tiny

    init(size: Int) { self = size > 10 ? .tiny : size > 5 ? .compact : .full }

    var columns: Int {
        switch self {
        case .full: 1
        case .compact: 2
        case .tiny: 4
        }
    }

    var rowHeight: CGFloat { self == .full ? rankRowHeight : 48 }
}

/// The one board every ranking is drawn on — a list in the editor, history or a
/// card, and a power-rankings ballot being made or read. It owns the columns and
/// their fill order; the caller draws each place, filled or empty, at the density
/// the board hands it.
struct RankBoard<Place: View>: View {
    /// The size the board is laid out for (5, 10 or 32).
    let size: Int
    /// How many places to draw: the whole board by default, or just the filled ones.
    var places: Int?
    @ViewBuilder let place: (_ index: Int, _ density: RankDensity) -> Place

    var body: some View {
        let density = RankDensity(size: size)
        let rows = Int((Double(max(size, 1)) / Double(density.columns)).rounded(.up))
        let count = places ?? size
        HStack(alignment: .top, spacing: 6) {
            ForEach(0..<density.columns, id: \.self) { column in
                VStack(spacing: 6) {
                    ForEach(Array(stride(from: column * rows, to: min(count, (column + 1) * rows), by: 1)), id: \.self) { index in
                        place(index, density)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

/// A place in a ranking nothing has been put in yet: its number, dashed.
struct EmptyRankSlot: View {
    let rank: Int
    let density: RankDensity
    /// "Choose a team", "Add a player"; the tiny board shows only the number.
    var prompt = "Choose a team"

    var body: some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.mono(14))
                .monospacedDigit()
                .frame(width: density == .tiny ? nil : 28, alignment: density == .tiny ? .center : .leading)
            if density != .tiny {
                Text(prompt).monoLabel(10, tracking: 0.08)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Theme.fgMuted)
        .padding(.horizontal, density == .tiny ? 0 : 12)
        .frame(maxWidth: .infinity, minHeight: density.rowHeight, maxHeight: density.rowHeight)
        .background(Theme.surfaceRaised.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Place \(rank), empty")
    }
}
