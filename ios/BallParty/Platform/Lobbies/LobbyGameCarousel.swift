import SwiftUI

// The room's Game tab: a swipeable row of cards, one per game the room can
// play. The host's swipe is the pick (it points the room at that game); a
// player's is only browsing, since the game actually being played is shown on
// the Room tab. A card is a fixed height whatever the game: what the game is,
// its current settings as pills, and for the host an Adjust settings button
// that opens them in a sheet. Everybody else reads what the host saved.

/// What a card in the row stands for.
enum GameCardID: Hashable {
    case game(MatchGame)
}

struct LobbyGameCarousel: View {
    @ObservedObject var viewModel: LobbyViewModel
    @State private var position: GameCardID?

    var body: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                // Not lazy: a lazy stack sizes the row from the cards it has
                // built, which clipped taller cards. There are only a handful.
                HStack(alignment: .top, spacing: 12) {
                    ForEach(MatchGame.allCases) { game in
                        GameCard(game: game, viewModel: viewModel)
                            .containerRelativeFrame(.horizontal) { length, _ in length - 32 }
                            .id(GameCardID.game(game))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position)
            .contentMargins(.horizontal, 16, for: .scrollContent)

            dots
            Text(viewModel.isHost ? "Swipe to choose a game" : "Swipe to browse the games")
                .monoLabel(9, tracking: 0.12)
        }
        .onAppear {
            guard position == nil else { return }
            let start = viewModel.selectedGame ?? MatchGame.allCases.first
            position = start.map(GameCardID.game)
            // The host opens on the first game, which is then the pick, so
            // there is always something for Start to act on.
            if viewModel.isHost, viewModel.selectedGame == nil, let start {
                Task { await viewModel.selectGame(start) }
            }
        }
        // The host's swipe is the pick.
        .onChange(of: position) { _, new in
            guard viewModel.isHost, case .game(let game)? = new, game != viewModel.selectedGame else { return }
            Task { await viewModel.selectGame(game) }
        }
        .onChange(of: viewModel.selectedGame) { _, selected in
            guard let selected else { return }
            // The host's own swipe lands here too, and is already in place. A
            // player is never moved off a game they are reading.
            if viewModel.isHost || position == nil {
                withAnimation { position = .game(selected) }
            }
        }
    }

    private var cards: [GameCardID] {
        MatchGame.allCases.map(GameCardID.game)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(cards, id: \.self) { card in
                Circle()
                    .fill(card == position ? Theme.fg : Theme.fg.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

private struct GameCard: View {
    let game: MatchGame
    @ObservedObject var viewModel: LobbyViewModel
    @State private var adjusting = false

    /// Every card is this tall, so the row never changes height as it is swiped.
    private static let height: CGFloat = 360

    private var isSelected: Bool { viewModel.selectedGame == game }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: "gamecontroller")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.fgMuted)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
                    .accessibilityHidden(true)
                Spacer()
                if isSelected {
                    Label("Picked", systemImage: "checkmark")
                        .monoLabel(9, weight: .bold, tracking: 0.1, color: Theme.surface)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.fg, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
                }
            }

            Text(game.label)
                .slabTitle(28)
                .padding(.top, 14)
                .accessibilityAddTraits(.isHeader)
            Text(game.playersLabel).monoLabel(10, weight: .semibold, tracking: 0.1)
                .padding(.top, 1)
            Text(game.tagline)
                .font(.sans(15))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Spacer(minLength: 14)

            settings
                .padding(.top, 12)
                .overlay(alignment: .top) { LineRule() }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(isSelected ? Theme.fg : Theme.line, lineWidth: isSelected ? 1.5 : 1)
        )
        .sheet(isPresented: $adjusting) {
            GameSettingsSheet(game: game, viewModel: viewModel)
        }
    }

    /// The current settings as pills, with the host's way to change them.
    /// Everybody else reads what the host saved.
    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings").monoLabel(9, weight: .semibold, tracking: 0.1)
            FlowLayout(spacing: 6) {
                ForEach(viewModel.displayedFormat.lines(for: game)) { line in
                    SettingPill(text: line.value)
                }
            }
            // Room for two rows of pills, so a game with one setting and a
            // game with four put the button in the same place.
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .accessibilityElement(children: .combine)

            if viewModel.isHost {
                Button {
                    adjusting = true
                } label: {
                    Label("Adjust settings", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(BPButtonStyle(variant: .ghost))
            }
        }
    }
}

/// The host's settings for one game, in a sheet over the Game tab. Each change
/// saves onto the room as it is made (see `LobbyViewModel`), so Done only
/// closes the sheet.
private struct GameSettingsSheet: View {
    let game: MatchGame
    @ObservedObject var viewModel: LobbyViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Adjust settings").monoLabel(10, weight: .bold, tracking: 0.14)
                    Text(game.label).slabTitle(24)
                        .accessibilityAddTraits(.isHeader)
                }
                LineRule()
                GameSettingsEditor(game: game, viewModel: viewModel)
                Button("Done") { dismiss() }
                    .buttonStyle(.solid)
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surfaceRaised)
    }
}

// MARK: - The host's pickers

/// One game's settings as controls, bound to the host's pickers on the view
/// model, which save themselves onto the room as they change.
private struct GameSettingsEditor: View {
    let game: MatchGame
    @ObservedObject var viewModel: LobbyViewModel

    var body: some View {
        switch game {
        case .higherOrLower: higherOrLower
        case .auctionTeamBuilder: auction
        case .wavelength: wavelength
        }
    }

    private var higherOrLower: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scoring").fieldLabel()
                PillChoice(
                    selection: $viewModel.scoringMode,
                    options: ScoringMode.allCases,
                    title: { $0.label },
                    accessibilityName: "Scoring"
                )
            }

            if !viewModel.seasonChoices.isEmpty {
                HStack(spacing: 12) {
                    SeasonMenu(title: "From", selection: $viewModel.seasonFrom, choices: viewModel.seasonChoices)
                    SeasonMenu(title: "To", selection: $viewModel.seasonTo, choices: viewModel.seasonChoices)
                }
            }
        }
    }

    private var auction: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scoring").fieldLabel()
                PillChoice(
                    selection: $viewModel.auctionScoringMode,
                    options: [ScoringMode.weekly, .seasonTotal],
                    title: { $0.label },
                    accessibilityName: "Scoring"
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Roster").fieldLabel()
                Picker("Roster", selection: $viewModel.rosterPreset) {
                    ForEach(RosterPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .menuFieldStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tokens per player").fieldLabel()
                PillChoice(
                    selection: $viewModel.tokenCount,
                    options: [0, 1, 2, 3],
                    title: { $0 == 0 ? "Off" : String($0) },
                    accessibilityName: "Tokens per player"
                )
            }

            if !viewModel.auctionSeasonChoices.isEmpty {
                HStack(spacing: 12) {
                    SeasonMenu(title: "From", selection: $viewModel.auctionFrom, choices: viewModel.auctionSeasonChoices)
                    SeasonMenu(title: "To", selection: $viewModel.auctionTo, choices: viewModel.auctionSeasonChoices)
                }
            }
        }
    }

    private var wavelength: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Mode").fieldLabel()
                PillChoice(
                    selection: $viewModel.wavelengthMode,
                    options: WavelengthMode.allCases,
                    title: { "\($0.label) · \($0.playerCount) players" },
                    accessibilityName: "Mode"
                )
            }

            if viewModel.wavelengthMode == .coop {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Game length").fieldLabel()
                    Picker("Game length", selection: $viewModel.wavelengthPreset) {
                        ForEach(WavelengthPreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .menuFieldStyle()
                }
            }
        }
    }

}

// MARK: - Start

/// The host's Start, pinned to the bottom of the Room tab. Says why it is
/// disabled (not enough players, nothing picked) above the button rather than
/// just greying out.
struct GameStartBar: View {
    @ObservedObject var viewModel: LobbyViewModel

    var body: some View {
        VStack(spacing: 8) {
            if let reason = viewModel.startBlockedReason {
                Text(reason).monoLabel(11, tracking: 0.1)
            }
            Button {
                Task { await viewModel.startGame() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isBusy { LoadingSpinner(size: 16) }
                    Text(viewModel.selectedGame.map { "Start \($0.label)" } ?? "Start the game")
                }
            }
            .buttonStyle(.solid)
            .disabled(!viewModel.canStart)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) { LineRule() }
    }
}
