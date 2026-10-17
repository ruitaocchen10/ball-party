import SwiftUI

// Weekly Awards on iOS: the six-award, opinion-only slate the web draws in
// `WeeklyAwards.tsx`. Same rules, phone-shaped controls. Presentation only —
// what a tap does and what makes a ballot complete is `HuddleViewModel`'s, and
// the server's (`submit_response`, 0175).

// MARK: - Tiles

/// A whole game as a choice — the web's `MatchupTile` — tagging the game rather
/// than a side. Both halves flood with their club's color when chosen; the other
/// games fade back.
struct AwardGameTile: View {
    let away: String
    let home: String
    let label: String
    var state: ChoiceTileState = .idle
    let action: () -> Void

    private var selected: Bool { state == .selected }

    var body: some View {
        Button(action: action) {
            TwoSidedFace {
                half(away)
            } home: {
                half(home)
            }
            .choiceTile(mark: ChoiceMark(selected: selected))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func half(_ code: String) -> some View {
        ChoiceHalf(code: code, flooded: selected, receded: state == .dimmed)
    }
}

// MARK: - Answering

/// The six awards: teams and the game are chosen from their options, the three
/// players are searched for. A tap on the chosen team or game clears it. Like
/// the web, one award is open at a time: the rest collapse to a row that says
/// what was picked (with Edit) or that nothing is yet (with Pick), and choosing
/// hands over to the next award still waiting for an answer.
struct WeeklyAwardsPicker: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    @State private var openSlot: UUID?
    @State private var started = false

    private let teamColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    private let gameColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(post.slots) { slot in
                if openSlot == slot.id {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(slot.label)
                            .font(.slab(15, relativeTo: .body))
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.fgMuted)
                            .accessibilityAddTraits(.isHeader)
                        input(for: slot)
                    }
                } else {
                    collapsedRow(slot)
                }
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            openSlot = post.slots.first { !isAnswered($0) }?.id
        }
    }

    private func isAnswered(_ slot: PromptSlot) -> Bool {
        slot.playerSearch
            ? viewModel.player(in: slot.id, of: post.id) != nil
            : !viewModel.selection(in: slot.id, of: post.id).isEmpty
    }

    /// Closes `slot` once it has an answer and opens the next award still waiting for one.
    private func advance(from slot: PromptSlot) {
        guard isAnswered(slot), let index = post.slots.firstIndex(where: { $0.id == slot.id }) else { return }
        let others = post.slots[(index + 1)...] + post.slots[..<index]
        openSlot = others.first { !isAnswered($0) }?.id
    }

    private func choose(_ option: PromptOption, in slot: PromptSlot) {
        viewModel.toggle(option.id, in: slot.id, of: post.id)
        advance(from: slot)
    }

    private func collapsedRow(_ slot: PromptSlot) -> some View {
        let player = slot.playerSearch ? viewModel.player(in: slot.id, of: post.id) : nil
        let option = viewModel.selection(in: slot.id, of: post.id).first.flatMap { id in slot.options.first { $0.id == id } }
        let summary = player?.name ?? option?.label
        return HStack(spacing: 10) {
            if let player {
                Portrait(name: player.name, url: player.headshotURL, size: 32)
            } else if let option {
                AwardOptionIcon(option: option, slot: slot, size: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.label).monoLabel(10, tracking: 0.08, color: Theme.fgMuted)
                Text(summary ?? "Not picked yet")
                    .font(.slab(18, relativeTo: .body))
                    .textCase(.uppercase)
                    .foregroundStyle(summary == nil ? Theme.fgMuted : Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            Button(summary == nil ? "Pick" : "Edit") { openSlot = slot.id }
                .font(.mono(11, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.fg)
                .underline()
                .accessibilityLabel("\(summary == nil ? "Pick" : "Edit") \(slot.label)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func input(for slot: PromptSlot) -> some View {
        let chosen = viewModel.selection(in: slot.id, of: post.id).first
        if slot.playerSearch {
            PlayerPickerView(
                label: slot.label,
                selection: viewModel.player(in: slot.id, of: post.id),
                search: { try await viewModel.searchPlayers($0) },
                onSelect: {
                    viewModel.setPlayer($0, in: slot.id, of: post.id)
                    advance(from: slot)
                }
            )
        } else if !slot.options.isEmpty, slot.options.allSatisfy({ $0.gameTeamCodes != nil }) {
            LazyVGrid(columns: gameColumns, spacing: 8) {
                ForEach(slot.options) { option in
                    if let game = option.gameTeamCodes {
                        AwardGameTile(
                            away: game.away, home: game.home, label: option.label,
                            state: ChoiceTileState(chosen: chosen, option: option.id)
                        ) { choose(option, in: slot) }
                    }
                }
            }
        } else if !slot.options.isEmpty, slot.options.allSatisfy({ $0.teamCode != nil }) {
            LazyVGrid(columns: teamColumns, spacing: 6) {
                ForEach(slot.options) { option in
                    TeamChoiceTile(
                        code: option.teamCode ?? "", name: option.label,
                        state: ChoiceTileState(chosen: chosen, option: option.id)
                    ) { choose(option, in: slot) }
                }
            }
        } else {
            SlotPicker(viewModel: viewModel, post: post, slot: slot)
        }
    }
}

// MARK: - After answering

/// What an award option looks like as a small mark: a player's headshot, both
/// clubs of a game, or a club's logo.
struct AwardOptionIcon: View {
    let option: PromptOption
    let slot: PromptSlot
    var size: CGFloat = 44

    var body: some View {
        if slot.playerSearch {
            Portrait(name: option.label, url: option.headshotURL, size: size)
        } else if let game = option.gameTeamCodes {
            HStack(spacing: -size * 0.2) {
                TeamLogo(code: game.away, size: size * 0.7)
                TeamLogo(code: game.home, size: size * 0.7)
            }
            .frame(width: size, height: size)
        } else if let code = option.teamCode {
            TeamLogo(code: code, size: size)
        } else {
            OptionBadge(option: option, size: size)
        }
    }
}

/// A saved Weekly Awards ballot: a row per award, flooded with the colour of
/// the team chosen, and the share of respondents who chose the same once known.
struct WeeklyAwardsBallot: View {
    let post: PromptPost
    let response: [UUID: [UUID]]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(post.slots) { slot in
                row(slot)
            }
        }
    }

    private func row(_ slot: PromptSlot) -> some View {
        let option = response[slot.id]?.first.flatMap { id in slot.options.first { $0.id == id } }
        let code = option.flatMap { $0.teamCode ?? $0.gameTeamCodes?.away }
        let color = code.flatMap(NFLTeams.primaryColor(for:))
        let percent = option.flatMap { post.aggregate?[slot.id]?[$0.id] }
        let onTeamColor = color != nil
        let crowd = option == nil ? nil : WeeklyAwardsResults.topPicks(in: slot, shares: post.aggregate?[slot.id]).first
        let softColor = onTeamColor ? Color.white.opacity(0.75) : Theme.fgMuted
        return HStack(spacing: 12) {
            if let option { AwardOptionIcon(option: option, slot: slot, size: 52) }
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.label).monoLabel(9, tracking: 0.08, color: onTeamColor ? Color.white.opacity(0.7) : Theme.fgMuted)
                Text(option?.label ?? "—")
                    .slabTitle(24, color: onTeamColor ? .white : Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let crowd {
                    // Where the crowd landed, so the share beside the pick has something to compare with.
                    if (percent ?? 0) >= crowd.percent {
                        Text("Crowd's pick").monoLabel(9, weight: .bold, tracking: 0.08, color: onTeamColor ? .white : Theme.fg)
                    } else {
                        Text("Leader: \(crowd.option.label) \(Int(crowd.percent.rounded()))%")
                            .font(.sans(13))
                            .foregroundStyle(softColor)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 8)
            if let percent {
                Text("\(Int(percent.rounded()))%")
                    .font(.mono(13, weight: .bold))
                    .foregroundStyle(onTeamColor ? Color.white.opacity(0.85) : Theme.fgMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if let color {
                LinearGradient(colors: [color, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                Theme.surfaceRaised
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(color == nil ? Theme.line : Color.white.opacity(0.2), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Per-award results: the options chosen most often and their share of the
/// respondents.
struct WeeklyAwardsResults: View {
    let post: PromptPost

    /// How many leaders each award lists.
    static let picksShown = 3

    /// The options chosen most often in a slot, highest share first, ties
    /// alphabetical. An option nobody chose is not a leader.
    static func topPicks(in slot: PromptSlot, shares: [UUID: Double]?) -> [(option: PromptOption, percent: Double)] {
        var leaders: [(option: PromptOption, percent: Double)] = []
        for option in slot.options {
            let percent = shares?[option.id] ?? 0
            if percent > 0 { leaders.append((option, percent)) }
        }
        leaders.sort { left, right in
            left.percent != right.percent ? left.percent > right.percent : left.option.label < right.option.label
        }
        return Array(leaders.prefix(picksShown))
    }

    var body: some View {
        if let aggregate = post.aggregate {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: "How everyone voted")
                ForEach(post.slots) { slot in
                    AwardLeaders(slot: slot, picks: Self.topPicks(in: slot, shares: aggregate[slot.id]))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// One award's leaders, or a note that nobody has voted yet.
private struct AwardLeaders: View {
    let slot: PromptSlot
    let picks: [(option: PromptOption, percent: Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(slot.label).monoLabel(10, tracking: 0.1)
            if picks.isEmpty {
                Text("No votes yet.").font(.sans(14)).foregroundStyle(Theme.fgMuted)
            }
            ForEach(picks, id: \.option.id) { pick in
                leader(pick.option, percent: pick.percent)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func leader(_ option: PromptOption, percent: Double) -> some View {
        HStack(spacing: 8) {
            AwardOptionIcon(option: option, slot: slot, size: 28)
            Text(option.label)
                .font(.slab(17, relativeTo: .body))
                .textCase(.uppercase)
                .foregroundStyle(Theme.fg)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text("\(Int(percent.rounded()))%")
                .font(.mono(12, weight: .bold))
                .foregroundStyle(Theme.fgMuted)
        }
    }
}
