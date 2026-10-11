import SwiftUI

// The room's Game tab: a swipeable row of cards, one per game the room can
// play. The host's swipe is the pick (it points the room at that game); a
// player's is only browsing, since the game actually being played is shown on
// the Room tab. A card lists what the game is and how it is set up: the host
// edits it there, and everybody else reads what the host saved.

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
                            .containerRelativeFrame(.horizontal) { length, _ in length - 48 }
                            .id(GameCardID.game(game))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $position)
            .contentMargins(.horizontal, 16, for: .scrollContent)

            dots
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
    /// Collapsed by default so a card doesn't tower over the screen; the
    /// summary under it already says what is set.
    @State private var editing = false

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
                .padding(.top, 2)
            Text(game.tagline)
                .font(.sans(15))
                .foregroundStyle(Theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            if let reason = viewModel.roomReadiness(for: game) {
                Text(reason)
                    .monoLabel(10, weight: .bold, tracking: 0.08, color: Theme.hiddenText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            settings
                .padding(.top, 12)
                .overlay(alignment: .top) { LineRule() }
                .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(isSelected ? Theme.fg : Theme.line, lineWidth: isSelected ? 1.5 : 1)
        )
    }

    /// The host can change these; everybody else reads what the host saved.
    @ViewBuilder private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isHost {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { editing.toggle() }
                } label: {
                    HStack {
                        Text("Settings").monoLabel(9, weight: .semibold, tracking: 0.1)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.fgMuted)
                            .rotationEffect(.degrees(editing ? 180 : 0))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(editing ? "Expanded" : "Collapsed")
            } else {
                Text("Settings").monoLabel(9, weight: .semibold, tracking: 0.1)
            }

            if viewModel.isHost && editing {
                GameSettingsEditor(game: game, viewModel: viewModel)
            } else {
                SettingsLines(lines: viewModel.displayedFormat.lines(for: game))
            }
        }
    }
}

/// The settings as label and value rows.
struct SettingsLines: View {
    let lines: [LobbyGameFormat.Line]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.label).monoLabel(10, tracking: 0.1)
                    Spacer(minLength: 8)
                    Text(line.value)
                        .font(.sans(15, weight: .medium))
                        .foregroundStyle(Theme.fg)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
        case .sabotageDraft: sabotage
        }
    }

    private var higherOrLower: some View {
        VStack(alignment: .leading, spacing: 12) {
            SegmentedChoice(
                selection: $viewModel.scoringMode,
                options: ScoringMode.allCases,
                title: { $0.label },
                accessibilityName: "Scoring"
            )

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
                SegmentedChoice(
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
                .fieldStyle()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tokens per player").fieldLabel()
                SegmentedChoice(
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
                SegmentedChoice(
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
                    .fieldStyle()
                }
            }
        }
    }

    private var sabotage: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Mode").fieldLabel()
            SegmentedChoice(
                selection: $viewModel.sabotageMode,
                options: SabotageMode.allCases,
                title: { $0.label },
                accessibilityName: "Mode"
            )
            Text(viewModel.sabotageMode.blurb).monoLabel(10, tracking: 0.08)
        }
    }
}

// MARK: - Start

/// The host's Start, pinned under the carousel so choosing and starting are
/// one place. Says why it is disabled rather than just greying out.
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
