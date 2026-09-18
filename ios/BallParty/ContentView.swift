import SwiftUI

/// Home screen behind the auth gate: the games a signed-in player can start,
/// and sign-out. Higher or Lower solo is the first; see
/// `docs/architecture/architecture.md` for what lands next.
struct ContentView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text("Ball Party")
                        .font(.largeTitle.weight(.bold))
                    if let email = viewModel.session?.user.email {
                        Text("Signed in as \(email)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let viewerId = viewModel.session?.user.id {
                    NavigationLink {
                        SoloRunScreen(viewerId: viewerId)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SOLO")
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("Higher or Lower")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("Call the next card. Make the streak last.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                Button("Sign out") {
                    Task { await viewModel.signOut() }
                }
            }
            .padding()
        }
    }
}
