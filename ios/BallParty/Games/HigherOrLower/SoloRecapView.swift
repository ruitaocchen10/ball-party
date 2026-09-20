import SwiftUI

/// The finished run: the score, how it compares to the player's best, and the
/// ladder they climbed.
struct SoloRecapView: View {
    @ObservedObject var viewModel: SoloRunViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let recap = viewModel.recap {
                VStack(alignment: .leading, spacing: 24) {
                    summary(recap)
                    ladder(recap)

                    if let message = viewModel.errorMessage {
                        ErrorBanner(message: message)
                    }

                    VStack(spacing: 8) {
                        Button {
                            Task { await viewModel.playAgain() }
                        } label: {
                            HStack(spacing: 8) {
                                if viewModel.isBusy { ProgressView() }
                                Text("Play again")
                            }
                        }
                        .buttonStyle(.solid)
                        .disabled(viewModel.isBusy)

                        Button("Change format") { viewModel.returnToSetup() }
                            .buttonStyle(.ghost)
                            .disabled(viewModel.isBusy)
                        Button("Back to games") { dismiss() }
                            .buttonStyle(.quiet)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
        }
    }

    private func summary(_ recap: SoloRunViewModel.Recap) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Run complete").eyebrow()
                Text("\(recap.correct) correct")
                    .slabTitle(56)
                    .accessibilityAddTraits(.isHeader)
            }

            personalBestBanner(recap)

            HStack(spacing: 0) {
                RunStat(label: "Questions right", value: recap.correct)
                Theme.line.frame(width: 1, height: 36).accessibilityHidden(true)
                RunStat(label: "All-time high", value: recap.personalBest)
            }
            .padding(.vertical, 12)
            .well()
        }
    }

    /// A new personal best is the one thing on this screen worth a panel.
    @ViewBuilder
    private func personalBestBanner(_ recap: SoloRunViewModel.Recap) -> some View {
        if recap.isNewPersonalBest {
            PanelCard(edge: false) {
                Label("New personal best!", systemImage: "trophy.fill")
                    .font(.slab(24, relativeTo: .title2))
                    .textCase(.uppercase)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if recap.correct == recap.personalBest {
            Label("You matched your personal best of \(recap.personalBest).", systemImage: "equal.circle.fill")
                .font(.sans(15))
                .foregroundStyle(Theme.fgMuted)
        } else {
            let gap = recap.personalBest - recap.correct
            Text("\(gap) short of your personal best of \(recap.personalBest).")
                .font(.sans(15))
                .foregroundStyle(Theme.fgMuted)
        }
    }

    private func ladder(_ recap: SoloRunViewModel.Recap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("The players you saw").eyebrow()
                Text("Your ladder").slabTitle(28)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(recap.ladder) { entry in
                HStack(spacing: 12) {
                    Text("\(entry.card.ordinal + 1)")
                        .font(.mono(10, weight: .bold))
                        .foregroundStyle(Theme.panelFg)
                        .frame(width: 22, height: 22)
                        .background(Theme.panel, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.card.displayName)
                            .slabTitle(18)
                            .lineLimit(1)
                        Text("\(entry.card.position) · \(entry.card.identityLine)")
                            .monoLabel(10, tracking: 0.07)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(entry.card.points.map(LadderCardView.formatPoints) ?? "—")
                            .slabTitle(26)
                            .monospacedDigit()
                        ResultBadge(text: entry.outcome.label, tone: entry.outcome.isCorrect ? .good : .neutral)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .well()
                .accessibilityElement(children: .combine)
            }
        }
    }
}
