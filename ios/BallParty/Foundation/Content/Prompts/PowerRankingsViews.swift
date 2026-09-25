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
private let rankRowHeight: CGFloat = 56

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

/// The feed card's art: six teams the admin chose, in placement order — two
/// large in the top corners, two large in the bottom, a smaller pair between —
/// behind the title, with green climbing on one side and red falling on the
/// other. It is the same for every viewer.
struct PowerRankingsCover: View {
    let teamCodes: [String]

    private static let red = Color(hex: 0xEF4444)
    private static let green = Color(hex: 0x4ADE80)

    var body: some View {
        PromptTicket {
            ZStack {
                HStack(spacing: 0) {
                    LinearGradient(colors: [Self.green.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, Self.red.opacity(0.16)], startPoint: .leading, endPoint: .trailing)
                }
                chevrons
                logo(0, size: 92, angle: -18, opacity: 0.9, alignment: .topLeading, x: -14, y: -6)
                logo(1, size: 92, angle: 18, opacity: 0.9, alignment: .topTrailing, x: 14, y: -6)
                logo(2, size: 92, angle: 14, opacity: 0.75, alignment: .bottomLeading, x: -14, y: 6)
                logo(3, size: 92, angle: -14, opacity: 0.75, alignment: .bottomTrailing, x: 6, y: 6)
                logo(4, size: 60, angle: 12, opacity: 0.75, alignment: .leading, x: 58, y: 0)
                logo(5, size: 60, angle: -12, opacity: 0.75, alignment: .trailing, x: -58, y: 0)
                title
            }
            .frame(height: 208)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Power Rankings")
    }

    private var title: some View {
        VStack(spacing: 4) {
            Text("NFL · Your order").monoLabel(9, weight: .bold, tracking: 0.2, color: .white)
            VStack(spacing: -6) {
                Text("Power").slabTitle(48, color: .white)
                Text("Rankings").slabTitle(48, color: Self.red)
            }
            Text("Top 5 · Top 10 · All 32").monoLabel(9, tracking: 0.12, color: Color(hex: 0xFFF8E4, opacity: 0.85))
        }
        .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 64)
    }

    private var chevrons: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 2) {
                ForEach([0.7, 0.45, 0.25], id: \.self) { opacity in
                    Image(systemName: "chevron.up").font(.system(size: 26, weight: .black)).foregroundStyle(Self.green.opacity(opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 14).padding(.top, 8)
            VStack(alignment: .trailing, spacing: 2) {
                ForEach([0.25, 0.45, 0.7], id: \.self) { opacity in
                    Image(systemName: "chevron.down").font(.system(size: 26, weight: .black)).foregroundStyle(Self.red.opacity(opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 14).padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func logo(
        _ index: Int, size: CGFloat, angle: Double, opacity: Double, alignment: Alignment, x: CGFloat, y: CGFloat
    ) -> some View {
        if teamCodes.indices.contains(index) {
            TeamLogo(code: teamCodes[index], size: size)
                .rotationEffect(.degrees(angle))
                .opacity(opacity)
                .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 6)
                .offset(x: x, y: y)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        }
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
        }
        .frame(height: height)
        .background(teamGradient(option.teamCode))
        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Making a ballot

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
                    Text("Tap teams to add them, then drag the rows into order.")
                        .font(.sans(14)).foregroundStyle(Theme.fgMuted)
                }
                depthPicker(depth)
                ranking(slot: slot, chosen: chosen, optionById: optionById, depth: depth)
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
                        .background(isSelected ? Theme.panel : Theme.surface)
                        .overlay(Rectangle().strokeBorder(isSelected ? Color.clear : Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityLabel("Number of teams to rank")
    }

    /// The ranked rows, in a `List` for its drag-to-reorder. The list sits
    /// inside the screen's own scroll view, so it is sized to its rows and
    /// doesn't scroll itself; edit mode is what turns on the drag handles.
    @ViewBuilder
    private func ranking(slot: PromptSlot, chosen: [UUID], optionById: [UUID: PromptOption], depth: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !chosen.isEmpty {
                List {
                    ForEach(Array(chosen.enumerated()), id: \.element) { index, optionId in
                        if let option = optionById[optionId] {
                            PowerRankRow(
                                rank: index + 1,
                                option: option,
                                movement: PowerRankingMovement(
                                    previous: option.teamCode.flatMap { post.previousRankByTeam[$0] }, current: index + 1
                                ),
                                onRemove: { viewModel.toggle(optionId, in: slot.id, of: post.id) }
                            )
                            .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .deleteDisabled(true)
                        }
                    }
                    .onMove { source, destination in
                        guard let from = source.first else { return }
                        // `onMove` hands over the gap dropped into; the view model
                        // takes the place the row ends up in.
                        viewModel.moveRanked(
                            from: from, to: destination > from ? destination - 1 : destination, in: slot.id, of: post.id
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .environment(\.editMode, .constant(.active))
                .frame(height: CGFloat(chosen.count) * (rankRowHeight + 6))
            }
            if chosen.count < depth {
                Text(chosen.isEmpty ? "Choose \(depth) teams below" : "Choose \(depth - chosen.count) more below")
                    .monoLabel(10, tracking: 0.08)
                    .frame(maxWidth: .infinity, minHeight: rankRowHeight, alignment: .center)
                    .overlay(Rectangle().strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4])))
            }
        }
    }

    private func pool(slot: PromptSlot, chosen: [UUID], depth: Int) -> some View {
        let available = slot.options.filter { !chosen.contains($0.id) }
        let isFull = chosen.count >= depth
        return VStack(alignment: .leading, spacing: 8) {
            Text("Available teams").monoLabel(10, tracking: 0.1)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(available) { option in
                    Button {
                        viewModel.toggle(option.id, in: slot.id, of: post.id)
                    } label: {
                        HStack(spacing: 8) {
                            PowerTeamMark(option: option, size: 36)
                            Text(option.label)
                                .font(.sans(15, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                            Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(teamGradient(option.teamCode))
                        .overlay(Rectangle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                        .contentShape(Rectangle())
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

/// The viewer's saved ballot as a board, with how each team moved since their
/// last one. As on the web it takes the width it needs: five teams are a
/// single column of full rows, ten or thirty-two two columns of compact ones,
/// reading down the left and then down the right.
struct PowerRankingsBoard: View {
    let post: PromptPost

    var body: some View {
        if let slot = post.slots.first {
            let optionById = Dictionary(slot.options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ranked = (post.viewerResponse?[slot.id] ?? []).compactMap { optionById[$0] }
            if !ranked.isEmpty {
                let columns = ranked.count > 5 ? 2 : 1
                let perColumn = (ranked.count + columns - 1) / columns
                HStack(alignment: .top, spacing: 6) {
                    ForEach(0..<columns, id: \.self) { column in
                        VStack(spacing: 6) {
                            ForEach(column * perColumn ..< min(ranked.count, (column + 1) * perColumn), id: \.self) { index in
                                PowerRankRow(
                                    rank: index + 1,
                                    option: ranked[index],
                                    movement: PowerRankingMovement(
                                        previous: ranked[index].teamCode.flatMap { post.previousRankByTeam[$0] },
                                        current: index + 1
                                    ),
                                    compact: columns == 2
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
            }
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

/// Somebody's saved ballot as a take shows it: their order as a compact grid of
/// `1 KC` chips, since a take card is no place for thirty-two rows.
struct PowerRankingTicket: View {
    let post: PromptPost
    let response: [UUID: [UUID]]

    var body: some View {
        if let slot = post.slots.first {
            let optionById = Dictionary(slot.options.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let ranked = (response[slot.id] ?? []).compactMap { optionById[$0] }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, option in
                    HStack(spacing: 5) {
                        Text("\(index + 1)").font(.mono(11, weight: .bold)).foregroundStyle(Theme.fgMuted)
                        Text(option.teamCode ?? option.label).font(.mono(12, weight: .bold)).foregroundStyle(Theme.fg)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                    .padding(.horizontal, 8)
                    .background(Theme.surface)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Ranked " + ranked.enumerated().map { "\($0.offset + 1), \($0.element.label)" }.joined(separator: "; ")
            )
        }
    }
}
