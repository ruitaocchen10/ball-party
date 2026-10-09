import SwiftUI

/// The Ball Knower / Gamer dashboard, shared by the signed-in player's own
/// Profile tab and another player's profile. Unlike the web profile card,
/// which can let its three tiles wrap on a wide-enough viewport, a phone never
/// has the width for that, so the two smaller tiles sit side by side and the
/// richer third (the standing ring / streak) gets its own full-width row
/// beneath them, instead of a horizontal scroller that hides it off-screen.
///
/// It owns no data: the caller passes the numbers and the two bindings, and
/// may append a `footer` (the own profile adds the leaderboard link).
struct StatsCard<Footer: View>: View {
    let title: String
    @Binding var statsView: ProfileViewModel.StatsView
    @Binding var statsRange: ProfileStatRange
    let knower: KnowerHighlight
    /// "Rookie" through "Ball god", from the lifetime percentile.
    let status: String
    let statusDetail: String
    let gamer: GamerHighlight
    /// What sits beside the empty ring.
    let unrankedStandingText: String
    /// What the streak tile says at zero.
    let noStreakText: String
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SectionTitle(text: title)

            HStack(spacing: 12) {
                SegmentedChoice(
                    selection: $statsView,
                    options: [.knower, .gamer],
                    title: { $0 == .knower ? "Ball knower" : "Gamer" },
                    accessibilityName: "Profile stat type"
                )

                // Kept in the layout (just hidden) on Gamer rather than
                // removed outright — SegmentedChoice's buttons are
                // `maxWidth: .infinity`, so if this view actually left the
                // HStack, the toggle would stretch to claim its space and
                // visibly resize on every tab switch.
                rangeMenu
                    .opacity(statsView == .knower ? 1 : 0)
                    .allowsHitTesting(statsView == .knower)
                    .accessibilityHidden(statsView != .knower)
            }

            if statsView == .knower {
                knowerTiles
            } else {
                gamerTiles
            }
        }
    }

    /// The reporting-range control, restyled to match `SegmentedChoice`'s
    /// bordered well instead of looking like a bare system menu next to it.
    private var rangeMenu: some View {
        Picker("Range", selection: $statsRange) {
            ForEach(ProfileStatRange.allCases, id: \.self) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.menu)
        .monoLabel(11, weight: .bold, tracking: 0.12, color: Theme.fg)
        .tint(Theme.fg)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .well()
        .fixedSize()
    }

    private var knowerTiles: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HighlightTile(
                    label: "Total points",
                    value: knower.totalPoints.formatted(),
                    detail: statsRange.windowLabel
                )
                HighlightTile(label: "Ball knower status", value: status, detail: statusDetail)
            }
            standingTile
            footer
        }
    }

    private var standingTile: some View {
        let percentile = knower.percentile
        return VStack(alignment: .leading, spacing: 10) {
            Text("Ball knower standing").monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
            HStack(spacing: 16) {
                PercentileRing(percentile: percentile)
                Text(
                    percentile == nil
                        ? unrankedStandingText
                        : "\(statsRange.label) · among active ball knowers"
                )
                .font(.sans(14))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            percentile == nil ? "Not ranked yet" : "\(percentile!)th percentile among active ball knowers, \(statsRange.label.lowercased())"
        )
    }

    private var gamerTiles: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HighlightTile(
                    label: "Games played",
                    value: "\(gamer.gamesPlayed)",
                    detail: "All-time multiplayer games"
                )
                HighlightTile(
                    label: "Win rate",
                    value: "\(gamer.winRate)%",
                    detail: "\(gamer.wins) multiplayer \(gamer.wins == 1 ? "win" : "wins")"
                )
            }
            streakTile
        }
    }

    /// The Gamer half's answer to `standingTile` — same full-width, richer
    /// row, so switching tabs doesn't leave Gamer feeling like the thinner
    /// half of the toggle.
    private var streakTile: some View {
        let streak = gamer.currentStreak
        return VStack(alignment: .leading, spacing: 10) {
            Text("Current streak").monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
            HStack(spacing: 16) {
                StreakDots(streak: streak)
                Text(
                    streak == 0
                        ? noStreakText
                        : "\(streak) consecutive \(streak == 1 ? "win" : "wins")"
                )
                .font(.sans(14))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(streak == 0 ? "No current win streak" : "\(streak) game win streak")
    }
}

/// One stat, in the recessed style every passive number on this screen uses.
private struct HighlightTile: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
            Text(value)
                .slabTitle(40)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(detail)
                .font(.sans(13))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .accessibilityElement(children: .combine)
    }
}

/// A player's lifetime-window percentile as a ring, the same 1–100 gauge the
/// web draws with an SVG circle.
private struct PercentileRing: View {
    let percentile: Int?

    var body: some View {
        let fraction = Double(max(0, min(100, percentile ?? 0))) / 100
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Theme.hiddenText, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percentile.map { "\($0)%" } ?? "—")
                .font(.slab(18))
                .foregroundStyle(Theme.fg)
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

/// The Gamer half's counterpart to `PercentileRing` — a win streak has no
/// natural 0–100 gauge, so it reads as filled beads instead, capped at 5 so a
/// long streak doesn't stretch the row; the count alongside always says the
/// real number.
private struct StreakDots: View {
    let streak: Int

    var body: some View {
        HStack(spacing: 6) {
            if streak == 0 {
                Circle().strokeBorder(Theme.line, lineWidth: 1).frame(width: 14, height: 14)
            } else {
                ForEach(0..<min(streak, 5), id: \.self) { _ in
                    Circle().fill(Theme.hiddenText).frame(width: 14, height: 14)
                }
            }
        }
        .frame(minWidth: 64, alignment: .leading)
        .accessibilityHidden(true)
    }
}
