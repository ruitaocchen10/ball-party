import SwiftUI

// Weekly Awards on iOS: the six-award, opinion-only slate the web draws in
// `WeeklyAwards.tsx`. Same rules, phone-shaped controls. Presentation only —
// what a tap does and what makes a ballot complete is `HuddleViewModel`'s, and
// the server's (`submit_response`, 0175).

// MARK: - Tiles

/// How a tile in a group of choices looks: nothing chosen yet, this one chosen,
/// or another one chosen.
enum ChoiceTileState {
    case idle, selected, dimmed

    init(chosen: UUID?, option: UUID) {
        self = chosen == nil ? .idle : chosen == option ? .selected : .dimmed
    }
}

/// A club as a tile: its logo over its name, flooded with its colour when chosen.
struct AwardTeamTile: View {
    let code: String
    let name: String
    var state: ChoiceTileState = .idle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                TeamLogo(code: code, size: 44)
                Text(name)
                    .font(.sans(12, weight: .semibold))
                    .foregroundStyle(state == .selected ? Color.white : Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(background)
            .overlay(Rectangle().strokeBorder(state == .selected ? Color.clear : Theme.line, lineWidth: 1))
            .opacity(state == .dimmed ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }

    @ViewBuilder
    private var background: some View {
        if state == .selected, let color = NFLTeams.primaryColor(for: code) {
            LinearGradient(colors: [color, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            Theme.surfaceRaised
        }
    }
}

/// A game as a tile: both clubs' logos and the matchup in words.
struct AwardGameTile: View {
    let away: String
    let home: String
    let label: String
    var state: ChoiceTileState = .idle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                TeamLogo(code: away, size: 40)
                Text("@").font(.mono(11, weight: .bold)).foregroundStyle(state == .selected ? Theme.panelMuted : Theme.fgMuted)
                TeamLogo(code: home, size: 40)
                Text(label)
                    .font(.slab(18, relativeTo: .body))
                    .textCase(.uppercase)
                    .foregroundStyle(state == .selected ? Theme.panelFg : Theme.fg)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(state == .selected ? Theme.panel : Theme.surfaceRaised)
            .overlay(Rectangle().strokeBorder(state == .selected ? Color.clear : Theme.line, lineWidth: 1))
            .opacity(state == .dimmed ? 0.45 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(state == .selected ? .isSelected : [])
    }
}

// MARK: - Answering

/// The six awards: teams and the game are chosen from their options, the three
/// players are searched for. A tap on the chosen team or game clears it.
struct WeeklyAwardsPicker: View {
    @ObservedObject var viewModel: HuddleViewModel
    let post: PromptPost

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(post.slots) { slot in
                VStack(alignment: .leading, spacing: 8) {
                    Text(slot.label)
                        .font(.slab(15, relativeTo: .body))
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.fgMuted)
                        .accessibilityAddTraits(.isHeader)
                    input(for: slot)
                }
            }
        }
    }

    @ViewBuilder
    private func input(for slot: PromptSlot) -> some View {
        let chosen = viewModel.selection(in: slot.id, of: post.id).first
        if slot.playerSearch {
            PlayerPickerView(
                label: slot.label,
                selection: viewModel.player(in: slot.id, of: post.id),
                search: { try await viewModel.searchPlayers($0) },
                onSelect: { viewModel.setPlayer($0, in: slot.id, of: post.id) }
            )
        } else if !slot.options.isEmpty, slot.options.allSatisfy({ $0.gameTeamCodes != nil }) {
            VStack(spacing: 8) {
                ForEach(slot.options) { option in
                    if let game = option.gameTeamCodes {
                        AwardGameTile(
                            away: game.away, home: game.home, label: option.label,
                            state: ChoiceTileState(chosen: chosen, option: option.id)
                        ) { viewModel.toggle(option.id, in: slot.id, of: post.id) }
                    }
                }
            }
        } else if !slot.options.isEmpty, slot.options.allSatisfy({ $0.teamCode != nil }) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(slot.options) { option in
                    AwardTeamTile(
                        code: option.teamCode ?? "", name: option.label,
                        state: ChoiceTileState(chosen: chosen, option: option.id)
                    ) { viewModel.toggle(option.id, in: slot.id, of: post.id) }
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
        return HStack(spacing: 12) {
            if let option { AwardOptionIcon(option: option, slot: slot, size: 52) }
            VStack(alignment: .leading, spacing: 4) {
                Text(slot.label).monoLabel(9, tracking: 0.08, color: onTeamColor ? Color.white.opacity(0.7) : Theme.fgMuted)
                Text(option?.label ?? "—")
                    .slabTitle(24, color: onTeamColor ? .white : Theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
        .overlay(Rectangle().strokeBorder(color == nil ? Theme.line : Color.white.opacity(0.2), lineWidth: 1))
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
