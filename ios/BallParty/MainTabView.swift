import SwiftUI

/// The app behind the auth gate: four tabs, each with its own navigation
/// stack, so going into a prompt or a lobby keeps you inside the tab you were
/// on. See `docs/architecture/architecture.md` for what lands next.
struct MainTabView: View {
    @ObservedObject var viewModel: AuthViewModel

    private enum Tab: Hashable {
        case home, games, party, profile
    }

    @State private var selection: Tab = .home

    var body: some View {
        // `AuthGateView` only builds this with a session, but the session can
        // clear a beat before the gate swaps this view out.
        if let user = viewModel.session?.user {
            TabView(selection: $selection) {
                NavigationStack { HuddleScreen(viewerId: user.id) }
                    .tabItem { Label("Home", systemImage: "house") }
                    .tag(Tab.home)

                NavigationStack { GamesScreen(viewerId: user.id) }
                    .tabItem { Label("Games", systemImage: "gamecontroller") }
                    .tag(Tab.games)

                NavigationStack { LobbyScreen(viewerId: user.id) }
                    .tabItem { Label("Party", systemImage: "person.3") }
                    .tag(Tab.party)

                NavigationStack { ProfileView(auth: viewModel, viewerId: user.id, email: user.email) }
                    .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                    .tag(Tab.profile)
            }
        }
    }
}

/// The Games tab: everything a player can start on their own.
private struct GamesScreen: View {
    let viewerId: UUID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "Solo",
                    title: "Games",
                    description: "Play on your own. Bring friends in from the Party tab."
                )

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
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One way into a game from the Games tab: a cream card with the red edge
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
