import XCTest
@testable import BallParty

/// `RoomLink.code(from:)` against the web's `/lobby/[code]` route.
final class RoomLinkTests: XCTestCase {
    func testParsesARoomLink() {
        XCTAssertEqual(RoomLink.code(from: URL(string: "https://ballparty.social/lobby/ab3k7")!), "AB3K7")
        XCTAssertEqual(RoomLink.code(from: RoomLink.url(code: "AB3K7")), "AB3K7")
        XCTAssertEqual(RoomLink.code(from: URL(string: "https://www.ballparty.social/lobby/AB3K7/?x=1")!), "AB3K7")
    }

    func testRejectsAnythingElse() {
        for raw in [
            "http://ballparty.social/lobby/AB3K7",
            "https://evil.example/lobby/AB3K7",
            "https://ballparty.social.evil.example/lobby/AB3K7",
            "https://ballparty.social/lobby",
            "https://ballparty.social/lobby/AB3K7/extra",
            "https://ballparty.social/lobby/AB-3K",
            "https://ballparty.social/friends/invite/AB3K7",
        ] {
            XCTAssertNil(RoomLink.code(from: URL(string: raw)!), raw)
        }
    }
}
