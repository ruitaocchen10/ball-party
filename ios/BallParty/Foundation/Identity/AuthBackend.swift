import AuthenticationServices
import Foundation
import Supabase

/// The slice of `SupabaseClient` that `AuthViewModel` needs, named as its own
/// protocol so tests can substitute a fake instead of hitting the network.
/// Defined with the exact parameter lists `AuthViewModel` calls with — Swift
/// protocol conformance is by exact signature, so `SupabaseAuthBackend` below
/// adapts the real client's defaulted parameters rather than extending it
/// directly.
protocol AuthBackend: Sendable {
    var currentSession: Session? { get }
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> { get }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthResponse
    func signIn(email: String, password: String) async throws -> Session
    func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session
    func signInWithOAuth(
        provider: Provider,
        redirectTo: URL,
        configure: @Sendable (ASWebAuthenticationSession) -> Void
    ) async throws -> Session
    func signOut() async throws

    /// Best-effort backfill for providers that hand us a display name outside
    /// the id token. Apple gives `fullName` only on the credential from the
    /// account's very first authorization, never on the id token itself and
    /// never again after — so callers only reach this once per account, right
    /// after `handle_new_user` has inserted its fallback row.
    func setDisplayName(_ displayName: String, userId: UUID) async throws
}

struct SupabaseAuthBackend: AuthBackend {
    let client: SupabaseClient

    var currentSession: Session? { client.auth.currentSession }

    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        client.auth.authStateChanges
    }

    func signUp(email: String, password: String, displayName: String) async throws -> AuthResponse {
        try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )
    }

    func signIn(email: String, password: String) async throws -> Session {
        try await client.auth.signIn(email: email, password: password)
    }

    func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session {
        try await client.auth.signInWithIdToken(credentials: credentials)
    }

    func signInWithOAuth(
        provider: Provider,
        redirectTo: URL,
        configure: @Sendable (ASWebAuthenticationSession) -> Void
    ) async throws -> Session {
        try await client.auth.signInWithOAuth(
            provider: provider,
            redirectTo: redirectTo,
            configure: configure
        )
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func setDisplayName(_ displayName: String, userId: UUID) async throws {
        try await client.from("profiles")
            .update(["display_name": displayName])
            .eq("id", value: userId.uuidString)
            .execute()
    }
}
