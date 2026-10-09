import Foundation

/// Mirrors `webapp/lib/foundation/identity/types.ts` and `validation.ts`. Keep
/// these in lockstep with the web constants — `profiles.display_name` has the
/// same `check` constraint regardless of which client wrote the row.
enum IdentityConstants {
    static let displayNameMin = 2
    static let displayNameMax = 16
    static let passwordMin = 8
    static let usernameMin = 3
    static let usernameMax = 20

    /// Trims, drops a leading "@" and validates a username against the same
    /// rule the database enforces (`^[A-Za-z0-9_]{3,20}$`, from
    /// `claim_username`). Pure so the form can show a hint before any network
    /// call; the RPC stays authoritative (reserved names and uniqueness are
    /// only known server-side).
    static func validateUsername(_ input: String) -> FieldValidation {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@") { trimmed.removeFirst() }
        guard trimmed.count >= usernameMin, trimmed.count <= usernameMax else {
            return .invalid("Username must be \(usernameMin)–\(usernameMax) characters.")
        }
        let allowed = trimmed.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
        }
        guard allowed else {
            return .invalid("Use letters, numbers and underscores only.")
        }
        return .valid(trimmed)
    }

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
    static let home = URL(string: "https://ballparty.social")!
    static let privacyPolicy = URL(string: "https://ballparty.social/privacy")!
    static let support = URL(string: "https://ballparty.social/support")!
}

/// What `claim_username` / `username_available` can refuse with, named so the
/// UI shows the same copy for each. Mirrors the error strings in migration
/// 0183 (`invalid_username`, `username_reserved`, `username_taken`,
/// `guests_cannot_have_username`, `rate_limited`).
enum UsernameError: Error, Equatable {
    case invalid
    case reserved
    case taken
    case guest
    case rateLimited
    case other

    /// Maps a PostgREST error (its `message` is the `raise exception` text,
    /// `code` the SQLSTATE) onto a case.
    init(message: String, code: String?) {
        if message.contains("username_taken") || code == "23505" {
            self = .taken
        } else if message.contains("username_reserved") {
            self = .reserved
        } else if message.contains("invalid_username") {
            self = .invalid
        } else if message.contains("guests_cannot_have_username") {
            self = .guest
        } else if message.contains("rate_limited") || code == "54000" {
            self = .rateLimited
        } else {
            self = .other
        }
    }

    var message: String {
        switch self {
        case .invalid: "Use 3–20 letters, numbers or underscores."
        case .reserved: "That username is reserved. Try another."
        case .taken: "That username is taken."
        case .guest: "Guests can’t have a username."
        case .rateLimited: "Too many changes. Try again later."
        case .other: "We couldn’t save your username. Please try again."
        }
    }
}
