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
                                if viewModel.isBusy { LoadingSpinner(size: 16) }
                                Text("Play again")
                            }
                        }
                        .buttonStyle(.solid)
                        .disabled(viewModel.isBusy)

                        // The format is chosen on the Games tab's card.
                        Button("Back to games") { dismiss() }
                            .buttonStyle(.ghost)
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
            PanelCard {
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
            // Two or three tiles a row, depending on the screen's width.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .top)], spacing: 8) {
                ForEach(recap.ladder) { entry in
                    ladderTile(entry)
                }
            }
        }
    }

    private func ladderTile(_ entry: SoloRunViewModel.RecapEntry) -> some View {
        let card = entry.card
        return VStack(alignment: .leading, spacing: 6) {
            Text("\(card.ordinal + 1)")
                .font(.mono(10, weight: .bold))
                .foregroundStyle(Theme.surface)
                .frame(width: 22, height: 22)
                .background(Theme.fg, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(card.displayName)
                    .slabTitle(15)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("\(card.position) · \(card.team)")
                    .monoLabel(10, tracking: 0.07)
                    .lineLimit(1)
                // Verbatim, so the season isn't run through number formatting ("2,021").
                Text(verbatim: card.week.map { "\(String(card.season)) · Wk \($0)" } ?? String(card.season))
                    .monoLabel(10, tracking: 0.07)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(card.points.map(LadderCardView.formatPoints) ?? "—")
                .slabTitle(24)
                .monospacedDigit()
            ResultBadge(text: entry.outcome.shortLabel, tone: entry.outcome.isCorrect ? .good : .neutral)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .well()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.ordinal + 1). \(card.displayName), \(card.identityLine)")
        .accessibilityValue("\(card.points.map(LadderCardView.formatPoints) ?? "no score"), \(entry.outcome.label)")
    }
}
