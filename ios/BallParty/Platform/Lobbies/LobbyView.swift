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
    @Environment(\.scenePhase) private var scenePhase
    /// Which match this screen pushed, so dismissing it can say *which* board
    /// was left rather than whichever one the room happens to show now.
    @State private var presentedMatch: UUID?

    init(viewerId: UUID) {
        _viewModel = StateObject(
            wrappedValue: LobbyViewModel(
                client: SupabaseLobbyClient(client: SupabaseConfig.client),
                game: SupabaseHigherOrLowerClient(client: SupabaseConfig.client),
                viewerId: viewerId
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.stage {
            case .entry: LobbyEntryView(viewModel: viewModel)
            case .room: LobbyRoomView(viewModel: viewModel)
            case .closed: ClosedRoomView(viewModel: viewModel)
            }
        }
        .navigationTitle("Play with friends")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: presentedMatchBinding) { route in
            MatchScreen(
                matchId: route.id,
                viewerId: viewModel.viewerId,
                roomCode: viewModel.roomCode,
                isHost: viewModel.isHost
            )
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
            get: { viewModel.matchToEnter.map(MatchRoute.init(id:)) },
            set: { route in
                guard route == nil, let left = presentedMatch else { return }
                viewModel.matchDismissed(left)
                presentedMatch = nil
            }
        )
    }

    /// A match id, as something `navigationDestination(item:)` can key off.
    private struct MatchRoute: Identifiable, Hashable {
        let id: UUID
    }
}

// MARK: - Host or join

private struct LobbyEntryView: View {
    @ObservedObject var viewModel: LobbyViewModel
    @FocusState private var codeFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TWO TO FOUR PLAYERS")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Play a room together.")
                        .font(.title2.weight(.bold))
                    Text("Host a room and share the code, or join one you were given.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.createRoom() }
                } label: {
                    HStack {
                        if viewModel.isBusy { ProgressView().tint(.white) }
                        Text("Host a room").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.isBusy)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Join with a code").font(.headline)
                    HStack(spacing: 8) {
                        TextField("ABCDE", text: $viewModel.code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.title3.monospaced().weight(.bold))
                            .padding(10)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                            .focused($codeFocused)
                            .submitLabel(.go)
                            .onSubmit { Task { await viewModel.joinRoom() } }
                        Button("Join") {
                            codeFocused = false
                            Task { await viewModel.joinRoom() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .disabled(viewModel.isBusy)
                    }
                }

                if let message = viewModel.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding()
        }
    }
}

// MARK: - The room

private struct LobbyRoomView: View {
    @ObservedObject var viewModel: LobbyViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                code
                roster

                if let matchId = viewModel.rejoinableMatch {
                    Button {
                        viewModel.rejoinMatch()
                    } label: {
                        Text("Rejoin the game").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Your seat in the game in progress is still yours")
                    .id(matchId)
                }

                if viewModel.waitingForNextRun {
                    Text("A game is in progress. You're in for the next one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                }
                nextUp

                if let message = viewModel.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }

                // Both land back on host-or-join rather than popping the
                // whole screen: somebody who just left a room is more likely
                // to want another one than to want the home screen.
                VStack(spacing: 8) {
                    if viewModel.canClose {
                        Button("Close the room", role: .destructive) {
                            Task { await viewModel.closeRoom() }
                        }
                    }
                    Button("Leave") {
                        Task { await viewModel.leaveRoom() }
                    }
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
        // Pushing the match screen takes this one off screen, which stops it
        // observing; coming back has to pick the room up again, or the roster
        // sits at whatever it said when the game started.
        .task {
            viewModel.observe()
            await viewModel.refresh()
            await viewModel.loadFormat()
        }
    }

    private var code: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("JOIN CODE")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text(viewModel.roomCode ?? "")
                    .font(.system(size: 40, weight: .heavy, design: .monospaced))
                    .kerning(4)
                    .accessibilityLabel(
                        "Join code \((viewModel.roomCode ?? "").map(String.init).joined(separator: " "))"
                    )
                if let code = viewModel.roomCode {
                    ShareLink(item: "Join my Ball Party room with the code \(code)") {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share the join code")
                }
            }
        }
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("At the table").font(.headline)
                Spacer()
                Text("\(viewModel.members.count) of 4 seats")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.members) { member in
                HStack(spacing: 10) {
                    Portrait(name: member.displayName, url: nil, size: 32)
                    Text(member.displayName).font(.subheadline.weight(.semibold))
                    if member.userId == viewModel.lobby?.hostId {
                        Text("HOST")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.tint)
                    }
                    Spacer()
                }
                .padding(10)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// What the room plays next. Picking and starting are two steps on
    /// purpose: the room can see what's coming before it begins.
    @ViewBuilder
    private var nextUp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next up").font(.headline)

            if viewModel.isHost {
                Picker("Game", selection: gameBinding) {
                    Text("Choose a game").tag(MatchGame?.none)
                    ForEach(MatchGame.allCases) { game in
                        Text(game.label).tag(MatchGame?.some(game))
                    }
                }
                .pickerStyle(.menu)
            } else if let game = viewModel.selectedGame {
                Text(game.label).font(.title3.weight(.bold))
                Text("Waiting for the host to start").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("The host hasn't picked a game yet.").font(.footnote).foregroundStyle(.secondary)
            }

            if viewModel.isHost, viewModel.selectedGame == .higherOrLower {
                format
                Button {
                    Task { await viewModel.startGame() }
                } label: {
                    HStack {
                        if viewModel.isBusy { ProgressView().tint(.white) }
                        Text("Start the game").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.canStart)
            }

            if let reason = viewModel.startBlockedReason {
                Text(reason.uppercased())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var format: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Scoring", selection: $viewModel.scoringMode) {
                ForEach(ScoringMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if !viewModel.seasonChoices.isEmpty {
                HStack(spacing: 12) {
                    SeasonPicker(title: "From", selection: $viewModel.seasonFrom, choices: viewModel.seasonChoices)
                    SeasonPicker(title: "To", selection: $viewModel.seasonTo, choices: viewModel.seasonChoices)
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

private struct SeasonPicker: View {
    let title: String
    @Binding var selection: Int
    let choices: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(choices, id: \.self) { season in
                    Text(String(season)).tag(season)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ClosedRoomView: View {
    @ObservedObject var viewModel: LobbyViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("This room has closed.").font(.headline)
            Button("Back") { viewModel.dismissClosedRoom() }
        }
        .padding()
    }
}
