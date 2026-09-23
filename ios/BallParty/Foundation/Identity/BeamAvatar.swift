import SwiftUI

/// A Swift port of `boring-avatars`' "beam" generator — the algorithm behind
/// `webapp/components/foundation/identity/PresetAvatarPicker.tsx`'s starter
/// avatars. Given a seed and a five-color palette it deterministically lays
/// out four pieces (background, bar, dot, line), the same way every time, so
/// choosing "Captain" means the same design on web and mobile.
///
/// This only computes the geometry; `BeamAvatarView` draws it and rasterizes
/// it to a PNG for upload, since `AsyncImage` can't decode the SVG the web
/// picker produces.
enum BeamAvatar {
    /// The SVG viewBox's side length every raw coordinate below is expressed in.
    static let canvasSize: CGFloat = 80

    /// Label, seed pairs — identical to `PresetAvatarPicker.tsx`'s `PRESETS`,
    /// in the same order, so the grid matches position-for-position.
    static let presets: [(label: String, seed: String)] = [
        ("Captain", "captain"),
        ("Rookie", "rookie"),
        ("Coach", "coach"),
        ("Ref", "referee"),
        ("MVP", "most-valuable-player"),
        ("Closer", "closer"),
        ("Wildcard", "wildcard"),
        ("Playmaker", "playmaker"),
        ("Gameday", "gameday"),
        ("Overtime", "overtime"),
        ("Rivalry", "rivalry"),
        ("Underdog", "underdog"),
    ]

    /// `boring-avatars`' neutral default palette, colors `webapp`'s
    /// `PresetAvatarPicker` starts every visitor with.
    static let defaultPalette: [Color] = [
        Color(hex: 0x92A1C6), Color(hex: 0x146A7C), Color(hex: 0xF0AB3D), Color(hex: 0xC271B4), Color(hex: 0xC20D90),
    ]

    /// One of the four pieces a beam avatar is built from, in raw SVG units
    /// (an 80×80 box) — `translateX`/`translateY` are the outer translate,
    /// `rotate` in degrees around the box's center (40, 40).
    struct Piece: Equatable {
        let color: Color
        let translateX: CGFloat
        let translateY: CGFloat
        let rotate: Double
        /// Whether the "bar" piece fills the whole box instead of a thin
        /// band — the same value for all four pieces, since the web reads
        /// it off the seed's hash directly rather than per-piece.
        let isSquare: Bool
    }

    /// The four pieces for `seed` against `palette`, in the fixed order the
    /// web draws them: background, bar, dot, line.
    static func pieces(seed: String, palette: [Color]) -> [Piece] {
        guard !palette.isEmpty else { return [] }
        let hash = stableHash(seed)
        let count = Int64(palette.count)
        return (0..<4).map { t in
            let index = t + 1
            let product = hash * Int64(index)
            let range = Int64(canvasSize / 2) - Int64(index + 16)
            return Piece(
                color: palette[Int((hash + Int64(t)) % count)],
                translateX: CGFloat(rangeValue(product, range, signDigit: 1)),
                translateY: CGFloat(rangeValue(product, range, signDigit: 2)),
                rotate: Double(rangeValue(product, 360, signDigit: nil)),
                isSquare: isEven(hash, 2)
            )
        }
    }

    /// The `l = (l << 5) - l + charCode; l |= 0` string hash `boring-avatars`
    /// hashes every seed with, widened to `Int64` before `abs` so the 32-bit
    /// wraparound can't overflow the way it would in `Int32`.
    static func stableHash(_ seed: String) -> Int64 {
        var hash: Int32 = 0
        for unit in seed.utf16 {
            hash = (hash &<< 5) &- hash &+ Int32(unit)
        }
        return abs(Int64(hash))
    }

    /// `floor(number / 10^position) % 10` — the decimal digit at `position`
    /// (0 = ones, 1 = tens, …), matching the web's `getDigit` exactly for
    /// every non-negative `number` this module ever calls it with.
    private static func digit(_ number: Int64, _ position: Int) -> Int64 {
        let divisor = Int64(pow(10, Double(position)))
        return (number / divisor) % 10
    }

    private static func isEven(_ number: Int64, _ position: Int) -> Bool {
        digit(number, position).isMultiple(of: 2)
    }

    /// `number % range`, negated when the digit at `signDigit` is even — the
    /// web's `getRangeValue`. `signDigit == nil` mirrors calling it with no
    /// third argument, which always keeps the positive value.
    private static func rangeValue(_ number: Int64, _ range: Int64, signDigit: Int?) -> Int64 {
        let magnitude = number % range
        if let signDigit, isEven(number, signDigit) { return -magnitude }
        return magnitude
    }
}

extension Color {
    /// A `"#RRGGBB"` string, as `boring-avatars` palettes and the native
    /// `ColorPicker` both hand back. Falls back to opaque black on anything
    /// that doesn't parse, since a bad swatch should still render *a* color.
    init(hexString: String) {
        var hex = hexString
        if hex.hasPrefix("#") { hex.removeFirst() }
        self = Color(hex: UInt32(hex, radix: 16) ?? 0)
    }
}
