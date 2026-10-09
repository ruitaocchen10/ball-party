import SwiftUI
@testable import BallParty
import XCTest

/// The generated avatar's geometry against what web's `GeneratedAvatar` (boring-avatars 2.0.4)
/// renders for the same names: the expected numbers are read off that library's SVG output.
final class GeneratedAvatarTests: XCTestCase {
    func test_aNamePicksTheSameStyleAndPaletteAsWeb() {
        let expected: [(String, UInt32, String, Int)] = [
            ("Ball Curator", 112_300_522, "marble", 4),
            ("Tasha", 2_335_597_068, "geometric", 3),
            ("Marcus", 235_257_612, "marble", 2),
            ("Priya", 56_376_696, "bauhaus", 4),
            ("Jordan", 7_592_655, "beam", 1),
            ("Sam", 3_709_640_156, "bauhaus", 1),
            ("Dee", 3_361_309_509, "sunset", 1),
            ("Mo", 1_647_190_325, "beam", 0),
            ("Casey", 60_318_424, "sunset", 4),
        ]
        for (name, hash, variant, palette) in expected {
            let choice = GeneratedAvatar.choice(for: name)
            XCTAssertEqual(choice.hash, hash, name)
            XCTAssertEqual(choice.variant, variant, name)
            XCTAssertEqual(choice.paletteIndex, palette, name)
        }
        XCTAssertEqual(GeneratedAvatar.choice(for: "Ball Curator").seed, "ball-party-1uuzmy")
    }

    func test_theNameIsTrimmedAndCaseInsensitive_andEmptyIsPlayer() {
        XCTAssertEqual(GeneratedAvatar.choice(for: "  ball curator "), GeneratedAvatar.choice(for: "Ball Curator"))
        XCTAssertEqual(GeneratedAvatar.choice(for: ""), GeneratedAvatar.choice(for: "Player"))
    }

    func test_theFaceMatchesWeb() throws {
        let tasha = GeneratedAvatar.choice(for: "Tasha")
        let face = GeneratedAvatar.face(seed: tasha.seed, colors: tasha.colors)
        XCTAssertEqual(face.backgroundColor, 0x606C38)
        XCTAssertEqual(face.wrapperColor, 0xFEFAE0)
        XCTAssertEqual(face.faceColor, 0x000000)
        XCTAssertEqual([face.wrapperTranslateX, face.wrapperTranslateY, face.wrapperRotate, face.wrapperScale], [-3, -3, 127, 1.1])
        XCTAssertTrue(face.isCircle)
        XCTAssertEqual([face.faceTranslateX, face.faceTranslateY, face.faceRotate], [-7, -3, -7])
        XCTAssertTrue(face.isMouthOpen)
        XCTAssertEqual(face.mouthSpread, 1)

        let jordan = GeneratedAvatar.choice(for: "Jordan")
        let other = GeneratedAvatar.face(seed: jordan.seed, colors: jordan.colors)
        XCTAssertEqual(other.backgroundColor, 0x2A9D8F)
        XCTAssertEqual(other.wrapperColor, 0xF4A261)
        XCTAssertEqual([other.wrapperTranslateX, other.wrapperTranslateY, other.wrapperRotate], [-4, -4, 88])
        XCTAssertEqual([other.faceTranslateX, other.faceTranslateY, other.faceRotate], [0, -4, 8])
    }

    func test_theMarbleLayersMatchWeb() {
        let curator = GeneratedAvatar.choice(for: "Ball Curator")
        let curatorLayers = GeneratedAvatar.marble(seed: curator.seed, colors: curator.colors)
        XCTAssertEqual(curatorLayers.map(\.color), [0xF2E9E4, 0x22223B, 0x4A4E69])
        XCTAssertEqual([curatorLayers[1].translateX, curatorLayers[1].translateY, curatorLayers[1].rotate], [4, -4, 196])
        XCTAssertEqual([curatorLayers[2].translateX, curatorLayers[2].translateY, curatorLayers[2].rotate, curatorLayers[2].scale], [2, 2, 114, 1.4])
        let marcus = GeneratedAvatar.choice(for: "Marcus")
        let layers = GeneratedAvatar.marble(seed: marcus.seed, colors: marcus.colors)
        XCTAssertEqual(layers.map(\.color), [0xB56576, 0xE56B6F, 0xEAAC8B])
        XCTAssertEqual([layers[1].translateX, layers[1].translateY, layers[1].rotate], [-4, 4, -4])
        XCTAssertEqual([layers[2].translateX, layers[2].translateY, layers[2].rotate, layers[2].scale], [-2, 2, -186, 1.4])
    }

    func test_theSunsetStopsMatchWeb() {
        let dee = GeneratedAvatar.choice(for: "Dee")
        XCTAssertEqual(GeneratedAvatar.sunset(seed: dee.seed, colors: dee.colors), [0xE76F51, 0x264653, 0x2A9D8F, 0xE9C46A])
    }

    func test_theBauhausPiecesMatchWeb() {
        let priya = GeneratedAvatar.choice(for: "Priya")
        let pieces = BeamAvatar.pieces(seed: priya.seed, palette: priya.colors.map { Color(hex: $0) })
        XCTAssertEqual(pieces[0].color, Color(hex: 0x22223B))
        XCTAssertEqual(pieces[1].color, Color(hex: 0x4A4E69))
        XCTAssertEqual([pieces[1].translateX, pieces[1].translateY, CGFloat(pieces[1].rotate)], [-4, -4, 88])
        XCTAssertEqual(pieces[2].color, Color(hex: 0x9A8C98))
        XCTAssertEqual([pieces[2].translateX, pieces[2].translateY], [3, -3])
        XCTAssertEqual([pieces[3].translateX, pieces[3].translateY, CGFloat(pieces[3].rotate)], [16, -16, 176])
    }

    func test_contrastPicksBlackOnLightAndWhiteOnDark() {
        XCTAssertEqual(GeneratedAvatar.contrast(0xFEFAE0), 0x000000)
        XCTAssertEqual(GeneratedAvatar.contrast(0x22223B), 0xFFFFFF)
    }

    func test_anSVGTransformScalesThenRotatesAboutTheCentreThenTranslates() {
        // translate(4 -4) rotate(90 40 40): (40, 0) is 40 above the centre; a quarter turn clockwise puts it 40 to the right.
        let turned = GeneratedAvatar.transform(translate: (4, -4), rotate: 90, about: 40)
        let point = CGPoint(x: 40, y: 0).applying(turned)
        XCTAssertEqual(point.x, 84, accuracy: 0.0001)
        XCTAssertEqual(point.y, 36, accuracy: 0.0001)
        // scale(2) applies first, about the origin.
        let scaled = CGPoint(x: 10, y: 10).applying(GeneratedAvatar.transform(translate: (0, 0), rotate: 0, about: 40, scale: 2))
        XCTAssertEqual(scaled.x, 20, accuracy: 0.0001)
        XCTAssertEqual(scaled.y, 20, accuracy: 0.0001)
    }
}
