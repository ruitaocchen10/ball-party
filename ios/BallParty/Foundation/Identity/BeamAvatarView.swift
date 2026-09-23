import SwiftUI

/// Draws a `BeamAvatar` — the on-screen preset tile, and (via `image(size:)`)
/// the PNG that gets uploaded when one is chosen.
///
/// Each piece is built in the SVG's raw 80×80 units, rotated around the
/// box's center, translated, then scaled to whatever size `Canvas` actually
/// draws at — vector operations on `Path`, not a `scaleEffect` on a rendered
/// bitmap, so it stays crisp at upload resolution.
struct BeamAvatarView: View {
    let seed: String
    var palette: [Color] = BeamAvatar.defaultPalette
    var size: CGFloat = 80

    var body: some View {
        Canvas { context, canvasSize in
            Self.draw(seed: seed, palette: palette, in: context, canvasSize: canvasSize)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    /// Rasterizes this design at `size` points and encodes it as a PNG —
    /// what `ProfileEditorViewModel` hands `ProfileClient.uploadAvatar`.
    @MainActor
    func png(size: CGFloat = 256) -> Data? {
        let renderer = ImageRenderer(content: BeamAvatarView(seed: seed, palette: palette, size: size))
        renderer.scale = 1
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #else
        return nil
        #endif
    }

    private static func draw(seed: String, palette: [Color], in context: GraphicsContext, canvasSize: CGSize) {
        let pieces = BeamAvatar.pieces(seed: seed, palette: palette)
        guard pieces.count == 4 else { return }
        let scale = canvasSize.width / BeamAvatar.canvasSize
        let pivot = CGPoint(x: BeamAvatar.canvasSize / 2, y: BeamAvatar.canvasSize / 2)

        context.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(pieces[0].color))

        let barHeight = pieces[1].isSquare ? BeamAvatar.canvasSize : BeamAvatar.canvasSize / 8
        let bar = CGRect(x: 10, y: 30, width: BeamAvatar.canvasSize, height: barHeight)
        context.fill(
            finalPath(Path(bar), piece: pieces[1], pivot: pivot, scale: scale),
            with: .color(pieces[1].color)
        )

        let dot = CGRect(x: 24, y: 24, width: 32, height: 32)
        context.fill(
            finalPath(Path(ellipseIn: dot), piece: pieces[2], pivot: pivot, scale: scale, rotates: false),
            with: .color(pieces[2].color)
        )

        let line = CGRect(x: 0, y: 39, width: BeamAvatar.canvasSize, height: 2)
        context.fill(
            finalPath(Path(line), piece: pieces[3], pivot: pivot, scale: scale),
            with: .color(pieces[3].color)
        )
    }

    /// SVG's `transform="translate(tx ty) rotate(deg cx cy)"`, applied to a
    /// raw-unit path in the same order — rotate about `pivot` first (the
    /// standard translate/rotate/untranslate recipe), then the outer
    /// translate, then the scale to actual canvas size.
    private static func finalPath(
        _ path: Path, piece: BeamAvatar.Piece, pivot: CGPoint, scale: CGFloat, rotates: Bool = true
    ) -> Path {
        var result = path
        if rotates {
            result = result
                .applying(CGAffineTransform(translationX: -pivot.x, y: -pivot.y))
                .applying(CGAffineTransform(rotationAngle: CGFloat(piece.rotate) * .pi / 180))
                .applying(CGAffineTransform(translationX: pivot.x, y: pivot.y))
        }
        return result
            .applying(CGAffineTransform(translationX: piece.translateX, y: piece.translateY))
            .applying(CGAffineTransform(scaleX: scale, y: scale))
    }
}

#Preview {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
        ForEach(BeamAvatar.presets, id: \.seed) { preset in
            BeamAvatarView(seed: preset.seed, size: 64)
        }
    }
    .padding()
}
