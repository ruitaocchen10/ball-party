@testable import BallParty
import XCTest

/// The reasons and refusal copy the report sheet shows. The raw values are the
/// ones `content_reports.reason` accepts (migration 0220) and the copy mirrors
/// the web's `reports.ts`, so a drift on either side fails here.
final class ReportClientTests: XCTestCase {
    func test_reasons_matchTheServersAllowedValuesInTheWebsOrder() {
        XCTAssertEqual(
            ReportReason.allCases.map(\.rawValue),
            ["harassment", "hate", "sexual", "violence", "spam", "other"]
        )
    }

    func test_everyReasonHasALabel() {
        XCTAssertEqual(
            ReportReason.allCases.map(\.label),
            ["Harassment or bullying", "Hate speech", "Sexual content", "Violence or threats", "Spam", "Something else"]
        )
    }

    func test_describe_wordsTheServersRefusals() {
        XCTAssertEqual(ReportError.describe(ReportError(message: "account_required")), "Create an account to report.")
        XCTAssertEqual(ReportError.describe(ReportError(message: "cannot_report_self")), "You can’t report your own take.")
        XCTAssertEqual(ReportError.describe(ReportError(message: "take_not_found")), "That take isn’t available anymore.")
    }

    func test_describe_fallsBackForAnythingElse() {
        XCTAssertEqual(ReportError.describe(ReportError(message: "boom")), "Couldn’t send that. Try again.")
        XCTAssertEqual(
            ReportError.describe(URLError(.notConnectedToInternet)),
            "Couldn’t send that. Check your connection and try again."
        )
    }
}
