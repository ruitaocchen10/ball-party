import AuthenticationServices
import Supabase
import SwiftUI

/// Mirrors `webapp/components/foundation/identity/AuthForm.tsx`: one form,
/// a mode toggle, Google above the fold, Apple beside it, email/password below.
struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    private enum Mode {
        case signIn
        case signUp
    }

    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                SignInWithAppleButton(.signIn) { request in
                    viewModel.prepareAppleSignInRequest(request)
                } onCompletion: { result in
                    Task { await viewModel.completeAppleSignIn(result) }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)

                Button {
                    Task { await viewModel.signInWithGoogle() }
                } label: {
                    Text(mode == .signUp ? "Sign up with Google" : "Sign in with Google")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    if mode == .signUp {
                        TextField("Display name", text: $displayName)
                            .textContentType(.nickname)
                            .textFieldStyle(.roundedBorder)
                    }

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.roundedBorder)

                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .textFieldStyle(.roundedBorder)

                    if let notice = viewModel.notice {
                        Text(notice.message)
                            .font(.footnote)
                            .foregroundStyle(noticeColor(notice))
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(viewModel.isBusy ? "Working…" : (mode == .signUp ? "Create account" : "Sign in"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isBusy)
                }

                toggleModeButton
            }
            .padding(24)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(mode == .signUp ? "Get in the game" : "Ball Party")
                .font(.largeTitle.bold())
            Text(mode == .signUp ? "Takes about ten seconds" : "Sign in to start or join a room")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var toggleModeButton: some View {
        Button {
            viewModel.notice = nil
            mode = mode == .signUp ? .signIn : .signUp
        } label: {
            Text(mode == .signUp ? "Already have an account? Sign in" : "New here? Create an account")
                .font(.footnote)
        }
    }

    private func submit() async {
        switch mode {
        case .signUp:
            await viewModel.signUp(displayName: displayName, email: email, password: password)
        case .signIn:
            await viewModel.signIn(email: email, password: password)
        }
    }

    private func noticeColor(_ notice: AuthViewModel.Notice) -> Color {
        switch notice {
        case .error: .red
        case .info: .secondary
        }
    }
}

/// A backend that only ever shows the signed-out form — enough for
/// `#Preview`, which never taps a network-backed button for real.
private struct PreviewAuthBackend: AuthBackend {
    var currentSession: Session? { nil }
    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        AsyncStream { $0.finish() }
    }
    func signUp(email: String, password: String, displayName: String) async throws -> AuthResponse {
        throw CancellationError()
    }
    func signIn(email: String, password: String) async throws -> Session { throw CancellationError() }
    func signInWithIdToken(credentials: OpenIDConnectCredentials) async throws -> Session { throw CancellationError() }
    func signInWithOAuth(
        provider: Provider,
        redirectTo: URL,
        configure: @Sendable (ASWebAuthenticationSession) -> Void
    ) async throws -> Session { throw CancellationError() }
    func signOut() async throws {}
    func setDisplayName(_ displayName: String, userId: UUID) async throws {}
}

#Preview {
    AuthView(viewModel: AuthViewModel(backend: PreviewAuthBackend()))
}
