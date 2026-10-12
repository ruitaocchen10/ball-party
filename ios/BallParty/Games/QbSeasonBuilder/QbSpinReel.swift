import SwiftUI

/// The suspense before a spin's team-season is revealed: a column of decoy
/// franchises translates upward and lands on the real one. This mirrors the
/// webapp's `SlotReel` (`webapp/components/foundation/ui-kit/SlotReel.tsx` +
/// its `reel-spin` keyframes in `webapp/app/globals.css`) — same duration,
/// same landing math, same overshoot-then-settle feel — so both platforms
/// build the same suspense over which quarterback a spin holds rather than
/// just a generic loading spinner.
///
/// SwiftUI has no direct equivalent of a CSS `@keyframes` animation with an
/// interior overshoot, so the web's single animation becomes two chained
/// `withAnimation` calls here: the first carries the reel past its landing
/// spot (mirroring the keyframes' 70%-mark overshoot), the second eases it
/// back the rest of the way. Both legs reuse the web's cubic-bezier timing
/// function, just split across the same total duration the CSS spends on
/// each leg.
struct QbSpinReel: View {
    let franchiseCode: String
    /// Nil for a spin with no season attached; the rows then drop the year line.
    let season: Int?
    /// Change this to remount and replay the animation — the SwiftUI
    /// equivalent of the web's `reelKey`.
    let spinKey: String

    /// Matches `SPIN_REVEAL_MS` in `QbSeasonBuilderMatch.tsx`, so a run
    /// entered from either platform holds its suspense for the same beat.
    static let revealSeconds: Double = 2.0
    /// The settled row height a landed `QbSpinHeader` also holds itself to,
    /// so revealing never reads as a jump to a different layout.
    static let rowHeight: CGFloat = 72

    private static let decoyCount = 7
    /// The web keyframes' `cubic-bezier(.16, .86, .23, 1)`.
    private static let timing = (0.16, 0.86, 0.23, 1.0)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0

    private var items: [String] {
        QbFranchises.reelDecoys(excluding: franchiseCode, key: spinKey, count: Self.decoyCount) + [franchiseCode]
    }

    var body: some View {
        Group {
            if reduceMotion {
                // A reel frozen mid-spin would tell a reduced-motion viewer
                // nothing true; say plainly that this is still in flight.
                Text("Spinning…")
                    .monoLabel(11, tracking: 0.15)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .center)
            } else {
                reel
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spinning")
    }

    private var reel: some View {
        let rows = items
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, code in
                QbTeamRow(code: code, season: season)
                    .frame(height: Self.rowHeight, alignment: .leading)
            }
        }
        .offset(y: offset)
        .frame(height: Self.rowHeight, alignment: .top)
        .clipped()
        .id(spinKey)
        .onAppear { spin(rowCount: rows.count) }
    }

    /// Runs once per `spinKey`, since `.id(spinKey)` remounts this view (and
    /// resets `offset`) whenever a new spin replaces the old one.
    private func spin(rowCount: Int) {
        offset = 0
        let n = CGFloat(rowCount)
        let restOffset = -(n - 1) * Self.rowHeight
        // The keyframes' 70%-mark overshoot: 4% of the reel's total height
        // (all n rows stacked) past where it finally settles.
        let overshootOffset = restOffset - 0.04 * n * Self.rowHeight
        let (x1, y1, x2, y2) = Self.timing

        withAnimation(.timingCurve(x1, y1, x2, y2, duration: Self.revealSeconds * 0.7)) {
            offset = overshootOffset
        } completion: {
            withAnimation(.timingCurve(x1, y1, x2, y2, duration: Self.revealSeconds * 0.3)) {
                offset = restOffset
            }
        }
    }
}

/// One team-season identity — a franchise's logo, name and year. The reel's
/// rows and the settled `QbSpinHeader` render this exact same content, so
/// landing never looks like a swap to a different layout, only a stop.
struct QbTeamRow: View {
    let code: String
    let season: Int?

    var body: some View {
        HStack(spacing: 12) {
            FranchiseLogo(code: code, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(QbFranchises.name(for: code))
                    .slabTitle(27)
                    .lineSpacing(0)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let season { Text(String(season)).monoLabel(11, tracking: 0.15) }
            }
            Spacer(minLength: 0)
        }
    }
}
