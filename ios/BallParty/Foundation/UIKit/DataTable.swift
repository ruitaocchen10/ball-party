import SwiftUI

// A ranked table: a header row of column titles over rows with hairlines
// between them, the leaderboards' look. A row can be picked out ("you"), which
// seats it on a panel. The columns are described once and the table lays every
// row out against them, so a scoreboard, a leaderboard or a draft's standings
// all line up the same way.

/// The colours a cell should draw in. A highlighted row sits on the dark
/// panel, where the ordinary text colours would vanish.
struct TableTone {
    let primary: Color
    let secondary: Color
    let onPanel: Bool
}

@MainActor
struct TableColumn<Row> {
    enum Width {
        /// Exactly this wide, for numbers and ranks.
        case fixed(CGFloat)
        /// Takes what the fixed columns leave. More than one splits it evenly.
        case flexible
    }

    let title: String
    let width: Width
    let alignment: Alignment
    let cell: (Row, TableTone) -> AnyView

    init<Cell: View>(
        _ title: String,
        width: Width = .flexible,
        alignment: Alignment = .leading,
        @ViewBuilder cell: @escaping (Row, TableTone) -> Cell
    ) {
        self.title = title
        self.width = width
        self.alignment = alignment
        self.cell = { AnyView(cell($0, $1)) }
    }

    /// A rank: big slab numerals, the top three at full strength.
    static func rank(_ title: String = "#", value: @escaping (Row) -> String?) -> TableColumn {
        TableColumn(title, width: .fixed(36)) { row, tone in
            let text = value(row)
            let top = text.flatMap(Int.init).map { $0 <= 3 } ?? false
            Text(text ?? "–")
                .slabTitle(top ? 30 : 24, color: top || tone.onPanel ? tone.primary : tone.secondary)
        }
    }

    /// A number, or any short value, set large and flush right.
    static func value(_ title: String, width: CGFloat = 64, value: @escaping (Row) -> String) -> TableColumn {
        TableColumn(title, width: .fixed(width), alignment: .trailing) { row, tone in
            Text(value(row))
                .slabTitle(26, color: tone.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

struct DataTable<Row: Identifiable>: View {
    let columns: [TableColumn<Row>]
    let rows: [Row]
    /// Rows to seat on a panel, like the viewer's own.
    var highlight: (Row) -> Bool = { _ in false }
    /// What VoiceOver reads for a whole row, since its cells are separate views.
    var spoken: (Row) -> String

    var body: some View {
        VStack(spacing: 0) {
            header
            ForEach(rows) { row in
                if highlight(row) {
                    PanelCard { line(row, tone: TableTone(primary: Theme.panelFg, secondary: Theme.panelMuted, onPanel: true)) }
                } else {
                    VStack(spacing: 0) {
                        LineRule()
                        line(row, tone: TableTone(primary: Theme.fg, secondary: Theme.fgMuted, onPanel: false))
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ForEach(columns.indices, id: \.self) { index in
                let column = columns[index]
                Text(column.title)
                    .monoLabel(9, weight: .semibold, tracking: 0.12)
                    .frame(width: fixedWidth(column), alignment: column.alignment)
                    .frame(maxWidth: isFlexible(column) ? .infinity : nil, alignment: column.alignment)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
        .accessibilityHidden(true)
    }

    private func line(_ row: Row, tone: TableTone) -> some View {
        HStack(spacing: 12) {
            ForEach(columns.indices, id: \.self) { index in
                let column = columns[index]
                column.cell(row, tone)
                    .frame(width: fixedWidth(column), alignment: column.alignment)
                    .frame(maxWidth: isFlexible(column) ? .infinity : nil, alignment: column.alignment)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken(row))
    }

    private func fixedWidth(_ column: TableColumn<Row>) -> CGFloat? {
        if case .fixed(let width) = column.width { width } else { nil }
    }

    private func isFlexible(_ column: TableColumn<Row>) -> Bool {
        if case .flexible = column.width { true } else { false }
    }
}
