import SwiftUI

/// The finished run: the score, how it compares to the player's best, and the
/// ladder they climbed.
struct SoloRecapView: View {
    @ObservedObject var viewModel: SoloRunViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            if let recap = viewModel.recap {
                VStack(alignment: .leading, spacing: 20) {
                    summary(recap)
                    ladder(recap)

                    if let message = viewModel.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }

                    VStack(spacing: 8) {
                        Button {
                            Task { await viewModel.playAgain() }
                        } label: {
                            HStack {
                                if viewModel.isBusy { ProgressView().tint(.white) }
                                Text("Play again").fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(viewModel.isBusy)

                        Button("Change format") { viewModel.returnToSetup() }
                            .disabled(viewModel.isBusy)
                        Button("Back home") { dismiss() }
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
        }
    }

    private func summary(_ recap: SoloRunViewModel.Recap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RUN COMPLETE")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Text("\(recap.correct) correct")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .accessibilityAddTraits(.isHeader)

            personalBestBanner(recap)

            HStack(spacing: 0) {
                RunStat(label: "Questions right", value: recap.correct)
                Divider().frame(height: 36)
                RunStat(label: "All-time high", value: recap.personalBest)
            }
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func personalBestBanner(_ recap: SoloRunViewModel.Recap) -> some View {
        if recap.isNewPersonalBest {
            Label("New personal best!", systemImage: "trophy.fill")
                .font(.headline)
                .foregroundStyle(.orange)
        } else if recap.correct == recap.personalBest {
            Label("You matched your personal best of \(recap.personalBest).", systemImage: "equal.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            let gap = recap.personalBest - recap.correct
            Text("\(gap) short of your personal best of \(recap.personalBest).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func ladder(_ recap: SoloRunViewModel.Recap) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your ladder").font(.title3.weight(.bold))
            ForEach(recap.ladder) { entry in
                HStack(spacing: 12) {
                    Text("\(entry.card.ordinal + 1)")
                        .font(.caption2.monospaced().weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.accentColor, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.card.displayName).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(entry.card.position) · \(entry.card.identityLine)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(entry.card.points.map(LadderCardView.formatPoints) ?? "—")
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                        Text(entry.outcome.label)
                            .font(.caption2.monospaced())
                            .foregroundStyle(entry.outcome.isCorrect ? Color.green : Color.secondary)
                    }
                }
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }
}
