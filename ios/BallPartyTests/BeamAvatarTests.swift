import SwiftUI
@testable import BallParty
import XCTest

/// `BeamAvatar`'s geometry against reference values computed by running the
/// actual `boring-avatars` "beam" algorithm (extracted from
/// `webapp/node_modules/boring-avatars/dist/index.js`) in Node for the same
/// seeds and default palette — the strongest available check that this port
/// draws the identical design a web viewer would get for the same preset.
final class BeamAvatarTests: XCTestCase {
    private let palette = BeamAvatar.defaultPalette

    func test_stableHash_matchesTheReferenceJavaScriptHash() {
        XCTAssertEqual(BeamAvatar.stableHash("captain"), 552_565_540)
        XCTAssertEqual(BeamAvatar.stableHash("rookie"), 925_320_267)
    }

    func test_pieces_forCaptain_matchesTheWebsReferenceOutput() {
        let pieces = BeamAvatar.pieces(seed: "captain", palette: palette)

        XCTAssertEqual(pieces.count, 4)
        assertPiece(pieces[0], color: palette[0], tx: -16, ty: 16, rotate: 100, isSquare: false)
        assertPiece(pieces[1], color: palette[1], tx: -20, ty: -20, rotate: 200, isSquare: false)
        assertPiece(pieces[2], color: palette[2], tx: -6, ty: -6, rotate: 300, isSquare: false)
        assertPiece(pieces[3], color: palette[3], tx: 0, ty: 0, rotate: 40, isSquare: false)
    }

    func test_pieces_forRookie_matchesTheWebsReferenceOutput() {
        let pieces = BeamAvatar.pieces(seed: "rookie", palette: palette)

        XCTAssertEqual(pieces.count, 4)
        assertPiece(pieces[0], color: palette[2], tx: -22, ty: -22, rotate: 27, isSquare: true)
        assertPiece(pieces[1], color: palette[3], tx: 6, ty: 6, rotate: 54, isSquare: true)
        assertPiece(pieces[2], color: palette[4], tx: -12, ty: -12, rotate: 81, isSquare: true)
        assertPiece(pieces[3], color: palette[0], tx: -8, ty: -8, rotate: 108, isSquare: true)
    }

    func test_pieces_isDeterministic_sameSeedAndPaletteAlwaysDrawTheSameDesign() {
        XCTAssertEqual(BeamAvatar.pieces(seed: "coach", palette: palette), BeamAvatar.pieces(seed: "coach", palette: palette))
    }

    func test_pieces_withAnEmptyPalette_isEmptyRatherThanCrashing() {
        XCTAssertEqual(BeamAvatar.pieces(seed: "coach", palette: []), [])
    }

    func test_pieces_withoutTheFullFivePresetColors_stillPicksAValidIndex() {
        // A palette shorter than the design's default five still wraps
        // safely via `% count`, rather than indexing out of bounds.
        let small = [Color(hexString: "#000000"), Color(hexString: "#FFFFFF")]
        let pieces = BeamAvatar.pieces(seed: "coach", palette: small)

        XCTAssertEqual(pieces.count, 4)
        for piece in pieces {
            XCTAssertTrue(small.contains(piece.color))
        }
    }

    func test_presets_hasTwelveUniqueSeedsMatchingTheWebsPicker() {
        let seeds = BeamAvatar.presets.map(\.seed)

        XCTAssertEqual(seeds.count, 12)
        XCTAssertEqual(Set(seeds).count, 12, "every preset should be a distinct design")
        XCTAssertEqual(seeds.first, "captain")
        XCTAssertEqual(seeds.last, "underdog")
    }

    func test_hexString_parsesWithOrWithoutALeadingHash() {
        XCTAssertEqual(Color(hexString: "#92A1C6"), Color(hexString: "92A1C6"))
        XCTAssertEqual(Color(hexString: "#92A1C6"), Color(hex: 0x92A1C6))
    }

    private func assertPiece(
        _ piece: BeamAvatar.Piece, color: Color, tx: CGFloat, ty: CGFloat, rotate: Double, isSquare: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(piece.color, color, file: file, line: line)
        XCTAssertEqual(piece.translateX, tx, file: file, line: line)
        XCTAssertEqual(piece.translateY, ty, file: file, line: line)
        XCTAssertEqual(piece.rotate, rotate, file: file, line: line)
        XCTAssertEqual(piece.isSquare, isSquare, file: file, line: line)
    }
}
