import SwiftUI

/// A finished season, revealed a step at a time: score, stat line, awards,
/// record, playoffs, and only then what explains the score. It can be skipped,
/// and plays once, since a finished run has no way back in.
struct QbResultView: View {
    @ObservedObject var viewModel: QbSeasonBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let result = viewModel.result {
                VStack(alignment: .leading, spacing: 16) {
                    header(result)

                    if viewModel.shows(.score) {
                        PlayerBuildPanel(viewModel: viewModel, result: result)
                    }
                    if viewModel.shows(.record) {
                        TeamSuccessPanel(result: result, showPlayoffs: viewModel.shows(.playoffs))
                    }

                    if viewModel.isRevealing {
                        Button("Skip to result") { viewModel.skipReveal() }
                            .buttonStyle(.quiet)
                            .frame(maxWidth: .infinity)
                    }

                    if viewModel.shows(.details) {
                        BreakdownPanel(result: result)
                        if let best = viewModel.personalBest {
                            personalBest(best, mode: result.mode)
                        }
                        actions
                    }
                }
                .padding(16)
                .animation(.easeOut(duration: 0.25), value: viewModel.revealStage)
            }
        }
        // One step at a time: each landing re-keys the task, which holds for the
        // next. Skipping or finishing leaves nothing left to advance.
        .task(id: viewModel.revealStage) {
            guard viewModel.isRevealing else { return }
            try? await Task.sleep(for: .seconds(QbSeasonBuilderViewModel.revealStepSeconds))
            if !Task.isCancelled { viewModel.advanceReveal() }
        }
    }

    private func header(_ result: QbSeasonResult) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Season complete").eyebrow()
            Spacer()
            Text("Grades \(result.mode.rawValue)").monoLabel(11, tracking: 0.13)
        }
    }

    private func personalBest(_ best: Double, mode: QbRatingMode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Personal best · \(mode.rawValue)").monoLabel(10, weight: .semibold, tracking: 0.13)
            Text(String(format: "%.1f", best)).slabTitle(40).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .well()
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                Task { await viewModel.newSeason() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isBusy { ProgressView() }
                    Text("New season")
                }
            }
            .buttonStyle(.solid)
            .disabled(viewModel.isBusy)

            if let message = viewModel.errorMessage {
                ErrorBanner(message: message)
            }

            Button("Back to games") { dismiss() }
                .buttonStyle(.quiet)
        }
        .frame(maxWidth: .infinity)
    }
}

/// A labelled surface, the result screen's unit: a small red caption over its
/// content, on a raised well with a hairline border.
private struct ResultPanel<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label).monoLabel(10, weight: .semibold, tracking: 0.15, color: Theme.hiddenText)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
        .transition(.opacity)
    }
}

/// The quarterback assembled from the run: score, production and honours.
private struct PlayerBuildPanel: View {
    @ObservedObject var viewModel: QbSeasonBuilderViewModel
    let result: QbSeasonResult

    var body: some View {
        ResultPanel(label: "Player build") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%.1f", result.score))
                    .slabTitle(64)
                    .monospacedDigit()
                Text("out of 100").monoLabel(11, tracking: 0.15)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Score \(String(format: "%.1f", result.score)) out of 100")

            if viewModel.shows(.statLine) {
                LineRule()
                statGrid
            }
            if viewModel.shows(.awards) {
                LineRule()
                awards
                if !viewModel.dealtSpins.isEmpty {
                    LineRule()
                    QbPlayersDealt(spins: viewModel.dealtSpins, picks: result.picks)
                }
            }
        }
    }

    private var statGrid: some View {
        let line = result.statLine
        let stats: [(String, String)] = [
            ("Comp / Att", "\(Self.grouped(line.completions)) / \(Self.grouped(line.attempts))"),
            ("Pass yards", Self.grouped(line.passYards)),
            ("Pass TDs", Self.grouped(line.passTds)),
            ("Interceptions", Self.grouped(line.interceptions)),
            ("Passer rating", String(format: "%.1f", line.rating)),
            ("Rush yards", Self.grouped(line.rushYards)),
            ("Rush TDs", Self.grouped(line.rushTds)),
        ]
        return LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
            ForEach(stats, id: \.0) { name, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).monoLabel(10, tracking: 0.13)
                    Text(value).slabTitle(26).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var awards: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Awards").monoLabel(10, tracking: 0.13)
            if result.awards.isEmpty {
                Text("No awards this season.")
                    .font(.sans(14))
                    .foregroundStyle(Theme.fgMuted)
            } else {
                ForEach(result.awards, id: \.self) { award in
                    Text(award.label)
                        .slabTitle(19)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                }
            }
        }
    }

    private static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

/// Team outcomes stay distinct from the player build that produced them.
private struct TeamSuccessPanel: View {
    let result: QbSeasonResult
    let showPlayoffs: Bool

    var body: some View {
        ResultPanel(label: "Team success") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Record").monoLabel(10, tracking: 0.13)
                Text("\(result.record.wins)–\(result.record.losses)").slabTitle(40).monospacedDigit()
            }
            .accessibilityElement(children: .combine)

            if showPlayoffs {
                LineRule()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Playoffs").monoLabel(10, tracking: 0.13)
                    Text(result.playoffs.result.label).slabTitle(27)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct BreakdownPanel: View {
    let result: QbSeasonResult

    var body: some View {
        ResultPanel(label: "Score breakdown") {
            VStack(spacing: 0) {
                ForEach(Array(result.breakdown.enumerated()), id: \.offset) { index, part in
                    if index > 0 { LineRule() }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(part.label).monoLabel(11, weight: .bold, tracking: 0.1, color: Theme.fg)
                            Text("\(result.weightPercent(of: part))% of the score · better than \(Int((part.percentile * 100).rounded()))% of real seasons")
                                .font(.sans(13))
                                .foregroundStyle(Theme.fgMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Text(QbPoints.format(part.points)).slabTitle(22).monospacedDigit()
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// In a hidden run, every option the player saw with its value — the ones passed
/// on and a respun-away spin included. Only the finished run's owner can read it.
private struct QbPlayersDealt: View {
    let spins: [QbShownSpin]
    let picks: [QbPick]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Players dealt").monoLabel(10, tracking: 0.13)
            ForEach(spins) { spin in
                spinCard(spin)
            }
        }
    }

    private func spinCard(_ spin: QbShownSpin) -> some View {
        let finalAttempt = spins.filter { $0.round == spin.round }.map(\.attempt).max() ?? spin.attempt
        let respun = spin.attempt < finalAttempt
        let picked = spin.attempt == finalAttempt ? picks.first { $0.round == spin.round } : nil

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FranchiseLogo(code: spin.franchiseCode, size: 24)
                // `Text("\(spin.season) …")` would run the year through
                // SwiftUI's default numeric formatting and print "2,013" —
                // stringifying first keeps it as a plain year.
                Text("\(String(spin.season)) \(QbFranchises.name(for: spin.franchiseCode))")
                    .monoLabel(10, weight: .bold, tracking: 0.08, color: Theme.fg)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if respun { Text("Respun").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText) }
            }
            ForEach(spin.spin.quarterbacks) { quarterback in
                let isPicked = picked?.playerId == quarterback.playerId
                HStack(alignment: .top, spacing: 10) {
                    Portrait(name: quarterback.displayName, url: quarterback.headshotURL, size: 32)
                        .opacity(respun || !isPicked ? 0.45 : 1)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(quarterback.displayName).slabTitle(17).lineLimit(1)
                        valueLine(quarterback: quarterback, cast: spin.spin.supportingCastGrade, picked: isPicked || picked?.slot == .supportingCast ? picked?.slot : nil)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
    }

    /// The grades as one wrapping run, the one that was taken marked out.
    private func valueLine(quarterback: QbQuarterback, cast: QbGrade?, picked: QbSlot?) -> some View {
        var entries: [(QbSlot, QbGrade)] = QbSlot.qualities.compactMap { slot in
            quarterback.grades?[slot].map { (slot, $0) }
        }
        if let cast { entries.append((.supportingCast, cast)) }
        return FlowText(entries: entries.map { slot, grade in
            FlowText.Entry(label: slot.label, value: grade.label, marked: picked == slot)
        })
    }
}

/// "Accuracy 88 · Arm Talent 91 · …" as wrapping mono captions, with the taken
/// one on the cream fill a chosen option row uses.
private struct FlowText: View {
    struct Entry: Identifiable {
        let label: String
        let value: String
        let marked: Bool
        var id: String { label }
    }

    let entries: [Entry]

    var body: some View {
        // Two columns keeps every grade lined up down the list.
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 4) {
            ForEach(entries) { entry in
                HStack(spacing: 6) {
                    Text(entry.label).monoLabel(9, tracking: 0.06)
                    Text(entry.value)
                        .font(.slab(15, relativeTo: .body))
                        .foregroundStyle(entry.marked ? Theme.panelFg : Theme.fg)
                        .padding(.horizontal, entry.marked ? 4 : 0)
                        .background(entry.marked ? Theme.panel : .clear)
                }
            }
        }
    }
}
