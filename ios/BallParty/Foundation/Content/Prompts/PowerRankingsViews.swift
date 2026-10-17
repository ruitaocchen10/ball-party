import SwiftUI

// Power Rankings on iOS: the weekly, opinion-only ranking of the league the web
// draws in `PromptPostUI.tsx` (`PowerRankingsBoard`), `SlotFaces.tsx`
// (`PowerRankingsSlot`) and `PromptContext.tsx` (the consensus rail). Same
// rules, phone-shaped controls: instead of dragging between a board and a pool,
// a player taps teams into the ranking and drags the rows to reorder them.
//
// Presentation only, like `PromptComponents`: what a tap does, how deep a
// ballot goes and what makes it complete is `HuddleViewModel`'s.

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

extension PromptOption {
    /// What a ranking draws for this option: the team, by its code and name.
    fileprivate var rankSubject: RankSubject { .team(code: teamCode ?? label, name: label) }
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
                    Text(depth > 10
                        ? "Tap a team to add it, or press and hold one and drag it to a place. Press and hold a row to reorder it; tap a placed team to remove it."
                        : "Tap a team to add it, or press and hold one and drag it to a place. Press and hold the rows to put them in order, tap a placed team to remove it.")
                        .font(.sans(14)).foregroundStyle(Theme.fgMuted)
                }
                depthPicker(depth)
                // The board and the pool share one space, so a team can be dragged from the
                // pool onto a place as well as tapped in.
                VStack(alignment: .leading, spacing: 16) {
                    ranking(slot: slot, chosen: chosen, optionById: optionById, depth: depth)
                    pool(slot: slot, chosen: chosen, depth: depth)
                }
                .reorderSpace { raw, index in
                    guard let id = UUID(uuidString: raw) else { return }
                    if let from = chosen.firstIndex(of: id) {
                        viewModel.moveRanked(from: from, to: min(index, chosen.count - 1), in: slot.id, of: post.id)
                    } else {
                        viewModel.insertRanked(id, at: index, in: slot.id, of: post.id)
                    }
                }
            }
        }
    }

    private func depthPicker(_ depth: Int) -> some View {
        PillChoice(
            selection: Binding(get: { depth }, set: { viewModel.setRankDepth($0, for: post.id) }),
            options: PromptPost.powerRankingDepths,
            title: { $0 == 32 ? "All 32" : "Top \($0)" },
            accessibilityName: "Number of teams to rank"
        )
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
                RankedRow(
                    rank: index + 1, subject: option.rankSubject, density: density,
                    movement: RankMovement(previous: option.teamCode.flatMap { post.previousRankByTeam[$0] }, current: index + 1),
                    onRemove: { viewModel.toggle(option.id, in: slot.id, of: post.id) },
                    dragItem: option.id.uuidString
                )
            } else {
                EmptyRankSlot(rank: index + 1, density: density)
            }
        }
        .reorderSlot(index)
    }

    /// The teams not yet ranked, as on the web: the shared team
    /// tile with a "+", four across. The team's name is the accessibility label only.
    /// Tapped to add at the end, or held and dragged to the place it should take.
    @ViewBuilder
    private func poolTile(_ option: PromptOption, slot: PromptSlot, isFull: Bool) -> some View {
        let tile = TeamChoiceTile(code: option.teamCode ?? option.label, name: option.label, adds: true) {
            viewModel.toggle(option.id, in: slot.id, of: post.id)
        }
        if isFull {
            tile.disabled(true)
        } else {
            tile.reorderHandle(item: option.id.uuidString, preview: tile)
        }
    }

    private func pool(slot: PromptSlot, chosen: [UUID], depth: Int) -> some View {
        let available = slot.options.filter { !chosen.contains($0.id) }
        let isFull = chosen.count >= depth
        return VStack(alignment: .leading, spacing: 8) {
            Text("Available teams").monoLabel(10, tracking: 0.1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(available) { option in
                    poolTile(option, slot: slot, isFull: isFull)
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
                        RankedRow(
                            rank: index + 1, subject: ranked[index].rankSubject, density: density,
                            movement: showsMovement
                                ? RankMovement(previous: ranked[index].teamCode.flatMap { post.previousRankByTeam[$0] }, current: index + 1)
                                : nil
                        )
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
