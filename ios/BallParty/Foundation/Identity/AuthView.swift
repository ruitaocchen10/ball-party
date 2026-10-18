import AuthenticationServices
import Supabase
import SwiftUI

/// The signed-out front door. No form up front: Apple, Google and email are
/// three "Continue with" buttons, and email opens a sheet that holds the
/// sign-in / create-account form. OAuth has no sign-in vs sign-up distinction,
/// so neither do these buttons; only the email sheet needs a mode.
struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel

    @State private var showEmailSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            Spacer(minLength: 24)
            actions
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .screenBackground()
        .sheet(isPresented: $showEmailSheet, onDismiss: { viewModel.notice = nil }) {
            EmailAuthSheet(viewModel: viewModel)
                .presentationBackground(Theme.surface)
                .presentationCornerRadius(0)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            Text("The group chat, but it keeps score").eyebrow()
            // Two lines stacked rather than one wrapped Text: SwiftUI won't
            // take a negative lineSpacing, and Bebas's line box is loose at
            // this size. The vertical padding trims some of that slack off the
            // top and bottom so the eyebrow and tagline sit close.
            VStack(alignment: .leading, spacing: -24) {
                Text("Ball").slabTitle(104)
                Text("Party").slabTitle(104)
            }
            .padding(.top, 1)
            .padding(.bottom, -4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Ball Party")
            .accessibilityAddTraits(.isHeader)
            Text("Post your takes, play stat games, and see who was right.")
                .font(.sans(18))
                .foregroundStyle(Theme.fg)
                .frame(maxWidth: 290, alignment: .leading)
            gradeChips
                .padding(.top, 18)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .leading)
    }

    /// A call that came in and one that missed, in the grade colours the
    /// take cards use: the "keeps score" of the eyebrow. Decorative, so
    /// VoiceOver skips it.
    private var gradeChips: some View {
        HStack(spacing: 8) {
            gradeChip("Called it", symbol: "checkmark", badge: Theme.gradeElite, ink: Theme.surface, fill: Theme.fg)
            gradeChip("Missed it", symbol: "xmark", badge: Theme.gradeRough, ink: Theme.fg, fill: nil)
        }
        .accessibilityHidden(true)
    }

    /// `fill: nil` is the outlined chip, for the result that didn't go your way.
    private func gradeChip(_ text: String, symbol: String, badge: Color, ink: Color, fill: Color?) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Theme.fg)
                .frame(width: 14, height: 14)
                .background(badge, in: Circle())
            Text(text)
                .font(.mono(11, weight: .bold))
                .tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(fill ?? .clear, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
        .overlay {
            if fill == nil { RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.line, lineWidth: 1) }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if !showEmailSheet, let notice = viewModel.notice {
                AuthNoticeLine(notice: notice)
            }

            SignInWithAppleButton(.continue) { request in
                viewModel.prepareAppleSignInRequest(request)
            } onCompletion: { result in
                Task { await viewModel.completeAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .disabled(viewModel.isBusy)

            Button {
                Task { await viewModel.signInWithGoogle() }
            } label: {
                HStack(spacing: 10) {
                    Image("GoogleG")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                    Text("Continue with Google")
                }
            }
            .buttonStyle(.ghost)
            .disabled(viewModel.isBusy)

            Button {
                viewModel.notice = nil
                showEmailSheet = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "envelope")
                        .font(.system(size: 16, weight: .medium))
                    Text("Continue with email")
                }
            }
            .buttonStyle(.ghost)
            .disabled(viewModel.isBusy)

            Text("By continuing you agree to our [Terms](\(SiteLinks.terms.absoluteString)), including the rules on what you can post, and our [Privacy Policy](\(SiteLinks.privacyPolicy.absoluteString)).")
                .font(.sans(12))
                .foregroundStyle(Theme.fgMuted)
                .tint(Theme.fg)
                .padding(.top, 4)
        }
    }
}

/// The email form: sign in by default, with a link to switch to creating an
/// account. Lives in a sheet so the front door stays free of fields.
private struct EmailAuthSheet: View {
    @ObservedObject var viewModel: AuthViewModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode {
        case signIn
        case signUp
    }

    private enum Focus {
        case displayName, username, email, password
    }

    @State private var mode: Mode = .signIn
    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var detent: PresentationDetent = .medium
    @FocusState private var focus: Focus?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                if mode == .signUp {
                    field("Display name") {
                        TextField("Display name", text: $displayName)
                            .textContentType(.nickname)
                            .focused($focus, equals: .displayName)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        field("Username (optional)") {
                            TextField("Username", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .username)
                        }
                        Text(usernameHint)
                            .font(.sans(13))
                            .foregroundStyle(Theme.fgMuted)
                    }
                }

                field("Email") {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                }

                field("Password") {
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signUp ? .newPassword : .password)
                        .focused($focus, equals: .password)
                }

                if let notice = viewModel.notice {
                    AuthNoticeLine(notice: notice)
                }

                Button {
                    Task { await submit() }
                } label: {
                    Text(viewModel.isBusy ? "Working…" : (mode == .signUp ? "Create account" : "Sign in"))
                }
                .buttonStyle(.solid)
                .disabled(viewModel.isBusy)

                Button {
                    viewModel.notice = nil
                    mode = mode == .signUp ? .signIn : .signUp
                } label: {
                    Text(mode == .signUp ? "Already have an account? Sign in" : "New here? Create an account")
                }
                .buttonStyle(.quiet)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large], selection: $detent)
        // The keyboard covers most of the medium detent, so go full height
        // as soon as a field is in use.
        .onChange(of: focus) { _, newValue in
            if newValue != nil { detent = .large }
        }
    }

    private var header: some View {
        HStack {
            Text(mode == .signUp ? "Create account" : "Sign in")
                .slabTitle(34)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.fgMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            .padding(.trailing, -12)
        }
    }

    /// A field with its caption above it, the way the web form lays them out.
    private func field<Field: View>(_ label: String, @ViewBuilder field: () -> Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.sans(14, weight: .medium)).foregroundStyle(Theme.fg)
            field().fieldStyle()
        }
    }

    /// Local format feedback only: availability needs a session, so the
    /// server decides right after the account exists.
    private var usernameHint: String {
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "3–20 letters, numbers or underscores. Leave blank and we’ll pick one from your name."
        }
        switch IdentityConstants.validateUsername(username) {
        case .valid: return "We’ll check it’s free when you create your account."
        case .invalid(let message): return message
        }
    }

    private func submit() async {
        switch mode {
        case .signUp:
            await viewModel.signUp(displayName: displayName, username: username, email: email, password: password)
        case .signIn:
            await viewModel.signIn(email: email, password: password)
        }
    }
}

private struct AuthNoticeLine: View {
    let notice: AuthViewModel.Notice

    var body: some View {
        Text(notice.message)
            .font(.sans(14))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var color: Color {
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
    func deleteAccount() async throws {}
    func setDisplayName(_ displayName: String, userId: UUID) async throws {}
    func claimUsername(_ username: String) async throws -> String { throw CancellationError() }
}

#Preview {
    AuthView(viewModel: AuthViewModel(backend: PreviewAuthBackend()))
}
