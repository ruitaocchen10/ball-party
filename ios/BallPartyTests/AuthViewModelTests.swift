import Foundation
@testable import BallParty
import Supabase
import XCTest

@MainActor
final class AuthViewModelTests: XCTestCase {
    private func makeSession(email: String = "player@example.com") -> Session {
        let now = Date()
        let user = User(
            id: UUID(),
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            email: email,
            createdAt: now,
            updatedAt: now
        )
        return Session(
            accessToken: "access-token",
            tokenType: "bearer",
            expiresIn: 3600,
            expiresAt: now.timeIntervalSince1970 + 3600,
            refreshToken: "refresh-token",
            user: user
        )
    }

    // MARK: - Sign up

    func test_signUp_rejectsShortDisplayName_withoutCallingBackend() async {
        let backend = FakeAuthBackend()
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signUp(displayName: "A", email: "player@example.com", password: "password123")

        XCTAssertEqual(viewModel.notice, .error("Display name must be 2–16 characters."))
        XCTAssertTrue(backend.signUpCalls.isEmpty)
        XCTAssertNil(viewModel.session)
    }

    func test_signUp_rejectsInvalidEmail_withoutCallingBackend() async {
        let backend = FakeAuthBackend()
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signUp(displayName: "Rui", email: "not-an-email", password: "password123")

        XCTAssertEqual(viewModel.notice, .error("Enter a valid email address."))
        XCTAssertTrue(backend.signUpCalls.isEmpty)
    }

    func test_signUp_rejectsShortPassword_withoutCallingBackend() async {
        let backend = FakeAuthBackend()
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signUp(displayName: "Rui", email: "player@example.com", password: "short")

        XCTAssertEqual(viewModel.notice, .error("Password must be at least 8 characters."))
        XCTAssertTrue(backend.signUpCalls.isEmpty)
    }

    func test_signUp_withValidInput_normalizesEmailAndTrimsDisplayName() async {
        let backend = FakeAuthBackend()
        backend.signUpResult = .success(.session(makeSession()))
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signUp(displayName: "  Rui  ", email: "  Player@Example.com  ", password: "password123")

        XCTAssertEqual(
            backend.signUpCalls,
            [FakeAuthBackend.SignUpCall(email: "player@example.com", password: "password123", displayName: "Rui")]
        )
        XCTAssertNotNil(viewModel.session)
        XCTAssertNil(viewModel.notice)
    }

    private func makeStore() -> (UsernameConfirmationStore, cleanup: () -> Void) {
        let suite = "auth-username-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (UsernameConfirmationStore(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
    }

    func test_signUp_withAnInvalidUsername_rejectsWithoutCallingBackend() async {
        let backend = FakeAuthBackend()
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signUp(displayName: "Rui", username: "a b", email: "player@example.com", password: "password123")

        XCTAssertEqual(viewModel.notice, .error("Use letters, numbers and underscores only."))
        XCTAssertTrue(backend.signUpCalls.isEmpty)
    }

    func test_signUp_withAUsername_claimsItAfterTheSessionAndMarksItConfirmed() async {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let backend = FakeAuthBackend()
        let session = makeSession()
        backend.signUpResult = .success(.session(session))
        let viewModel = AuthViewModel(backend: backend, confirmations: store)

        await viewModel.signUp(displayName: "Rui", username: " @rui_k ", email: "player@example.com", password: "password123")

        XCTAssertEqual(backend.claimUsernameCalls, ["rui_k"])
        XCTAssertNotNil(viewModel.session)
        XCTAssertTrue(store.isConfirmed(session.user.id))
    }

    func test_signUp_whenTheUsernameClaimIsRefused_stillSignsInAndLeavesThePromptForLater() async {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let backend = FakeAuthBackend()
        let session = makeSession()
        backend.signUpResult = .success(.session(session))
        backend.claimUsernameResult = .failure(UsernameError.taken)
        let viewModel = AuthViewModel(backend: backend, confirmations: store)

        await viewModel.signUp(displayName: "Rui", username: "rui_k", email: "player@example.com", password: "password123")

        XCTAssertNotNil(viewModel.session)
        XCTAssertFalse(store.isConfirmed(session.user.id))
    }

    func test_signUp_withABlankUsername_doesNotClaimAnything() async {
        let (store, cleanup) = makeStore()
        defer { cleanup() }
        let backend = FakeAuthBackend()
        backend.signUpResult = .success(.session(makeSession()))
        let viewModel = AuthViewModel(backend: backend, confirmations: store)

        await viewModel.signUp(displayName: "Rui", username: "  ", email: "player@example.com", password: "password123")

        XCTAssertTrue(backend.claimUsernameCalls.isEmpty)
        XCTAssertNotNil(viewModel.session)
    }

    func test_signUp_withoutImmediateSession_showsConfirmationNotice() async {
        let backend = FakeAuthBackend()
        let user = makeSession().user
        backend.signUpResult = .success(.user(user))
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signUp(displayName: "Rui", email: "player@example.com", password: "password123")

        XCTAssertNil(viewModel.session)
        XCTAssertEqual(viewModel.notice, .info("Check your email to confirm your account, then sign in."))
    }

    func test_signUp_whenBackendThrows_surfacesGenericError() async {
        struct SomeError: Error {}
        let backend = FakeAuthBackend()
        backend.signUpResult = .failure(SomeError())
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signUp(displayName: "Rui", email: "player@example.com", password: "password123")

        XCTAssertEqual(viewModel.notice, .error("We couldn't create your account. Try again."))
        XCTAssertNil(viewModel.session)
    }

    // MARK: - Sign in

    func test_signIn_rejectsEmptyFields_withoutCallingBackend() async {
        let backend = FakeAuthBackend()
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signIn(email: "", password: "")

        XCTAssertEqual(viewModel.notice, .error("Enter your email and password."))
        XCTAssertTrue(backend.signInCalls.isEmpty)
    }

    func test_signIn_withValidCredentials_updatesSession() async {
        let backend = FakeAuthBackend()
        backend.signInResult = .success(makeSession())
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signIn(email: "Player@Example.com", password: "password123")

        XCTAssertEqual(backend.signInCalls, [FakeAuthBackend.SignInCall(email: "player@example.com", password: "password123")])
        XCTAssertNotNil(viewModel.session)
    }

    func test_signIn_whenBackendThrows_surfacesVagueError() async {
        struct SomeError: Error {}
        let backend = FakeAuthBackend()
        backend.signInResult = .failure(SomeError())
        let viewModel = AuthViewModel(backend: backend)

        await viewModel.signIn(email: "player@example.com", password: "wrong-password")

        XCTAssertEqual(viewModel.notice, .error("That email and password don't match an account."))
        XCTAssertNil(viewModel.session)
    }

    // MARK: - Sign out

    func test_signOut_clearsSessionEvenIfBackendThrows() async {
        struct SomeError: Error {}
        let backend = FakeAuthBackend()
        backend.currentSession = makeSession()
        backend.signOutError = SomeError()
        let viewModel = AuthViewModel(backend: backend)
        XCTAssertNotNil(viewModel.session)

        await viewModel.signOut()

        XCTAssertEqual(backend.signOutCallCount, 1)
        XCTAssertNil(viewModel.session)
    }

    // MARK: - Delete account

    func test_deleteAccount_onSuccess_clearsTheSessionAndReturnsTrue() async {
        let backend = FakeAuthBackend()
        backend.currentSession = makeSession()
        let viewModel = AuthViewModel(backend: backend)

        let deleted = await viewModel.deleteAccount()

        XCTAssertTrue(deleted)
        XCTAssertEqual(backend.deleteAccountCallCount, 1)
        XCTAssertNil(viewModel.session)
        XCTAssertNil(viewModel.notice)
    }

    func test_deleteAccount_onFailure_keepsTheSessionAndReturnsFalse() async {
        struct SomeError: Error {}
        let backend = FakeAuthBackend()
        backend.currentSession = makeSession()
        backend.deleteAccountError = SomeError()
        let viewModel = AuthViewModel(backend: backend)

        let deleted = await viewModel.deleteAccount()

        XCTAssertFalse(deleted)
        XCTAssertNotNil(viewModel.session)
        // A failure notice would resurface on the next sign-in screen.
        XCTAssertNil(viewModel.notice)
        XCTAssertFalse(viewModel.isBusy)
    }
}
