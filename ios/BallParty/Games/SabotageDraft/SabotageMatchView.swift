import SwiftUI

/// Entry point for one live Sabotage Draft match: owns the view model and shows
/// the board until the season is run, then the standings.
///
/// Like the other games, it dismisses itself once a post-game choice exists —
/// where that leads is the room's business, not the game's.
struct SabotageMatchScreen: View {
    @StateObject private var viewModel: SabotageViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// `roomCode` and `isHost` come from the room that pushed this screen — a
    /// game may not read the lobby itself (`architecture.md`).
    init(matchId: UUID, viewerId: UUID, roomCode: String?, isHost: Bool) {
        _viewModel = StateObject(
            wrappedValue: SabotageViewModel(
                client: SupabaseSabotageClient(client: SupabaseConfig.client),
                matchId: matchId,
                viewerId: viewerId,
                roomCode: roomCode,
                isHost: isHost
            )
        )
    }

    /// For previews and tests: a screen over a view model the caller built.
    init(viewModel: SabotageViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.snapshot == nil {
                LoadingState(label: "Dealing the board…")
            } else if viewModel.isFinished {
                SabotageFinalView(viewModel: viewModel)
            } else {
                SabotagePlayView(viewModel: viewModel)
            }
        }
        .screenBackground()
        .navigationTitle("Sabotage Draft")
        .navigationBarTitleDisplayMode(.inline)
        // A live match is not somewhere to tab away from by accident.
        .toolbar(.hidden, for: .tabBar)
        .task { await viewModel.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.appReturnedToForeground() }
        }
        .onChange(of: viewModel.postGameAction) { _, action in
            if action != nil { dismiss() }
        }
        .onDisappear { viewModel.stopObserving() }
    }
}

// MARK: - Play

private enum SabotageTab: Hashable { case draft, rosters, log }

private struct SabotagePlayView: View {
    @ObservedObject var viewModel: SabotageViewModel
    @State private var tab: SabotageTab = .draft

    var body: some View {
        GameTabShell(
            tabs: [
                GameTab(id: SabotageTab.draft, title: "Draft", systemImage: "scope"),
                GameTab(id: SabotageTab.rosters, title: "Rosters", systemImage: "person.3"),
                GameTab(id: SabotageTab.log, title: "Log", systemImage: "list.bullet.rectangle"),
            ],
            selection: $tab
        ) {
            if let board = viewModel.board {
                SabotageHeader(viewModel: viewModel, clock: viewModel.clock, board: board)
            }
        } content: { tab in
            switch tab {
            case .draft: SabotageDraftTab(viewModel: viewModel)
            case .rosters: SabotageRostersTab(viewModel: viewModel)
            case .log: SabotageLogTab(viewModel: viewModel)
            }
        }
    }
}

/// What a player must never lose sight of: the round and slot, how their own
/// roster is coming, who is on the clock, and the clock itself.
private struct SabotageHeader: View {
    @ObservedObject var viewModel: SabotageViewModel
    @ObservedObject var clock: MatchClockDriver
    let board: SabotageBoard

    var body: some View {
        let remaining = clock.remainingMs
        let urgent = remaining.map { $0 <= 3_000 } ?? false

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Round \(min(board.currentRound, board.roundCount)) of \(board.roundCount) · \(SabotageRules.slotShort(board.slot))")
                    .monoLabel(11, weight: .semibold, tracking: 0.15, color: Theme.fg)
                    .lineLimit(1)
                Spacer()
                Text(board.mode.label).monoLabel(10, tracking: 0.1)
            }
            HeaderStats(
                stats: [
                    HeaderStat(caption: "Your picks", value: "\(viewModel.myFilledCount) / \(board.roundCount)"),
                    HeaderStat(
                        caption: "On the clock",
                        value: viewModel.isActive ? "You" : (viewModel.activePlayer?.name ?? "—"),
                        urgent: viewModel.isActive
                    ),
                    HeaderStat(caption: "Turn clock", value: display(remaining), urgent: urgent || (viewModel.isActive && remaining != nil)),
                ],
                fraction: viewModel.clockFraction,
                tickSeconds: Double(MatchClockConstants.tickMs) / 1_000
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Round \(min(board.currentRound, board.roundCount)) of \(board.roundCount), \(SabotageRules.slotLabel(board.slot)). "
                + "You have locked \(viewModel.myFilledCount) of \(board.roundCount) picks. "
                + (viewModel.isActive ? "You are on the clock. " : "\(viewModel.activePlayer?.name ?? "Someone") is on the clock. ")
                + (remaining.map { "\(Int((Double($0) / 1_000).rounded(.up))) seconds left" } ?? "No timer running")
        )
    }

    /// Whole seconds, then tenths in the last five — a shot clock's convention.
    private func display(_ remaining: Int?) -> String {
        guard let remaining else { return "—" }
        if remaining < 5_000 { return String(format: "%.1f", Double(remaining) / 1_000) }
        return "\(Int((Double(remaining) / 1_000).rounded(.up)))"
    }
}

// MARK: - Shared pieces

private enum PickerTarget: String, Identifiable {
    case pick, guess, replacement

    var id: String { rawValue }
}

// MARK: - Draft tab

private struct SabotageDraftTab: View {
    @ObservedObject var viewModel: SabotageViewModel
    @State private var picker: PickerTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.isPaused {
                    ErrorBanner(message: "The host paused the game.")
                }
                spinCard
                action
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
                waiting
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .sheet(item: $picker) { target in
            sheet(for: target)
        }
    }

    // MARK: The spin

    /// What is publicly true right now, whether or not it is the viewer's move:
    /// whose franchise this is and what its drafter may take from it.
    @ViewBuilder
    private var spinCard: some View {
        PanelCard {
            HStack(spacing: 14) {
                if let spin = viewModel.activeSpin {
                    FranchiseLogo(code: spin.franchiseCode, size: 56)
                } else {
                    Color.clear.frame(width: 56, height: 56)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.isActive ? "You are picking" : "\(viewModel.activePlayer?.name ?? "…") is picking")
                        .monoLabel(10, tracking: 0.13, color: Theme.panelMuted)
                    if let spin = viewModel.activeSpin {
                        Text(SabotageRules.franchiseName(spin.franchiseCode))
                            .slabTitle(24, color: Theme.panelFg)
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                    } else {
                        WaitingNote(text: "Waiting on the spin…", size: 18)
                            .slabTitle(24, color: Theme.panelFg)
                    }
                    if let board = viewModel.board {
                        Text("Choosing \(SabotageRules.chooseLabel(board.slot))")
                            .monoLabel(11, tracking: 0.08, color: Theme.panelMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Your move

    @ViewBuilder
    private var action: some View {
        if viewModel.board?.xFactorOpen == true {
            xFactor
        } else if viewModel.turnOpen {
            if viewModel.isActive { pickForm } else { guessForm }
        } else {
            card("Between turns", "Waiting on the next turn to open.", waiting: true)
        }
    }

    private func card(_ title: String, _ message: String, waiting: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your move").monoLabel(10, tracking: 0.13)
            Text(title).slabTitle(22)
            Group {
                if waiting { WaitingNote(text: message) } else { Text(message) }
            }
            .font(.sans(14)).foregroundStyle(Theme.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
    }

    // The drafter's hidden pick.

    @ViewBuilder
    private var pickForm: some View {
        if let mine = viewModel.myPick {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your move").monoLabel(10, tracking: 0.13)
                Text("Your pick is locked").slabTitle(22)
                HStack(spacing: 10) {
                    Portrait(name: mine.name, url: mine.headshotURL, size: 36)
                    Text("\(mine.name) · \(String(mine.season))").font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                }
                WaitingNote(text: "Waiting on the rest of the table.").font(.sans(14)).foregroundStyle(Theme.fgMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .well()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your move").monoLabel(10, tracking: 0.13)
                Text("Make your hidden pick").slabTitle(22)
                Text("Nobody sees who you chose, or which year.").font(.sans(14)).foregroundStyle(Theme.fgMuted)
                PoolField(choice: viewModel.pickChoice, placeholder: "Search \(viewModel.board.map { SabotageRules.chooseLabel($0.slot) } ?? "a player")…") {
                    picker = .pick
                }
                Button {
                    Task { await viewModel.lockPick() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSaving { LoadingSpinner(size: 16) }
                        Text(viewModel.isSaving ? "Locking…" : "Lock in pick")
                    }
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canLockPick)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .well()
        }
    }

    // Everyone else: one guess or one pass, aimed at whoever is on the clock.

    @ViewBuilder
    private var guessForm: some View {
        let name = viewModel.activePlayer?.name ?? "them"
        if viewModel.hasActed {
            card(
                viewModel.myPass != nil ? "You passed on this turn" : "Guess spent on this turn",
                "Waiting on the rest of the table.",
                waiting: true
            )
        } else if let kind = viewModel.guessKind {
            let exact = kind == .exact
            VStack(alignment: .leading, spacing: 10) {
                Text("Your move").monoLabel(10, tracking: 0.13)
                Text("Sabotage \(name)'s pick").slabTitle(22)
                HStack {
                    Text(exact ? "Guessing the player and year" : "Guessing the player")
                        .font(.sans(14, weight: .semibold)).foregroundStyle(Theme.fg)
                    Spacer()
                    Button("Change") { viewModel.chooseGuessKind(nil) }
                        .font(.mono(11, weight: .bold)).foregroundStyle(Theme.fgMuted)
                        .disabled(viewModel.isSaving)
                }
                if exact { Text("Step 1 of 2 — guess the player").monoLabel(10, tracking: 0.1) }
                PoolField(choice: viewModel.guessChoice, placeholder: "Search a name…") { picker = .guess }
                if exact, viewModel.guessChoice != nil {
                    Text("Step 2 of 2 — choose their replacement").monoLabel(10, tracking: 0.1)
                    PoolField(choice: viewModel.replacementChoice, placeholder: "Search a replacement…") {
                        picker = .replacement
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.lockGuess() }
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isSaving { LoadingSpinner(size: 16) }
                            Text(viewModel.isSaving ? "Locking…" : "Lock in guess")
                        }
                    }
                    .buttonStyle(.solid)
                    .disabled(!viewModel.canLockGuess)
                    Button("Pass") { Task { await viewModel.pass() } }
                        .buttonStyle(.ghost)
                        .fixedSize()
                        .disabled(!viewModel.canGuess)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .well()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your move").monoLabel(10, tracking: 0.13)
                Text("Sabotage \(name)'s pick").slabTitle(22)
                kindButton(.player, "Guess the player", "Right? Same player, a random different year — you don't choose it")
                kindButton(.exact, "Guess the player and year", "Right? You choose exactly what replaces it")
                Button("Pass") { Task { await viewModel.pass() } }
                    .buttonStyle(.ghost)
                    .disabled(!viewModel.canGuess)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .well()
        }
    }

    private func kindButton(_ kind: SabotageViewModel.GuessKind, _ title: String, _ detail: String) -> some View {
        Button {
            viewModel.chooseGuessKind(kind)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                Text(detail).font(.sans(12)).foregroundStyle(Theme.fgMuted).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canGuess)
    }

    // The wildcard upgrade.

    @ViewBuilder
    private var xFactor: some View {
        if !viewModel.isActive {
            card("\(viewModel.activePlayer?.name ?? "…")'s X-Factor", "Waiting on their decision.", waiting: true)
        } else if let decision = viewModel.myDecision {
            card("X-Factor decision locked", decision.replaceSlot.map { "Replaces \($0.replacingOccurrences(of: "_", with: " "))" } ?? "Discarded")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your move").monoLabel(10, tracking: 0.13)
                Text("Assign or discard your X-Factor").slabTitle(22)
                if let pick = viewModel.xFactorPick {
                    HStack(spacing: 10) {
                        Portrait(name: pick.name, url: pick.headshotURL, size: 36)
                        Text("\(pick.name) · \(String(pick.season))").font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg)
                    }
                }
                Text("Replace a slot at the same position, or keep your roster as it is.")
                    .font(.sans(14)).foregroundStyle(Theme.fgMuted)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(viewModel.xFactorSlots, id: \.self) { slot in
                        Button("Replace \(SabotageRules.slotShort(slot))") {
                            Task { await viewModel.decideXFactor(replacing: slot) }
                        }
                        .buttonStyle(.ghost)
                        .disabled(!viewModel.canDecideXFactor)
                    }
                }
                Button("Discard X-Factor") {
                    Task { await viewModel.decideXFactor(replacing: nil) }
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canDecideXFactor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .well()
        }
    }

    /// Who the turn is still waiting on — short, so the tab stays one screen.
    @ViewBuilder
    private var waiting: some View {
        if viewModel.turnOpen, viewModel.board?.xFactorOpen != true {
            let pending = viewModel.seatsStillToAct
            let text = pending.isEmpty
                ? "Everyone has acted — the turn closes now."
                : "Waiting on " + pending.map { $0.userId == viewModel.viewerId ? "you" : $0.name }.joined(separator: ", ")
            WaitingNote(text: text, size: 12).monoLabel(10, tracking: 0.1)
        }
    }

    // MARK: The search sheet

    @ViewBuilder
    private func sheet(for target: PickerTarget) -> some View {
        switch target {
        case .pick:
            SabotagePickerSheet(title: "Your pick", options: viewModel.pool, needsSeason: true) {
                viewModel.pickChoice = $0
            }
        case .guess:
            SabotagePickerSheet(
                title: "Guess \(viewModel.activePlayer?.name ?? "their")'s pick",
                options: viewModel.pool,
                needsSeason: viewModel.guessKind == .exact
            ) { viewModel.chooseGuess($0) }
        case .replacement:
            SabotagePickerSheet(title: "Their replacement", options: viewModel.pool, needsSeason: true) {
                viewModel.replacementChoice = $0
            }
        }
    }
}

/// A button that looks like a search field: the chosen player, or a prompt.
private struct PoolField: View {
    let choice: SabotageOption?
    let placeholder: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let choice {
                    Portrait(name: choice.name, url: choice.headshotURL, size: 30)
                    Text(choice.name).font(.sans(15, weight: .semibold)).foregroundStyle(Theme.fg).lineLimit(1)
                    Text("· \(String(choice.season))").font(.mono(12)).foregroundStyle(Theme.fgMuted)
                    Spacer(minLength: 8)
                    Text("Change").monoLabel(10, weight: .bold, tracking: 0.1)
                } else {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.fgMuted)
                    Text(placeholder).font(.sans(15)).foregroundStyle(Theme.fgMuted).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.map { "\($0.name), \($0.season). Change" } ?? placeholder)
    }
}

// MARK: - Rosters tab

private struct SabotageRostersTab: View {
    @ObservedObject var viewModel: SabotageViewModel
    @State private var opened: Set<UUID>

    init(viewModel: SabotageViewModel) {
        self.viewModel = viewModel
        // Yours is the one roster always worth checking.
        _opened = State(initialValue: [viewModel.viewerId])
    }

    /// The viewer first, then seat order.
    private var ordered: [SabotagePlayer] {
        let mine = viewModel.players.filter { $0.userId == viewModel.viewerId }
        return mine + viewModel.players.filter { $0.userId != viewModel.viewerId }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(ordered) { player in
                    rosterCard(player)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func rosterCard(_ player: SabotagePlayer) -> some View {
        let mine = player.userId == viewModel.viewerId
        let active = player.userId == viewModel.board?.activeUserId
        let hits = viewModel.hitCount(on: player)
        let isOpen = opened.contains(player.userId)
        let roundCount = viewModel.roundCount

        return VStack(spacing: 0) {
            Button {
                if isOpen { opened.remove(player.userId) } else { opened.insert(player.userId) }
            } label: {
                HStack(spacing: 10) {
                    Avatar(name: player.name, url: player.avatarURL, size: 36, isMine: mine)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(mine ? "You" : player.name).slabTitle(18).lineLimit(1)
                            if player.absent {
                                Text("AWAY").monoLabel(8, weight: .bold, tracking: 0.07)
                            }
                        }
                        Text(active ? "On the clock" : "\(viewModel.filledCount(of: player))/\(roundCount) filled")
                            .monoLabel(9, tracking: 0.07, color: active ? Theme.hiddenText : Theme.fgMuted)
                    }
                    Spacer(minLength: 8)
                    Text(hits == 0 ? "No hits" : "\(hits) hit\(hits == 1 ? "" : "s")")
                        .monoLabel(10, weight: hits == 0 ? .regular : .bold, tracking: 0.07, color: hits == 0 ? Theme.fgMuted : Theme.hiddenText)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.fgMuted)
                }
                .padding(12)
                .background(active ? Theme.hiddenInk.opacity(0.14) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Collapses this roster" : "Expands this roster")

            if isOpen {
                VStack(spacing: 6) {
                    ForEach(1...max(roundCount, 1), id: \.self) { round in
                        RosterRow(
                            slot: SabotageRules.slot(forRound: round, roundCount: roundCount),
                            player: player,
                            mine: mine,
                            value: viewModel.cell(for: player, round: round)
                        )
                    }
                }
                .padding(8)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .well()
    }
}

private struct RosterRow: View {
    let slot: String
    let player: SabotagePlayer
    let mine: Bool
    let value: (cell: SabotageViewModel.RosterCell, respun: Bool, sabotaged: Bool)

    var body: some View {
        HStack(spacing: 8) {
            Text(SabotageRules.slotShort(slot))
                .monoLabel(10, weight: .bold, tracking: 0.1, color: Theme.panelMuted)
                .frame(width: 50, alignment: .leading)
            content
            Spacer(minLength: 4)
            if value.respun {
                badge("Respun", fill: Theme.panelShade, ink: Theme.panelMuted)
            }
            if value.sabotaged {
                badge("Sabotaged", fill: Theme.hidden, ink: Theme.fg)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(border, style: dashed ? StrokeStyle(lineWidth: 1, dash: [3, 3]) : StrokeStyle(lineWidth: 1)))
        .accessibilityElement(children: .combine)
    }

    private var dashed: Bool {
        switch value.cell {
        case .upNext, .notReached: true
        default: false
        }
    }

    private var border: Color {
        switch value.cell {
        case .pick where mine: Theme.hiddenInk.opacity(0.4)
        case .choosing: Theme.hiddenInk.opacity(0.5)
        default: Theme.panelFg.opacity(0.12)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch value.cell {
        case .pick(let pick):
            HStack(spacing: 8) {
                Portrait(name: pick.name, url: pick.headshotURL, size: 26)
                Text("\(pick.name) · \(String(pick.season))")
                    .font(.sans(14, weight: .semibold)).foregroundStyle(Theme.panelFg).lineLimit(1)
            }
        case .locked:
            Text("Locked").font(.sans(14, weight: .semibold)).foregroundStyle(Theme.panelFg)
        case .concealed(let franchise):
            Concealed(label: "\(player.name)'s concealed pick", compact: true) {
                HStack(spacing: 6) {
                    if let franchise { FranchiseLogo(code: franchise, size: 16) }
                    Text(franchise.map(SabotageRules.franchiseName) ?? "Locked")
                        .monoLabel(10, weight: .bold, tracking: 0.06, color: Theme.fg)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .fixedSize()
        case .choosing:
            Text("Choosing…").monoLabel(10, weight: .bold, tracking: 0.1, color: Theme.hiddenInk)
        case .upNext:
            Text("— up next —").monoLabel(10, tracking: 0.06, color: Theme.panelMuted)
        case .notReached:
            Text("— not reached —").monoLabel(10, tracking: 0.06, color: Theme.panelMuted)
        }
    }

    private func badge(_ text: String, fill: Color, ink: Color) -> some View {
        Text(text.uppercased())
            .monoLabel(8, weight: .bold, tracking: 0.05, color: ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(fill)
    }
}

// MARK: - Log tab

private struct SabotageLogTab: View {
    @ObservedObject var viewModel: SabotageViewModel

    var body: some View {
        let log = viewModel.turnLog
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                liveTurn
                if log.isEmpty {
                    EmptyState(title: "Nothing yet", message: "Each turn's guesses and hits land here, newest first.")
                }
                ForEach(rounds(of: log), id: \.round) { group in
                    Text("Round \(group.round)").monoLabel(11, weight: .bold, tracking: 0.14, color: Theme.fg)
                        .padding(.top, 4)
                    ForEach(group.turns) { turn in
                        TurnWell(turn: turn, viewerId: viewModel.viewerId)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private func rounds(of log: [SabotageViewModel.TurnRecord]) -> [(round: Int, turns: [SabotageViewModel.TurnRecord])] {
        var groups: [(round: Int, turns: [SabotageViewModel.TurnRecord])] = []
        for turn in log {
            if let last = groups.last, last.round == turn.round {
                groups[groups.count - 1].turns.append(turn)
            } else {
                groups.append((turn.round, [turn]))
            }
        }
        return groups
    }

    /// The turn in progress, above the ones that are over.
    @ViewBuilder
    private var liveTurn: some View {
        if viewModel.turnOpen, let board = viewModel.board, let active = viewModel.activePlayer {
            let pending = viewModel.seatsStillToAct
            VStack(alignment: .leading, spacing: 4) {
                Text("On the clock").monoLabel(10, weight: .bold, tracking: 0.13, color: Theme.hiddenText)
                Text(viewModel.isActive ? "You are drafting" : "\(active.name) is drafting").slabTitle(18)
                Text(
                    "Round \(board.currentRound) · \(SabotageRules.slotShort(board.slot)) — "
                        + (pending.isEmpty ? "everyone has acted" : "waiting on " + pending.map { $0.userId == viewModel.viewerId ? "you" : $0.name }.joined(separator: ", "))
                )
                .monoLabel(10, tracking: 0.06)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .well()
        }
    }
}

private struct TurnWell: View {
    let turn: SabotageViewModel.TurnRecord
    let viewerId: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(turn.drafter.userId == viewerId ? "You drafted" : "\(turn.drafter.name) drafted").slabTitle(18)
                Spacer(minLength: 8)
                Text(SabotageRules.slotShort(turn.slot)).monoLabel(9, tracking: 0.1)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            HStack(spacing: 8) {
                if let pick = turn.pick {
                    Portrait(name: pick.name, url: pick.headshotURL, size: 22)
                    Text("\(pick.name) · \(String(pick.season))").font(.sans(13, weight: .semibold)).foregroundStyle(Theme.fg)
                } else if let spin = turn.spin {
                    FranchiseLogo(code: spin.franchiseCode, size: 18)
                    Text(SabotageRules.franchiseName(spin.franchiseCode)).monoLabel(10, tracking: 0.06)
                }
                Spacer(minLength: 8)
                Text(turn.outcome.uppercased())
                    .monoLabel(9, weight: .bold, tracking: 0.08, color: turn.respun || turn.sabotaged ? Theme.hiddenText : Theme.fgMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            LineRule()

            ForEach(turn.actions) { action in
                HStack {
                    Text("\(action.player.userId == viewerId ? "You" : action.player.name) · \(label(action.kind))")
                        .font(.sans(14, weight: .semibold)).foregroundStyle(Theme.fg)
                    Spacer(minLength: 8)
                    Text(result(action))
                        .monoLabel(10, weight: action.result == .miss || action.result == nil ? .regular : .bold, tracking: 0.06,
                                   color: action.result == .respun || action.result == .sabotaged ? Theme.hiddenText : Theme.fgMuted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            if turn.actions.isEmpty {
                Text("No guesses").monoLabel(10, tracking: 0.08).padding(12)
            }
            Spacer().frame(height: 4)
        }
        .well()
        .accessibilityElement(children: .combine)
    }

    private func label(_ kind: SabotageViewModel.TurnAction.Kind) -> String {
        switch kind {
        case .guess: "player only"
        case .exactGuess: "player + year"
        case .pass: "pass"
        }
    }

    private func result(_ action: SabotageViewModel.TurnAction) -> String {
        guard action.kind != .pass else { return "—" }
        switch action.result {
        case .miss: return "Miss"
        case .respun: return "Respun year"
        case .sabotaged: return "Exact hit"
        case nil: return "Pending"
        }
    }
}
