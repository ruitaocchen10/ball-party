import SwiftUI

/// Entry point for one live auction: owns the view model and shows the board
/// until it ends, then the final table.
///
/// It dismisses itself once a post-game choice exists. Where that leads is the
/// room's business, not the game's: the room is already following its own run,
/// so a replay appears there as a new match to carry everybody into, and "back
/// to the room" is simply this screen going away.
struct AuctionMatchScreen: View {
    @StateObject private var viewModel: AuctionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// `roomCode` and `isHost` come from the room that pushed this screen — a
    /// game may not read the lobby itself (`architecture.md`), the same reason
    /// the web's match page passes them in as props.
    init(matchId: UUID, viewerId: UUID, roomCode: String?, isHost: Bool) {
        _viewModel = StateObject(
            wrappedValue: AuctionViewModel(
                client: SupabaseAuctionClient(client: SupabaseConfig.client),
                matchId: matchId,
                viewerId: viewerId,
                roomCode: roomCode,
                isHost: isHost
            )
        )
    }

    /// For previews and tests: a screen over a view model the caller built.
    init(viewModel: AuctionViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if viewModel.snapshot == nil {
                LoadingState(label: "Dealing the board…")
            } else if viewModel.isFinished {
                AuctionFinalView(viewModel: viewModel)
            } else {
                AuctionPlayView(viewModel: viewModel)
            }
        }
        .screenBackground()
        .navigationTitle("Auction")
        .navigationBarTitleDisplayMode(.inline)
        // A live auction is not somewhere to tab away from by accident.
        .toolbar(.hidden, for: .tabBar)
        .task { await viewModel.load() }
        // Coming back from the background is when a screen is most likely to be
        // wrong: the countdown may barely have run, and several lots may have
        // sold.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.appReturnedToForeground() }
        }
        .onChange(of: viewModel.postGameAction) { _, action in
            if action != nil { dismiss() }
        }
        .onDisappear { viewModel.stopObserving() }
    }
}

// MARK: - Playing

private enum AuctionTab: Hashable {
    case auction, table, board
}

/// The live auction: a pinned header (budget, standing bid, clock) over three
/// native tabs. **Auction** is where you act and fits one screen; **Table** is
/// every roster; **Board** is the lot history. The view model lives above, so
/// a tab switch never touches the clock or a half-typed bid.
private struct AuctionPlayView: View {
    @ObservedObject var viewModel: AuctionViewModel
    @State private var tab: AuctionTab = .auction
    /// Sales already seen on the Table tab, so it can badge new ones.
    @State private var seenSales = 0

    private var sales: Int { viewModel.lots.filter { $0.wasPresented && $0.winnerId != nil }.count }

    var body: some View {
        if let turn = viewModel.turn, let phase = viewModel.phase {
            GameTabShell(
                tabs: [
                    GameTab(id: AuctionTab.auction, title: "Auction", systemImage: "hammer"),
                    GameTab(
                        id: AuctionTab.table, title: "Table", systemImage: "person.2",
                        badge: tab == .table ? 0 : max(0, sales - seenSales)),
                    GameTab(id: AuctionTab.board, title: "Board", systemImage: "list.bullet"),
                ],
                selection: $tab
            ) {
                AuctionHeader(viewModel: viewModel, clock: viewModel.clock, turn: turn, phase: phase)
            } content: { id in
                switch id {
                case .auction: AuctionTabView(viewModel: viewModel, phase: phase)
                case .table: TableTabView(viewModel: viewModel, phase: phase)
                case .board: BoardTabView(viewModel: viewModel, turn: turn, phase: phase)
                }
            }
            .onAppear { seenSales = sales }
            .onChange(of: sales) { _, now in if tab == .table { seenSales = now } }
            .onChange(of: tab) { _, now in if now == .table { seenSales = sales } }
        } else {
            LoadingState(label: "Waiting for the next lot…")
        }
    }
}

// MARK: - The pinned header

/// What a bidder must never lose sight of, on every tab: the lot, their own
/// budget, the standing bid, and the countdown. Bidding and sealed rounds run
/// on the visible-slack clock so a move sent as the bar empties still lands
/// inside the real deadline.
private struct AuctionHeader: View {
    @ObservedObject var viewModel: AuctionViewModel
    @ObservedObject var clock: MatchClockDriver
    let turn: AuctionTurn
    let phase: ViewerPhase

    private static let tenthsThresholdMs = 5_000

    var body: some View {
        let remaining = clock.remainingMs
        let live = phase == .biddingSelf || phase == .biddingOther || phase == .sealed
        let duration = (live ? AuctionTurn.Phase.bidding : .lotPreview).durationMs
        let fraction = remaining.map {
            min(1, Double($0) / Double(max(1, live ? duration - MatchClockConstants.visibleSlackMs : duration)))
        } ?? 0
        let urgent = live && (remaining.map { $0 <= 3_000 } ?? false)
        let seconds = remaining.map { Int((Double($0) / 1_000).rounded(.up)) }

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Lot \(min(turn.currentLot, lotCount)) of \(lotCount)")
                    .monoLabel(11, weight: .semibold, tracking: 0.15, color: Theme.fg)
                Spacer()
                Text(formatLabel).monoLabel(10, tracking: 0.1)
            }
            HeaderStats(
                stats: [
                    HeaderStat(caption: "Your budget", value: viewModel.me.map { "$\($0.budget)" } ?? "—"),
                    HeaderStat(caption: "Standing bid", value: phase == .lotPreview ? "—" : "$\(viewModel.price)"),
                    HeaderStat(
                        caption: clockCaption, value: display(remaining),
                        urgent: phase == .biddingSelf || urgent),
                ],
                fraction: fraction,
                tickSeconds: Double(MatchClockConstants.tickMs) / 1_000
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Lot \(min(turn.currentLot, lotCount)) of \(lotCount). "
                + "Budget \(viewModel.me.map { "$\($0.budget)" } ?? "none"). "
                + "Standing bid \(phase == .lotPreview ? "none" : "$\(viewModel.price)"). "
                + (seconds.map { "\(clockCaption). \($0) seconds left" } ?? clockCaption)
        )
    }

    /// The lots that can still be played, not the dealt total — the match ends
    /// the moment every roster is full, so spare lots may never come up.
    private var lotCount: Int { viewModel.visibleLotCount }

    private var formatLabel: String {
        guard let format = viewModel.format else { return "" }
        return "\(format.scoringLabel) · \(format.eraLabel)"
    }

    private var clockCaption: String {
        switch phase {
        case .lotPreview: "Bidding starts"
        case .sold: "Sold · next lot"
        case .sealed: "Sealed bids"
        case .biddingSelf: "Your turn"
        case .biddingOther: "\(viewModel.onClock?.name ?? "Someone")'s turn"
        }
    }

    private func display(_ remaining: Int?) -> String {
        guard let remaining else { return "—" }
        if remaining < Self.tenthsThresholdMs { return String(format: "%.1f", Double(remaining) / 1_000) }
        return "\(Int((Double(remaining) / 1_000).rounded(.up)))"
    }
}

// MARK: - Tab: Auction

private struct AuctionTabView: View {
    @ObservedObject var viewModel: AuctionViewModel
    let phase: ViewerPhase

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if viewModel.isPaused {
                    Label("The host paused the game.", systemImage: "pause.circle.fill")
                        .monoLabel(11, weight: .semibold, tracking: 0.13, color: Theme.fg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .well()
                }

                if let lot = viewModel.lot {
                    LotCard(viewModel: viewModel, lot: lot, phase: phase)
                    controls
                } else {
                    LoadingState(label: "Waiting for the next lot…")
                        .padding(.vertical, 40)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var controls: some View {
        if viewModel.me == nil {
            Text("You're watching this one.").monoLabel(11, tracking: 0.13)
        } else {
            VStack(spacing: 12) {
                if phase == .sealed {
                    SealedBidBar(viewModel: viewModel)
                } else {
                    BidBar(viewModel: viewModel, phase: phase)
                }
                if let format = viewModel.format, format.tokenCount > 0 {
                    TokenRow(viewModel: viewModel, total: format.tokenCount)
                }
                if let message = viewModel.scoutError {
                    Text(message).monoLabel(11, tracking: 0.08, color: Theme.hiddenText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - The lot reel

/// The suspense before a lot's player appears: a column of earlier players
/// scrolls up and lands on this lot's. Mirrors the web's `LotSpinner` (a
/// `SlotReel` with the same decoy rule and the same overshoot-then-settle
/// landing as `QbSpinReel`). Decoys come only from lots already presented, so
/// a future player is never spoiled; with fewer than seven, the rest of the
/// reel is neutral "?" rows. Remount with `.id(lot.seq)` to replay.
private struct LotReel: View {
    let lot: AuctionLot
    let duration: Double

    private static let rowHeight: CGFloat = 64
    private static let decoyCount = 7
    /// The same cubic-bezier as the web's `reel-spin` keyframes.
    private static let timing = (0.16, 0.86, 0.23, 1.0)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A snapshot taken at mount: `lots` changes on every realtime refresh,
    /// and re-deriving decoys from it would reshuffle the reel mid-spin.
    @State private var rows: [AuctionLot?]
    @State private var offset: CGFloat = 0

    init(lot: AuctionLot, lots: [AuctionLot], duration: Double) {
        self.lot = lot
        self.duration = duration
        let settled = lots
            .filter { $0.seq < lot.seq && $0.resolvedAt != nil }
            .shuffled()
            .prefix(Self.decoyCount)
        let decoys: [AuctionLot?] = (0..<Self.decoyCount).map { index in
            index < settled.count ? settled[settled.startIndex + index] : nil
        }
        _rows = State(initialValue: decoys + [lot])
    }

    var body: some View {
        if reduceMotion {
            HStack(spacing: 12) {
                LoadingSpinner(size: 28).tint(Theme.panelMuted).frame(width: 64)
                Text("Revealing…").monoLabel(11, weight: .bold, tracking: 0.15, color: Theme.hiddenInk)
                Spacer()
            }
            .frame(minHeight: Self.rowHeight)
            .padding(.horizontal, 16)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    reelRow(row).frame(height: Self.rowHeight, alignment: .leading)
                }
            }
            .offset(y: offset)
            .frame(height: Self.rowHeight, alignment: .top)
            .clipped()
            .padding(.horizontal, 16)
            .onAppear(perform: spin)
        }
    }

    @ViewBuilder
    private func reelRow(_ row: AuctionLot?) -> some View {
        HStack(spacing: 12) {
            if let row {
                Portrait(name: row.displayName, url: row.headshotURL, size: 64)
                Text(row.displayName)
                    .slabTitle(28, color: Theme.panelFg)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } else {
                Text("?").slabTitle(40, color: Theme.panelMuted).frame(width: 64)
                Text("Scanning…").monoLabel(11, weight: .bold, tracking: 0.15, color: Theme.panelMuted)
            }
            Spacer(minLength: 0)
        }
    }

    private func spin() {
        offset = 0
        let n = CGFloat(rows.count)
        let rest = -(n - 1) * Self.rowHeight
        // The keyframes' 70%-mark overshoot: 4% of the stacked height past rest.
        let overshoot = rest - 0.04 * n * Self.rowHeight
        let (x1, y1, x2, y2) = Self.timing
        withAnimation(.timingCurve(x1, y1, x2, y2, duration: duration * 0.7)) {
            offset = overshoot
        } completion: {
            withAnimation(.timingCurve(x1, y1, x2, y2, duration: duration * 0.3)) {
                offset = rest
            }
        }
    }
}

// MARK: - The lot

/// The lot, kept short so the bid controls stay on the same screen: position and
/// team on one line, then portrait beside the name, then the hidden points as a
/// slim band.
private struct LotCard: View {
    @ObservedObject var viewModel: AuctionViewModel
    let lot: AuctionLot
    let phase: ViewerPhase

    /// The seq whose identity has been shown. A brief suspense beat before each
    /// lot's player appears — the identity is already in `lots`, this only
    /// paces when it is shown. Keyed by seq rather than a flag so a new lot is
    /// concealed again from its first frame.
    @State private var revealedSeq: Int?

    private static let revealDuration: Double = 3
    private static let revealDelay: Duration = .seconds(revealDuration)

    var body: some View {
        let identityShown = revealedSeq == lot.seq
        PanelCard {
            VStack(spacing: 0) {
                HStack {
                    Text(lot.position).slabTitle(18, color: Theme.panelFg)
                    Spacer()
                    Text(lot.team).monoLabel(11, weight: .bold, tracking: 0.1, color: Theme.panelMuted)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)

                Reveal(revealed: identityShown) {
                    LotReel(lot: lot, lots: viewModel.lots, duration: Self.revealDuration)
                        .id(lot.seq)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Revealing this lot's player")
                } content: {
                    HStack(spacing: 12) {
                        Portrait(name: lot.displayName, url: lot.headshotURL, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(lot.displayName)
                                .slabTitle(28, color: Theme.panelFg)
                                .minimumScaleFactor(0.7)
                                .lineLimit(2)
                            Text(lot.identityLine)
                                .monoLabel(10, tracking: 0.1, color: Theme.panelMuted)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 64)
                    .padding(.horizontal, 16)
                    .accessibilityElement(children: .combine)
                }
                .padding(.vertical, 10)

                if phase == .sold {
                    SoldHeadline(viewModel: viewModel, lot: lot)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }

                pointsBand
            }
        }
        .task(id: lot.seq) {
            try? await Task.sleep(for: Self.revealDelay)
            guard !Task.isCancelled else { return }
            revealedSeq = lot.seq
        }
    }

    /// The score is the card's final band: concealed during the contest, then a
    /// bold result.
    private var pointsBand: some View {
        Reveal(revealed: phase == .sold) {
            Concealed(label: "Fantasy points, hidden until this lot is won") {
                HStack(spacing: 10) {
                    Text("Fantasy points").monoLabel(10, weight: .bold, tracking: 0.15, color: Theme.fg)
                    Text("? ? ?").slabTitle(30, color: Theme.fg)
                    // This player's own scouted tier only — the row behind it
                    // never reaches a client it doesn't belong to.
                    if let hint = viewModel.myHint {
                        Text("Scouted: \(hint.tier)")
                            .monoLabel(10, weight: .bold, tracking: 0.1, color: Theme.fg)
                            .accessibilityLabel("Scouted: a \(hint.tier) performance")
                    }
                }
                .padding(.vertical, 10)
            }
        } content: {
            HStack(spacing: 10) {
                Text("Fantasy points").monoLabel(10, weight: .bold, tracking: 0.15, color: Theme.panelMuted)
                Text(formatPoints(lot.points))
                    .slabTitle(34, color: tierColor(lot.revealTier))
                    .monospacedDigit()
                if let tier = lot.revealTier {
                    Text(tier.copy).monoLabel(10, weight: .bold, tracking: 0.1, color: Theme.panelMuted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.panelShade, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
            .accessibilityElement(children: .combine)
        }
    }
}

private struct SoldHeadline: View {
    @ObservedObject var viewModel: AuctionViewModel
    let lot: AuctionLot

    var body: some View {
        if let winnerId = lot.winnerId {
            let winner = viewModel.seats.first { $0.userId == winnerId }?.name ?? "Unknown buyer"
            VStack(alignment: .leading, spacing: 2) {
                Text("Sold to").monoLabel(10, weight: .bold, tracking: 0.12, color: Theme.panelMuted)
                HStack(alignment: .firstTextBaseline) {
                    Text(winner).slabTitle(22, color: Theme.panelFg).lineLimit(1)
                    Spacer()
                    Text("$\(lot.price ?? 0)").font(.mono(14, weight: .bold)).foregroundStyle(Theme.panelFg)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.panelLine, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(lot.displayName) sold to \(winner) for $\(lot.price ?? 0). It reveals \(formatPoints(lot.points)) fantasy points."
            )
        } else {
            Text("No sale").monoLabel(12, weight: .bold, tracking: 0.12, color: Theme.panelMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(lot.displayName) received no bids.")
        }
    }
}

// MARK: - Controls

/// The bid controls. A disabled control always says why: four different
/// situations produce the same greyed button otherwise, and "you already have a
/// quarterback" being indistinguishable from a broken app is the difference
/// between a rule and a bug.
private struct BidBar: View {
    @ObservedObject var viewModel: AuctionViewModel
    let phase: ViewerPhase

    @State private var customOpen = false
    @State private var customText = ""
    @FocusState private var customFocused: Bool

    /// The popover is keyed to the interaction rather than to a boolean, which
    /// is what closes it on a turn change, a new price or a sale: the key it was
    /// opened against simply stops being the current one.
    private var interactionKey: String {
        "\(phase):\(viewModel.onClock?.seat ?? -1):\(viewModel.price)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isClaimable {
                Button("Take for $0") { Task { await viewModel.raise(to: 0) } }
                    .buttonStyle(.solid)
                    .disabled(!viewModel.canAct)
            } else {
                HStack(spacing: 8) {
                    ForEach(AuctionRules.increments, id: \.self) { increment in
                        Button("+$\(increment)") {
                            Task { await viewModel.raise(to: viewModel.price + increment) }
                        }
                        .buttonStyle(.solid)
                        .disabled(!viewModel.canRaise(by: increment))
                    }
                    Button("Custom") {
                        customText = String(viewModel.minimumBid)
                        customOpen = true
                        customFocused = true
                    }
                    .buttonStyle(.solid)
                    .disabled(!viewModel.canAct)
                }
            }

            if customOpen { customBid }

            if let message = viewModel.errorMessage {
                Text(message).monoLabel(11, tracking: 0.05, color: Theme.hiddenText)
            } else {
                if viewModel.isWaitingOnOthers {
                    WaitingNote(text: viewModel.statusLine).monoLabel(11, tracking: 0.05)
                } else {
                    Text(viewModel.statusLine).monoLabel(11, tracking: 0.05)
                }
            }

            // Passing is permanent for this lot, so it gets a deliberate target
            // of its own below a rule. Stuck is the one case with no free pass
            // at all — declining there spends the Pass token in the tray.
            if !viewModel.isStuck {
                LineRule()
                Button(viewModel.isFreeFallback ? "Pass to opener" : "Pass") {
                    Task { await viewModel.pass() }
                }
                .buttonStyle(.ghost)
                .disabled(!viewModel.canAct)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
        .onChange(of: interactionKey) { _, _ in customOpen = false }
    }

    private var customBid: some View {
        let amount = Int(customText)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Custom bid").fieldLabel()
            TextField("Amount", text: $customText)
                .keyboardType(.numberPad)
                .font(.mono(18, weight: .bold))
                .fieldStyle()
                .focused($customFocused)
            Text("Minimum is $\(viewModel.minimumBid). Your maximum is $\(viewModel.me?.budget ?? 0).")
                .monoLabel(11, tracking: 0.05)
            HStack(spacing: 8) {
                Button("Bid $\(amount ?? 0)") {
                    guard let amount else { return }
                    customOpen = false
                    Task { await viewModel.raise(to: amount) }
                }
                .buttonStyle(.ink)
                .disabled(!viewModel.isValidCustomBid(amount) || viewModel.isBusy)
                Button("Cancel") { customOpen = false }
                    .buttonStyle(.quiet)
            }
        }
    }
}

/// The sealed phase's own control: unlike `BidBar`, there is no turn to wait
/// for — every live player sees this at once. One exact amount, first price.
/// After submitting there is nothing left to decide, just who the engine is
/// still waiting on, by name and never by amount.
private struct SealedBidBar: View {
    @ObservedObject var viewModel: AuctionViewModel
    @State private var text = "0"

    var body: some View {
        let budget = viewModel.me?.budget ?? 0
        let amount = Int(text)
        let valid = amount.map { $0 >= 0 && $0 <= budget } ?? false

        VStack(alignment: .leading, spacing: 12) {
            Text("Sealed bid").monoLabel(10, weight: .bold, tracking: 0.14)
            Text("Your budget · $\(budget) left").monoLabel(11, tracking: 0.08)

            if let mine = viewModel.mySealedBid {
                Text("You bid $\(mine.amount)").slabTitle(28).monospacedDigit()
                let waiting = viewModel.sealedWaitingOn
                WaitingNote(text: waiting.isEmpty ? "Everyone's in — resolving…" : "Waiting on \(waiting.joined(separator: ", ")).")
                    .monoLabel(11, tracking: 0.05)
            } else {
                Text("Amount").fieldLabel()
                HStack(spacing: 8) {
                    TextField("0", text: $text)
                        .keyboardType(.numberPad)
                        .font(.mono(18, weight: .bold))
                        .fieldStyle()
                    Button("Submit") {
                        guard let amount else { return }
                        Task { await viewModel.submitSealedBid(amount) }
                    }
                    .buttonStyle(BPButtonStyle(variant: .solid, fullWidth: false))
                    .disabled(!valid || viewModel.isBusy || viewModel.isPaused)
                }
                Text(viewModel.errorMessage ?? "Nobody sees this but you until the lot resolves.")
                    .monoLabel(11, tracking: 0.05, color: viewModel.errorMessage == nil ? Theme.fgMuted : Theme.hiddenText)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .well()
    }
}

/// The three single-use abilities as one row of buttons. A token never
/// disappears, it only changes state, so a player always knows all three exist;
/// what each one does is a tap away on the info sheet rather than printed inline.
private struct TokenRow: View {
    @ObservedObject var viewModel: AuctionViewModel
    let total: Int
    @State private var showInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tokens").monoLabel(10, weight: .bold, tracking: 0.14)
                Spacer()
                Text("\(viewModel.tokensLeft) of \(total) left").monoLabel(10, tracking: 0.08)
                Button {
                    showInfo = true
                } label: {
                    Image(systemName: "info.circle").foregroundStyle(Theme.fgMuted)
                        .frame(width: 32, height: 24)
                }
                .accessibilityLabel("What the tokens do")
            }
            HStack(spacing: 8) {
                token(label: "Pass", symbol: "nosign", state: viewModel.passState, pending: viewModel.isBusy) {
                    await viewModel.spendPassToken()
                }
                token(label: "Scout", symbol: "magnifyingglass", state: viewModel.scoutState, pending: viewModel.isScouting) {
                    await viewModel.scout()
                }
                token(label: "Seal", symbol: "lock", state: viewModel.sealState, pending: viewModel.isBusy) {
                    await viewModel.seal()
                }
            }
        }
        .sheet(isPresented: $showInfo) { TokenInfoSheet() }
    }

    private func token(
        label: String, symbol: String, state: TokenState, pending: Bool, use: @escaping () async -> Void
    ) -> some View {
        let usable = state == .usable
        return Button {
            Task { await use() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: state == .used ? "checkmark" : symbol).font(.system(size: 15, weight: .semibold))
                Text(label).slabTitle(16, color: usable ? Theme.panelFg : Theme.fgMuted)
                Text(stateText(state))
                    .monoLabel(8, weight: .bold, tracking: 0.08, color: usable ? Theme.panelMuted : Theme.fgMuted)
            }
            .foregroundStyle(usable ? Theme.panelFg : Theme.fgMuted)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(usable ? Theme.hidden : Theme.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.line, lineWidth: usable ? 0 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!usable || pending)
        .accessibilityLabel("\(label) token")
        .accessibilityHint("\(stateText(state)). \(Self.description(of: label))")
    }

    static func description(of label: String) -> String {
        switch label {
        case "Pass": "Decline a lot you'd otherwise be stuck with, for free. Usable only when you're the only bidder left on it."
        case "Scout": "Peek a rough performance tier for the current lot before it sells. Only you see it."
        default: "Force this lot into a simultaneous blind bid instead of back-and-forth raising."
        }
    }

    private func stateText(_ state: TokenState) -> String {
        switch state {
        case .usable: "Ready"
        case .used: "Used"
        case .inactive: "Not now"
        }
    }
}

private struct TokenInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Tokens").slabTitle(28)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.quiet)
            }
            ForEach(["Pass", "Scout", "Seal"], id: \.self) { name in
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).slabTitle(20)
                    Text(TokenRow.description(of: name)).font(.sans(15)).foregroundStyle(Theme.fg)
                }
                LineRule()
            }
            Text("Each token can be used once per player.").monoLabel(10, tracking: 0.08)
            Spacer(minLength: 0)
        }
        .padding(20)
        .screenBackground()
        .presentationDetents([.medium])
    }
}

// MARK: - Tab: Table

/// Everyone's budget and running total, with every roster open, which is what
/// lets a player tell whether they are chasing or protecting and read what the
/// others still need.
private struct TableTabView: View {
    @ObservedObject var viewModel: AuctionViewModel
    let phase: ViewerPhase

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(viewModel.seats) { seat in
                    PlayerRow(
                        viewModel: viewModel,
                        seat: seat,
                        justSold: phase == .sold && viewModel.lot?.winnerId == seat.userId ? viewModel.lot : nil
                    )
                    .well()
                }
            }
            .padding(16)
        }
    }
}

private struct PlayerRow: View {
    @ObservedObject var viewModel: AuctionViewModel
    let seat: AuctionSeat
    /// The lot this player just won, when the board is showing its sale.
    let justSold: AuctionLot?

    @State private var expanded: Bool

    init(viewModel: AuctionViewModel, seat: AuctionSeat, justSold: AuctionLot?) {
        self.viewModel = viewModel
        self.seat = seat
        self.justSold = justSold
        _expanded = State(initialValue: true)
    }

    private var isMine: Bool { seat.userId == viewModel.viewerId }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Avatar(name: seat.name, url: seat.avatarURL, size: 28, isMine: isMine)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(isMine ? "You" : seat.name).slabTitle(18).lineLimit(1)
                            if isMine {
                                Text("YOU").monoLabel(9, weight: .bold, tracking: 0.08, color: Theme.hiddenText)
                            }
                        }
                        let highlighted = viewModel.holder == seat.userId || seat.seat == viewModel.turn?.turnSeat
                        Text(viewModel.status(of: seat))
                            .monoLabel(10, tracking: 0.07, color: highlighted ? Theme.hiddenText : Theme.fgMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatPoints(viewModel.points(of: seat)))
                            .font(.mono(16, weight: .bold))
                            .foregroundStyle(Theme.fg)
                            .monospacedDigit()
                        HStack(spacing: 6) {
                            Text("$\(seat.budget)").monoLabel(10, tracking: 0.05)
                            if let format = viewModel.format, format.tokenCount > 0 {
                                Text("🎫\(AuctionRules.tokensRemaining(format: format, seat: seat))")
                                    .monoLabel(10, tracking: 0.05)
                            }
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.fgMuted)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(expanded ? "Hides their roster" : "Shows their roster")

            if expanded {
                RosterView(lots: viewModel.lots, userId: seat.userId, format: viewModel.format, highlight: justSold)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .background(justSold != nil ? Theme.fg.opacity(0.1) : .clear)
    }
}

/// Filled slots are a legible roster row; empty slots stay a dashed gap.
private struct RosterView: View {
    let lots: [AuctionLot]
    let userId: UUID
    let format: AuctionFormat?
    var highlight: AuctionLot?

    var body: some View {
        VStack(spacing: 6) {
            ForEach(AuctionRules.rosterSlots(format)) { slot in
                let won = lots.filter { $0.winnerId == userId && $0.slot == slot.slot.rawValue }
                let lot = won.indices.contains(slot.index - 1) ? won[slot.index - 1] : nil
                HStack(spacing: 8) {
                    Text(slot.label).monoLabel(10, weight: .bold, tracking: 0.08, color: Theme.panelMuted)
                        .frame(width: 44, alignment: .leading)
                    if let lot {
                        Portrait(name: lot.displayName, url: lot.headshotURL, size: 22)
                        Text(lot.displayName).font(.sans(14, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(formatPoints(lot.points)).font(.mono(12, weight: .bold)).monospacedDigit()
                    } else {
                        Text("— empty —").monoLabel(10, tracking: 0.05, color: Theme.panelMuted)
                        Spacer()
                    }
                }
                .foregroundStyle(Theme.panelFg)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.chipRadius))
                .overlay {
                    if lot == nil {
                        RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.panelLine, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    } else if lot?.seq == highlight?.seq {
                        RoundedRectangle(cornerRadius: Theme.chipRadius).strokeBorder(Theme.hidden, lineWidth: 2)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    lot.map { "\(slot.label) slot, \($0.displayName), \(formatPoints($0.points)) points" }
                        ?? "\(slot.label) slot, empty"
                )
            }
        }
    }
}

// MARK: - Tab: Board

/// The auction's memory as a list: every settled lot naming who got what at
/// what price, then the one on the block and what is still to come. The length
/// comes from the turn, not the dealt rows, so undealt frames never need an
/// identity.
private struct BoardTabView: View {
    @ObservedObject var viewModel: AuctionViewModel
    let turn: AuctionTurn
    let phase: ViewerPhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Settled lots").monoLabel(10, weight: .bold, tracking: 0.14)
                VStack(spacing: 0) {
                    if past.isEmpty {
                        Text("Nothing has sold yet.").monoLabel(11, tracking: 0.08).padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(Array(past.enumerated()), id: \.element) { index, seq in
                        if index > 0 { LineRule() }
                        row(seq)
                    }
                }
                .well()

                Text("Coming up").monoLabel(10, weight: .bold, tracking: 0.14).padding(.top, 4)
                VStack(spacing: 0) {
                    current
                    ForEach(upcoming, id: \.self) { seq in
                        LineRule()
                        HStack(spacing: 10) {
                            Text("\(seq)").monoLabel(10, weight: .bold, tracking: 0.06).frame(width: 36, alignment: .leading)
                            Text("Not yet dealt").monoLabel(10, tracking: 0.08)
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Lot \(seq), not yet dealt")
                    }
                }
                .well()
            }
            .padding(16)
        }
    }

    private var lotCount: Int { viewModel.visibleLotCount }
    private var past: [Int] { Array(1..<max(1, min(turn.currentLot, lotCount + 1))) }
    private var upcoming: [Int] { turn.currentLot < lotCount ? Array((turn.currentLot + 1)...lotCount) : [] }

    private var current: some View {
        HStack(spacing: 10) {
            Text("Now").monoLabel(10, weight: .bold, tracking: 0.06, color: Theme.hiddenText).frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("Lot \(min(turn.currentLot, lotCount))").slabTitle(17)
                Text(currentCaption).monoLabel(10, tracking: 0.08, color: Theme.hiddenText)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var currentCaption: String {
        switch phase {
        case .lotPreview: "Coming up"
        case .sold: "Sold"
        case .sealed: "Sealed bidding"
        case .biddingSelf, .biddingOther: "On the clock"
        }
    }

    @ViewBuilder
    private func row(_ seq: Int) -> some View {
        if let lot = viewModel.lots.first(where: { $0.seq == seq }), lot.wasPresented {
            let winner = viewModel.seats.first { $0.userId == lot.winnerId }?.name
            HStack(spacing: 10) {
                Text(lot.slot ?? "—").monoLabel(10, weight: .bold, tracking: 0.06, color: Theme.fg)
                    .frame(width: 36, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lot.displayName).slabTitle(17).lineLimit(1)
                    Text("\(winner ?? "No bids") · \(lot.season) · \(lot.team)")
                        .monoLabel(10, tracking: 0.05).lineLimit(1)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatPoints(lot.points)).font(.mono(15, weight: .bold)).foregroundStyle(Theme.fg).monospacedDigit()
                    Text(lot.price.map { "$\($0)" } ?? "—").monoLabel(10, tracking: 0.05)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Lot \(lot.seq), \(lot.displayName), \(lot.slot ?? "unfilled"), "
                    + "\(lot.price.map { "$\($0)" } ?? "no price"), "
                    + (winner.map { "won by \($0)" } ?? "no winner")
            )
        } else {
            // A lot the dealer skipped was never shown to anyone, so the history
            // says it was skipped rather than naming a player nobody saw.
            HStack(spacing: 10) {
                Text("—").monoLabel(10, tracking: 0.06).frame(width: 36, alignment: .leading)
                Text("Skipped").monoLabel(10, tracking: 0.08)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .opacity(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Lot \(seq), skipped")
        }
    }
}

// MARK: - The ending

private struct AuctionFinalView: View {
    @ObservedObject var viewModel: AuctionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Final").eyebrow()
                    Text(viewModel.headline)
                        .slabTitle(44)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                ForEach(viewModel.finalStandings) { row in
                    // The winner is the thing that matters, so the winner is a panel.
                    if row.rank == 1 {
                        PanelCard {
                            finalRow(row, onPanel: true).padding(14)
                        }
                    } else {
                        finalRow(row, onPanel: false)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .well()
                    }
                }

                if let message = viewModel.errorMessage {
                    ErrorBanner(message: message)
                }

                postGameControls
            }
            .padding(16)
        }
    }

    private func finalRow(_ row: AuctionViewModel.FinalStanding, onPanel: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("#\(row.rank)")
                    .font(.mono(16, weight: .bold))
                    .foregroundStyle(row.rank == 1 ? (onPanel ? Theme.hiddenInk : Theme.hiddenText) : Theme.fgMuted)
                    .frame(width: 40, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .slabTitle(24, color: onPanel ? Theme.panelFg : Theme.fg)
                            .lineLimit(1)
                        if row.isViewer {
                            Text("You")
                                .monoLabel(9, weight: .bold, tracking: 0.08, color: onPanel ? Theme.hiddenInk : Theme.hiddenText)
                        }
                    }
                    Text("\(formatPoints(row.points)) pts")
                        .monoLabel(11, tracking: 0.08, color: onPanel ? Theme.panelMuted : Theme.fgMuted)
                }
                Spacer()
            }
            FinalRoster(lots: viewModel.lots, userId: row.userId, format: viewModel.format, onPanel: onPanel)
        }
        .accessibilityElement(children: .contain)
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
                        if viewModel.isBusy { LoadingSpinner(size: 16) }
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
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 8) {
                WaitingNote(text: "Waiting for the host to choose what's next.")
                    .monoLabel(11, tracking: 0.13)
                Button("Back to the room") { dismiss() }
                    .buttonStyle(.ghost)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// The post-game roster: every slot, with the price paid and the points it
/// returned. Points are tinted by how the performance graded for its position.
private struct FinalRoster: View {
    let lots: [AuctionLot]
    let userId: UUID
    let format: AuctionFormat?
    let onPanel: Bool

    var body: some View {
        let muted = onPanel ? Theme.panelMuted : Theme.fgMuted
        let primary = onPanel ? Theme.panelFg : Theme.fg
        let won = lots.filter { $0.winnerId == userId }

        VStack(spacing: 8) {
            ForEach(AuctionRules.rosterSlots(format)) { slot in
                let inSlot = won.filter { $0.slot == slot.slot.rawValue }
                let lot = inSlot.indices.contains(slot.index - 1) ? inSlot[slot.index - 1] : nil
                HStack(spacing: 10) {
                    Text(slot.label).monoLabel(10, weight: .bold, tracking: 0.08, color: muted)
                        .frame(width: 44, alignment: .leading)
                    if let lot {
                        Portrait(name: lot.displayName, url: lot.headshotURL, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(lot.displayName).font(.sans(14, weight: .semibold)).foregroundStyle(primary).lineLimit(1)
                            Text("\(lot.season) · \(lot.team)\(lot.opponent.map { " vs \($0)" } ?? "")")
                                .monoLabel(10, tracking: 0.04, color: muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(formatPoints(lot.points))
                                .font(.mono(16, weight: .bold))
                                .foregroundStyle(onPanel ? tierColor(lot.revealTier) : primary)
                                .monospacedDigit()
                            Text("$\(lot.price ?? 0)").monoLabel(10, tracking: 0.04, color: muted)
                        }
                    } else {
                        Text("—").monoLabel(11, tracking: 0.05, color: muted)
                        Spacer()
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    lot.map { "\(slot.label), \($0.displayName), \(formatPoints($0.points)) points, $\($0.price ?? 0)" }
                        ?? "\(slot.label), empty"
                )
            }
        }
    }
}

// MARK: - Formatting

/// Points arrive as numeric strings; one decimal is how the game reads them.
func formatPoints(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.1f", value)
}

/// A revealed result's tint on a cream panel: rough/solid/great by position.
private func tierColor(_ tier: AuctionLot.RevealTier?) -> Color {
    switch tier {
    case .rough: Theme.gradeRough
    case .solid: Theme.gradeStrong
    case .great: Theme.gradeElite
    case nil: Theme.panelFg
    }
}
