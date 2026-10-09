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

    // MARK: - Username

    func test_validateUsername_acceptsLettersDigitsUnderscoresAndKeepsCase() {
        XCTAssertEqual(IdentityConstants.validateUsername("Sam_99"), .valid("Sam_99"))
        XCTAssertEqual(IdentityConstants.validateUsername("abc"), .valid("abc"))
        XCTAssertEqual(IdentityConstants.validateUsername(String(repeating: "a", count: 20)), .valid(String(repeating: "a", count: 20)))
    }

    func test_validateUsername_trimsWhitespaceAndALeadingAt() {
        XCTAssertEqual(IdentityConstants.validateUsername("  @sam_k "), .valid("sam_k"))
    }

    func test_validateUsername_rejectsTooShortAndTooLong() {
        XCTAssertEqual(
            IdentityConstants.validateUsername("ab"), .invalid("Username must be 3–20 characters.")
        )
        XCTAssertEqual(
            IdentityConstants.validateUsername(String(repeating: "a", count: 21)),
            .invalid("Username must be 3–20 characters.")
        )
    }

    func test_validateUsername_rejectsOtherCharacters() {
        let expected = FieldValidation.invalid("Use letters, numbers and underscores only.")
        XCTAssertEqual(IdentityConstants.validateUsername("sam k"), expected)
        XCTAssertEqual(IdentityConstants.validateUsername("sam-k"), expected)
        XCTAssertEqual(IdentityConstants.validateUsername("sám_k"), expected)
    }

    func test_usernameError_mapsTheRpcErrorStrings() {
        XCTAssertEqual(UsernameError(message: "username_taken", code: "23505"), .taken)
        XCTAssertEqual(UsernameError(message: "duplicate", code: "23505"), .taken)
        XCTAssertEqual(UsernameError(message: "username_reserved", code: "22023"), .reserved)
        XCTAssertEqual(UsernameError(message: "invalid_username", code: "22023"), .invalid)
        XCTAssertEqual(UsernameError(message: "guests_cannot_have_username", code: "42501"), .guest)
        XCTAssertEqual(UsernameError(message: "rate_limited", code: "54000"), .rateLimited)
        XCTAssertEqual(UsernameError(message: "boom", code: nil), .other)
    }

    func test_rpcScalars_decodeFromTheJSONPostgRESTReturns() throws {
        // `username_available` returns a bare boolean and `claim_username` a
        // bare string; `.execute().value` decodes both as JSON fragments.
        XCTAssertEqual(try JSONDecoder().decode(Bool.self, from: Data("true".utf8)), true)
        XCTAssertEqual(try JSONDecoder().decode(String.self, from: Data("\"Sam_99\"".utf8)), "Sam_99")
    }

    func test_usernameConfirmationStore_isPerUser() {
        let suite = "username-confirm-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsernameConfirmationStore(defaults: defaults)
        let a = UUID()
        let b = UUID()

        XCTAssertFalse(store.isConfirmed(a))
        store.markConfirmed(a)

        XCTAssertTrue(store.isConfirmed(a))
        XCTAssertFalse(store.isConfirmed(b))
    }

    func test_siteLinks_pointAtTheWebsPrivacyAndSupportRoutes() {
        XCTAssertEqual(SiteLinks.privacyPolicy.absoluteString, "https://ballparty.social/privacy")
        XCTAssertEqual(SiteLinks.support.absoluteString, "https://ballparty.social/support")
    }
}
