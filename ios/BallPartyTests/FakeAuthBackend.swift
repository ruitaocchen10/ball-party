import AuthenticationServices
import Foundation
@testable import BallParty
import Supabase

/// Records every call `AuthViewModel` makes and lets a test script the
/// response, so `AuthViewModelTests` can exercise the view model's
/// orchestration (validation gating, error surfacing, session updates)
/// without touching the network.
final class FakeAuthBackend: AuthBackend, @unchecked Sendable {
    struct SignUpCall: Equatable { let email: String; let password: String; let displayName: String }
    struct SignInCall: Equatable { let email: String; let password: String }
    struct SetDisplayNameCall: Equatable { let displayName: String; let userId: UUID }

    var currentSession: Session?
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        AsyncStream { $0.finish() }
    }

    var signUpCalls: [SignUpCall] = []
    var signUpResult: Result<AuthResponse, Error> = .failure(CancellationError())

    var signInCalls: [SignInCall] = []
    var signInResult: Result<Session, Error> = .failure(CancellationError())

    var signInWithIdTokenCalls: [OpenIDConnectCredentials] = []
    var signInWithIdTokenResult: Result<Session, Error> = .failure(CancellationError())

    var signInWithOAuthCallCount = 0
    var signInWithOAuthResult: Result<Session, Error> = .failure(CancellationError())

    var signOutCallCount = 0
    var signOutError: Error?
    var setDisplayNameCalls: [SetDisplayNameCall] = []

    func signUp(email: String, password: String, displayName: String) async throws -> AuthResponse {
        signUpCalls.append(SignUpCall(email: email, password: password, displayName: displayName))
        return try signUpResult.get()
    }

    func signIn(email: String, password: String) async throws -> Session {
        signInCalls.append(SignInCall(email: email, password: password))
        return try signInResult.get()
    }

    func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session {
        signInWithIdTokenCalls.append(credentials)
        return try signInWithIdTokenResult.get()
    }

    func signInWithOAuth(
        provider: Provider,
        redirectTo: URL,
        configure: @Sendable (ASWebAuthenticationSession) -> Void
    ) async throws -> Session {
        signInWithOAuthCallCount += 1
        return try signInWithOAuthResult.get()
    }

    func signOut() async throws {
        signOutCallCount += 1
        if let signOutError { throw signOutError }
    }

    func setDisplayName(_ displayName: String, userId: UUID) async throws {
        setDisplayNameCalls.append(SetDisplayNameCall(displayName: displayName, userId: userId))
    }
}
