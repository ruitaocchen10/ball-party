import Foundation

/// One live auction, from the first lot to the final table.
///
/// The server is authoritative for every rule — eligibility, whose turn it is,
/// when a lot sells, who won. This decides which RPC to call and what to show,
/// and computes the *reasons* a control is off (`AuctionRules`) so a greyed
/// button can say why.
///
/// The same three things that keep `MatchViewModel` honest apply here:
///
/// - **Payloads are applied directly.** A round trip per bid inside a 20-second
///   turn is not a game, so rows arriving over the channel are merged into what
///   is on screen. Nothing is optimistic, though: a bid is not shown until the
///   server confirms it, because the number on screen is what everybody is
///   reasoning about.
/// - **Realtime is the fast path, not the only path.** A full re-read fires
///   whenever a channel (re)subscribes, when the app returns to the foreground,
///   when a deadline stays past too long, and when the match ends.
/// - **Expiry is asked for repeatedly, and never only by the player on the
///   clock** — closing the app is exactly the case the timer exists for. The
///   player on the clock skips it; everyone else asks, jittered, while they get
///   first crack at acting.
@MainActor
final class AuctionViewModel: ObservableObject {
    /// A row of the final table.
    struct FinalStanding: Equatable, Identifiable {
        let userId: UUID
        /// 1-based; shared by a genuine tie.
        let rank: Int
        let name: String
        let avatarURL: URL?
        let points: Double
        let isViewer: Bool

        var id: UUID { userId }
    }

    @Published private(set) var snapshot: AuctionSnapshot?
    /// A bid, pass, seal or sealed bid is in flight.
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?
    /// Scouting is not a bidding action — it has no turn to wait for — so it
    /// gets its own pending/error pair rather than disabling raise and pass
    /// while a scout call is in flight.
    @Published private(set) var isScouting = false
    @Published private(set) var scoutError: String?

    let matchId: UUID
    let viewerId: UUID
    /// The room this match was started from, and whether this player hosts it.
    /// Handed in by the room that pushed this screen rather than read from the
    /// match: which lobby a run belongs to is the lobby's fact, and a game may
    /// never reach for it (`architecture.md`).
    let roomCode: String?
    let isHost: Bool
    private let client: AuctionClient
    private let now: () -> Date

    /// Drives the countdown and the expiry/reconcile asks.
    private(set) lazy var clock = MatchClockDriver(
        now: now,
        expire: { [weak self] in await self?.expire() },
        reconcile: { [weak self] in await self?.reconcile() }
    )

    private var observation: Task<Void, Never>?
    private var readsIssued = 0
    private var latestApplied = 0
    /// The re-read the end of the match owes the final screen, asked for once.
    private var finalReadRequested = false

    init(
        client: AuctionClient,
        matchId: UUID,
        viewerId: UUID,
        roomCode: String? = nil,
        isHost: Bool = false,
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.matchId = matchId
        self.viewerId = viewerId
        self.roomCode = roomCode
        self.isHost = isHost
        self.now = now
    }

    deinit {
        observation?.cancel()
    }

    // MARK: - Derived state

    var turn: AuctionTurn? { snapshot?.turn }
    var lots: [AuctionLot] { snapshot?.lots ?? [] }
    var seats: [AuctionSeat] { snapshot?.seats ?? [] }
    var bids: [AuctionBid] { snapshot?.bids ?? [] }
    var format: AuctionFormat? { snapshot?.format }

    /// Cells to draw in the lot strip — not `turn.lotCount`, which includes spare
    /// lots the match may never reach. See `AuctionRules.playableLotCount`.
    var visibleLotCount: Int {
        guard let turn else { return 0 }
        return AuctionRules.playableLotCount(turn: turn, lots: lots, seats: seats, format: format)
    }

    var me: AuctionSeat? { seats.first { $0.userId == viewerId } }

    /// A match is over the moment every roster is full, not only when the deck
    /// runs out — either signal alone is right at the moment its source
    /// updates, and the two can disagree for a tick.
    var isFinished: Bool {
        guard let snapshot else { return false }
        return snapshot.turn.currentLot > snapshot.turn.lotCount || snapshot.matchStatus == .complete
    }

    var isPaused: Bool { snapshot?.matchStatus == .paused }

    var lot: AuctionLot? { turn.flatMap { AuctionRules.lot(lots, at: $0.currentLot) } }
    var phase: ViewerPhase? { turn.map { AuctionRules.viewerPhase($0, viewerSeat: me?.seat) } }
    var price: Int { lot.map { AuctionRules.standingPrice(bids, seq: $0.seq) } ?? 0 }
    var holder: UUID? { lot.flatMap { AuctionRules.highBidder(bids, seq: $0.seq) } }
    var onClock: AuctionSeat? { seats.first { $0.seat == turn?.turnSeat } }

    var passed: Bool {
        guard let lot, let me else { return false }
        return AuctionRules.hasPassed(bids, seq: lot.seq, userId: me.userId)
    }

    func hasPassed(_ seat: AuctionSeat) -> Bool {
        guard let lot else { return false }
        return AuctionRules.hasPassed(bids, seq: lot.seq, userId: seat.userId)
    }

    var filled: [Slot: Int] {
        me.map { AuctionRules.filledSlots(lots, userId: $0.userId) } ?? [:]
    }

    /// Where a win would land: the natural slot if open, otherwise FLEX.
    var targetSlot: Slot? {
        lot.map { AuctionRules.targetSlot(for: $0, filled: filled, format: format) }
    }

    var blocked: Blocked? {
        guard let turn, let lot, let me else { return .notYourTurn }
        return AuctionRules.blockedReason(
            lot: lot, me: me, lots: lots, seats: seats, turnSeat: turn.turnSeat,
            format: format, passed: passed, price: price
        )
    }

    /// Nobody else is live on this lot — the board would hand it over for $0
    /// the moment the viewer acts. Declining it is what the Pass token is for.
    var isStuck: Bool {
        guard let me, let turn else { return false }
        return turn.stuckSeat == me.seat && price == 0
    }

    /// The broke opener may take the lot free or pass it back.
    var isFreeFallback: Bool {
        guard let turn else { return false }
        return turn.freeFallbackSeat != nil && price == 0
    }

    /// Taking the lot for $0 is on offer instead of raising.
    var isClaimable: Bool { isFreeFallback || isStuck }

    var tokensLeft: Int { AuctionRules.tokensRemaining(format: format, seat: me) }

    var myHint: ScoutHint? {
        guard let lot else { return nil }
        return snapshot?.scoutHints.first { $0.seq == lot.seq && $0.userId == viewerId }
    }

    var mySealedBid: SealedBid? {
        guard let lot else { return nil }
        return snapshot?.sealedBids.first { $0.seq == lot.seq && $0.userId == viewerId }
    }

    private var noBidsYet: Bool {
        guard let lot else { return true }
        return !bids.contains { $0.seq == lot.seq }
    }

    /// Whether the viewer may act on the bid bar right now.
    var canAct: Bool {
        phase == .biddingSelf && blocked == nil && !isBusy && !isPaused
    }

    func canRaise(by increment: Int) -> Bool {
        canAct && !isClaimable && AuctionRules.canAfford(price: price, budget: me?.budget ?? 0, increment: increment)
    }

    /// The smallest bid the custom field accepts.
    var minimumBid: Int { isClaimable ? 0 : price + 1 }

    func isValidCustomBid(_ amount: Int?) -> Bool {
        guard let amount, let me else { return false }
        return amount >= minimumBid && amount <= me.budget
    }

    var passTokenAvailable: Bool {
        guard let me else { return false }
        return !me.usedPassToken && tokensLeft > 0
    }

    var passState: TokenState {
        if me?.usedPassToken == true { return .used }
        return isStuck && passTokenAvailable ? .usable : .inactive
    }

    var scoutState: TokenState {
        // A seat-row update can lag a beat behind the action that caused it, so
        // the hint this screen already holds counts as proof of use.
        if me?.usedScoutToken == true || myHint != nil { return .used }
        guard let me, phase != .sold, phase != nil, !me.usedScoutToken, tokensLeft > 0 else { return .inactive }
        return .usable
    }

    /// Sealing only makes sense pre-bid and with a real contest on the other
    /// side — the server re-checks both; this keeps the button from inviting a
    /// refusal it could have predicted.
    var sealState: TokenState {
        if me?.usedSealToken == true { return .used }
        guard let me, let lot, phase == .biddingSelf || phase == .biddingOther,
              noBidsYet, tokensLeft > 0, !me.usedSealToken
        else { return .inactive }
        let contenders = seats.filter {
            AuctionRules.isEligible(lot, lots: lots, seats: seats, userId: $0.userId, format: format)
        }
        return contenders.count >= 2 ? .usable : .inactive
    }

    /// Names of live players who have not locked in their sealed bid yet.
    var sealedWaitingOn: [String] {
        guard let lot, let me else { return [] }
        return seats
            .filter { $0.userId != me.userId }
            .filter { AuctionRules.isEligible(lot, lots: lots, seats: seats, userId: $0.userId, format: format) }
            .filter { !hasSubmittedSealedBid($0) }
            .map(\.name)
    }

    func hasSubmittedSealedBid(_ seat: AuctionSeat) -> Bool {
        guard let lot else { return false }
        return snapshot?.sealedStatuses.contains { $0.seq == lot.seq && $0.userId == seat.userId && $0.submitted } ?? false
    }

    func points(of seat: AuctionSeat) -> Double {
        AuctionRules.revealedTotal(lots, userId: seat.userId)
    }

    /// What one seat is doing right now, for the rail's second line.
    func status(of seat: AuctionSeat) -> String {
        guard let turn else { return "" }
        if turn.phase == .sealed {
            return hasSubmittedSealedBid(seat) ? "Submitted" : "Deciding"
        }
        if holder == seat.userId { return "High bid · $\(price)" }
        if seat.seat == turn.turnSeat { return "On the clock" }
        if hasPassed(seat) { return "Passed" }
        let wonCount = lots.filter { $0.winnerId == seat.userId && $0.slot != nil }.count
        return "\(wonCount)/\(AuctionRules.rosterSlots(format).count) filled"
    }

    /// The line under the bid bar: why it is off, or what a win would do.
    var statusLine: String {
        guard let turn, let lot else { return "" }
        if isPaused { return "The host paused the game." }
        switch turn.phase {
        case .lotPreview: return "This player enters the auction."
        case .sold: return "The next player is coming up."
        case .sealed: return ""
        case .bidding: break
        }
        if let blocked { return blocked.text(position: lot.position) }
        if isStuck {
            return passTokenAvailable
                ? "Nobody else can bid on this one. Take it free, or spend your Pass token below to let it go unsold."
                : "Nobody else can bid on this one, and you're out of pass tokens — it's yours for $0."
        }
        if isFreeFallback { return "Take this lot free, or pass it back to the original opener." }
        if let budget = me?.budget, !AuctionRules.canAfford(price: price, budget: budget, increment: AuctionRules.increments[1]) {
            return "You can only raise by $\(AuctionRules.increments[0])."
        }
        return "A win fills your open \(targetSlot?.rawValue ?? "slot")."
    }

    // MARK: The ending

    /// The final table, ranked as the platform recorded it.
    var finalStandings: [FinalStanding] {
        guard let snapshot, isFinished else { return [] }
        let ranked = byPlacement(snapshot.standings)
        return ranked.enumerated().map { index, standing in
            let seat = snapshot.seats.first { $0.userId == standing.userId }
            return FinalStanding(
                userId: standing.userId,
                rank: standing.placement ?? index + 1,
                name: seat?.name ?? "Unknown player",
                avatarURL: seat?.avatarURL,
                points: standing.rawScore ?? 0,
                isViewer: standing.userId == viewerId
            )
        }
    }

    /// Names a winner, so the game ends rather than merely stopping.
    var headline: String {
        let winners = finalStandings.filter { $0.rank == 1 }
        switch winners.count {
        case 0: return "Game over"
        case 1: return "\(winners[0].name) wins"
        default: return "\(winners.map(\.name).joined(separator: " & ")) tie"
        }
    }

    /// The choice made for this finished match, by whoever made it. Non-nil is
    /// the screen's cue to leave: the room carries everybody to the replay, or
    /// back to the lobby.
    var postGameAction: PostGameAction? { snapshot?.postGame }

    /// Only the host advances a room, and only once.
    var canChoosePostGame: Bool {
        isFinished && isHost && postGameAction == nil && !isBusy
    }

    // MARK: - Intents

    /// Read the match and start following it. Subscribing first means the
    /// `SUBSCRIBED` re-read covers anything that changed while this was in flight.
    func load() async {
        observe()
        await reconcile()
        clock.start()
    }

    /// Raise to `amount`. `0` takes a claimable lot for free.
    func raise(to amount: Int) async {
        guard canAct else { return }
        await act { try await self.client.placeBid(matchId: self.matchId, amount: amount) }
    }

    func pass() async {
        guard canAct else { return }
        await act { try await self.client.pass(matchId: self.matchId) }
    }

    /// Spend the Pass token on a stuck lot. It is the same RPC as an ordinary
    /// pass; it is reached from a different control once the token moves there.
    func spendPassToken() async {
        guard passState == .usable, !isBusy, !isPaused else { return }
        await act { try await self.client.pass(matchId: self.matchId) }
    }

    func scout() async {
        guard scoutState == .usable, !isScouting, !isPaused, let lot else { return }
        isScouting = true
        scoutError = nil
        defer { isScouting = false }
        do {
            let tier = try await client.useScoutToken(matchId: matchId)
            // The realtime INSERT would deliver the same row, but the RPC
            // already hands back the tier it wrote — no reason to make the
            // viewer wait a round trip to see their own answer.
            let hint = ScoutHint(seq: lot.seq, userId: viewerId, tier: tier)
            if snapshot?.scoutHints.contains(where: { $0.seq == hint.seq && $0.userId == hint.userId }) == false {
                snapshot?.scoutHints.append(hint)
            }
        } catch {
            scoutError = AuctionServerError.describe(error)
        }
    }

    func seal() async {
        guard sealState == .usable, !isBusy, !isPaused else { return }
        await act { try await self.client.useSealToken(matchId: self.matchId) }
    }

    func submitSealedBid(_ amount: Int) async {
        guard phase == .sealed, mySealedBid == nil, !isBusy, !isPaused,
              let budget = me?.budget, amount >= 0, amount <= budget
        else { return }
        await act { try await self.client.submitSealedBid(matchId: self.matchId, amount: amount) }
    }

    /// Replay in the same format, or send the room back to its lobby.
    func choosePostGame(_ choice: PostGameAction.Choice) async {
        guard canChoosePostGame else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            snapshot?.postGame = try await client.choosePostGame(matchId: matchId, choice: choice)
        } catch {
            errorMessage = AuctionServerError.describe(error)
        }
    }

    /// The app returned to the foreground. Hands off to the clock, which
    /// reconciles unconditionally — a suspended app's countdown may barely have
    /// run, and the board may have moved several lots without it.
    func appReturnedToForeground() {
        clock.appReturnedToForeground()
    }

    /// Re-read the whole match and apply it. This is the clock's `reconcile`.
    func reconcile() async {
        readsIssued += 1
        let issued = readsIssued
        do {
            let fresh = try await client.snapshot(matchId: matchId)
            guard issued > latestApplied else { return }
            latestApplied = issued
            apply(fresh)
        } catch {
            // A failed background re-read leaves the last good screen up; the
            // next payload, write, or foreground tries again.
        }
    }

    func stopObserving() {
        observation?.cancel()
        observation = nil
        clock.stop()
    }

    // MARK: - Private

    private func act(_ move: () async throws -> AuctionTurn) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            apply(turn: try await move())
        } catch {
            errorMessage = AuctionServerError.describe(error)
            // A refusal usually means the server already knows something this
            // screen doesn't (the lot sold, a turn passed), so put the screen
            // back on the server's truth.
            await reconcile()
        }
    }

    private func observe() {
        guard observation == nil else { return }
        // Subscribed here rather than inside the task, so the channels exist
        // the moment this returns: a task only starts when the actor next
        // yields, and anything the match did in between would reach nobody.
        let events = client.events(matchId: matchId)
        observation = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
    }

    private func handle(_ event: AuctionEvent) async {
        guard snapshot != nil else {
            // Nothing to merge into yet — but a payload arriving at all means
            // the match has moved. `start_run` opens a match in `'setup'` and
            // the game deals into it a moment later, so a player carried in
            // during that gap has nothing to read yet; the deal arriving here
            // is what turns a permanently empty screen into a dealt one.
            await reconcile()
            return
        }
        switch event {
        case .subscribed:
            await reconcile()
        case .turn(let turn):
            apply(turn: turn)
        case .lot(let lot):
            // Upsert, not just replace: a declined lot (Pass token) appends a
            // brand-new lot to the deck mid-match.
            if let lots = snapshot?.lots { snapshot?.lots = AuctionRules.upserting(lot, into: lots) }
        case .seat(let seat):
            if let index = snapshot?.seats.firstIndex(where: { $0.userId == seat.userId }),
               let existing = snapshot?.seats[index] {
                snapshot?.seats[index] = seat.named(like: existing)
            }
        case .bid(let bid):
            if snapshot?.bids.contains(where: { $0.seq == bid.seq && $0.bidSeq == bid.bidSeq }) == false {
                snapshot?.bids.append(bid)
            }
        case .scoutHint(let hint):
            if snapshot?.scoutHints.contains(where: { $0.seq == hint.seq && $0.userId == hint.userId }) == false {
                snapshot?.scoutHints.append(hint)
            }
        case .sealedBid(let bid):
            if snapshot?.sealedBids.contains(where: { $0.seq == bid.seq && $0.userId == bid.userId }) == false {
                snapshot?.sealedBids.append(bid)
            }
        case .sealedStatus(let status):
            snapshot?.sealedStatuses.removeAll { $0.seq == status.seq && $0.userId == status.userId }
            snapshot?.sealedStatuses.append(status)
        case .standing(let standing):
            snapshot?.standings.removeAll { $0.userId == standing.userId }
            snapshot?.standings.append(standing)
        case .matchStatus(let status):
            snapshot?.matchStatus = status
            observeClock()
            requestFinalReadIfNeeded()
        case .postGame(let action):
            snapshot?.postGame = action
        }
    }

    private func apply(_ fresh: AuctionSnapshot) {
        snapshot = fresh
        observeClock()
        requestFinalReadIfNeeded()
    }

    private func apply(turn: AuctionTurn) {
        if let serverNow = turn.serverNow { snapshot?.serverNow = serverNow }
        snapshot?.turn = turn
        observeClock()
        requestFinalReadIfNeeded()
    }

    /// The final screen is built from `lots`, so make sure it is the server's
    /// full list at the moment the match ends rather than whatever realtime
    /// happened to deliver.
    private func requestFinalReadIfNeeded() {
        guard isFinished, !finalReadRequested else { return }
        finalReadRequested = true
        Task { await reconcile() }
    }

    /// The clock's `expire`: ask the server to advance a passed deadline. If it
    /// did, the new turn comes back; the rows behind it arrive over the channel
    /// (and the watchdog repairs anything that doesn't).
    private func expire() async {
        do {
            apply(turn: try await client.expireTurn(matchId: matchId))
        } catch {
            // Asking again is free; the clock retries.
        }
    }

    private func observeClock() {
        guard let snapshot else { return }
        let bidding = snapshot.turn.phase == .bidding
        let onTheClock = bidding && me != nil && snapshot.turn.turnSeat == me?.seat
        clock.observe(
            serverNow: snapshot.serverNow,
            // A finished match has no deadline to chase, whatever the row says.
            deadline: isFinished ? nil : snapshot.turn.activeDeadline,
            config: MatchClockConfig(
                // Bidding is the one phase a move can be sent in, so it is the
                // one the visible countdown ends early for.
                visibleSlackMs: bidding ? MatchClockConstants.visibleSlackMs : 0,
                skipExpiry: onTheClock,
                paused: isPaused
            )
        )
    }
}
