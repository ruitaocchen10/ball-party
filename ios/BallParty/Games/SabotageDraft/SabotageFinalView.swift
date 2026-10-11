import SwiftUI

/// The season's ending: seventeen simulated games boiled down to a record and a
/// letter grade per table, ranked best first. Each table expands into the
/// roster behind its grade, with every pick's own position-relative grade.
///
/// `tiebreak_rank` is only unique *within* a shared win count, so the rank shown
/// is the position after sorting by (wins, then tiebreak) — a total order, with
/// exactly one winner.
struct SabotageFinalView: View {
    @ObservedObject var viewModel: SabotageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var opened: Set<UUID> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Final").eyebrow()

                VStack(spacing: 12) {
                    ForEach(Array(viewModel.rankedStandings.enumerated()), id: \.element.userId) { index, standing in
                        standingCard(rank: index + 1, standing: standing)
                    }
                }

                tiebreaks

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
                postGameControls
            }
            .padding(16)
        }
    }

    // MARK: Standings

    private func standingCard(rank: Int, standing: SabotageStanding) -> some View {
        let player = viewModel.player(standing.userId)
        let mine = standing.userId == viewModel.viewerId
        let isOpen = opened.contains(standing.userId)
        let grade = SabotageRules.gradeForTeam(rosterStrength: standing.rosterStrength, mode: viewModel.mode)

        return PanelCard {
            VStack(spacing: 0) {
                Button {
                    if isOpen { opened.remove(standing.userId) } else { opened.insert(standing.userId) }
                } label: {
                    HStack(spacing: 12) {
                        Text("\(rank)").font(.slab(26)).foregroundStyle(Theme.panelMuted).frame(width: 28)
                        Avatar(name: player?.name ?? "Unknown", url: player?.avatarURL, size: 38, isMine: mine)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mine ? "You" : player?.name ?? "Unknown").slabTitle(20, color: Theme.panelFg).lineLimit(1)
                            Text("\(standing.wins)-\(standing.losses)").monoLabel(12, weight: .bold, tracking: 0.08, color: Theme.panelMuted)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("DRAFT GRADE").monoLabel(8, tracking: 0.12, color: Theme.panelMuted)
                            GradeBadge(grade: grade, large: true)
                        }
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.panelMuted)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(rank). \(mine ? "You" : player?.name ?? "Unknown"), \(standing.wins) and \(standing.losses), grade \(grade)")
                .accessibilityHint(isOpen ? "Collapses the roster" : "Shows the roster")

                if isOpen {
                    LineRule()
                    finalRoster(userId: standing.userId)
                        .padding(14)
                }
            }
        }
    }

    /// Every pick but the X-Factor, in round order — plus, when accepted, the
    /// X-Factor swap replacing the slot it targeted, with the replaced player
    /// struck through rather than just disappearing.
    private func finalRoster(userId: UUID) -> some View {
        let snapshot = viewModel.snapshot
        let picks = snapshot?.picks ?? []
        let avs = snapshot?.pickAvs ?? []
        let roundCount = viewModel.roundCount
        let decision = snapshot?.decisions.first { $0.userId == userId }
        let xFactorPick = decision?.replaceSlot != nil
            ? picks.first { $0.round == roundCount && $0.userId == userId }
            : nil

        func av(_ round: Int) -> SabotagePickAv? { avs.first { $0.round == round && $0.userId == userId } }

        return VStack(spacing: 8) {
            ForEach(Array(SabotageRules.rosterSlots(roundCount: roundCount).enumerated()), id: \.offset) { index, slot in
                let round = index + 1
                let pick = picks.first { $0.round == round && $0.userId == userId }
                let replaced = decision?.replaceSlot == slot
                let shown = replaced && xFactorPick != nil ? xFactorPick : pick
                let value = replaced && xFactorPick != nil ? av(roundCount) : av(round)
                HStack(spacing: 10) {
                    Text(SabotageRules.slotShort(slot))
                        .monoLabel(10, weight: .bold, tracking: 0.08, color: Theme.panelMuted)
                        .frame(width: 44, alignment: .leading)
                    if let shown {
                        Portrait(name: shown.name, url: shown.headshotURL, size: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(shown.name) · \(String(shown.season))")
                                .font(.sans(13, weight: .semibold)).foregroundStyle(Theme.panelFg).lineLimit(1)
                            if replaced, let pick {
                                Text(pick.name).font(.sans(11)).foregroundStyle(Theme.panelMuted).strikethrough().lineLimit(1)
                            }
                        }
                    } else {
                        Text("—").foregroundStyle(Theme.panelMuted)
                    }
                    Spacer(minLength: 4)
                    GradeBadge(
                        grade: shown != nil ? value.map {
                            SabotageRules.gradeForPick(slot: slot, av: $0.av, pickCategory: $0.category)
                        } : nil,
                        large: false
                    )
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Tiebreaks

    /// A saved tiebreak is a sequence of actual one-game matchups, not just an
    /// explanation for the final order. Each tied record keeps its own board.
    @ViewBuilder
    private var tiebreaks: some View {
        let games = viewModel.snapshot?.tiebreaks ?? []
        if !games.isEmpty {
            let records = Set(games.map(\.recordWins)).sorted(by: >)
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Tiebreak bracket")
                ForEach(records, id: \.self) { wins in
                    let ofRecord = games.filter { $0.recordWins == wins }
                    let rounds = Set(ofRecord.map(\.bracketRound)).sorted()
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(wins)-\(17 - wins) tiebreak").slabTitle(18)
                            Spacer()
                            Text("One-game playoff").monoLabel(9, tracking: 0.1)
                        }
                        ForEach(rounds, id: \.self) { round in
                            Text(round == rounds.last ? "Final" : "Round \(round)").monoLabel(9, weight: .bold, tracking: 0.14)
                            ForEach(ofRecord.filter { $0.bracketRound == round }.sorted { $0.gameNumber < $1.gameNumber }, id: \.gameNumber) { game in
                                bracketGame(game)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .well()
                }
            }
        }
    }

    @ViewBuilder
    private func bracketGame(_ game: SabotageTiebreak) -> some View {
        if let b = game.playerB {
            VStack(spacing: 0) {
                competitor(game.playerA, score: game.playerAScore, won: game.winnerUserId == game.playerA)
                competitor(b, score: game.playerBScore, won: game.winnerUserId == b)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        } else {
            HStack {
                Text(name(game.playerA)).font(.sans(14, weight: .semibold)).foregroundStyle(Theme.fg)
                Spacer()
                Text("Bye · advances").monoLabel(10, tracking: 0.08)
            }
            .padding(10)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        }
    }

    private func competitor(_ id: UUID, score: Int?, won: Bool) -> some View {
        HStack {
            Text(name(id)).font(.sans(14, weight: won ? .bold : .regular)).lineLimit(1)
            Spacer(minLength: 8)
            Text(score.map(String.init) ?? "—").font(.mono(14, weight: .bold)).monospacedDigit()
        }
        .foregroundStyle(won ? Theme.panelFg : Theme.fgMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(won ? Theme.fg.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
    }

    private func name(_ id: UUID) -> String {
        id == viewModel.viewerId ? "You" : viewModel.player(id)?.name ?? "Unknown"
    }

    // MARK: Post-game

    /// The host advances the whole room; everybody else can keep reading the
    /// result until they do.
    @ViewBuilder
    private var postGameControls: some View {
        if viewModel.roomCode == nil {
            EmptyView()
        } else if viewModel.isHost {
            VStack(spacing: 8) {
                Button {
                    Task { await viewModel.choosePostGame(.replay) }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSaving { LoadingSpinner(size: 16) }
                        Text("Play again")
                    }
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canChoosePostGame)

                Button("Back to the room") {
                    Task { await viewModel.choosePostGame(.lobby) }
                }
                .buttonStyle(.ghost)
                .disabled(!viewModel.canChoosePostGame)
            }
        } else {
            VStack(spacing: 8) {
                WaitingNote(text: "Waiting for the host to choose what's next.")
                    .monoLabel(11, tracking: 0.13)
                Button("Back to the room") { dismiss() }
                    .buttonStyle(.ghost)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// A compact scoremark. Grades are colour-coded without the concealed red: red
/// means one player knows what another does not, while a poor grade is fully
/// public feedback. `nil` (no AV to grade yet) stays deliberately quiet.
private struct GradeBadge: View {
    let grade: String?
    let large: Bool

    var body: some View {
        Text(grade ?? "—")
            .font(.mono(large ? 18 : 12, weight: .bold))
            .foregroundStyle(grade == nil ? Theme.panelMuted : Theme.fg)
            .frame(minWidth: large ? 44 : 32)
            .padding(.vertical, large ? 5 : 3)
            .background(grade == nil ? Color.clear : tone, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
            .accessibilityLabel(grade.map { "Grade \($0)" } ?? "No grade yet")
    }

    private var tone: Color {
        switch grade?.first {
        case "A": Theme.gradeElite
        case "B": Theme.gradeStrong
        case "C": Theme.gradeEven
        default: Theme.gradeRough
        }
    }
}
