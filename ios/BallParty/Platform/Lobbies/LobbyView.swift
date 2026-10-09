import SwiftUI

/// Entry point for playing with other people: owns the room's view model and
/// shows whichever stage it is in — host-or-join, the room itself, or a room
/// that has closed.
///
/// The room is also what navigates into a match, for everybody: the host's own
/// tap on Start and another player's arrival in a run they were seated into
/// are the same event here — a run appeared that this player is on.
struct LobbyScreen: View {
    @StateObject private var viewModel: LobbyViewModel
    @StateObject private var inbox = RoomInvitesInboxViewModel(
        client: SupabaseRoomInvitesClient(client: SupabaseConfig.client)
    )
    @Environment(\.scenePhase) private var scenePhase
    /// Which match this screen pushed, so dismissing it can say *which* board
    /// was left rather than whichever one the room happens to show now.
    @State private var presentedMatch: UUID?

    init(viewerId: UUID) {
        _viewModel = StateObject(
            wrappedValue: LobbyViewModel(
                client: SupabaseLobbyClient(client: SupabaseConfig.client),
                game: SupabaseHigherOrLowerClient(client: SupabaseConfig.client),
                auction: SupabaseAuctionClient(client: SupabaseConfig.client),
                viewerId: viewerId
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.stage {
            case .entry: LobbyEntryView(viewModel: viewModel, inbox: inbox)
            case .room: LobbyRoomView(viewModel: viewModel, inbox: inbox)
            case .closed: ClosedRoomView(viewModel: viewModel)
            }
        }
        .task { await inbox.load() }
        .task { await inbox.observe(recipientId: viewModel.viewerId) }
        .screenBackground()
        .navigationTitle("Play with friends")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: presentedMatchBinding) { route in
            Group {
                switch route.game {
                case .higherOrLower:
                    MatchScreen(
                        matchId: route.id,
                        viewerId: viewModel.viewerId,
                        roomCode: viewModel.roomCode,
                        isHost: viewModel.isHost
                    )
                case .auctionTeamBuilder:
                    AuctionMatchScreen(
                        matchId: route.id,
                        viewerId: viewModel.viewerId,
                        roomCode: viewModel.roomCode,
                        isHost: viewModel.isHost
                    )
                }
            }
            .onAppear { presentedMatch = route.id }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: viewModel.appBecameActive()
            case .background: viewModel.appEnteredBackground()
            default: break
            }
        }
        .onDisappear { viewModel.stopObserving() }
    }

    private var presentedMatchBinding: Binding<MatchRoute?> {
        Binding(
            get: { viewModel.matchToEnter.map { MatchRoute(id: $0, game: viewModel.gameToEnter) } },
            set: { route in
                guard route == nil, let left = presentedMatch else { return }
                viewModel.matchDismissed(left)
                presentedMatch = nil
            }
        )
    }

    /// A match id and its game, as something `navigationDestination(item:)`
    /// can key off. The game picks which screen the room opens.
    private struct MatchRoute: Identifiable, Hashable {
        let id: UUID
        let game: MatchGame
    }
}

// MARK: - Host or join

private struct LobbyEntryView: View {
    @ObservedObject var viewModel: LobbyViewModel
    @ObservedObject var inbox: RoomInvitesInboxViewModel
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RoomInvitesInboxSection(viewModel: inbox, hasRoom: false) { lobby in
                    Task { await viewModel.adopt(lobby) }
                }

                PageHeader(
                    eyebrow: "Two to four players",
                    title: "Play a room together.",
                    description: "Host a room and share the code, or join one you were given."
                )

                Button {
                    Task { await viewModel.createRoom() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isBusy { ProgressView() }
                        Text("Host a room")
                    }
                }
                .buttonStyle(.solid)
                .disabled(viewModel.isBusy)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Join with a code").fieldLabel()
                    HStack(spacing: 8) {
                        TextField("ABCDE", text: $viewModel.code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.mono(20, weight: .bold, relativeTo: .title3))
                            .fieldStyle()
                            .focused($codeFocused)
                            .submitLabel(.go)
                            .onSubmit { Task { await viewModel.joinRoom() } }
                        Button("Join") {
                            codeFocused = false
                            Task { await viewModel.joinRoom() }
                        }
                        .buttonStyle(BPButtonStyle(variant: .ghost, fullWidth: false))
                        .disabled(viewModel.isBusy)
                    }
                }

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(16)
        }
        .refreshable { await inbox.load() }
    }
}

// MARK: - The room

private struct LobbyRoomView: View {
    @ObservedObject var viewModel: LobbyViewModel
    @ObservedObject var inbox: RoomInvitesInboxViewModel
    @State private var inviting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RoomInvitesInboxSection(viewModel: inbox, hasRoom: true) { lobby in
                    Task { await viewModel.adopt(lobby) }
                }
                code
                roster

                if let lobbyId = viewModel.lobby?.id {
                    Button("Invite friends") { inviting = true }
                        .buttonStyle(.ghost)
                        .sheet(isPresented: $inviting) { InviteFriendsSheet(lobbyId: lobbyId) }
                }

                if let matchId = viewModel.rejoinableMatch {
                    Button {
                        viewModel.rejoinMatch()
                    } label: {
                        Text("Rejoin the game")
                    }
                    .buttonStyle(.solid)
                    .accessibilityHint("Your seat in the game in progress is still yours")
                    .id(matchId)
                }

                if viewModel.waitingForNextRun {
                    Text("A game is in progress. You're in for the next one.")
                        .monoLabel(11, tracking: 0.1)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .well()
                }
                nextUp

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }

                // Both land back on host-or-join rather than popping the
                // whole screen: somebody who just left a room is more likely
                // to want another one than to want the home screen.
                VStack(spacing: 8) {
                    if viewModel.canClose {
                        Button("Close the room", role: .destructive) {
                            Task { await viewModel.closeRoom() }
                        }
                        .buttonStyle(.ghost)
                    }
                    Button("Leave") {
                        Task { await viewModel.leaveRoom() }
                    }
                    .buttonStyle(.quiet)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
        .refreshable { await inbox.load() }
        // Pushing the match screen takes this one off screen, which stops it
        // observing; coming back has to pick the room up again, or the roster
        // sits at whatever it said when the game started.
        .task {
            viewModel.observe()
            await viewModel.refresh()
            await viewModel.loadFormat()
        }
    }

    /// The code is what the whole room needs to read out loud, so it gets a panel.
    private var code: some View {
        PanelCard(edge: false) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Join code").monoLabel(10, weight: .bold, tracking: 0.16, color: Theme.panelMuted)
                    Text(viewModel.roomCode ?? "")
                        .font(.mono(40, weight: .bold, relativeTo: .largeTitle))
                        .tracking(6)
                        .foregroundStyle(Theme.panelFg)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .accessibilityLabel(
                            "Join code \((viewModel.roomCode ?? "").map(String.init).joined(separator: " "))"
                        )
                }
                Spacer(minLength: 0)
                if let code = viewModel.roomCode {
                    ShareLink(item: "Join my Ball Party room with the code \(code)") {
                        Image(systemName: "square.and.arrow.up")
                            .frame(width: 24)
                    }
                    .buttonStyle(BPButtonStyle(variant: .ink, fullWidth: false))
                    .accessibilityLabel("Share the join code")
                }
            }
            .padding(16)
        }
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "At the table", trailing: "\(viewModel.members.count) of 4 seats")
            ForEach(viewModel.members) { member in
                HStack(spacing: 12) {
                    Avatar(name: member.displayName, url: member.avatarURL, size: 32, isMine: member.userId == viewModel.viewerId)
                    Text(member.displayName).slabTitle(20).lineLimit(1)
                    if member.userId == viewModel.lobby?.hostId {
                        Text("Host").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText)
                    }
                    Spacer()
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .well()
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// What the room plays next. Picking and starting are two steps on
    /// purpose: the room can see what's coming before it begins.
    @ViewBuilder
    private var nextUp: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: "Next up")

            if viewModel.isHost {
                Picker("Game", selection: gameBinding) {
                    Text("Choose a game").tag(MatchGame?.none)
                    ForEach(MatchGame.allCases) { game in
                        Text(game.label).tag(MatchGame?.some(game))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fieldStyle()
            } else if let game = viewModel.selectedGame {
                Text(game.label).slabTitle(32)
                Text("Waiting for the host to start").monoLabel(11, tracking: 0.13)
            } else {
                Text("The host hasn't picked a game yet.").monoLabel(11, tracking: 0.13)
            }

            if viewModel.isHost, let chosen = viewModel.selectedGame {
                switch chosen {
                case .higherOrLower: format
                case .auctionTeamBuilder: auctionFormat
                }
                Button {
                    Task { await viewModel.startGame() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isBusy { ProgressView() }
                        Text("Start the game")
                    }
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canStart)
            }

            if let reason = viewModel.startBlockedReason {
                Text(reason).monoLabel(11, tracking: 0.1)
            }
        }
    }

    private var format: some View {
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

    private var auctionFormat: some View {
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

    private var gameBinding: Binding<MatchGame?> {
        Binding(
            get: { viewModel.selectedGame },
            set: { game in
                guard let game else { return }
                Task { await viewModel.selectGame(game) }
            }
        )
    }
}

private struct ClosedRoomView: View {
    @ObservedObject var viewModel: LobbyViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "This room has closed.")
            Button("Back") { Task { await viewModel.dismissClosedRoom() } }
                .buttonStyle(.solid)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
