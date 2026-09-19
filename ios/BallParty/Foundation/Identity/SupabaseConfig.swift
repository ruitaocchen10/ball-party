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

    private static func infoPlistString(for key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }
}
