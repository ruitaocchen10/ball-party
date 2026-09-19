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
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48)
                .clipShape(Rectangle())

                Button {
                    Task { await viewModel.signInWithGoogle() }
                } label: {
                    Text(mode == .signUp ? "Sign up with Google" : "Sign in with Google")
                }
                .buttonStyle(.ghost)

                HStack(spacing: 12) {
                    LineRule()
                    Text("or").monoLabel(10, tracking: 0.15)
                    LineRule()
                }

                VStack(alignment: .leading, spacing: 12) {
                    if mode == .signUp {
                        field("Display name") {
                            TextField("Display name", text: $displayName)
                                .textContentType(.nickname)
                        }
                    }

                    field("Email") {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    field("Password") {
                        SecureField("Password", text: $password)
                            .textContentType(mode == .signUp ? .newPassword : .password)
                    }

                    if let notice = viewModel.notice {
                        Text(notice.message)
                            .font(.sans(14))
                            .foregroundStyle(noticeColor(notice))
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        Text(viewModel.isBusy ? "Working…" : (mode == .signUp ? "Create account" : "Sign in"))
                    }
                    .buttonStyle(.solid)
                    .disabled(viewModel.isBusy)
                    .padding(.top, 4)
                }

                toggleModeButton
            }
            .padding(24)
        }
        .screenBackground()
    }

    /// A field with its caption above it, the way the web form lays them out.
    private func field<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.sans(14, weight: .medium)).foregroundStyle(Theme.fg)
            field().fieldStyle()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .signUp ? "Get in the game" : "Ball Party")
                .slabTitle(48)
                .accessibilityAddTraits(.isHeader)
            Text(mode == .signUp ? "Takes about ten seconds" : "Sign in to start or join a room")
                .monoLabel(11, tracking: 0.15)
        }
    }

    private var toggleModeButton: some View {
        Button {
            viewModel.notice = nil
            mode = mode == .signUp ? .signIn : .signUp
        } label: {
            Text(mode == .signUp ? "Already have an account? Sign in" : "New here? Create an account")
        }
        .buttonStyle(.quiet)
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
        case .error: Theme.hiddenText
        case .info: Theme.fgMuted
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
