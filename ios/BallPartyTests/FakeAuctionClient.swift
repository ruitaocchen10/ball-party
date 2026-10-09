import Foundation
@testable import BallParty

/// An in-memory stand-in for the auction half of the server, behind the same
/// `AuctionClient` seam the app uses. It plays only the rules a screen's
/// behavior depends on — whose turn it is, a raise or pass landing in the bid
/// log, tokens being spent once, a lot's points staying `nil` until it sells —
/// so view-model tests can drive a whole auction without a network.
///
/// Its test controls are written from the *table's* point of view
/// (`anotherPlayerRaises`, `lotSells`), because that is what a match screen has
/// to react to.
final class FakeAuctionClient: AuctionClient, @unchecked Sendable {
    let viewerId: UUID
    let matchId = UUID()

    // Server-side state.
    private(set) var turn: AuctionTurn
    private(set) var lots: [AuctionLot] = []
    private(set) var seats: [AuctionSeat] = []
    private(set) var bids: [AuctionBid] = []
    private(set) var standings: [MatchStanding] = []
    private(set) var hints: [ScoutHint] = []
    private(set) var sealedBids: [SealedBid] = []
    private(set) var sealedStatuses: [SealedBidStatus] = []
    private(set) var matchStatus: MatchStatus = .playing
    private(set) var postGame: PostGameAction?
    var format: AuctionFormat? = AuctionFormat.standard(tokenCount: 1)
    var serverNow = Date(timeIntervalSince1970: 1_786_795_200)
    var bounds = AuctionEra(seasonMin: 2010, seasonMax: 2025, minSpan: 4)
    /// What `use_scout_token` reports.
    var scoutTier = "solid"

    // What the app asked for.
    private(set) var snapshotCount = 0
    private(set) var placedBids: [Int] = []
    private(set) var passCount = 0
    private(set) var expireCount = 0
    private(set) var scoutCount = 0
    private(set) var sealCount = 0
    private(set) var submittedSealedAmounts: [Int] = []
    private(set) var postGameChoices: [PostGameAction.Choice] = []
    private(set) var startCalls: [(scoringMode: ScoringMode, preset: RosterPreset, era: SeasonRange?, tokens: Int)] = []

    /// Scripted failures, keyed by RPC name.
    var failures: [String: AuctionServerError] = [:]

    private var continuation: AsyncStream<AuctionEvent>.Continuation?

    init(viewerId: UUID) {
        self.viewerId = viewerId
        turn = AuctionTurn(lotCount: 8, currentLot: 1, turnSeat: 0, phase: .bidding)
    }

    // MARK: - Test controls

    /// Seats the viewer (seat 0) and one seat per name, and deals eight lots.
    /// Returns the other players' ids in the order named.
    @discardableResult
    func dealMatch(others names: [String] = ["Sam"], positions: [String]? = nil, budget: Int = 25) -> [UUID] {
        let ids = names.map { _ in UUID() }
        seats = [AuctionSeat(userId: viewerId, seat: 0, budget: budget, name: "You")]
            + zip(names, ids).enumerated().map { index, pair in
                AuctionSeat(userId: pair.1, seat: index + 1, budget: budget, name: pair.0)
            }
        let cycle = positions ?? ["RB", "WR", "QB", "TE", "RB", "WR", "QB", "TE"]
        lots = cycle.enumerated().map { index, position in
            AuctionLot(
                seq: index + 1, displayName: "Player \(index + 1)", position: position, season: 2019,
                team: "KC", week: 5, opponent: "DEN"
            )
        }
        turn = AuctionTurn(lotCount: lots.count, currentLot: 1, turnSeat: 0, phase: .bidding, serverNow: serverNow)
        return ids
    }

    /// Replaces the board pointer without the app asking, and says so on the
    /// channel the way updating the `auction_matches` row does.
    func setTurn(_ new: AuctionTurn, emit shouldEmit: Bool = true) {
        turn = new
        if shouldEmit { emit(.turn(new)) }
    }

    func setTurn(
        currentLot: Int = 1, turnSeat: Int?, phase: AuctionTurn.Phase = .bidding,
        stuckSeat: Int? = nil, freeFallbackSeat: Int? = nil, emit shouldEmit: Bool = true
    ) {
        setTurn(
            AuctionTurn(
                lotCount: lots.count, currentLot: currentLot, turnSeat: turnSeat,
                freeFallbackSeat: freeFallbackSeat, stuckSeat: stuckSeat, phase: phase, serverNow: serverNow
            ),
            emit: shouldEmit
        )
    }

    func setSeat(_ seat: AuctionSeat) {
        guard let index = seats.firstIndex(where: { $0.userId == seat.userId }) else { return }
        seats[index] = seat
    }

    func setStandings(_ new: [MatchStanding]) { standings = new }

    /// A seat's win, written the way `resolve` does: the lot gets a winner,
    /// slot, price and — only now — its points.
    func lotSells(seq: Int, to winner: UUID, price: Int, slot: String, points: Double) {
        guard let index = lots.firstIndex(where: { $0.seq == seq }) else { return }
        let old = lots[index]
        lots[index] = AuctionLot(
            seq: old.seq, displayName: old.displayName, position: old.position, season: old.season,
            team: old.team, week: old.week, opponent: old.opponent, points: points, price: price,
            slot: slot, winnerId: winner, resolvedAt: serverNow
        )
        emit(.lot(lots[index]))
    }

    func anotherPlayerRaises(_ userId: UUID, to price: Int, lot: Int = 1) {
        let bid = AuctionBid(seq: lot, bidSeq: bids.count + 1, userId: userId, action: .raise, price: price)
        bids.append(bid)
        emit(.bid(bid))
    }

    func anotherPlayerPasses(_ userId: UUID, lot: Int = 1) {
        let bid = AuctionBid(seq: lot, bidSeq: bids.count + 1, userId: userId, action: .pass, price: nil)
        bids.append(bid)
        emit(.bid(bid))
    }

    func anotherPlayerSubmitsASealedBid(_ userId: UUID, lot: Int = 1) {
        let status = SealedBidStatus(seq: lot, userId: userId, submitted: true)
        sealedStatuses.append(status)
        emit(.sealedStatus(status))
    }

    func matchEnds() {
        matchStatus = .complete
        emit(.matchStatus(.complete))
    }

    func matchPauses() {
        matchStatus = .paused
        emit(.matchStatus(.paused))
    }

    func hostChooses(_ choice: PostGameAction.Choice) {
        let action = PostGameAction(choice: choice, nextMatchId: choice == .replay ? UUID() : nil)
        postGame = action
        emit(.postGame(action))
    }

    /// The channel (re)subscribed — a first connect or a reconnect.
    func channelSubscribes() { emit(.subscribed) }

    func emit(_ event: AuctionEvent) { continuation?.yield(event) }

    var isObserved: Bool { continuation != nil }

    // MARK: - AuctionClient

    func seasonBounds() async throws -> AuctionEra {
        try fail("season_bounds")
        return bounds
    }

    func start(
        matchId: UUID, scoringMode: ScoringMode, rosterPreset: RosterPreset, era: SeasonRange?, tokenCount: Int
    ) async throws -> AuctionTurn {
        try fail("start")
        startCalls.append((scoringMode, rosterPreset, era, tokenCount))
        return turn
    }

    func snapshot(matchId: UUID) async throws -> AuctionSnapshot {
        try fail("snapshot")
        snapshotCount += 1
        return AuctionSnapshot(
            turn: turn, serverNow: serverNow, lots: lots, seats: seats, bids: bids, standings: standings,
            format: format, scoutHints: hints, sealedBids: sealedBids, sealedStatuses: sealedStatuses,
            matchStatus: matchStatus, postGame: postGame
        )
    }

    func placeBid(matchId: UUID, amount: Int) async throws -> AuctionTurn {
        try fail("place_bid")
        guard turn.turnSeat == viewerSeat else { throw AuctionServerError(message: "not_your_turn") }
        guard amount <= (seats.first { $0.userId == viewerId }?.budget ?? 0) else {
            throw AuctionServerError(message: "insufficient_budget")
        }
        placedBids.append(amount)
        let bid = AuctionBid(seq: turn.currentLot, bidSeq: bids.count + 1, userId: viewerId, action: .raise, price: amount)
        bids.append(bid)
        emit(.bid(bid))
        return advanceTurn()
    }

    func pass(matchId: UUID) async throws -> AuctionTurn {
        try fail("pass_lot")
        guard turn.turnSeat == viewerSeat else { throw AuctionServerError(message: "not_your_turn") }
        passCount += 1
        let bid = AuctionBid(seq: turn.currentLot, bidSeq: bids.count + 1, userId: viewerId, action: .pass, price: nil)
        bids.append(bid)
        emit(.bid(bid))
        return advanceTurn()
    }

    func expireTurn(matchId: UUID) async throws -> AuctionTurn {
        try fail("expire_turn")
        expireCount += 1
        return turn
    }

    func useScoutToken(matchId: UUID) async throws -> String {
        try fail("use_scout_token")
        scoutCount += 1
        return scoutTier
    }

    func useSealToken(matchId: UUID) async throws -> AuctionTurn {
        try fail("use_seal_token")
        sealCount += 1
        turn = AuctionTurn(
            lotCount: turn.lotCount, currentLot: turn.currentLot, turnSeat: nil, phase: .sealed, serverNow: serverNow
        )
        emit(.turn(turn))
        return turn
    }

    func submitSealedBid(matchId: UUID, amount: Int) async throws -> AuctionTurn {
        try fail("submit_sealed_bid")
        submittedSealedAmounts.append(amount)
        let bid = SealedBid(seq: turn.currentLot, userId: viewerId, amount: amount)
        sealedBids.append(bid)
        emit(.sealedBid(bid))
        return turn
    }

    func choosePostGame(matchId: UUID, choice: PostGameAction.Choice) async throws -> PostGameAction {
        try fail("choose_post_game")
        postGameChoices.append(choice)
        let action = PostGameAction(choice: choice, nextMatchId: choice == .replay ? UUID() : nil)
        postGame = action
        return action
    }

    func events(matchId: UUID) -> AsyncStream<AuctionEvent> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.onTermination = { _ in self.continuation = nil }
        }
    }

    // MARK: - Private

    private var viewerSeat: Int? { seats.first { $0.userId == viewerId }?.seat }

    private func fail(_ rpc: String) throws {
        if let error = failures[rpc] { throw error }
    }

    /// Hands the clock to the next seat, as `apply` does after a move.
    private func advanceTurn() -> AuctionTurn {
        let next = ((turn.turnSeat ?? 0) + 1) % max(1, seats.count)
        turn = AuctionTurn(
            lotCount: turn.lotCount, currentLot: turn.currentLot, turnSeat: next, phase: .bidding, serverNow: serverNow
        )
        emit(.turn(turn))
        return turn
    }
}

extension AuctionFormat {
    /// The Standard preset, as `auction_matches` stores it once dealt.
    static func standard(tokenCount: Int) -> AuctionFormat {
        AuctionFormat(
            scoringMode: "weekly", rosterPreset: "standard", qbSlots: 1, rbSlots: 1, wrSlots: 1, teSlots: 1,
            flexSlots: 1, purse: 25, seasonFrom: 2010, seasonTo: 2025, tokenCount: tokenCount
        )
    }
}
