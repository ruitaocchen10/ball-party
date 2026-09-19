import AuthenticationServices
import Foundation
import Supabase

/// Owns the app's session state and every sign-in/up/out path. There is no
/// guest mode on iOS — `AuthGateView` shows `AuthView` for any nil session,
/// full stop, so nothing here ever mints an anonymous session.
@MainActor
final class AuthViewModel: ObservableObject {
    enum Notice: Equatable {
        case error(String)
        case info(String)

        var message: String {
            switch self {
            case .error(let message), .info(let message): message
            }
        }
    }

    @Published private(set) var session: Session?
    @Published private(set) var isBusy = false
    @Published var notice: Notice?

    private let backend: AuthBackend
    private var authStateTask: Task<Void, Never>?

    /// Set right before presenting the Apple sheet, consumed when it
    /// completes. `ASAuthorizationAppleIDRequest` only carries the *hashed*
    /// nonce; Supabase needs the raw value back to verify the id token's
    /// `nonce` claim against it.
    private var pendingAppleNonce: String?

    init(backend: AuthBackend) {
        self.backend = backend
        session = backend.currentSession
        authStateTask = Task { [backend] in
            for await (_, session) in backend.authStateChanges {
                await MainActor.run { [weak self] in self?.session = session }
            }
        }
    }

    convenience init() {
        self.init(backend: SupabaseAuthBackend(client: SupabaseConfig.client))
    }

    deinit {
        authStateTask?.cancel()
    }

    /// Unwraps a `FieldValidation`, surfacing `.invalid` as a `notice` and
    /// returning `nil` so the caller can `guard` its way out.
    private func require(_ validation: FieldValidation) -> String? {
        switch validation {
        case .valid(let value): return value
        case .invalid(let message): notice = .error(message); return nil
        }
    }

    func signUp(displayName: String, email: String, password: String) async {
        notice = nil

        guard let name = require(IdentityConstants.validateDisplayName(displayName)) else { return }
        guard let normalizedEmail = require(IdentityConstants.validateEmail(email)) else { return }
        guard require(IdentityConstants.validateNewPassword(password)) != nil else { return }

        isBusy = true
        defer { isBusy = false }

        do {
            let response = try await backend.signUp(email: normalizedEmail, password: password, displayName: name)
            if let session = response.session {
                self.session = session
            } else {
                // Email confirmations are on (see supabase/config.toml) — no
                // session until the link is clicked. Same destination as the
                // web's /check-email, just phrased as a status line here.
                notice = .info("Check your email to confirm your account, then sign in.")
            }
        } catch {
            notice = .error("We couldn't create your account. Try again.")
        }
    }

    func signIn(email: String, password: String) async {
        notice = nil

        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedEmail.isEmpty, !password.isEmpty else {
            notice = .error("Enter your email and password.")
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            session = try await backend.signIn(email: normalizedEmail, password: password)
        } catch {
            // Deliberately vague, matching the web: this can't be used to
            // probe whether an address has an account.
            notice = .error("That email and password don't match an account.")
        }
    }

    func signInWithGoogle() async {
        notice = nil
        isBusy = true
        defer { isBusy = false }

        do {
            session = try await backend.signInWithOAuth(
                provider: .google,
                redirectTo: SupabaseConfig.oauthRedirectURL,
                configure: { _ in }
            )
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User dismissed the sheet — not a failure worth surfacing.
        } catch {
            notice = .error("Google sign-in failed. Try again.")
        }
    }

    /// Called from `SignInWithAppleButton`'s `onRequest`.
    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.generate()
        pendingAppleNonce = nonce.raw
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.hashed
    }

    /// Called from `SignInWithAppleButton`'s `onCompletion`.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        notice = nil
        let rawNonce = pendingAppleNonce
        pendingAppleNonce = nil

        let authorization: ASAuthorization
        switch result {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            return
        case .failure:
            notice = .error("Sign in with Apple failed. Try again.")
            return
        case .success(let value):
            authorization = value
        }

        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let identityTokenData = credential.identityToken,
            let identityToken = String(data: identityTokenData, encoding: .utf8),
            let rawNonce
        else {
            notice = .error("Sign in with Apple failed. Try again.")
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let session = try await backend.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: identityToken, nonce: rawNonce)
            )
            self.session = session

            // Only present on the credential from the account's very first
            // authorization — never in the id token, never again after.
            // `handle_new_user` has already inserted a fallback row by now,
            // so this is a follow-up update, not a race with the trigger.
            if let fullName = credential.fullName, let displayName = Self.displayName(from: fullName) {
                try? await backend.setDisplayName(displayName, userId: session.user.id)
            }
        } catch {
            notice = .error("Sign in with Apple failed. Try again.")
        }
    }

    func signOut() async {
        try? await backend.signOut()
        session = nil
    }

    private static func displayName(from components: PersonNameComponents) -> String? {
        let formatted = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
        guard case .valid(let name) = IdentityConstants.validateDisplayName(formatted) else { return nil }
        return name
    }
}
