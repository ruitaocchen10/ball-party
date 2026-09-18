@testable import BallParty
import SwiftUI
import UIKit
import XCTest

/// The design system's fonts are registered through `UIAppFonts`. A face that
/// fails to register doesn't crash — SwiftUI quietly substitutes the system
/// font — so this is the only thing that notices.
final class ThemeTests: XCTestCase {
    func test_everyBundledFaceLoads() {
        for name in Theme.Face.all {
            XCTAssertNotNil(UIFont(name: name, size: 12), "\(name) is not registered — check UIAppFonts in Info.plist")
        }
    }

    func test_sansWeightsResolveToDistinctFaces() {
        XCTAssertEqual(Theme.sansFace(for: .regular), Theme.Face.sansRegular)
        XCTAssertEqual(Theme.sansFace(for: .medium), Theme.Face.sansMedium)
        XCTAssertEqual(Theme.sansFace(for: .semibold), Theme.Face.sansSemibold)
        XCTAssertEqual(Theme.sansFace(for: .bold), Theme.Face.sansBold)
        XCTAssertEqual(Theme.sansFace(for: .heavy), Theme.Face.sansBold)
    }

    func test_monoWeightsCollapseToTwoFaces() {
        XCTAssertEqual(Theme.monoFace(for: .regular), Theme.Face.monoRegular)
        XCTAssertEqual(Theme.monoFace(for: .semibold), Theme.Face.monoBold)
        XCTAssertEqual(Theme.monoFace(for: .bold), Theme.Face.monoBold)
    }

    /// The hex initialiser is the one place a transposed digit could hide, and
    /// every colour in the app goes through it.
    func test_hexColorsDecodeToTheirChannels() {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(Color(hex: 0xC9382C, opacity: 0.5)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(red, 0xC9 / 255, accuracy: 0.002)
        XCTAssertEqual(green, 0x38 / 255, accuracy: 0.002)
        XCTAssertEqual(blue, 0x2C / 255, accuracy: 0.002)
        XCTAssertEqual(alpha, 0.5, accuracy: 0.002)
    }
}
