import SwiftUI

/// Home screen behind the auth gate: Huddle, the games a signed-in player can
/// start, and sign-out. See `docs/architecture/architecture.md` for what lands
/// next.
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
                        HuddleScreen(viewerId: viewerId)
                    } label: {
                        GameTile(
                            eyebrow: "Feed",
                            title: "Huddle",
                            blurb: "Make your picks on this week's prompts, then talk it over."
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        SoloRunScreen(viewerId: viewerId)
                    } label: {
                        GameTile(
                            eyebrow: "Solo",
                            title: "Higher or Lower",
                            blurb: "Call the next card. Make the streak last."
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        LobbyScreen(viewerId: viewerId)
                    } label: {
                        GameTile(
                            eyebrow: "Multiplayer",
                            title: "Play with friends",
                            blurb: "Host a room or join with a code, then play a ladder together."
                        )
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

/// One way into the app from the home screen.
private struct GameTile: View {
    let eyebrow: String
    let title: String
    let blurb: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(blurb)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
