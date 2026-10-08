import Foundation

/// Mirrors `webapp/lib/foundation/identity/types.ts` and `validation.ts`. Keep
/// these in lockstep with the web constants — `profiles.display_name` has the
/// same `check` constraint regardless of which client wrote the row.
enum IdentityConstants {
    static let displayNameMin = 2
    static let displayNameMax = 16
    static let passwordMin = 8

    /// Trims and validates a display name. Pure and synchronous so it can run
    /// before any network call.
    static func validateDisplayName(_ input: String) -> FieldValidation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= displayNameMin, trimmed.count <= displayNameMax else {
            return .invalid("Display name must be \(displayNameMin)–\(displayNameMax) characters.")
        }
        return .valid(trimmed)
    }

    static func validateEmail(_ input: String) -> FieldValidation {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            return .invalid("Enter a valid email address.")
        }
        return .valid(trimmed)
    }

    static func validateNewPassword(_ input: String) -> FieldValidation {
        guard input.count >= passwordMin else {
            return .invalid("Password must be at least \(passwordMin) characters.")
        }
        return .valid(input)
    }
}

/// A validated value or the message to show the user — deliberately not
/// `Result<String, Error>`: there's nothing to throw here, just a field that
/// did or didn't pass, the same shape as the web's early-return checks.
enum FieldValidation: Equatable {
    case valid(String)
    case invalid(String)
}

/// The public pages App Store review and players expect to reach from inside
/// the app. These are the web's `/privacy` and `/support` routes
/// (`webapp/app/privacy`, `webapp/app/support`); the host mirrors `SITE_URL`
/// in `webapp/lib/seo/site.ts`.
enum SiteLinks {
    static let privacyPolicy = URL(string: "https://ballparty.social/privacy")!
    static let support = URL(string: "https://ballparty.social/support")!
}
