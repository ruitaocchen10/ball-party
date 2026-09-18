import SwiftUI

/// Home screen behind the auth gate: Huddle, the games a signed-in player can
/// start, and sign-out. See `docs/architecture/architecture.md` for what lands
/// next.
struct ContentView: View {
    @ObservedObject var viewModel: AuthViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    PageHeader(
                        title: "Ball Party",
                        description: viewModel.session?.user.email.map { "Signed in as \($0)" }
                    )

                    if let viewerId = viewModel.session?.user.id {
                        NavigationLink {
                            HuddleScreen(viewerId: viewerId)
                        } label: {
                            GameTile(
                                kind: "Feed",
                                title: "Huddle",
                                blurb: "Make your picks on this week's prompts, then talk it over.",
                                footnote: "Everyone",
                                action: "Open"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            SoloRunScreen(viewerId: viewerId)
                        } label: {
                            GameTile(
                                kind: "Solo",
                                title: "Higher or Lower",
                                blurb: "Call the next card. Make the streak last.",
                                footnote: "1 player",
                                action: "Play"
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            LobbyScreen(viewerId: viewerId)
                        } label: {
                            GameTile(
                                kind: "Multiplayer",
                                title: "Play with friends",
                                blurb: "Host a room or join with a code, then play a ladder together.",
                                footnote: "2–4 players",
                                action: "Start"
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Sign out") {
                        Task { await viewModel.signOut() }
                    }
                    .buttonStyle(.quiet)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// One way into the app from the home screen: a cream card with the red edge
/// (the answer to "how did the room do" is always behind it), the game's name,
/// and one control.
private struct GameTile: View {
    let kind: String
    let title: String
    let blurb: String
    let footnote: String
    let action: String

    var body: some View {
        PanelCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(kind).monoLabel(10, tracking: 0.16, color: Theme.hiddenInk)
                Text(title)
                    .slabTitle(34, color: Theme.panelFg)
                    .lineSpacing(0)
                    .fixedSize(horizontal: false, vertical: true)
                Text(blurb)
                    .font(.sans(15))
                    .foregroundStyle(Theme.panelBody)
                    .fixedSize(horizontal: false, vertical: true)

                DashedRule().padding(.top, 4)

                HStack {
                    Text(footnote).monoLabel(10, tracking: 0.11, color: Theme.panelMuted)
                    Spacer()
                    Text(action)
                        .font(.slab(16, relativeTo: .body))
                        .tracking(0.64)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.panel)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Theme.panelFg)
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }
}
