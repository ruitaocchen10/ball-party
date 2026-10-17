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
    /// Owned by the tab shell, which also reads its count for the bell.
    @ObservedObject var inbox: RoomInvitesInboxViewModel
    /// A room code from a room link. Joined once this screen is not already in
    /// a room, then cleared.
    @Binding var pendingRoomCode: String?
    /// A room the player joined from the notification inbox; stepped into once, then cleared.
    @Binding var joinedLobby: Lobby?
    @Environment(\.scenePhase) private var scenePhase
    /// Which match this screen pushed, so dismissing it can say *which* board
    /// was left rather than whichever one the room happens to show now.
    @State private var presentedMatch: UUID?
    /// Which of the room's tabs is showing. Held here, above the room, so the
    /// header can draw the tabs and a match pushed on top doesn't reset it.
    @State private var roomTab: RoomTab = .room
    /// The win total as of the last time the Scoreboard was on screen, so the
    /// tab can show a dot when somebody has won since. Nil outside a room.
    @State private var seenWins: Int?
    @State private var confirmingLeave = false

    init(
        viewerId: UUID, inbox: RoomInvitesInboxViewModel, pendingRoomCode: Binding<String?> = .constant(nil),
        joinedLobby: Binding<Lobby?> = .constant(nil)
    ) {
        self.inbox = inbox
        _pendingRoomCode = pendingRoomCode
        _joinedLobby = joinedLobby
        _viewModel = StateObject(
            wrappedValue: LobbyViewModel(
                client: SupabaseLobbyClient(client: SupabaseConfig.client),
                game: SupabaseHigherOrLowerClient(client: SupabaseConfig.client),
                auction: SupabaseAuctionClient(client: SupabaseConfig.client),
                wavelength: SupabaseWavelengthClient(client: SupabaseConfig.client),
                viewerId: viewerId
            )
        )
    }

    var body: some View {
        framed
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
                case .wavelength:
                    WavelengthMatchScreen(
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
        .onChange(of: viewModel.stage) { _, stage in
            if stage == .room {
                seenWins = viewModel.totalWins
            } else {
                seenWins = nil
                roomTab = .room
            }
        }
        .onChange(of: viewModel.totalWins) { _, total in
            if roomTab == .scoreboard { seenWins = total }
        }
        .onChange(of: roomTab) { _, tab in
            if tab == .scoreboard { seenWins = viewModel.totalWins }
        }
        // A link or an inbox join arriving with the screen decides the room; with
        // neither, a player the server still has in a room goes back into it.
        .task {
            guard pendingRoomCode == nil, joinedLobby == nil else { return }
            await viewModel.restoreCurrentRoom()
        }
        .task(id: pendingRoomCode) { await joinPendingRoom() }
        .task(id: joinedLobby?.id) {
            guard let lobby = joinedLobby else { return }
            // Cleared once the room is open, not before: it is what this task is
            // keyed on, so changing it cancels the task, which cut the room's load
            // short and put the player back on the entry screen with an error.
            await viewModel.adopt(lobby)
            joinedLobby = nil
        }
        .onDisappear { viewModel.stopObserving() }
    }

    /// A room link only joins from the host-or-join stage; someone already in a
    /// room is never moved out of it by a tap on a link.
    private func joinPendingRoom() async {
        guard let pending = pendingRoomCode else { return }
        defer { pendingRoomCode = nil }
        guard viewModel.stage == .entry else { return }
        await viewModel.joinRoom(code: pending)
    }

    private var stageView: some View {
        Group {
            switch viewModel.stage {
            case .entry: LobbyEntryView(viewModel: viewModel, inbox: inbox)
            case .room: LobbyRoomView(viewModel: viewModel, inbox: inbox, tab: $roomTab)
            case .closed: ClosedRoomView(viewModel: viewModel)
            }
        }
        .screenBackground()
    }

    /// The header, with the room's tabs under it only while in a room. Two
    /// branches rather than one optional row, because a header with tabs below
    /// it drops its own hairline.
    @ViewBuilder private var framed: some View {
        if viewModel.stage == .room {
            stageView.screenHeader("Party") {
                leaveButton
            } trailing: {
                RootBell()
            } tabs: {
                HeaderTabs(
                    selection: $roomTab,
                    options: RoomTab.allCases,
                    title: \.title,
                    badge: { tab in
                        tab == .scoreboard && seenWins.map { viewModel.totalWins > $0 } == true ? 1 : 0
                    },
                    accessibilityName: "Room"
                )
            }
        } else {
            stageView.screenHeader("Party") { RootBell() }
        }
    }

    /// The header's leave icon. The dialog hangs off the button itself, not
    /// the screen, so it opens from the icon rather than from the screen's
    /// bottom edge.
    private var leaveButton: some View {
        HeaderIconButton(
            systemName: "rectangle.portrait.and.arrow.right",
            label: viewModel.isHost ? "Leave or close the room" : "Leave the room"
        ) { confirmingLeave = true }
        .confirmationDialog(
            viewModel.isHost ? "Leave or close this room?" : "Leave this room?",
            isPresented: $confirmingLeave,
            titleVisibility: .visible
        ) {
            // Both land back on host-or-join rather than popping the whole
            // screen: somebody who just left a room is more likely to want
            // another one than to want the home screen.
            Button("Leave room", role: viewModel.isHost ? nil : .destructive) {
                Task { await viewModel.leaveRoom() }
            }
            if viewModel.canClose {
                Button("Close room for everyone", role: .destructive) {
                    Task { await viewModel.closeRoom() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.isHost
                ? "Leaving hands the room to the player who has been in it longest. Closing ends it for everyone."
                : "You can rejoin with the code while the room is open.")
        }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RoomInvitesInboxSection(viewModel: inbox, hasRoom: false) { lobby in
                    Task { await viewModel.adopt(lobby) }
                }

                startCard

                GameInfoSection()

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(16)
        }
        .refreshable { await inbox.load() }
    }

    /// The primary path, so it is the big raised card. The whole card is the
    /// button.
    private var startCard: some View {
        Button {
            Task { await viewModel.createRoom() }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    if viewModel.isBusy {
                        LoadingSpinner(size: 18)
                    } else {
                        Image(systemName: "party.popper")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(Theme.fg)
                    }
                }
                .frame(width: 44, height: 44)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
                .padding(.bottom, 8)
                .accessibilityHidden(true)
                Text("Start a party").slabTitle(38, color: Theme.surface)
                    .padding(.bottom, 2)
                Text("Opens a room. Invite friends or send them the link, and pick a game once they're in.")
                    .font(.sans(14))
                    .foregroundStyle(Theme.surface.opacity(0.75))
                    .multilineTextAlignment(.leading)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.fg)
                    .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 10)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(StartCardPressStyle())
        .disabled(viewModel.isBusy)
        .accessibilityLabel("Start a party")
        .accessibilityHint("Opens a room you can invite friends to")
    }
}

/// A press dips the card, the way the dark button's hover does.
private struct StartCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - The room

/// The three views of a room under the header. Everyone sees all three: the
/// Game tab is where the host picks a game and sets it up, and where everybody
/// else sees what the host has picked. Starting it is on the Room tab.
private enum RoomTab: Hashable, CaseIterable {
    case room, game, scoreboard

    var title: String {
        switch self {
        case .room: "Room"
        case .game: "Game"
        case .scoreboard: "Scoreboard"
        }
    }
}

private struct LobbyRoomView: View {
    @ObservedObject var viewModel: LobbyViewModel
    @ObservedObject var inbox: RoomInvitesInboxViewModel
    @Binding var tab: RoomTab
    @State private var inviting = false

    var body: some View {
        Group {
            switch tab {
            case .room: roomContent
            case .game: gameContent
            case .scoreboard: scoreboard
            }
        }
        // On the room itself, not on a tab's content, so switching tabs
        // doesn't restart the channel. Pushing the match screen takes this
        // off screen, which stops it observing; coming back has to pick the
        // room up again, or the roster sits at whatever it said when the game
        // started.
        .task {
            viewModel.observe()
            await viewModel.refresh()
            await viewModel.loadFormat()
        }
        // The invite sheet: the room link and the friend list. Any open seat
        // opens it.
        .sheet(isPresented: $inviting) {
            if let lobbyId = viewModel.lobby?.id {
                InviteFriendsSheet(lobbyId: lobbyId, roomCode: viewModel.roomCode ?? "")
            }
        }
    }

    private var roomContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                RoomInvitesInboxSection(viewModel: inbox, hasRoom: true) { lobby in
                    Task { await viewModel.adopt(lobby) }
                }
                roster

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
                nextUpSummary

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
            }
            .padding(16)
        }
        .refreshable { await inbox.load() }
        // Start is the room's one call to action, so it stays in reach under
        // the seats and says what is missing above it. Not while a game is
        // under way: the room then offers to rejoin it instead.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isHost, viewModel.snapshot?.run?.inFlightMatch == nil {
                GameStartBar(viewModel: viewModel)
            }
        }
    }

    /// The Game tab: a row of game cards. The host's swipe picks and their
    /// controls set the game up; everybody else browses and reads the host's
    /// settings. Starting it is on the Room tab.
    private var gameContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.waitingForNextRun {
                    Text("A game is in progress. You're in for the next one.")
                        .monoLabel(11, tracking: 0.1)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .well()
                        .padding(.horizontal, 16)
                }
                LobbyGameCarousel(viewModel: viewModel)

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 16)
        }
    }

    /// The game being played next, with how it is set up, on the Room tab.
    /// Opens the Game tab, where the host changes it.
    private var nextUpSummary: some View {
        let game = viewModel.selectedGame
        return Button {
            tab = .game
        } label: {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next up").monoLabel(10, weight: .bold, tracking: 0.14)
                    Text(game?.label ?? (viewModel.isHost ? "Choose a game" : "Not picked yet"))
                        .slabTitle(22, color: game == nil ? Theme.fgMuted : Theme.fg)
                        .lineLimit(1)
                    if let game {
                        Text(viewModel.displayedFormat.lines(for: game).map(\.value).joined(separator: " · "))
                            .monoLabel(10, tracking: 0.08)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.fgMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .well()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Next up: \(game?.label ?? "no game picked")")
        .accessibilityHint("Opens the Game tab")
    }

    /// Wins in this room since it opened. Resets when the room closes, like
    /// the web's scoreboard.
    private var scoreboard: some View {
        let standings = viewModel.standings
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DataTable(
                    columns: [
                        .rank { $0.rank.map(String.init) },
                        TableColumn("Player") { (standing: LobbyViewModel.Standing, tone) in
                            HStack(spacing: 10) {
                                Avatar(name: standing.member.displayName, url: standing.member.avatarURL, size: 32)
                                Text(standing.member.userId == viewModel.viewerId
                                    ? "\(standing.member.displayName) · You" : standing.member.displayName)
                                    .font(.sans(16, weight: standing.member.userId == viewModel.viewerId ? .semibold : .medium))
                                    .foregroundStyle(tone.primary)
                                    .lineLimit(1)
                            }
                        },
                        .value("Wins") { String($0.wins) },
                    ],
                    rows: standings,
                    highlight: { $0.member.userId == viewModel.viewerId },
                    spoken: { standing in
                        let wins = standing.wins == 1 ? "1 win" : "\(standing.wins) wins"
                        let rank = standing.rank.map { "Rank \($0), " } ?? ""
                        return "\(rank)\(standing.member.displayName), \(wins)"
                    }
                )
                if viewModel.totalWins == 0 {
                    Text("First win starts the board.")
                        .font(.sans(15))
                        .foregroundStyle(Theme.fgMuted)
                        .padding(.top, 4)
                }
            }
            .padding(16)
        }
        .refreshable { await viewModel.refresh() }
    }

    /// The four seats as a 2x2 grid: a card per player, then an open-seat card
    /// for each place still free, which opens the invite sheet.
    private var roster: some View {
        let members = viewModel.members
        let open = max(0, Self.seatCount - members.count)
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(members.enumerated()), id: \.element.id) { seat, member in
                seatCard(member, seat: seat + 1)
            }
            ForEach(0..<open, id: \.self) { _ in openSeat }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Players at the table")
    }

    private static let seatCount = 4
    private static let seatHeight: CGFloat = 208

    /// A player's seat: a light card, so the people at the table stand out from
    /// the dark screen and from the open seats around them.
    private func seatCard(_ member: LobbyMember, seat: Int) -> some View {
        let isYou = member.userId == viewModel.viewerId
        let isHost = member.userId == viewModel.lobby?.hostId
        let ink = Theme.surface
        let muted = Theme.surface.opacity(0.6)
        return VStack(spacing: 0) {
            HStack {
                Text("Seat \(seat)").monoLabel(9, weight: .bold, tracking: 0.12, color: muted)
                Spacer(minLength: 4)
                if isHost {
                    Text("Host")
                        .monoLabel(8, weight: .bold, tracking: 0.1, color: Theme.fg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ink, in: RoundedRectangle(cornerRadius: 3))
                }
            }
            Spacer(minLength: 8)
            Avatar(name: member.displayName, url: member.avatarURL, size: 64, isMine: isYou)
            Spacer(minLength: 8)
            Text(member.displayName)
                .slabTitle(20, color: ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(isYou ? "you" : "at the table")
                .monoLabel(9, tracking: 0.1, color: muted)
                .padding(.top, 4)
            SeatForm(form: viewModel.memberForm[member.userId], ink: ink, muted: muted)
                .padding(.top, 8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: Self.seatHeight)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.fg)
                .shadow(color: .black.opacity(0.4), radius: 10, x: 0, y: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Seat \(seat), \(member.displayName)\(isHost ? ", host" : "")\(isYou ? ", you" : ""). "
                + SeatForm.spoken(viewModel.memberForm[member.userId])
        )
    }

    /// An empty seat: a dashed outline with one red plus, so the only loud
    /// thing in the grid is the way to fill it. Opens the invite sheet.
    private var openSeat: some View {
        Button { inviting = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.fg)
                    .frame(width: 48, height: 48)
                    .background(Theme.hidden, in: Circle())
                Text("Open seat").slabTitle(18, color: Theme.fgMuted)
                Text("Invite a friend").monoLabel(9, weight: .bold, tracking: 0.1, color: Theme.hiddenText)
            }
            .frame(maxWidth: .infinity, minHeight: Self.seatHeight)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(Theme.fg.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open seat")
        .accessibilityHint("Invite a friend")
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

/// A player's form under their seat, as on web: win rate, best streak and their
/// last few results (a red dot is a win), or "New" before their first game.
private struct SeatForm: View {
    let form: LobbyMemberForm?
    let ink: Color
    let muted: Color

    var body: some View {
        if let form, !form.isNew {
            VStack(spacing: 6) {
                HStack(spacing: 12) {
                    stat("trophy", "\(form.winRate)%")
                    stat("flame", "\(form.bestStreak)")
                }
                HStack(spacing: 4) {
                    ForEach(Array(form.recent.enumerated()), id: \.offset) { _, won in
                        Circle()
                            .fill(won ? Theme.hiddenInk : ink.opacity(0.28))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .accessibilityHidden(true)
        } else {
            Text("New").monoLabel(9, weight: .bold, tracking: 0.12, color: muted)
                .accessibilityHidden(true)
        }
    }

    private func stat(_ symbol: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.hiddenInk)
            Text(value).monoLabel(11, weight: .bold, tracking: 0.02, color: ink)
        }
    }

    static func spoken(_ form: LobbyMemberForm?) -> String {
        guard let form, !form.isNew else { return "New player" }
        let recent = form.recent.map { $0 ? "win" : "loss" }.joined(separator: ", ")
        return "\(form.winRate) percent win rate, best streak \(form.bestStreak). Recent: \(recent)"
    }
}
