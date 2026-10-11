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
                    LadderCardsView(anchor: anchor, challenger: challenger)
                } else {
                    Text("Waiting for the next card…")
                        .monoLabel(11, tracking: 0.13)
                        .padding(.vertical, 40)
                }

                callArea

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(16)
        }
        // Both card faces are visual idioms; this is the whole announcement.
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.questionLabel).monoLabel(11, weight: .semibold, tracking: 0.15)
                Spacer()
                Text(viewModel.formatLabel).monoLabel(11, tracking: 0.13)
            }
            HStack(spacing: 0) {
                RunStat(label: "Correct", value: viewModel.correctCount)
                statDivider
                RunStat(label: "Streak", value: viewModel.currentStreak)
                statDivider
                RunStat(label: "All-time high", value: viewModel.allTimeHigh)
            }
            .padding(.vertical, 12)
            .well()
        }
    }

    private var statDivider: some View {
        Theme.line.frame(width: 1, height: 36).accessibilityHidden(true)
    }

    @ViewBuilder
    private var callArea: some View {
        if let outcome = viewModel.currentOutcome {
            // The question has revealed: say how it went, then wait for the
            // player — solo has no timer pushing them out of a reveal.
            VStack(spacing: 12) {
                ResultBadge(text: outcome.label, tone: outcome.isCorrect ? .good : .bad)
                Button {
                    Task { await viewModel.continueRun() }
                } label: {
                    Text(outcome.isCorrect ? "Continue" : "See your run")
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canContinue)
            }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.call(.higher) }
                    } label: {
                        Label("Higher", systemImage: "arrow.up")
                    }
                    .buttonStyle(.solid)
                    Button {
                        Task { await viewModel.call(.lower) }
                    } label: {
                        Label("Lower", systemImage: "arrow.down")
                    }
                    .buttonStyle(.ghost)
                }
                .disabled(!viewModel.canCall)

                if let call = viewModel.myCall {
                    Text(call.timedOut ? "You ran out of time." : "You called \(call.direction?.rawValue ?? "").")
                        .monoLabel(11, tracking: 0.13)
                }
            }
        }
    }
}

/// The two sides of a question belong together: the player compares them at a
/// glance, rather than reading one card and then scrolling to the other.
struct LadderCardsView: View {
    let anchor: LadderCard
    let challenger: LadderCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LadderCardView(label: "Anchor", card: anchor)
            LadderCardView(label: "Challenger", card: challenger)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct RunStat: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(spacing: 4) {
            Text(label).monoLabel(10, weight: .bold, tracking: 0.14)
            Text("\(value)")
                .slabTitle(32)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One card and its number. The same view for both sides of a question because
/// they are the same card at two moments — every challenger becomes the next
/// anchor.
///
/// The number is the concealed thing: red and woven until the server writes it,
/// then a cream panel.
struct LadderCardView: View {
    let label: String
    let card: LadderCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).monoLabel(10, tracking: 0.13)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.position).slabTitle(18)
                        Spacer()
                        TeamLogo(code: card.team, size: 24)
                    }
                    VStack(spacing: 6) {
                        Portrait(name: card.displayName, url: card.headshotUrl.flatMap(URL.init(string:)), size: 56)
                        Text(card.displayName)
                            .slabTitle(22)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(card.identityLine)
                            .monoLabel(9, tracking: 0.08)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(10)

                pointsPanel
            }
            .well()
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var pointsPanel: some View {
        Reveal(revealed: card.points != nil) {
            // A missing number is an honest rendering of an absent value: the
            // server has not written this card's points yet.
            Concealed(label: "Fantasy points, hidden until this question reveals") {
                VStack(spacing: 4) {
                    Text("Fantasy points").monoLabel(10, weight: .bold, tracking: 0.12, color: Theme.fg)
                    Text("? ? ?").slabTitle(32, color: Theme.fg)
                }
                .padding(.vertical, 12)
            }
        } content: {
            VStack(spacing: 4) {
                Text("Fantasy points").monoLabel(10, weight: .bold, tracking: 0.12, color: Theme.panelMuted)
                Text(card.points.map(Self.formatPoints) ?? "")
                    .slabTitle(32, color: Theme.panelFg)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
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

/// The visible countdown. Hidden entirely when nothing is timed — which is every
/// solo phase — and otherwise a bar and seconds fed by the shared match clock.
struct CountdownView: View {
    @ObservedObject var clock: MatchClockDriver
    let phase: HigherOrLowerPhase

    var body: some View {
        if let remainingMs = clock.remainingMs {
            let seconds = Int((Double(remainingMs) / 1_000).rounded(.up))
            let fraction = min(1, Double(remainingMs) / Double(max(1, phase.durationMs - MatchClockConstants.visibleSlackMs)))
            VStack(alignment: .leading, spacing: 8) {
                Text(phase.clockLabel).monoLabel(11, tracking: 0.15)
                Text(ClockText.text(seconds: seconds))
                    .slabTitle(32)
                    .monospacedDigit()
                MeterBar(fraction: fraction)
                    .animation(.linear(duration: Double(MatchClockConstants.tickMs) / 1_000), value: fraction)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .well(bordered: false)
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
