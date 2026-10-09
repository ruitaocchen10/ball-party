import SwiftUI

/// The avatar a player gets before they choose an image: a Swift port of web's
/// `GeneratedAvatar` (`webapp/components/foundation/identity/GeneratedAvatar.tsx`) over
/// `boring-avatars` 2.0.4, so the same name draws the same picture on both apps.
///
/// The name picks everything. It is trimmed and lowercased, hashed with 32-bit FNV-1a, and the
/// hash picks one of five styles (`beam`, `bauhaus`, `marble`, `geometric`, `sunset`) and one of
/// five palettes. The seed `ball-party-<hash in base 36>` then feeds the style's own geometry.
/// In 2.0.4 `beam` and `geometric` are both the face, and `bauhaus` is the four-piece style
/// `BeamAvatar` already draws, so there are four looks. Everything here is the geometry (what the
/// tests check against web); `GeneratedAvatarView` draws it.
enum GeneratedAvatar {
    static let variants = ["beam", "bauhaus", "marble", "geometric", "sunset"]

    /// The five palettes, as `0xRRGGBB`: identical to web's `PALETTES`, in the same order.
    static let palettes: [[UInt32]] = [
        [0x92A1C6, 0x146A7C, 0xF0AB3D, 0xC271B4, 0xC20D90],
        [0x264653, 0x2A9D8F, 0xE9C46A, 0xF4A261, 0xE76F51],
        [0x355070, 0x6D597A, 0xB56576, 0xE56B6F, 0xEAAC8B],
        [0x606C38, 0x283618, 0xFEFAE0, 0xDDA15E, 0xBC6C25],
        [0x4A4E69, 0x9A8C98, 0xC9ADA7, 0xF2E9E4, 0x22223B],
    ]

    /// What a name resolves to before any geometry: the hash, the style and palette it picks.
    struct Choice: Equatable {
        let hash: UInt32
        let seed: String
        let variant: String
        let paletteIndex: Int
        var colors: [UInt32] { GeneratedAvatar.palettes[paletteIndex] }
    }

    /// Web's `stableHash`: 32-bit FNV-1a over the UTF-16 units of the trimmed, lowercased name.
    static func choice(for name: String) -> Choice {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var hash: UInt32 = 2_166_136_261
        for unit in (trimmed.isEmpty ? "player" : trimmed).utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16_777_619
        }
        return Choice(
            hash: hash,
            seed: "ball-party-" + String(hash, radix: 36),
            variant: variants[Int(hash) % variants.count],
            paletteIndex: (Int(hash) / variants.count) % palettes.count
        )
    }

    // MARK: - boring-avatars' helpers

    private static func digit(_ number: Int64, _ position: Int) -> Int64 {
        var divisor: Int64 = 1
        for _ in 0..<position { divisor *= 10 }
        return (number / divisor) % 10
    }

    /// `getBoolean`: true when the digit at `position` is even.
    private static func flag(_ number: Int64, _ position: Int) -> Bool { digit(number, position) % 2 == 0 }

    /// `getUnit`: `number % range`, negated when the digit at `signDigit` is even.
    private static func unit(_ number: Int64, _ range: Int64, signDigit: Int? = nil) -> Double {
        let magnitude = number % range
        if let signDigit, flag(number, signDigit) { return Double(-magnitude) }
        return Double(magnitude)
    }

    /// `getRandomColor`: `colors[number % colors.count]`.
    private static func color(_ number: Int64, _ colors: [UInt32]) -> UInt32 { colors[Int(number % Int64(colors.count))] }

    /// `getContrast`: black on a light colour, white on a dark one.
    static func contrast(_ hex: UInt32) -> UInt32 {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        return (r * 299 + g * 587 + b * 114) / 1000 >= 128 ? 0x000000 : 0xFFFFFF
    }

    // MARK: - Face (`beam`, and `geometric`, which 2.0.4 maps to the same component)

    struct Face: Equatable {
        let wrapperColor: UInt32
        let faceColor: UInt32
        let backgroundColor: UInt32
        let wrapperTranslateX: Double
        let wrapperTranslateY: Double
        let wrapperRotate: Double
        let wrapperScale: Double
        let isMouthOpen: Bool
        let isCircle: Bool
        let eyeSpread: Double
        let mouthSpread: Double
        let faceRotate: Double
        let faceTranslateX: Double
        let faceTranslateY: Double
    }

    static let faceCanvas = 36.0

    static func face(seed: String, colors: [UInt32]) -> Face {
        let i = BeamAvatar.stableHash(seed)
        let size = faceCanvas
        let n = unit(i, 10, signDigit: 1)
        let tx = n < 5 ? n + size / 9 : n
        let s = unit(i, 10, signDigit: 2)
        let ty = s < 5 ? s + size / 9 : s
        let wrapper = color(i, colors)
        return Face(
            wrapperColor: wrapper,
            faceColor: contrast(wrapper),
            backgroundColor: color(i + 13, colors),
            wrapperTranslateX: tx,
            wrapperTranslateY: ty,
            wrapperRotate: unit(i, 360),
            wrapperScale: 1 + unit(i, Int64(size / 12)) / 10,
            isMouthOpen: flag(i, 2),
            isCircle: flag(i, 1),
            eyeSpread: unit(i, 5),
            mouthSpread: unit(i, 3),
            faceRotate: unit(i, 10, signDigit: 3),
            faceTranslateX: tx > size / 6 ? tx / 2 : unit(i, 8, signDigit: 1),
            faceTranslateY: ty > size / 6 ? ty / 2 : unit(i, 7, signDigit: 2)
        )
    }

    // MARK: - Marble

    struct MarbleLayer: Equatable {
        let color: UInt32
        let translateX: Double
        let translateY: Double
        let scale: Double
        let rotate: Double
    }

    static let marbleCanvas = 80.0

    /// Three layers: the background colour, then the two blurred shapes (the second blends as
    /// `overlay`). Both shapes are scaled by the *third* layer's scale, as the library does.
    static func marble(seed: String, colors: [UInt32]) -> [MarbleLayer] {
        let i = BeamAvatar.stableHash(seed)
        let size = Int64(marbleCanvas)
        return (0..<3).map { t in
            let product = i * Int64(t + 1)
            return MarbleLayer(
                color: color(i + Int64(t), colors),
                translateX: unit(product, size / 10, signDigit: 1),
                translateY: unit(product, size / 10, signDigit: 2),
                scale: 1.2 + unit(product, size / 20) / 10,
                rotate: unit(product, 360, signDigit: 1)
            )
        }
    }

    // MARK: - Sunset

    /// Four gradient stops: the top half runs `[0]` to `[1]`, the bottom half `[2]` to `[3]`.
    static func sunset(seed: String, colors: [UInt32]) -> [UInt32] {
        let i = BeamAvatar.stableHash(seed)
        return (0..<4).map { color(i + Int64($0), colors) }
    }

    // MARK: - SVG transforms

    /// SVG's `translate(tx ty) rotate(deg cx cy) scale(s)`: the scale applies first, then the
    /// rotation about `(cx, cy)`, then the translation.
    static func transform(translate: (Double, Double), rotate: Double, about center: Double, scale: Double = 1) -> CGAffineTransform {
        let c = CGFloat(center)
        return CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale))
            .concatenating(CGAffineTransform(translationX: -c, y: -c))
            .concatenating(CGAffineTransform(rotationAngle: CGFloat(rotate * .pi / 180)))
            .concatenating(CGAffineTransform(translationX: c, y: c))
            .concatenating(CGAffineTransform(translationX: CGFloat(translate.0), y: CGFloat(translate.1)))
    }
}

/// A circle of the generated avatar for `name`.
struct GeneratedAvatarView: View {
    let name: String

    var body: some View {
        let choice = GeneratedAvatar.choice(for: name)
        Canvas { context, size in
            context.clip(to: Path(ellipseIn: CGRect(origin: .zero, size: size)))
            switch choice.variant {
            case "bauhaus": Self.drawBauhaus(&context, size, choice)
            case "marble": Self.drawMarble(&context, size, choice)
            case "sunset": Self.drawSunset(&context, size, choice)
            default: Self.drawFace(&context, size, choice)
            }
        }
        .accessibilityHidden(true)
    }

    private static func swatch(_ hex: UInt32) -> GraphicsContext.Shading { .color(Color(hex: hex)) }

    // MARK: Face

    private static func drawFace(_ context: inout GraphicsContext, _ size: CGSize, _ choice: GeneratedAvatar.Choice) {
        let canvas = GeneratedAvatar.faceCanvas
        let f = GeneratedAvatar.face(seed: choice.seed, colors: choice.colors)
        context.scaleBy(x: size.width / canvas, y: size.height / canvas)
        context.fill(Path(CGRect(x: 0, y: 0, width: canvas, height: canvas)), with: swatch(f.backgroundColor))

        var wrapper = context
        wrapper.concatenate(GeneratedAvatar.transform(
            translate: (f.wrapperTranslateX, f.wrapperTranslateY), rotate: f.wrapperRotate, about: canvas / 2, scale: f.wrapperScale
        ))
        let rect = CGRect(x: 0, y: 0, width: canvas, height: canvas)
        wrapper.fill(
            Path(roundedRect: rect, cornerRadius: f.isCircle ? canvas : canvas / 6), with: swatch(f.wrapperColor)
        )

        var face = context
        face.concatenate(GeneratedAvatar.transform(
            translate: (f.faceTranslateX, f.faceTranslateY), rotate: f.faceRotate, about: canvas / 2
        ))
        let ink = swatch(f.faceColor)
        let mouthY = 19 + f.mouthSpread
        if f.isMouthOpen {
            // "M15 y c2 1 4 1 6 0", a 1-unit round-capped stroke.
            var mouth = Path()
            mouth.move(to: CGPoint(x: 15, y: mouthY))
            mouth.addCurve(to: CGPoint(x: 21, y: mouthY), control1: CGPoint(x: 17, y: mouthY + 1), control2: CGPoint(x: 19, y: mouthY + 1))
            face.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: 1, lineCap: .round))
        } else {
            // "M13,y a1,0.75 0 0,0 10,0": the radii are too small for the chord, so SVG scales them up
            // to a half ellipse 5 wide and 3.75 deep, drawn below the line (a smile).
            var mouth = Path()
            mouth.move(to: CGPoint(x: 13, y: mouthY))
            for step in 0...32 {
                let angle = Double.pi - Double.pi * Double(step) / 32
                mouth.addLine(to: CGPoint(x: 18 + 5 * cos(angle), y: mouthY + 3.75 * sin(angle)))
            }
            mouth.closeSubpath()
            face.fill(mouth, with: ink)
        }
        for x in [14 - f.eyeSpread, 20 + f.eyeSpread] {
            face.fill(Path(roundedRect: CGRect(x: x, y: 14, width: 1.5, height: 2), cornerRadius: 0.75), with: ink)
        }
    }

    // MARK: Bauhaus (the four-piece style `BeamAvatar` computes)

    private static func drawBauhaus(_ context: inout GraphicsContext, _ size: CGSize, _ choice: GeneratedAvatar.Choice) {
        let canvas = BeamAvatar.canvasSize
        let pieces = BeamAvatar.pieces(seed: choice.seed, palette: choice.colors.map { Color(hex: $0) })
        guard pieces.count == 4 else { return }
        context.scaleBy(x: size.width / canvas, y: size.height / canvas)
        context.fill(Path(CGRect(x: 0, y: 0, width: canvas, height: canvas)), with: .color(pieces[0].color))

        func placed(_ piece: BeamAvatar.Piece, rotates: Bool) -> GraphicsContext {
            var layer = context
            layer.concatenate(GeneratedAvatar.transform(
                translate: (Double(piece.translateX), Double(piece.translateY)), rotate: rotates ? piece.rotate : 0, about: canvas / 2
            ))
            return layer
        }
        // Bar: x = 10, y = 30, as wide as the canvas, a full square or an eighth tall.
        let bar = pieces[1]
        placed(bar, rotates: true).fill(
            Path(CGRect(x: 10, y: 30, width: canvas, height: bar.isSquare ? canvas : canvas / 8)), with: .color(bar.color)
        )
        // Dot: centred, radius a fifth of the canvas.
        let dot = pieces[2]
        placed(dot, rotates: false).fill(
            Path(ellipseIn: CGRect(x: canvas / 2 - canvas / 5, y: canvas / 2 - canvas / 5, width: canvas * 2 / 5, height: canvas * 2 / 5)),
            with: .color(dot.color)
        )
        // Line: across the middle, 2 wide.
        let line = pieces[3]
        var stroke = Path()
        stroke.move(to: CGPoint(x: 0, y: canvas / 2))
        stroke.addLine(to: CGPoint(x: canvas, y: canvas / 2))
        placed(line, rotates: true).stroke(stroke, with: .color(line.color), lineWidth: 2)
    }

    // MARK: Marble

    private static func drawMarble(_ context: inout GraphicsContext, _ size: CGSize, _ choice: GeneratedAvatar.Choice) {
        let canvas = GeneratedAvatar.marbleCanvas
        let layers = GeneratedAvatar.marble(seed: choice.seed, colors: choice.colors)
        context.scaleBy(x: size.width / canvas, y: size.height / canvas)
        context.fill(Path(CGRect(x: 0, y: 0, width: canvas, height: canvas)), with: swatch(layers[0].color))

        // Both shapes blur by 7 and use the third layer's scale, as the library does.
        let first = Self.polygon([
            (32.414, 59.35), (50.376, 70.5), (72.5, 70.5), (72.5, -0.5), (33.728, -0.5), (26.5, 13.381), (45.557, 40.461),
        ])
        let second = Self.polygon([
            (22.216, 24), (0, 46.75), (14.108, 84.879), (78, 86), (74.919, 26.724), (52.541, 30.729), (65.513, 50.915), (42.163, 78.31),
        ])
        for (index, shape) in [(1, first), (2, second)] {
            var layer = context
            layer.addFilter(.blur(radius: 7))
            if index == 2 { layer.blendMode = .overlay }
            layer.concatenate(GeneratedAvatar.transform(
                translate: (layers[index].translateX, layers[index].translateY),
                rotate: layers[index].rotate, about: canvas / 2, scale: layers[2].scale
            ))
            layer.fill(shape, with: swatch(layers[index].color))
        }
    }

    private static func polygon(_ points: [(Double, Double)]) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let p = CGPoint(x: point.0, y: point.1)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    // MARK: Sunset

    private static func drawSunset(_ context: inout GraphicsContext, _ size: CGSize, _ choice: GeneratedAvatar.Choice) {
        let canvas = 80.0
        let stops = GeneratedAvatar.sunset(seed: choice.seed, colors: choice.colors)
        context.scaleBy(x: size.width / canvas, y: size.height / canvas)
        func band(y: Double, from: UInt32, to: UInt32) {
            context.fill(
                Path(CGRect(x: 0, y: y, width: canvas, height: canvas / 2)),
                with: .linearGradient(
                    Gradient(colors: [Color(hex: from), Color(hex: to)]),
                    startPoint: CGPoint(x: canvas / 2, y: y), endPoint: CGPoint(x: canvas / 2, y: y + canvas / 2)
                )
            )
        }
        band(y: 0, from: stops[0], to: stops[1])
        band(y: canvas / 2, from: stops[2], to: stops[3])
    }
}
