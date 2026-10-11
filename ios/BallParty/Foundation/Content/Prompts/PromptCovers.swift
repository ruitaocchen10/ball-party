import SwiftUI

// The feed-card art for the prompt kinds iOS can't play yet. The web draws these
// in `PromptPostUI.tsx` (`WeeklyAwardsCover`, `BoldPredictionsCover`) on top of
// `PromptCover.tsx`: a dark ticket, a colored glow on each side, three motif
// shapes per side that fade as they step inward, and a centered two-line title.

/// A glow on each side, three motif shapes per side, and the title. The shapes
/// take SF Symbols standing in for the web's clip-path polygons.
private struct MotifCover: View {
    let label: String
    let symbol: String
    let title: (String, String)
    let subtitle: String
    let leftTint: Color
    let rightTint: Color
    /// Per-side rotations (large, medium, small) in degrees: left, then right.
    let leftAngles: [Double]
    let rightAngles: [Double]

    private static let red = Color(hex: 0xEF4444)

    var body: some View {
        PromptTicket {
            ZStack {
                HStack(spacing: 0) {
                    LinearGradient(colors: [leftTint.opacity(0.24), .clear], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.clear, rightTint.opacity(0.22)], startPoint: .leading, endPoint: .trailing)
                }
                shape(size: 92, angle: leftAngles[0], opacity: 0.75, tint: leftTint, alignment: .topLeading, x: 16, y: 8)
                shape(size: 54, angle: leftAngles[1], opacity: 0.45, tint: leftTint, alignment: .topLeading, x: 88, y: 92)
                shape(size: 44, angle: leftAngles[2], opacity: 0.3, tint: leftTint, alignment: .bottomLeading, x: 12, y: -12)
                shape(size: 92, angle: rightAngles[0], opacity: 0.75, tint: rightTint, alignment: .bottomTrailing, x: -16, y: -8)
                shape(size: 54, angle: rightAngles[1], opacity: 0.45, tint: rightTint, alignment: .topTrailing, x: -88, y: 24)
                shape(size: 44, angle: rightAngles[2], opacity: 0.3, tint: rightTint, alignment: .topTrailing, x: -12, y: 12)
                titleBlock
            }
            .frame(height: 208)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var titleBlock: some View {
        VStack(spacing: 10) {
            VStack(spacing: -6) {
                Text(title.0).slabTitle(48, color: .white)
                Text(title.1).slabTitle(48, color: Self.red)
            }
            Text(subtitle).monoLabel(9, tracking: 0.12, color: Color(hex: 0xFFF8E4, opacity: 0.85))
        }
        .shadow(color: .black.opacity(0.9), radius: 6, x: 0, y: 3)
        .padding(.horizontal, 64)
    }

    private func shape(
        size: CGFloat, angle: Double, opacity: Double, tint: Color, alignment: Alignment, x: CGFloat, y: CGFloat
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .black))
            .foregroundStyle(tint.opacity(opacity))
            .rotationEffect(.degrees(angle))
            .offset(x: x, y: y)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

/// Blue stars on one side, red on the other.
struct WeeklyAwardsCover: View {
    var body: some View {
        MotifCover(
            label: "Weekly Awards", symbol: "star.fill",
            title: ("Weekly", "Awards"), subtitle: "Hand out the hardware",
            leftTint: Color(hex: 0x3B82F6), rightTint: Color(hex: 0xEF4444),
            leftAngles: [-12, 10, -6], rightAngles: [12, -10, 6]
        )
    }
}

/// Blue bolts on one side, red on the other, the red set flipped to strike back.
struct BoldPredictionsCover: View {
    var body: some View {
        MotifCover(
            label: "Bold Predictions", symbol: "bolt.fill",
            title: ("Bold", "Predictions"), subtitle: "Call it before it happens",
            leftTint: Color(hex: 0x3B82F6), rightTint: Color(hex: 0xEF4444),
            leftAngles: [-12, 10, -6], rightAngles: [168, 190, 174]
        )
    }
}
