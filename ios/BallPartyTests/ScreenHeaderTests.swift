import XCTest

@testable import BallParty

final class ScreenHeaderTests: XCTestCase {
    func testBadgeShowsNothingForZeroOrLess() {
        XCTAssertNil(NotificationBadge.label(count: 0))
        XCTAssertNil(NotificationBadge.label(count: -1))
    }

    func testBadgeShowsTheCountUpToNine() {
        XCTAssertEqual(NotificationBadge.label(count: 1), "1")
        XCTAssertEqual(NotificationBadge.label(count: 9), "9")
    }

    func testBadgeCapsAtNinePlus() {
        XCTAssertEqual(NotificationBadge.label(count: 10), "9+")
        XCTAssertEqual(NotificationBadge.label(count: 250), "9+")
    }
}
