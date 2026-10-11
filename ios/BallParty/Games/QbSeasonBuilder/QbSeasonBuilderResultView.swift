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
                    if viewModel.isBusy { LoadingSpinner(size: 16) }
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
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
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
                let players = viewModel.pickedPlayers
                if !players.isEmpty {
                    LineRule()
                    QbPlayersPicked(players: players)
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
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
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

/// The players the run took, as faces in a row — the team's logo for the
/// Supporting Cast. Tapping one opens their card.
private struct QbPlayersPicked: View {
    let players: [QbPickedPlayer]
    @State private var selected: QbPickedPlayer?

    private static let faceSize: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Players picked").monoLabel(10, tracking: 0.13)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.faceSize), spacing: 10, alignment: .leading)],
                alignment: .leading, spacing: 10
            ) {
                ForEach(players) { player in
                    Button { selected = player } label: { face(player) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(player.title), \(player.pick.slot.label)")
                        .accessibilityHint("Shows their card")
                }
            }
        }
        .sheet(item: $selected) { player in
            QbPickedPlayerCard(player: player)
                .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private func face(_ player: QbPickedPlayer) -> some View {
        if player.pick.playerId != nil {
            Portrait(name: player.title, url: player.pick.headshotURL, size: Self.faceSize)
        } else {
            FranchiseLogo(code: player.pick.franchiseCode, size: Self.faceSize - 10)
                .frame(width: Self.faceSize, height: Self.faceSize)
                .background(Theme.surfaceRaised, in: Circle())
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: 1))
        }
    }
}

/// One pick: who or which team it was, where from, and every grade the run
/// showed for it with the one taken on the cream fill a chosen option row uses.
private struct QbPickedPlayerCard: View {
    let player: QbPickedPlayer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                if player.pick.playerId != nil {
                    Portrait(name: player.title, url: player.pick.headshotURL, size: 56)
                } else {
                    FranchiseLogo(code: player.pick.franchiseCode, size: 56)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.title).slabTitle(24).lineLimit(2)
                    // Stringified so the year is not grouped into "2,013".
                    Text("\(String(player.pick.season)) \(QbFranchises.name(for: player.pick.franchiseCode))")
                        .monoLabel(10, weight: .bold, tracking: 0.08, color: Theme.fgMuted)
                }
            }
            Text("Picked for \(player.pick.slot.label)").monoLabel(10, tracking: 0.13)
            VStack(spacing: 0) {
                ForEach(Array(player.gradeLines.enumerated()), id: \.element.slot) { index, line in
                    if index > 0 { LineRule() }
                    HStack {
                        Text(line.slot.label).monoLabel(11, tracking: 0.1, color: line.isPicked ? Theme.panelFg : Theme.fg)
                        Spacer(minLength: 8)
                        Text(line.grade.label)
                            .slabTitle(22, color: line.isPicked ? Theme.panelFg : Theme.fg)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(line.isPicked ? Theme.hidden : .clear)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(line.slot.label) \(line.grade.spoken)\(line.isPicked ? ", picked" : "")")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised.ignoresSafeArea())
    }
}
