@testable import BallParty
import XCTest

final class AppleSignInNonceTests: XCTestCase {
    func test_sha256_matchesKnownVector() {
        // echo -n "hello" | shasum -a 256
        XCTAssertEqual(
            AppleSignInNonce.sha256("hello"),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func test_randomString_hasRequestedLength() {
        XCTAssertEqual(AppleSignInNonce.randomString(length: 32).count, 32)
        XCTAssertEqual(AppleSignInNonce.randomString(length: 8).count, 8)
    }

    func test_randomString_isNotRepeated() {
        let first = AppleSignInNonce.randomString(length: 32)
        let second = AppleSignInNonce.randomString(length: 32)
        XCTAssertNotEqual(first, second)
    }

    func test_generate_hashesTheRawValue() {
        let (raw, hashed) = AppleSignInNonce.generate()
        XCTAssertEqual(hashed, AppleSignInNonce.sha256(raw))
    }
}
