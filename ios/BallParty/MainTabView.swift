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
    /// The one-time "confirm your username" sheet; nil once dealt with.
    @State private var usernamePrompt: UsernameConfirmViewModel?

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
            .task(id: user.id) {
                usernamePrompt = await UsernameConfirmViewModel.make(
                    client: SupabaseProfileClient(client: SupabaseConfig.client), userId: user.id
                )
            }
            .sheet(item: $usernamePrompt) { prompt in
                UsernameConfirmView(viewModel: prompt)
                    .presentationBackground(Theme.surface)
            }
        }
    }
}

/// The Games tab: everything a player can start on their own.
private struct GamesScreen: View {
    let viewerId: UUID

    @StateObject private var higherOrLowerFormat = SoloRunFormat(
        client: SupabaseHigherOrLowerClient(client: SupabaseConfig.client)
    )
    @State private var qbMode: QbRatingMode = .visible
    @State private var qbEra: QbEra = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SoloGameCard(
                    name: ["QB season", "builder"],
                    tagline: "Spin a team-season six times and build one quarterback from the best trait on offer."
                ) {
                    StackedChoice(
                        legend: "Ratings",
                        options: QbRatingMode.allCases,
                        selection: $qbMode,
                        label: \.label,
                        summary: \.summary
                    )
                    EraChoice(selection: $qbEra)
                } destination: {
                    QbSeasonBuilderScreen(viewerId: viewerId, mode: qbMode, era: qbEra)
                }

                SoloGameCard(
                    name: ["Higher", "or lower"],
                    tagline: "Call the next card. Make the streak last."
                ) {
                    StackedChoice(
                        legend: "Scoring",
                        options: ScoringMode.allCases,
                        selection: $higherOrLowerFormat.scoringMode,
                        label: \.label,
                        summary: \.summary
                    )
                    if !higherOrLowerFormat.seasonChoices.isEmpty {
                        SeasonRangeChoice(format: higherOrLowerFormat)
                    }
                } destination: {
                    SoloRunScreen(
                        viewerId: viewerId,
                        scoringMode: higherOrLowerFormat.scoringMode,
                        era: higherOrLowerFormat.era
                    )
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Games")
        .navigationBarTitleDisplayMode(.inline)
        .task { await higherOrLowerFormat.loadBounds() }
    }
}

/// One game a lone player can start, read as a small games shelf card the way
/// the web's `SoloCard` does: icon and a "1 player" tag, the name, the pitch,
/// then Play solo. The card itself isn't the control — only the button at the
/// bottom is — so a choice the run is locked to (`options`) can be made on it.
private struct SoloGameCard<Options: View, Destination: View>: View {
    let name: [String]
    let tagline: String
    private let hasOptions: Bool
    @ViewBuilder var options: Options
    @ViewBuilder var destination: Destination

    /// Collapsed by default, like the web card's Settings section, so a card
    /// with choices doesn't tower over one without. The choices live in the
    /// parent's state, so shutting this keeps what was picked and the run
    /// still starts with it.
    @State private var settingsOpen = false

    fileprivate init(
        name: [String],
        tagline: String,
        hasOptions: Bool,
        @ViewBuilder options: () -> Options,
        @ViewBuilder destination: () -> Destination
    ) {
        self.name = name
        self.tagline = tagline
        self.hasOptions = hasOptions
        self.options = options()
        self.destination = destination()
    }

    init(
        name: [String],
        tagline: String,
        @ViewBuilder options: () -> Options,
        @ViewBuilder destination: () -> Destination
    ) {
        self.init(name: name, tagline: tagline, hasOptions: true, options: options, destination: destination)
    }

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
                if hasOptions {
                    settingsDisclosure
                }
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

extension SoloGameCard {
    /// The Settings row and, when open, the card's choices.
    @ViewBuilder fileprivate var settingsDisclosure: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { settingsOpen.toggle() }
            } label: {
                HStack {
                    Text("Settings").monoLabel(9, weight: .semibold, tracking: 0.1)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.fgMuted)
                        .rotationEffect(.degrees(settingsOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(settingsOpen ? "Expanded" : "Collapsed")

            if settingsOpen {
                options
            }
        }
    }
}

extension SoloGameCard where Options == EmptyView {
    init(name: [String], tagline: String, @ViewBuilder destination: () -> Destination) {
        self.init(name: name, tagline: tagline, hasOptions: false, options: { EmptyView() }, destination: destination)
    }
}

/// A choice the run is locked to once it starts, made on the card because there
/// is no screen before the run to make it on. One stacked card per option, a
/// label and a sentence each; the first option is the default.
private struct StackedChoice<Option: Identifiable & Hashable>: View {
    let legend: String
    let options: [Option]
    @Binding var selection: Option
    let label: KeyPath<Option, String>
    let summary: KeyPath<Option, String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(legend).monoLabel(9, weight: .semibold, tracking: 0.1)
                .padding(.bottom, 2)
            ForEach(options) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(isSelected ? Theme.fg : Theme.fgMuted)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option[keyPath: label]).monoLabel(11, weight: .bold, tracking: 0.1, color: Theme.fg)
                            Text(option[keyPath: summary])
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
        .accessibilityLabel(legend)
    }
}

/// A choice the run is locked to once it starts, same as `StackedChoice`
/// alongside it — one segmented row rather than `StackedChoice`'s stacked
/// cards, since three short labels (as opposed to two with a sentence each)
/// read fine in a line and the card is already asking for one choice above
/// this one.
private struct EraChoice: View {
    @Binding var selection: QbEra

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Era").monoLabel(9, weight: .semibold, tracking: 0.1)
                .padding(.bottom, 2)
            HStack(spacing: 6) {
                ForEach(QbEra.allCases) { era in
                    let isSelected = era == selection
                    Button {
                        selection = era
                    } label: {
                        Text(era.label)
                            .monoLabel(10, weight: .bold, tracking: 0.08, color: isSelected ? Theme.fg : Theme.fgMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? Theme.surface : .clear)
                            .overlay(Rectangle().strokeBorder(isSelected ? Theme.fg : Theme.line, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityLabel("\(era.label): \(era.summary)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Era")
    }
}

/// Higher or Lower's era: the first and last season the ladder is dealt from.
/// Only offered once the pool's limits have loaded; until then (or if they
/// never do) a run takes the whole pool.
private struct SeasonRangeChoice: View {
    @ObservedObject var format: SoloRunFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Era").monoLabel(9, weight: .semibold, tracking: 0.1)
                .padding(.bottom, 2)
            HStack(spacing: 12) {
                SeasonMenu(title: "From", selection: $format.seasonFrom, choices: format.seasonChoices)
                SeasonMenu(title: "To", selection: $format.seasonTo, choices: format.seasonChoices)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Era")
    }
}
