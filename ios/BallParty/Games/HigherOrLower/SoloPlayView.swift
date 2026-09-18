import SwiftUI

/// The ladder, on one screen: the anchor card, the hidden challenger, the two
/// calls, and the run's running tallies.
struct SoloPlayView: View {
    @ObservedObject var viewModel: SoloRunViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                if let board = viewModel.board {
                    CountdownView(clock: viewModel.clock, phase: board.phase)
                }

                if let anchor = viewModel.anchor, let challenger = viewModel.challenger {
                    LadderCardView(label: "Anchor", card: anchor)
                    LadderCardView(label: "Challenger", card: challenger)
                } else {
                    Text("Waiting for the next card…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 40)
                }

                callArea

                if let message = viewModel.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        // Both card faces are visual idioms; this is the whole announcement.
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.questionLabel.uppercased())
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.formatLabel.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 0) {
                RunStat(label: "Correct", value: viewModel.correctCount)
                Divider().frame(height: 36)
                RunStat(label: "Streak", value: viewModel.currentStreak)
                Divider().frame(height: 36)
                RunStat(label: "All-time high", value: viewModel.allTimeHigh)
            }
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var callArea: some View {
        if let outcome = viewModel.currentOutcome {
            // The question has revealed: say how it went, then wait for the
            // player — solo has no timer pushing them out of a reveal.
            VStack(spacing: 12) {
                Text(outcome.label)
                    .font(.headline)
                    .foregroundStyle(outcome.isCorrect ? Color.green : Color.red)
                Button {
                    Task { await viewModel.continueRun() }
                } label: {
                    Text(outcome.isCorrect ? "Continue" : "See your run").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canContinue)
            }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.call(.higher) }
                    } label: {
                        Label("Higher", systemImage: "arrow.up").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        Task { await viewModel.call(.lower) }
                    } label: {
                        Label("Lower", systemImage: "arrow.down").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                .disabled(!viewModel.canCall)

                if let call = viewModel.myCall {
                    Text(call.timedOut ? "You ran out of time." : "You called \(call.direction?.rawValue ?? "").")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RunStat: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One card and its number. The same view for both sides of a question because
/// they are the same card at two moments — every challenger becomes the next
/// anchor.
struct LadderCardView: View {
    let label: String
    let card: LadderCard

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                HStack {
                    Text(card.position).font(.title3.weight(.bold))
                    Spacer()
                    Text(card.team).font(.caption.monospaced().weight(.bold)).foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    Portrait(name: card.displayName, url: card.headshotUrl.flatMap(URL.init(string:)))
                    Text(card.displayName)
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(card.identityLine)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)

            Divider()

            pointsPanel
        }
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var pointsPanel: some View {
        VStack(spacing: 2) {
            Text("FANTASY POINTS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(card.points == nil ? Color.secondary : Color.white.opacity(0.7))
            // A missing number is an honest rendering of an absent value: the
            // server has not written this card's points yet.
            Text(card.points.map(Self.formatPoints) ?? "? ? ?")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(card.points == nil ? Color.secondary : Color.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(card.points == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.accentColor))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
        .animation(.easeOut(duration: 0.25), value: card.points)
    }

    private var accessibilitySummary: String {
        let points = card.points.map { "\(Self.formatPoints($0)) fantasy points" } ?? "points hidden"
        return "\(label). \(card.displayName), \(card.position), \(card.identityLine), \(points)."
    }

    /// One decimal is how the game reads points.
    static func formatPoints(_ points: Double) -> String {
        String(format: "%.1f", points)
    }
}

/// A player's headshot, falling back to their initial when there is no image
/// or it fails to load.
struct Portrait: View {
    let name: String
    let url: URL?
    var size: CGFloat = 88

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.accentColor.opacity(0.85)
                    Text(String(name.prefix(1)).uppercased())
                        .font(.system(size: size * 0.42, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// The visible countdown. Hidden entirely when nothing is timed — which is every
/// solo phase — and otherwise a bar and seconds fed by the shared match clock.
struct CountdownView: View {
    @ObservedObject var clock: MatchClockDriver
    let phase: HigherOrLowerPhase

    var body: some View {
        if let remainingMs = clock.remainingMs {
            let seconds = Int((Double(remainingMs) / 1_000).rounded(.up))
            let fraction = min(1, Double(remainingMs) / Double(max(1, phase.durationMs - MatchClockConstants.visibleSlackMs)))
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(phase.clockLabel.uppercased())
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(seconds)s")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                }
                ProgressView(value: fraction)
                    .animation(.linear(duration: Double(MatchClockConstants.tickMs) / 1_000), value: fraction)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(seconds) seconds left")
        }
    }
}

extension HigherOrLowerPhase {
    /// The length of the phase's timer on the server, so the countdown bar can
    /// show a fraction. Mirrors the durations `MatchClock` in the web reads off
    /// its phase names.
    var durationMs: Int {
        switch self {
        case .boardIntro: 5_000
        case .call: 12_000
        case .suddenDeathCall: 8_000
        case .reveal, .suddenDeathReveal, .complete: 4_000
        }
    }

    var clockLabel: String {
        switch self {
        case .boardIntro: "The board is coming into view"
        case .call, .suddenDeathCall: "Make your call"
        case .reveal, .suddenDeathReveal: "The answer is revealed"
        case .complete: "Match complete"
        }
    }
}
