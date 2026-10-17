import Foundation
import Supabase

/// Reads the project's Supabase coordinates out of Info.plist, where they land
/// via `$(SUPABASE_URL)` / `$(SUPABASE_ANON_KEY)` build-setting substitution —
/// see `ios/Secrets.xcconfig.example`. Mirrors `webapp/lib/supabase/client.ts`,
/// which reads the same values from `NEXT_PUBLIC_SUPABASE_URL` /
/// `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. Both are the publishable key, safe
/// to ship in a compiled app — RLS is what protects the data.
enum SupabaseConfig {
    /// Custom URL scheme the app registers (`CFBundleURLTypes` in Info.plist)
    /// so `ASWebAuthenticationSession` can hand OAuth control back to us.
    static let oauthCallbackScheme = "com.ballparty.app"

    static var oauthRedirectURL: URL {
        URL(string: "\(oauthCallbackScheme)://login-callback")!
    }

    /// The project URL, for links to public Storage objects such as the team
    /// logos. `client` traps when it is missing; a logo that can't be built
    /// should only fall back to text, so this doesn't.
    static var projectURL: URL? {
        URL(string: infoPlistString(for: "SUPABASE_URL"))
    }

    static let client: SupabaseClient = {
        guard let url = URL(string: infoPlistString(for: "SUPABASE_URL")) else {
            preconditionFailure(
                "SUPABASE_URL is missing or invalid. Copy ios/Secrets.xcconfig.example to ios/Secrets.xcconfig and fill it in."
            )
        }
        let key = infoPlistString(for: "SUPABASE_ANON_KEY")
        precondition(
            !key.isEmpty,
            "SUPABASE_ANON_KEY is missing. Copy ios/Secrets.xcconfig.example to ios/Secrets.xcconfig and fill it in."
        )
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()

    /// Whether PostgREST refused the request over its token (`JWT expired`,
    /// `Invalid JWT`; PGRST301/303), as opposed to a rule the server raised.
    static func isAuthFailure(_ error: Error) -> Bool {
        guard let error = error as? PostgrestError else { return false }
        return error.code == "PGRST301" || error.code == "PGRST303"
            || error.message.localizedCaseInsensitiveContains("jwt")
    }

    /// Runs `body`, and when the server rejects the token, as on a cold launch
    /// whose stored session has expired, refreshes the session and runs it once
    /// more. A refresh that fails too surfaces the original error.
    static func retryingAfterRefresh<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch where isAuthFailure(error) {
            guard (try? await client.auth.refreshSession()) != nil else { throw error }
            return try await body()
        }
    }

    private static func infoPlistString(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
