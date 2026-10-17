import SwiftUI

/// The Ball Knower / Gamer dashboard, shared by the signed-in player's own
/// Profile tab and another player's profile. The Ball Knower half is two
/// tiles side by side (the points gauge and the status); the Gamer half keeps
/// two tiles.
///
/// It owns no data: the caller passes the numbers and the two bindings, and
/// may append a `footer` (the own profile adds the leaderboard link).
struct StatsCard<Footer: View>: View {
    @Binding var statsView: ProfileViewModel.StatsView
    @Binding var statsRange: ProfileStatRange
    let knower: KnowerHighlight
    /// "Benchwarmer" through "Hall of Famer", from the lifetime percentile.
    let status: String
    let statusDetail: String
    let gamer: GamerHighlight
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                SegmentedChoice(
                    selection: $statsView,
                    options: [.knower, .gamer],
                    title: { $0 == .knower ? "Ball knower" : "Gamer" },
                    accessibilityName: "Profile stat type",
                    pill: true
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

    /// The reporting-range control, a capsule to match the pill toggle beside it.
    private var rangeMenu: some View {
        MenuPill(label: "Range", selection: $statsRange, options: Array(ProfileStatRange.allCases), title: \.label)
    }

    private var knowerTiles: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                KnowerPointsTile(knower: knower)
                HighlightTile(label: "Status", value: status, detail: statusDetail, valueSize: 32, valueLines: 2)
            }
            // The tiles stretch to the taller one, so the pair always matches.
            .fixedSize(horizontal: false, vertical: true)
            footer
        }
    }

    private var gamerTiles: some View {
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
        // The tiles stretch to the taller one, so the pair always matches.
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One stat, in the recessed style every passive number on this screen uses.
private struct HighlightTile: View {
    let label: String
    let value: String
    let detail: String
    /// Text values (the status) take a smaller size and may wrap; numbers keep
    /// the big single line.
    var valueSize: CGFloat = 40
    var valueLines = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
            Spacer(minLength: 8)
            Text(value)
                .slabTitle(valueSize)
                .lineLimit(valueLines)
                // Wrapping comes first; this only catches a single word too
                // long for the tile.
                .minimumScaleFactor(valueLines > 1 ? 0.8 : 0.6)
            Spacer(minLength: 8)
            Text(detail)
                .font(.sans(13))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        .well()
        .accessibilityElement(children: .combine)
    }
}

/// The Ball Knower points gauge: a half-circle bar that fills to the player's
/// percentile for the selected range, split into picks and likes by each one's
/// share of the points (mirrors the web's `KnowerPoints`). A negative like
/// total draws no likes segment. The total sits inside the arc.
private struct KnowerPointsTile: View {
    let knower: KnowerHighlight

    private let lineWidth: CGFloat = 24
    private var cap: StrokeStyle { StrokeStyle(lineWidth: lineWidth, lineCap: .round) }

    var body: some View {
        let fill = Double(max(0, min(100, knower.percentile ?? 0))) / 100
        let picks = Double(max(0, knower.pickPoints))
        let likes = Double(max(0, knower.likePoints))
        let likeShare = picks + likes > 0 ? likes / (picks + likes) : 0
        let pickEnd = fill * (1 - likeShare)
        let likeEnd = fill

        VStack(alignment: .leading, spacing: 10) {
            Text("Ball knower points").monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)

            Spacer(minLength: 8)

            ZStack(alignment: .bottom) {
                HalfArc().stroke(Theme.line, style: cap)
                // Likes run the full fill and the picks draw over their
                // share, so both ends stay round without a seam.
                if likeEnd > pickEnd {
                    HalfArc().trim(from: 0, to: likeEnd).stroke(Theme.ball, style: cap)
                }
                if pickEnd > 0 {
                    HalfArc().trim(from: 0, to: pickEnd).stroke(Theme.fg, style: cap)
                }
                VStack(spacing: 0) {
                    Text(knower.totalPoints.formatted())
                        .slabTitle(30)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("points")
                        .font(.sans(12))
                        .foregroundStyle(Theme.fgMuted)
                }
                .padding(.horizontal, lineWidth)
                // Bottom-aligned to the arc's centerline, the label would
                // stop short of the end caps; drop it to their bottom edge.
                .offset(y: lineWidth / 2)
            }
            .padding(lineWidth / 2)
            .aspectRatio(2, contentMode: .fit)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 8)

            HStack(spacing: 12) {
                KeyDot(color: Theme.fg, label: "Picks")
                KeyDot(color: Theme.ball, label: "Likes")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        .well()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            knower.percentile.map { "\(knower.totalPoints) points, \($0.ordinal) percentile" }
                ?? "\(knower.totalPoints) points, not ranked yet"
        )
    }
}

/// The upper half of a circle, left to right, so `trim` fills it like a gauge.
private struct HalfArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width / 2,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }
}

private struct KeyDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label).font(.sans(12)).foregroundStyle(Theme.fgMuted)
        }
    }
}
