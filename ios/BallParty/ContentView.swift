import SwiftUI

/// Placeholder home screen behind the auth gate. No game or Huddle features
/// yet — see `docs/architecture/architecture.md` — so this just proves the
/// gate works: signed in, and able to sign back out.
struct ContentView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Ball Party")
                .font(.title)

            if let email = viewModel.session?.user.email {
                Text("Signed in as \(email)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Sign out") {
                Task { await viewModel.signOut() }
            }
        }
        .padding()
    }
}
