import SwiftUI

// Power Rankings on iOS: the weekly, opinion-only ranking of the league the web
// draws in `PromptPostUI.tsx` (`PowerRankingsBoard`), `SlotFaces.tsx`
// (`PowerRankingsSlot`) and `PromptContext.tsx` (the consensus rail). Same
// rules, phone-shaped controls: instead of dragging between a board and a pool,
// a player taps teams into the ranking and drags the rows to reorder them.
//
// Presentation only, like `PromptComponents`: what a tap does, how deep a
// ballot goes and what makes it complete is `HuddleViewModel`'s.

/// The height of one ranked team.

private func teamGradient(_ code: String?) -> LinearGradient {
    let primary = code.flatMap(NFLTeams.primaryColor(for:)) ?? Theme.surfaceRaised
    return LinearGradient(
        colors: [primary, Color(hex: 0x171914)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.72, y: 1)
    )
}

/// A team's logo when it has one, otherwise the option's own badge.
private struct PowerTeamMark: View {
    let option: PromptOption
    var size: CGFloat = 40

    var body: some View {
        if let code = option.teamCode {
            TeamLogo(code: code, size: size)
        } else {
            OptionBadge(option: option, size: size * 0.8)
        }
    }
}

// MARK: - Cover

/// The feed card's art: the six teams the admin chose, in placement order, the
/// first three climbing on the green side and the last three falling on the red,
/// each side with a big vertical block arrow behind its logos. It is the same for
/// every viewer.
struct PowerRankingsCover: View {
    let teamCodes: [String]

    /// Where a logo sits: how far in from its own edge and down from the top (as
    /// fractions of the banner, so the spread follows its width) and its size.
    private struct Place { let x: CGFloat; let y: CGFloat; let size: CGFloat }

    /// Outside in: risers climb toward the middle and grow as they go (so #1 is the
    /// biggest, nearest the middle); fallers fall away from it and shrink (#4
    /// nearest the middle, #6 at the edge). Matches the web's banner.
    private static let risers = [Place(x: 0.03, y: 0.57, size: 36), Place(x: 0.13, y: 0.37, size: 54), Place(x: 0.27, y: 0.02, size: 92)]
    private static let fallers = [Place(x: 0.27, y: 0.18, size: 92), Place(x: 0.13, y: 0.41, size: 54), Place(x: 0.03, y: 0.61, size: 36)]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    LinearGradient(colors: [PromptArt.greenBase.opacity(0.26), .clear], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, PromptArt.red.opacity(0.26)], startPoint: .leading, endPoint: .trailing)
                }
                arrow(color: PromptArt.greenBase, height: height * 0.78)
                    .position(x: width * 0.07 + height * 0.78 / 3, y: height * 0.12 + height * 0.39)
                arrow(color: PromptArt.red, height: height * 0.78)
                    .rotationEffect(.degrees(180))
                    .position(x: width * 0.93 - height * 0.78 / 3, y: height * 0.10 + height * 0.39)
                // The first three are the risers, shown from the edge in: #3, #2, #1.
                ForEach(Array(teamCodes.prefix(3).enumerated()), id: \.offset) { index, code in
                    let place = Self.risers[Self.risers.count - 1 - index]
                    logo(code, place.size)
                        .position(x: width * place.x + place.size / 2, y: height * place.y + place.size / 2)
                }
                ForEach(Array(teamCodes.dropFirst(3).prefix(3).enumerated()), id: \.offset) { index, code in
                    let place = Self.fallers[index]
                    logo(code, place.size)
                        .position(x: width * (1 - place.x) - place.size / 2, y: height * place.y + place.size / 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: PromptArt.height)
        .background(Theme.surface)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power Rankings")
    }

    private func logo(_ code: String, _ size: CGFloat) -> some View {
        TeamLogo(code: code, size: size)
            .shadow(color: .black.opacity(0.7), radius: 5, x: 0, y: 5)
    }

    private func arrow(color: Color, height: CGFloat) -> some View {
        BlockArrow()
            .fill(color.opacity(0.3))
            .frame(width: height * 2 / 3, height: height)
    }
}

/// A block arrow pointing up, as the web's `BlockArrow` draws it.
private struct BlockArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width / 24
        let h = rect.height / 36
        var path = Path()
        path.move(to: CGPoint(x: 12 * w, y: 0))
        path.addLine(to: CGPoint(x: 24 * w, y: 15 * h))
        path.addLine(to: CGPoint(x: 16 * w, y: 15 * h))
        path.addLine(to: CGPoint(x: 16 * w, y: 36 * h))
        path.addLine(to: CGPoint(x: 8 * w, y: 36 * h))
        path.addLine(to: CGPoint(x: 8 * w, y: 15 * h))
        path.addLine(to: CGPoint(x: 0, y: 15 * h))
        path.closeSubpath()
        return path
    }
}

// MARK: - A ranked team

/// How a team moved since the viewer's last ballot, on a cream tab.
private struct MovementBadge: View {
    let movement: PowerRankingMovement
    var width: CGFloat = 44
    var height: CGFloat = rankRowHeight

    var body: some View {
        Text(text)
            .font(.mono(width < 40 ? 11 : 12, weight: .bold))
            .foregroundStyle(color)
            .minimumScaleFactor(0.7)
            .lineLimit(1)
            .frame(width: width, height: height)
            .background(Color(hex: 0xF7F5EE))
            .accessibilityLabel(spoken)
    }

    // The web prints the same em dash for "no change" and "new".
    private var text: String {
        switch movement {
        case .up(let places): "+\(places)"
        case .down(let places): "-\(places)"
        case .unchanged, .new: "—"
        }
    }

    private var color: Color {
        switch movement {
        case .up: Theme.gradeElite
        case .down: Theme.gradeRough
        case .unchanged, .new: Theme.panelMuted
        }
    }

    private var spoken: String {
        switch movement {
        case .up(let places): "Up \(places)"
        case .down(let places): "Down \(places)"
        case .unchanged: "No change"
        case .new: "New"
        }
    }
}

/// One team at one place in a ranking: its number, its mark and name, and — on
/// the tab at the end — how far it moved since last time.
private struct PowerRankRow: View {
    let rank: Int
    let option: PromptOption
    var movement: PowerRankingMovement?
    /// Present only while composing; a tap sends the team back to the pool.
    var onRemove: (() -> Void)?
    /// Half a board wide, as on the web's 10- and 32-team boards: the mark and
    /// the team's code, not its name.
    var compact = false
    /// A grip cell at the trailing edge; the board lays the drag gesture over it.
    var grip = false

    private var height: CGFloat { compact ? 48 : rankRowHeight }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(.slab(compact ? 20 : 26))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: compact ? 30 : 40, height: height)
                .background(Color.black.opacity(0.45))
            HStack(spacing: compact ? 4 : 8) {
                PowerTeamMark(option: option, size: compact ? 32 : 40)
                Text(compact ? (option.teamCode ?? option.label) : option.label)
                    .font(compact ? .mono(12, weight: .bold) : .sans(17, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityLabel(option.label)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 5 : 8)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 36, height: height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove \(option.label)")
            }
            if let movement {
                MovementBadge(movement: movement, width: compact ? 34 : 44, height: height)
            }
            if grip { GripGlyph(width: GripGlyph.fullWidth, height: height) }
        }
        .frame(height: height)
        .background(teamGradient(option.teamCode))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Making a ballot

/// A ranked team on the thirty-two-team board, where a column is under ninety
/// points wide: its number, a logo and the movement tab, no name.
private struct TinyRankCell: View {
    let rank: Int
    let option: PromptOption
    var movement: PowerRankingMovement?
    var grip = false

    private let height: CGFloat = 48

    var body: some View {
        HStack(spacing: 0) {
            Text("\(rank)")
                .font(.slab(16))
                .foregroundStyle(.white)
                .monospacedDigit()
                .frame(width: 24, height: height)
                .background(Color.black.opacity(0.45))
            PowerTeamMark(option: option, size: 40)
                .frame(maxWidth: .infinity)
                .clipped()
            if let movement {
                MovementBadge(movement: movement, width: 24, height: height)
            }
            if grip { GripGlyph(width: GripGlyph.tinyWidth, height: height) }
        }
        .frame(height: height)
        .background(teamGradient(option.teamCode))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rank), \(option.label)")
    }
}

/// Composing a ballot: choose how deep to go, tap teams into the ranking, drag
/// the rows into order. A ballot is complete when every place is filled.
struct PowerRankingsPicker: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost
    var body: some View {
        if let slot = post.slots.first {
            let chosen = viewModel.selection(in: slot.id, of: post.id)
            let depth = viewModel.rankDepth(for: post.id)
            let optionById = Dictionary(slot.options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(text: "Your power rankings", trailing: "\(chosen.count)/\(depth) ranked")
                    Text(depth > 10
                        ? "Tap teams to add them, drag by the grip to reorder, tap a placed team to remove it."
                        : "Tap teams to add them, then drag the rows by their grips into order.")
                        .font(.sans(14)).foregroundStyle(Theme.fgMuted)
                }
                depthPicker(depth)
                ranking(slot: slot, chosen: chosen, optionById: optionById, depth: depth)
                    .reorderSpace { raw, index in
                        guard let id = UUID(uuidString: raw), let from = chosen.firstIndex(of: id) else { return }
                        viewModel.moveRanked(from: from, to: min(index, chosen.count - 1), in: slot.id, of: post.id)
                    }
                pool(slot: slot, chosen: chosen, depth: depth)
            }
        }
    }

    private func depthPicker(_ depth: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(PromptPost.powerRankingDepths, id: \.self) { count in
                let isSelected = depth == count
                Button {
                    viewModel.setRankDepth(count, for: post.id)
                } label: {
                    Text(count == 32 ? "All 32" : "Top \(count)")
                        .monoLabel(11, weight: .bold, tracking: 0.1, color: isSelected ? Theme.panelFg : Theme.fgMuted)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(isSelected ? Theme.hidden : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(isSelected ? Color.clear : Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityLabel("Number of teams to rank")
    }

    /// Every place is on the board from the start, as on the web: the ranked
    /// teams fill it from the top and the places not yet chosen are numbered,
    /// dashed slots after them. A ranked row is dragged onto another place to
    /// move it there; dropping on an empty place moves it to the end.
    private func ranking(slot: PromptSlot, chosen: [UUID], optionById: [UUID: PromptOption], depth: Int) -> some View {
        RankBoard(size: depth) { index, density in
            place(index, density: density, slot: slot, chosen: chosen, optionById: optionById)
        }
    }

    private func place(
        _ index: Int, density: RankDensity, slot: PromptSlot, chosen: [UUID], optionById: [UUID: PromptOption]
    ) -> some View {
        Group {
            if chosen.indices.contains(index), let option = optionById[chosen[index]] {
                rankedTeam(index, option: option, density: density, slot: slot)
                    .overlay(alignment: .trailing) {
                        Color.clear.frame(width: density == .tiny ? GripGlyph.tinyWidth : GripGlyph.fullWidth)
                            .reorderGrip(
                                item: option.id.uuidString,
                                preview: rankedTeam(index, option: option, density: .compact, slot: slot)
                            )
                    }
            } else {
                EmptyRankSlot(rank: index + 1, density: density)
            }
        }
        .reorderSlot(index)
    }

    @ViewBuilder
    private func rankedTeam(_ index: Int, option: PromptOption, density: RankDensity, slot: PromptSlot) -> some View {
        let movement = PowerRankingMovement(
            previous: option.teamCode.flatMap { post.previousRankByTeam[$0] }, current: index + 1
        )
        let remove = { viewModel.toggle(option.id, in: slot.id, of: post.id) }
        switch density {
        case .full:
            PowerRankRow(rank: index + 1, option: option, movement: movement, onRemove: remove, grip: true)
        case .compact:
            PowerRankRow(rank: index + 1, option: option, movement: movement, onRemove: remove, compact: true, grip: true)
        case .tiny:
            TinyRankCell(rank: index + 1, option: option, movement: movement, grip: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: remove)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Removes \(option.label) from your ranking")
        }
    }

    /// The teams not yet ranked, as on the web: a ticket-shaped card with the
    /// logo cropped large behind a "+", four across with smaller cut corners
    /// than the web's. The team's name is the accessibility label only.
    private func pool(slot: PromptSlot, chosen: [UUID], depth: Int) -> some View {
        let available = slot.options.filter { !chosen.contains($0.id) }
        let isFull = chosen.count >= depth
        return VStack(alignment: .leading, spacing: 8) {
            Text("Available teams").monoLabel(10, tracking: 0.1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(available) { option in
                    Button {
                        viewModel.toggle(option.id, in: slot.id, of: post.id)
                    } label: {
                        PowerTeamMark(option: option, size: 64)
                            .shadow(color: .black.opacity(0.5), radius: 4, y: 4)
                            .frame(maxWidth: .infinity, minHeight: rankRowHeight, maxHeight: rankRowHeight)
                            .clipped()
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "plus")
                                    .font(.system(size: 15, weight: .black))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .padding(.trailing, 10)
                                    .padding(.bottom, 4)
                            }
                            .background(teamGradient(option.teamCode))
                            .clipShape(TicketShape(cutX: 14, cutY: 8))
                            .overlay(TicketShape(cutX: 14, cutY: 8).stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .contentShape(TicketShape(cutX: 14, cutY: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isFull)
                    .opacity(isFull ? 0.4 : 1)
                    .accessibilityLabel("Add \(option.label)")
                }
            }
            if available.isEmpty {
                Text("Every team is ranked.").monoLabel(10, tracking: 0.08)
            }
        }
    }
}

// MARK: - After the ballot

/// A saved ballot as a board — the viewer's own by default, with how each team
/// moved since their last one. It is drawn on the same `RankBoard` as the
/// ballot being made, so five teams are a column of full rows, ten two columns
/// and thirty-two four.
struct PowerRankingsBoard: View {
    let post: PromptPost
    /// Whose ballot to draw; the viewer's when nil.
    var response: [UUID: [UUID]]?
    /// Movement is measured against the viewer's own last ballot, so it is
    /// meaningful only on a board the viewer made.
    var showsMovement = true

    var body: some View {
        if let slot = post.slots.first {
            let optionById = Dictionary(slot.options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ranked = ((response ?? post.viewerResponse)?[slot.id] ?? []).compactMap { optionById[$0] }
            if !ranked.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    RankBoard(size: ranked.count, places: ranked.count) { index, density in
                        let movement = showsMovement
                            ? PowerRankingMovement(previous: ranked[index].teamCode.flatMap { post.previousRankByTeam[$0] }, current: index + 1)
                            : nil
                        if density == .tiny {
                            TinyRankCell(rank: index + 1, option: ranked[index], movement: movement)
                        } else {
                            PowerRankRow(rank: index + 1, option: ranked[index], movement: movement, compact: density == .compact)
                        }
                    }
                    PowerRankingCrowdLine(post: post, slot: slot, ranked: ranked)
                }
            }
        }
    }
}

/// Under a ballot: the crowd's top five as small logos, dimmed where the ballot
/// left that team out of its own top five, and how many it matched. It stands
/// in for the crowd panel that used to sit between the cards.
struct PowerRankingCrowdLine: View {
    let post: PromptPost
    let slot: PromptSlot
    let ranked: [PromptOption]

    /// How many of the crowd's top-five teams this ballot also has in its top five.
    static func matched(crowd: [UUID], ranked: [UUID]) -> Int {
        let mine = Set(ranked.prefix(5))
        return crowd.filter(mine.contains).count
    }

    var body: some View {
        let optionById = Dictionary(slot.options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let crowd = post.powerRankingTopFive.compactMap { optionById[$0.optionId] }
        if !crowd.isEmpty {
            let mine = Set(ranked.prefix(5).map(\.id))
            let matched = Self.matched(crowd: crowd.map(\.id), ranked: ranked.map(\.id))
            VStack(alignment: .leading, spacing: 8) {
                LineRule()
                HStack(spacing: 6) {
                    Text("Crowd's top 5").monoLabel(10, tracking: 0.1)
                    Spacer(minLength: 8)
                    ForEach(crowd) { option in
                        PowerTeamMark(option: option, size: 26)
                            .opacity(mine.contains(option.id) ? 1 : 0.35)
                    }
                    Text("matched \(matched) of \(crowd.count)").monoLabel(10, tracking: 0.06)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The crowd's top five: \(crowd.map(\.label).joined(separator: ", ")). This ballot matched \(matched) of \(crowd.count).")
        }
    }
}

/// What a Power Rankings post shows about the crowd once it is revealed: the
/// most common top five. The viewer's own board is `PowerRankingsBoard`, in
/// their card; other people's individual ballots stay theirs — they show only
/// as the takes they were posted with.
struct PowerRankingsResults: View {
    let post: PromptPost

    var body: some View {
        if let slot = post.slots.first {
            consensus(slot)
        }
    }

    @ViewBuilder
    private func consensus(_ slot: PromptSlot) -> some View {
        let optionById = Dictionary(slot.options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = post.powerRankingTopFive.compactMap { entry in
            optionById[entry.optionId].map { (entry, $0) }
        }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(
                    text: "Most common top 5",
                    trailing: "\(post.responseCount) \(post.responseCount == 1 ? "ballot" : "ballots")"
                )
                ForEach(Array(entries.enumerated()), id: \.element.0.optionId) { index, pair in
                    let (entry, option) = pair
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.slab(22))
                            .foregroundStyle(Theme.fgMuted)
                            .monospacedDigit()
                            .frame(width: 22)
                        PowerTeamMark(option: option, size: 30)
                        Text(option.label).font(.sans(17, weight: .semibold)).foregroundStyle(Theme.fg)
                        Spacer()
                        Text(String(format: "avg %.1f", entry.averageRank)).monoLabel(10, tracking: 0.06)
                        Text("\(percent(entry))%")
                            .font(.mono(14, weight: .bold))
                            .foregroundStyle(Theme.fg)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(14)
            .well()
        }
    }

    /// The share of ballots that put the team in their top five.
    private func percent(_ entry: PowerRankingConsensusEntry) -> Int {
        guard post.responseCount > 0 else { return 0 }
        return Int((Double(entry.topFiveCount) / Double(post.responseCount) * 100).rounded())
    }
}

/// Somebody's saved ballot as a take shows it: the same team rows as the
/// viewer's own card, less the movement tab — that compares against the
/// viewer's last ballot, which says nothing about theirs.
struct PowerRankingTicket: View {
    let post: PromptPost
    let response: [UUID: [UUID]]

    var body: some View {
        PowerRankingsBoard(post: post, response: response, showsMovement: false)
    }
}
