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

                // Party mode's real screen (`LobbyScreen`) is fully built but
                // not turned on for mobile yet; this tab points at a
                // placeholder until it is.
                NavigationStack {
                    ComingSoonView(
                        title: "Party",
                        message: "Playing with friends on mobile is on the way. In the meantime, play Games on your own."
                    )
                }
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

    @State private var qbMode: QbRatingMode = .visible

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SoloGameCard(
                    name: ["Higher", "or lower"],
                    tagline: "Call the next card. Make the streak last."
                ) {
                    SoloRunScreen(viewerId: viewerId)
                }

                SoloGameCard(
                    name: ["QB season", "builder"],
                    tagline: "Spin a team-season six times and build one quarterback from the best trait on offer."
                ) {
                    RatingsChoice(selection: $qbMode)
                } destination: {
                    QbSeasonBuilderScreen(viewerId: viewerId, mode: qbMode)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One game a lone player can start, read as a small games shelf card the way
/// the web's `SoloCard` does: icon and a "1 player" tag, the name, the pitch,
/// then Play solo. The card itself isn't the control — only the button at the
/// bottom is — so a choice the run is locked to (`options`) can be made on it.
private struct SoloGameCard<Options: View, Destination: View>: View {
    let name: [String]
    let tagline: String
    @ViewBuilder var options: Options
    @ViewBuilder var destination: Destination

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.fgMuted)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityHidden(true)
                Spacer()
                Text("1 player")
                    .monoLabel(9, weight: .semibold, tracking: 0.1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.surface)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: -4) {
                ForEach(name, id: \.self) { line in
                    Text(line)
                }
            }
            .slabTitle(28)
            .lineSpacing(0)
            .padding(.top, 16)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Text(tagline)
                .font(.sans(15))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                options
                NavigationLink {
                    destination
                } label: {
                    Text("Play solo")
                }
                .buttonStyle(.solid)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { LineRule() }
            .padding(.top, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}

extension SoloGameCard where Options == EmptyView {
    init(name: [String], tagline: String, @ViewBuilder destination: () -> Destination) {
        self.init(name: name, tagline: tagline, options: { EmptyView() }, destination: destination)
    }
}

/// A choice the run is locked to once it starts, made on the card because there
/// is no screen before the run to make it on. The first mode is the default.
private struct RatingsChoice: View {
    @Binding var selection: QbRatingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ratings").monoLabel(9, weight: .semibold, tracking: 0.1)
                .padding(.bottom, 2)
            ForEach(QbRatingMode.allCases) { mode in
                let isSelected = mode == selection
                Button {
                    selection = mode
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(isSelected ? Theme.fg : Theme.fgMuted)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.label).monoLabel(11, weight: .bold, tracking: 0.1, color: Theme.fg)
                            Text(mode.summary)
                                .font(.sans(13))
                                .foregroundStyle(Theme.fgMuted)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isSelected ? Theme.surface : .clear)
                    .overlay(Rectangle().strokeBorder(isSelected ? Theme.fg : Theme.line, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ratings")
    }
}
