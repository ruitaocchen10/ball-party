import SwiftUI

/// Entry point for one live Wavelength match: owns the view model and shows the
/// board until it ends, then the result.
///
/// Like the auction, it dismisses itself once a post-game choice exists — where
/// that leads is the room's business, not the game's.
struct WavelengthMatchScreen: View {
    @StateObject private var viewModel: WavelengthViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// `roomCode` and `isHost` come from the room that pushed this screen — a
    /// game may not read the lobby itself (`architecture.md`).
    init(matchId: UUID, viewerId: UUID, roomCode: String?, isHost: Bool) {
        _viewModel = StateObject(
            wrappedValue: WavelengthViewModel(
                client: SupabaseWavelengthClient(client: SupabaseConfig.client),
                matchId: matchId,
                viewerId: viewerId,
                roomCode: roomCode,
                isHost: isHost
            )
        )
    }

    /// For previews and tests: a screen over a view model the caller built.
    init(viewModel: WavelengthViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.snapshot == nil {
                LoadingState(label: "Dealing the cards…")
            } else if viewModel.isFinished {
                WavelengthFinalView(viewModel: viewModel)
            } else {
                WavelengthPlayView(viewModel: viewModel)
            }
        }
        .screenBackground()
        .navigationTitle("Wavelength")
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

private enum WavelengthTab: Hashable { case dial, rounds }

private struct WavelengthPlayView: View {
    @ObservedObject var viewModel: WavelengthViewModel
    @State private var tab: WavelengthTab = .dial

    var body: some View {
        GameTabShell(
            tabs: [
                GameTab(id: WavelengthTab.dial, title: "Dial", systemImage: "dial.medium"),
                GameTab(id: WavelengthTab.rounds, title: "Rounds", systemImage: "list.number"),
            ],
            selection: $tab
        ) {
            if let board = viewModel.board {
                WavelengthHeader(viewModel: viewModel, clock: viewModel.clock, board: board)
            }
        } content: { tab in
            switch tab {
            case .dial: WavelengthDialTab(viewModel: viewModel)
            case .rounds: WavelengthRoundsTab(viewModel: viewModel)
            }
        }
    }
}

/// What a player must never lose sight of: the round, the score, and the clock.
private struct WavelengthHeader: View {
    @ObservedObject var viewModel: WavelengthViewModel
    @ObservedObject var clock: MatchClockDriver
    let board: WavelengthBoard

    var body: some View {
        let remaining = clock.remainingMs
        let seconds = remaining.map { Int((Double($0) / 1_000).rounded(.up)) }
        let urgent = (board.phase == .guess || board.phase == .fill) && (seconds.map { $0 <= 5 } ?? false)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(board.mode == .coop ? "Co-op" : "2v2") · \(phaseLabel)")
                    .monoLabel(11, weight: .semibold, tracking: 0.15, color: Theme.fg)
                Spacer()
                if let psychic = viewModel.current.flatMap({ viewModel.player($0.psychicId) }), board.phase != .fill {
                    Text("\(psychic.userId == viewModel.viewerId ? "Your" : "\(psychic.name)'s") clue")
                        .monoLabel(10, tracking: 0.1)
                        .lineLimit(1)
                }
            }
            HeaderStats(
                stats: [
                    HeaderStat(caption: "Round", value: "\(min(board.currentRound, board.roundCount)) / \(board.roundCount)"),
                    HeaderStat(caption: board.mode == .coop ? "Team score" : "Team 1 – Team 2", value: scoreText),
                    HeaderStat(caption: clockCaption, value: display(seconds), urgent: urgent),
                ],
                fraction: viewModel.clockFraction,
                tickSeconds: Double(MatchClockConstants.tickMs) / 1_000
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Round \(min(board.currentRound, board.roundCount)) of \(board.roundCount). \(phaseLabel). "
                + "Score \(scoreText). "
                + (seconds.map { "\(clockCaption). \($0) seconds left" } ?? clockCaption)
        )
    }

    private var scoreText: String {
        board.mode == .coop
            ? "\(board.teamScores.first ?? 0)"
            : "\(board.teamScores.first ?? 0) – \(board.teamScores.dropFirst().first ?? 0)"
    }

    private var phaseLabel: String {
        switch board.phase {
        case .fill: "Writing clues"
        case .guess: "Guessing"
        case .reveal: "Revealed"
        case .complete: "Finished"
        }
    }

    private var clockCaption: String {
        switch board.phase {
        case .fill: "Clues due"
        case .guess: viewModel.isGuesser ? "Your guess" : "Guess clock"
        case .reveal: "Next round"
        case .complete: "Done"
        }
    }

    private func display(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        return seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds)"
    }
}

// MARK: - Dial tab

private struct WavelengthDialTab: View {
    @ObservedObject var viewModel: WavelengthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if viewModel.isPaused {
                    ErrorBanner(message: "The host paused the game.")
                }
                board
                controls
                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
                if let round = settledRound, viewModel.board?.phase != .reveal {
                    WavelengthRevealBanner(round: round, scores: viewModel.board?.teamScores ?? [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var settledRound: WavelengthRound? {
        viewModel.revealRound.flatMap { number in viewModel.rounds.first { $0.round == number } }
    }

    @ViewBuilder
    private var board: some View {
        switch viewModel.board?.phase {
        case .fill:
            if viewModel.canFill {
                WavelengthBoardPanel(
                    card: viewModel.fillCard, target: viewModel.fillTarget,
                    caption: "Only you can see the target", concealed: true
                )
            } else {
                EmptyState(
                    title: "Cards are out",
                    message: "Everyone fills out their own cards in private."
                )
            }
        case .guess:
            WavelengthBoardPanel(
                card: viewModel.currentCard, clue: .some(viewModel.currentClue),
                target: viewModel.isPsychic ? viewModel.currentTarget : nil,
                needle: viewModel.needle, interactive: viewModel.canLock,
                onMove: { viewModel.moveNeedle(to: $0) }, concealed: true
            )
        case .reveal:
            if let round = viewModel.current {
                WavelengthBoardPanel(
                    card: viewModel.currentCard, clue: .some(viewModel.currentClue),
                    target: round.revealedTarget, needle: round.guessPosition,
                    result: .some(round)
                )
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.board?.phase {
        case .fill: fillControls
        case .guess: guessControls
        case .reveal: revealControls
        default: EmptyView()
        }
    }

    private var fillControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.canFill {
                Text("Your move").monoLabel(10, tracking: 0.13)
                Text("Write your clue\(viewModel.fillTotal > 1 ? " (\(viewModel.fillWritten + 1) of \(viewModel.fillTotal))" : "")")
                    .slabTitle(22)
                Text("One shot, aimed at the hidden target only you can see.")
                    .font(.sans(14)).foregroundStyle(Theme.fgMuted)
                TextField("Clue", text: $viewModel.clueDraft, axis: .vertical)
                    .lineLimit(2...4)
                    .textInputAutocapitalization(.sentences)
                    .fieldStyle()
                let words = WavelengthRules.wordCount(viewModel.clueDraft)
                let chars = viewModel.clueDraft.count
                let over = words > WavelengthRules.clueMaxWords || chars > WavelengthRules.clueMaxChars
                Text("\(words)/\(WavelengthRules.clueMaxWords) words · \(chars)/\(WavelengthRules.clueMaxChars) characters · no digits")
                    .monoLabel(10, tracking: 0.06, color: over ? Theme.hiddenText : Theme.fgMuted)
                Button {
                    Task { await viewModel.submitClue() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSaving { LoadingSpinner(size: 16) }
                        Text(viewModel.isSaving ? "Writing clue…" : "Lock in clue")
                    }
                }
                .buttonStyle(.solid)
                .disabled(viewModel.isSaving || viewModel.clueDraft.isEmpty || viewModel.clueProblem != nil)
            } else {
                Text("Your move").monoLabel(10, tracking: 0.13)
                Text(waitingText).font(.sans(15)).foregroundStyle(Theme.fgMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
    }

    private var waitingText: String {
        if viewModel.fillTotal > 0, viewModel.fillWritten == viewModel.fillTotal {
            return "Your clues are written. Waiting for the others."
        }
        return viewModel.mode == .coop ? "Your teammate is writing the clues." : "The others are writing their clues."
    }

    private var guessControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your move").monoLabel(10, tracking: 0.13)
            Text(viewModel.isGuesser ? "Place the needle" : "Watching").slabTitle(22)
            Text(guessCopy).font(.sans(14)).foregroundStyle(Theme.fgMuted)
            if viewModel.isGuesser {
                Button {
                    Task { await viewModel.lockGuess() }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isLocking { LoadingSpinner(size: 16) }
                        Text(viewModel.isLocking ? "Locking…" : "Confirm guess")
                    }
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canLock)
            }
            LineRule()
            HStack(spacing: 14) {
                legend("Bullseye", "4", WavelengthPalette.bullseye)
                legend("Near", "3", WavelengthPalette.near)
                legend("Edge", "2", WavelengthPalette.edge)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
    }

    private var guessCopy: String {
        if viewModel.isGuesser {
            return "Drag along the arc to where you think the clue points, then lock it in."
        }
        return viewModel.isPsychic
            ? "Your target is hidden from everyone else until the guess locks."
            : "Watch the guesser set the needle."
    }

    private func legend(_ name: String, _ points: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text("\(name) · \(points)").monoLabel(10, tracking: 0.06, color: Theme.fg)
        }
        .accessibilityElement(children: .combine)
    }

    private var revealControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Round locked").monoLabel(10, tracking: 0.13)
            Text(viewModel.current?.status == .skipped ? "Clue skipped" : "\(viewModel.current?.points ?? 0) points")
                .slabTitle(22)
            Text("The target is visible to everyone now. The next round starts automatically.")
                .font(.sans(14)).foregroundStyle(Theme.fgMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .well()
    }
}

// MARK: - Board panel

/// The spectrum on a card: its two ends, the dial, and whichever of a clue or a
/// score goes with the moment. Red along the top edge while something on it is
/// still concealed, cream-only once everything is revealed.
private struct WavelengthBoardPanel: View {
    var card: WavelengthCard?
    /// `nil` hides the clue block; `.some(nil)` shows "waiting for the clue".
    var clue: String?? = nil
    var target: Int?
    var needle: Int?
    var interactive = false
    var onMove: ((Int) -> Void)?
    var caption: String?
    var result: WavelengthRound??
    var concealed = false

    var body: some View {
        PanelCard {
            VStack(spacing: 12) {
                if let clue {
                    VStack(spacing: 2) {
                        Text("The clue").monoLabel(10, tracking: 0.13, color: Theme.panelMuted)
                        Text("“\(clue ?? "Waiting for the clue…")”")
                            .slabTitle(30, color: Theme.panelFg)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let caption {
                    Text(caption).monoLabel(10, tracking: 0.13, color: Theme.panelMuted)
                }
                if let card {
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.leftLabel)
                        Spacer(minLength: 12)
                        Text(card.rightLabel).multilineTextAlignment(.trailing)
                    }
                    .slabTitle(16, color: Theme.panelFg)
                    WavelengthDial(needle: needle, target: target, interactive: interactive, onMove: onMove)
                }
                if let result, let round = result {
                    Text(round.status == .skipped ? "Clue skipped" : "\(round.points ?? 0) points")
                        .slabTitle(24, color: Theme.panelFg)
                }
            }
            .padding(16)
        }
    }
}

/// A non-blocking flash for a round that just settled while the table has
/// already moved on, so the last guess is never missed.
private struct WavelengthRevealBanner: View {
    let round: WavelengthRound
    let scores: [Int]

    var body: some View {
        let skipped = round.status == .skipped
        PanelCard {
            HStack(spacing: 14) {
                if !skipped {
                    WavelengthDial(needle: round.guessPosition, target: round.revealedTarget)
                        .frame(width: 110)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(skipped ? WavelengthRules.reaction(points: nil, skipped: true)
                        : "\(WavelengthRules.reaction(points: round.points, skipped: false)) · \(round.points ?? 0) points")
                        .slabTitle(20, color: Theme.panelFg)
                    Text("Round \(round.round) · running score \(scores.map(String.init).joined(separator: " – "))")
                        .monoLabel(10, tracking: 0.06, color: Theme.panelMuted)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dial

enum WavelengthPalette {
    static let base = Color(hex: 0xD7D1C3)
    static let bullseye = Color(hex: 0xD94B45)
    static let near = Color(hex: 0xE49B55)
    static let edge = Color(hex: 0xE8CF75)

    static func wedge(_ points: Int) -> Color {
        switch points {
        case 4: bullseye
        case 3: near
        default: edge
        }
    }
}

/// The half-circle spectrum. The target's five scoring wedges are drawn only
/// when a `target` is given — the psychic's own card, or a revealed round.
/// When `interactive`, a touch anywhere moves the needle.
///
/// The geometry is the web's (`DIAL` in `board.ts`): the pivot sits at the
/// bottom centre, positions run 0 (left) to 1000 (right) along the arc.
struct WavelengthDial: View {
    var needle: Int?
    var target: Int?
    var interactive = false
    var label = "Guess needle"
    var onMove: ((Int) -> Void)?

    private static let aspect = 1000.0 / 530.0
    private static let radiusFraction = 0.47
    private static let tipInset = 0.03

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let pivot = CGPoint(x: size.width / 2, y: size.height)
            let radius = size.width * Self.radiusFraction

            Canvas { context, _ in
                context.fill(slice(0, 1000, pivot: pivot, radius: radius), with: .color(WavelengthPalette.base))
                if let target {
                    for wedge in WavelengthRules.scoringWedges(target: target) where wedge.to > wedge.from {
                        context.fill(
                            slice(wedge.from, wedge.to, pivot: pivot, radius: radius),
                            with: .color(WavelengthPalette.wedge(wedge.points))
                        )
                    }
                }
                if let needle {
                    var line = Path()
                    line.move(to: pivot)
                    line.addLine(to: point(needle, pivot: pivot, radius: radius - size.width * Self.tipInset))
                    context.stroke(
                        line, with: .color(Theme.panelFg),
                        style: StrokeStyle(lineWidth: max(3, size.width * 0.008), lineCap: .round)
                    )
                }
                let hub = max(5, size.width * 0.014)
                context.fill(
                    Path(ellipseIn: CGRect(x: pivot.x - hub, y: pivot.y - hub, width: hub * 2, height: hub * 2)),
                    with: .color(Theme.panelFg)
                )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard interactive, let onMove else { return }
                        onMove(WavelengthRules.position(dx: value.location.x - pivot.x, dy: value.location.y - pivot.y))
                    },
                including: interactive ? .all : .none
            )
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(needle.map { "Needle at \($0) of \(WavelengthRules.scaleMax)" } ?? "No needle")
        .accessibilityAdjustableAction { direction in
            guard interactive, let onMove, let needle else { return }
            let step = direction == .increment ? 25 : -25
            onMove(min(max(needle + step, 0), WavelengthRules.scaleMax))
        }
    }

    private func point(_ position: Int, pivot: CGPoint, radius: Double) -> CGPoint {
        let angle = WavelengthRules.angle(for: position)
        return CGPoint(x: pivot.x + radius * cos(angle), y: pivot.y - radius * sin(angle))
    }

    /// A pie slice from the pivot out to the arc, between two positions.
    private func slice(_ from: Int, _ to: Int, pivot: CGPoint, radius: Double) -> Path {
        var path = Path()
        path.move(to: pivot)
        let steps = max(2, (to - from) / 10)
        for step in 0...steps {
            let position = from + (to - from) * step / steps
            path.addLine(to: point(position, pivot: pivot, radius: radius))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Rounds tab

private struct WavelengthRoundsTab: View {
    @ObservedObject var viewModel: WavelengthViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(viewModel.teams, id: \.self) { team in
                    WavelengthTeamCard(viewModel: viewModel, team: team)
                }
                WavelengthRoundList(viewModel: viewModel)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }
}

private struct WavelengthTeamCard: View {
    @ObservedObject var viewModel: WavelengthViewModel
    let team: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(WavelengthRules.teamName(team, mode: viewModel.mode)).slabTitle(20)
                Spacer()
                Text("\(viewModel.score(of: team))")
                    .font(.mono(22, weight: .bold)).foregroundStyle(Theme.fg).monospacedDigit()
            }
            ForEach(viewModel.teamPlayers(team)) { player in
                let status = viewModel.status(of: player)
                HStack(spacing: 10) {
                    Avatar(name: player.name, url: player.avatarURL, size: 26, isMine: player.userId == viewModel.viewerId)
                    Text(player.userId == viewModel.viewerId ? "You" : player.name)
                        .font(.sans(14, weight: .semibold)).foregroundStyle(Theme.fg).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(status.text)
                        .monoLabel(10, tracking: 0.06, color: status.concealed ? Theme.hiddenText : Theme.fgMuted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
    }
}

/// Every round the match will play: settled ones with what they scored and the
/// clue that was given, the current one marked, the rest numbered.
private struct WavelengthRoundList: View {
    @ObservedObject var viewModel: WavelengthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "Rounds", trailing: "\(viewModel.rounds.filter(WavelengthRules.settled).count) of \(viewModel.board?.roundCount ?? viewModel.rounds.count)")
            ForEach(viewModel.rounds) { round in
                row(round)
            }
        }
    }

    private func row(_ round: WavelengthRound) -> some View {
        let settled = WavelengthRules.settled(round)
        let isCurrent = round.round == viewModel.board?.currentRound && !settled
        let psychic = viewModel.player(round.psychicId)?.name ?? "Unknown player"
        let guesser = viewModel.player(round.guesserId)?.name ?? ""
        let clue = viewModel.snapshot?.clues.first { $0.round == round.round }?.clue
        let card = viewModel.snapshot?.cards.first { $0.round == round.round }
        // A clue is public once its round is open; before then it is the
        // psychic's alone, and that is a hidden thing, so it reads red.
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("R\(round.round)").monoLabel(11, weight: .bold, tracking: 0.08, color: isCurrent ? Theme.fg : Theme.fgMuted)
                    .frame(width: 34, alignment: .leading)
                Text("\(psychic) → \(guesser)").font(.sans(14, weight: .semibold)).foregroundStyle(Theme.fg).lineLimit(1)
                Spacer(minLength: 8)
                trailing(round, settled: settled, isCurrent: isCurrent)
            }
            if let clue, settled || isCurrent {
                Text("“\(clue)”").slabTitle(18)
            }
            if let card, settled {
                Text("\(card.leftLabel)  ↔  \(card.rightLabel)").monoLabel(10, tracking: 0.04)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .opacity(settled || isCurrent ? 1 : 0.55)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func trailing(_ round: WavelengthRound, settled: Bool, isCurrent: Bool) -> some View {
        if round.status == .skipped {
            Text("Skipped").monoLabel(10, weight: .bold, tracking: 0.1)
        } else if settled {
            Text("\(round.points ?? 0) pts").font(.mono(15, weight: .bold)).foregroundStyle(Theme.fg).monospacedDigit()
        } else if isCurrent {
            Text("Now").monoLabel(10, weight: .bold, tracking: 0.1, color: Theme.hiddenText)
        } else {
            Text("Upcoming").monoLabel(10, tracking: 0.1)
        }
    }
}

// MARK: - Final

private struct WavelengthFinalView: View {
    @ObservedObject var viewModel: WavelengthViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final").eyebrow()
                    Text(headline)
                        .slabTitle(44)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                scoreCard

                ForEach(viewModel.teams, id: \.self) { team in
                    WavelengthTeamCard(viewModel: viewModel, team: team)
                }
                WavelengthRoundList(viewModel: viewModel)

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }
                postGameControls
            }
            .padding(16)
        }
    }

    private var headline: String {
        guard let result = viewModel.result else { return "Game over" }
        if result.mode == .coop { return result.won ? "You won!" : "Not this time" }
        if let team = viewModel.winningTeam { return "Team \(team + 1) wins" }
        return "Game over"
    }

    @ViewBuilder
    private var scoreCard: some View {
        if let result = viewModel.result {
            PanelCard {
                VStack(alignment: .leading, spacing: 8) {
                    if result.mode == .coop {
                        let maximum = (result.preset ?? .short).maxScore
                        Text("\(result.score) / \(maximum) points").slabTitle(30, color: Theme.panelFg)
                        Text("\(result.bullseyes) \(result.bullseyes == 1 ? "bullseye" : "bullseyes")")
                            .monoLabel(11, tracking: 0.08, color: Theme.panelMuted)
                        let stars = result.stars ?? 0
                        Text(String(repeating: "★", count: stars) + String(repeating: "☆", count: max(0, 3 - stars)))
                            .font(.sans(26, weight: .bold)).foregroundStyle(Theme.panelFg)
                            .accessibilityLabel("\(stars) of 3 stars")
                    } else {
                        let scores = viewModel.board?.teamScores ?? []
                        Text("Team 1: \(scores.first ?? 0)  ·  Team 2: \(scores.dropFirst().first ?? 0)")
                            .slabTitle(26, color: Theme.panelFg)
                        if let settled = viewModel.settledBy {
                            Text(settled).monoLabel(11, tracking: 0.08, color: Theme.panelMuted)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    /// The host advances the whole room; everybody else can keep reading the
    /// result until they do.
    @ViewBuilder
    private var postGameControls: some View {
        if viewModel.roomCode == nil {
            EmptyView()
        } else if viewModel.isHost {
            VStack(spacing: 8) {
                Button {
                    Task { await viewModel.choosePostGame(.replay) }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isSaving { LoadingSpinner(size: 16) }
                        Text("Play again")
                    }
                }
                .buttonStyle(.solid)
                .disabled(!viewModel.canChoosePostGame)

                Button("Back to the room") {
                    Task { await viewModel.choosePostGame(.lobby) }
                }
                .buttonStyle(.ghost)
                .disabled(!viewModel.canChoosePostGame)
            }
        } else {
            VStack(spacing: 8) {
                Text("Waiting for the host to choose what's next.")
                    .monoLabel(11, tracking: 0.13)
                Button("Back to the room") { dismiss() }
                    .buttonStyle(.ghost)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
