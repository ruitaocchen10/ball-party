@testable import BallParty
import XCTest

/// Mirrors `webapp/lib/foundation/identity/validation.test.ts` — same
/// boundaries, same rows, ported per constraint.
final class IdentityConstantsTests: XCTestCase {
    func test_validateDisplayName_trimsWhitespace() {
        guard case .valid(let name) = IdentityConstants.validateDisplayName("  Rui  ") else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(name, "Rui")
    }

    func test_validateDisplayName_rejectsBelowMinimum() {
        guard case .invalid(let message) = IdentityConstants.validateDisplayName("A") else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(message, "Display name must be 2–16 characters.")
    }

    func test_validateDisplayName_acceptsMinimumLength() {
        guard case .valid(let name) = IdentityConstants.validateDisplayName("Al") else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(name, "Al")
    }

    func test_validateDisplayName_acceptsMaximumLength() {
        let name16 = String(repeating: "x", count: 16)
        guard case .valid(let name) = IdentityConstants.validateDisplayName(name16) else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(name, name16)
    }

    func test_validateDisplayName_rejectsAboveMaximum() {
        let name17 = String(repeating: "x", count: 17)
        guard case .invalid(let message) = IdentityConstants.validateDisplayName(name17) else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(message, "Display name must be 2–16 characters.")
    }

    func test_validateEmail_lowercasesAndTrims() {
        guard case .valid(let email) = IdentityConstants.validateEmail("  Player@Example.COM  ") else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(email, "player@example.com")
    }

    func test_validateEmail_rejectsMissingAtSign() {
        guard case .invalid = IdentityConstants.validateEmail("not-an-email") else {
            return XCTFail("expected failure")
        }
    }

    func test_validateNewPassword_rejectsBelowMinimum() {
        guard case .invalid(let message) = IdentityConstants.validateNewPassword("short") else {
            return XCTFail("expected failure")
        }
        XCTAssertEqual(message, "Password must be at least 8 characters.")
    }

    func test_validateNewPassword_acceptsMinimumLength() {
        guard case .valid(let password) = IdentityConstants.validateNewPassword("12345678") else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(password, "12345678")
    }

    func test_siteLinks_pointAtTheWebsPrivacyAndSupportRoutes() {
        XCTAssertEqual(SiteLinks.privacyPolicy.absoluteString, "https://ballparty.social/privacy")
        XCTAssertEqual(SiteLinks.support.absoluteString, "https://ballparty.social/support")
    }
}
