import Foundation
@testable import BallParty
import XCTest

/// The pure board rules and the row decoding — the iOS counterpart of
/// `webapp/lib/games/auction/board.test.ts`, plus the eligibility and flex rules
/// that file leaves to the screen tests.
final class AuctionModelsTests: XCTestCase {
    private func lot(
        _ seq: Int, _ position: String = "RB", week: Int? = 12, opponent: String? = "NO",
        winner: UUID? = nil, points: Double? = nil, slot: String? = nil
    ) -> AuctionLot {
        AuctionLot(
            seq: seq, displayName: "P\(seq)", position: position, season: 2018, team: "KC", week: week,
            opponent: opponent, points: points, slot: slot, winnerId: winner
        )
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - Naming a lot

    func test_identityLine_namesThePlayersTeamBeforeTheirOpponentForAWeeklyLot() {
        XCTAssertEqual(lot(1).identityLine, "2018 · Week 12 · KC vs. NO")
    }

    func test_identityLine_keepsTheTeamOnlyIdentityForASeasonTotalLot() {
        XCTAssertEqual(lot(1, week: nil, opponent: nil).identityLine, "2018 · KC")
    }

    // MARK: - Grading a result

    func test_revealTier_usesQuarterbackSpecificThresholds() {
        XCTAssertEqual(lot(1, "QB", points: 14.9).revealTier, .rough)
        XCTAssertEqual(lot(1, "QB", points: 15).revealTier, .solid)
        XCTAssertEqual(lot(1, "QB", points: 25).revealTier, .great)
    }

    func test_revealTier_sharesThresholdsAcrossRunningBacksAndReceivers() {
        XCTAssertEqual(lot(1, "RB", points: 9.9).revealTier, .rough)
        XCTAssertEqual(lot(1, "WR", points: 10).revealTier, .solid)
        XCTAssertEqual(lot(1, "WR", points: 20).revealTier, .great)
    }

    func test_revealTier_recognisesALowerUsefulScoreForTightEndsAndLeavesSeasonLotsNeutral() {
        XCTAssertEqual(lot(1, "TE", points: 8).revealTier, .solid)
        XCTAssertEqual(lot(1, "TE", points: 16).revealTier, .great)
        XCTAssertNil(lot(1, "RB", week: nil, opponent: nil, points: 150).revealTier)
    }

    func test_revealTier_isNothingUntilThePointsAreRevealed() {
        XCTAssertNil(lot(1, "QB", points: nil).revealTier)
    }

    // MARK: - Tokens

    func test_tokensRemaining_isTheMatchBudgetWhenNothingHasBeenSpent() {
        let format = AuctionFormat.standard(tokenCount: 2)
        let seat = AuctionSeat(userId: UUID(), seat: 0, budget: 25)
        XCTAssertEqual(AuctionRules.tokensRemaining(format: format, seat: seat), 2)
    }

    func test_tokensRemaining_countsASpendAgainstTheSharedBudgetWhicheverAbilityItWas() {
        let format = AuctionFormat.standard(tokenCount: 2)
        let seat = AuctionSeat(userId: UUID(), seat: 0, budget: 25, usedScoutToken: true)
        XCTAssertEqual(AuctionRules.tokensRemaining(format: format, seat: seat), 1)
    }

    func test_tokensRemaining_floorsAtZeroEvenPastTheBudget() {
        let format = AuctionFormat.standard(tokenCount: 2)
        let seat = AuctionSeat(
            userId: UUID(), seat: 0, budget: 25, usedPassToken: true, usedScoutToken: true, usedSealToken: true
        )
        XCTAssertEqual(AuctionRules.tokensRemaining(format: format, seat: seat), 0)
    }

    func test_tokensRemaining_isZeroWithNoFormatOrNoSeat() {
        let seat = AuctionSeat(userId: UUID(), seat: 0, budget: 25)
        XCTAssertEqual(AuctionRules.tokensRemaining(format: nil, seat: seat), 0)
        XCTAssertEqual(AuctionRules.tokensRemaining(format: .standard(tokenCount: 2), seat: nil), 0)
    }

    // MARK: - The deck

    func test_upserting_replacesTheLotWithTheSameSeqInPlace() {
        let out = AuctionRules.upserting(
            AuctionLot(seq: 2, displayName: "Updated", position: "RB", season: 2018, team: "KC"),
            into: [lot(1), lot(2)]
        )
        XCTAssertEqual(out.map(\.displayName), ["P1", "Updated"])
    }

    func test_upserting_appendsALotItHasNeverSeen_whichIsWhatADeclinedLotsRedrawIs() {
        XCTAssertEqual(AuctionRules.upserting(lot(3), into: [lot(1), lot(2)]).map(\.seq), [1, 2, 3])
    }

    func test_upserting_keepsSeqOrderWhenALateLotArrivesOutOfOrder() {
        XCTAssertEqual(AuctionRules.upserting(lot(2), into: [lot(1), lot(3)]).map(\.seq), [1, 2, 3])
    }

    // MARK: - The bid log

    func test_standingPrice_isZeroUntilSomeoneRaises_andThenTheHighestRaise() {
        let a = UUID(), b = UUID()
        XCTAssertEqual(AuctionRules.standingPrice([], seq: 1), 0)

        let bids = [
            AuctionBid(seq: 1, bidSeq: 1, userId: a, action: .raise, price: 3),
            AuctionBid(seq: 1, bidSeq: 2, userId: b, action: .raise, price: 8),
            AuctionBid(seq: 1, bidSeq: 3, userId: a, action: .pass, price: nil),
            AuctionBid(seq: 2, bidSeq: 4, userId: a, action: .raise, price: 20),
        ]
        XCTAssertEqual(AuctionRules.standingPrice(bids, seq: 1), 8)
        XCTAssertEqual(AuctionRules.highBidder(bids, seq: 1), b)
        XCTAssertTrue(AuctionRules.hasPassed(bids, seq: 1, userId: a))
        XCTAssertFalse(AuctionRules.hasPassed(bids, seq: 1, userId: b))
        XCTAssertFalse(AuctionRules.hasPassed(bids, seq: 2, userId: a))
    }

    // MARK: - Rosters

    func test_rosterSlots_numbersRepeatsAndLeavesSingletonsPlain() {
        let deep = AuctionFormat(
            scoringMode: "weekly", rosterPreset: "deep", qbSlots: 2, rbSlots: 2, wrSlots: 3, teSlots: 1,
            flexSlots: 2, purse: 50, seasonFrom: 2010, seasonTo: 2025, tokenCount: 1
        )
        XCTAssertEqual(
            AuctionRules.rosterSlots(deep).map(\.label),
            ["QB 1", "QB 2", "RB 1", "RB 2", "WR 1", "WR 2", "WR 3", "TE", "FLEX 1", "FLEX 2"]
        )
        XCTAssertEqual(AuctionRules.rosterSlots(.standard(tokenCount: 1)).map(\.label), ["QB", "RB", "WR", "TE", "FLEX"])
    }

    func test_rosterSlots_aBoardWithNoFormatKeepsTheOriginalShape() {
        XCTAssertEqual(AuctionRules.rosterSlots(nil).count, 5)
    }

    func test_filledSlots_isDerivedFromTheLotsAPlayerWon() {
        let me = UUID(), other = UUID()
        let lots = [
            lot(1, "QB", winner: me, slot: "QB"),
            lot(2, "RB", winner: me, slot: "RB"),
            lot(3, "RB", winner: me, slot: "FLEX"),
            lot(4, "WR", winner: other, slot: "WR"),
        ]
        let filled = AuctionRules.filledSlots(lots, userId: me)
        XCTAssertEqual(filled[.qb], 1)
        XCTAssertEqual(filled[.rb], 1)
        XCTAssertEqual(filled[.flex], 1)
        XCTAssertEqual(filled[.wr], 0)
    }

    func test_revealedTotal_sumsOnlyWhatAPlayerWon() {
        let me = UUID(), other = UUID()
        let lots = [lot(1, winner: me, points: 12.5), lot(2, winner: me, points: 7), lot(3, winner: other, points: 30), lot(4)]
        XCTAssertEqual(AuctionRules.revealedTotal(lots, userId: me), 19.5)
    }

    // MARK: - Eligibility

    func test_eligibility_anOpenNaturalSlotIsAlwaysEligible() {
        let me = UUID()
        let seats = [AuctionSeat(userId: me, seat: 0, budget: 25)]
        XCTAssertEqual(
            AuctionRules.eligibility(of: lot(1, "WR"), lots: [lot(1, "WR")], seats: seats, userId: me, format: .standard(tokenCount: 0)),
            .eligible
        )
    }

    func test_eligibility_aFullQuarterbackSlotNeverSpillsIntoFlex() {
        let me = UUID()
        let lots = [lot(1, "QB", winner: me, slot: "QB"), lot(2, "QB")]
        let seats = [AuctionSeat(userId: me, seat: 0, budget: 25)]
        XCTAssertEqual(
            AuctionRules.eligibility(of: lots[1], lots: lots, seats: seats, userId: me, format: .standard(tokenCount: 0)),
            .noSlot
        )
    }

    func test_eligibility_aFullFlexSlotIsNoSlotAtAll() {
        let me = UUID()
        let lots = [
            lot(1, "RB", winner: me, slot: "RB"), lot(2, "RB", winner: me, slot: "FLEX"), lot(3, "RB"),
        ]
        let seats = [AuctionSeat(userId: me, seat: 0, budget: 25)]
        XCTAssertEqual(
            AuctionRules.eligibility(of: lots[2], lots: lots, seats: seats, userId: me, format: .standard(tokenCount: 0)),
            .noSlot
        )
    }

    func test_eligibility_flexIsRefusedWhenItWouldStrandSomeoneWhoStillNeedsThePosition() {
        let me = UUID(), sam = UUID()
        // The viewer's RB slot is full; Sam still needs one and this is the
        // last RB in the deck, so spilling into FLEX would strand him.
        let lots = [lot(1, "RB", winner: me, slot: "RB"), lot(2, "RB")]
        let seats = [AuctionSeat(userId: me, seat: 0, budget: 25), AuctionSeat(userId: sam, seat: 1, budget: 25)]
        XCTAssertEqual(
            AuctionRules.eligibility(of: lots[1], lots: lots, seats: seats, userId: me, format: .standard(tokenCount: 0)),
            .flexWouldStrand
        )
    }

    func test_eligibility_flexIsAllowedWhenEnoughOfThePositionRemainsForEveryoneElse() {
        let me = UUID(), sam = UUID()
        let lots = [lot(1, "RB", winner: me, slot: "RB"), lot(2, "RB"), lot(3, "RB")]
        let seats = [AuctionSeat(userId: me, seat: 0, budget: 25), AuctionSeat(userId: sam, seat: 1, budget: 25)]
        XCTAssertEqual(
            AuctionRules.eligibility(of: lots[1], lots: lots, seats: seats, userId: me, format: .standard(tokenCount: 0)),
            .eligible
        )
    }

    // MARK: - How many lots to show

    private func four() -> [AuctionSeat] {
        (0..<4).map { AuctionSeat(userId: UUID(), seat: $0, budget: 25) }
    }

    private func turn(_ currentLot: Int, _ phase: AuctionTurn.Phase = .bidding, lotCount: Int = 22) -> AuctionTurn {
        AuctionTurn(lotCount: lotCount, currentLot: currentLot, turnSeat: 0, phase: phase)
    }

    func test_playableLotCount_dropsTheFlexSparesFromTheOpeningCount() {
        // Four players, five slots each: 20 lots to play out of the 22 dealt.
        XCTAssertEqual(
            AuctionRules.playableLotCount(turn: turn(1), lots: [lot(1)], seats: four(), format: .standard(tokenCount: 0)),
            20
        )
    }

    func test_playableLotCount_isTheLotsBehindTheTableTheOneOnTheBlockAndTheSlotsStillOpen() {
        let seats = four()
        let lots = [
            lot(1, winner: seats[0].userId, slot: "RB"),
            lot(2, "QB", winner: seats[1].userId, slot: "QB"),
            lot(3),
        ]
        // Two slots filled, so 18 open; lot 3 is on the block and fills one.
        XCTAssertEqual(
            AuctionRules.playableLotCount(turn: turn(3), lots: lots, seats: seats, format: .standard(tokenCount: 0)),
            3 + 17
        )
    }

    func test_playableLotCount_aSoldCurrentLotIsAlreadyFilledNotStillAhead() {
        let seats = four()
        let lots = [lot(1, winner: seats[0].userId, slot: "RB")]
        XCTAssertEqual(
            AuctionRules.playableLotCount(turn: turn(1, .sold), lots: lots, seats: seats, format: .standard(tokenCount: 0)),
            1 + 19
        )
    }

    func test_playableLotCount_landsExactlyOnTheLastLotWhenOnlyItIsLeft() {
        let seats = four()
        var lots: [AuctionLot] = []
        for (index, seat) in seats.enumerated() {
            for (offset, slot) in ["QB", "RB", "WR", "TE", "FLEX"].enumerated() {
                // The last seat's FLEX is the lot still on the block.
                if index == 3 && slot == "FLEX" { continue }
                lots.append(lot(index * 5 + offset + 1, winner: seat.userId, slot: slot))
            }
        }
        lots.append(lot(20))
        XCTAssertEqual(
            AuctionRules.playableLotCount(turn: turn(20), lots: lots, seats: seats, format: .standard(tokenCount: 0)),
            20
        )
    }

    func test_playableLotCount_neverExceedsWhatTheServerDealt() {
        XCTAssertEqual(
            AuctionRules.playableLotCount(
                turn: turn(1, lotCount: 6), lots: [lot(1)], seats: four(), format: .standard(tokenCount: 0)
            ),
            6
        )
    }

    func test_playableLotCount_aBoardWithNoFormatKeepsTheOriginalFiveSlotShape() {
        XCTAssertEqual(AuctionRules.playableLotCount(turn: turn(1), lots: [lot(1)], seats: four(), format: nil), 20)
    }

    func test_playableLotCount_sizesADeepBoardFromItsOwnSlotCounts() {
        let deep = AuctionFormat(
            scoringMode: "weekly", rosterPreset: "deep", qbSlots: 2, rbSlots: 2, wrSlots: 3, teSlots: 1,
            flexSlots: 2, purse: 50, seasonFrom: 2010, seasonTo: 2025, tokenCount: 1
        )
        XCTAssertEqual(
            AuctionRules.playableLotCount(turn: turn(1, lotCount: 40), lots: [lot(1)], seats: four(), format: deep),
            40
        )
    }

    // MARK: - The phase

    func test_viewerPhase_splitsBiddingIntoMineAndTheirsButNothingElse() {
        let bidding = AuctionTurn(lotCount: 8, currentLot: 1, turnSeat: 2, phase: .bidding)
        XCTAssertEqual(AuctionRules.viewerPhase(bidding, viewerSeat: 2), .biddingSelf)
        XCTAssertEqual(AuctionRules.viewerPhase(bidding, viewerSeat: 0), .biddingOther)
        XCTAssertEqual(AuctionRules.viewerPhase(bidding, viewerSeat: nil), .biddingOther)
        XCTAssertEqual(
            AuctionRules.viewerPhase(AuctionTurn(lotCount: 8, currentLot: 1, turnSeat: nil, phase: .sealed), viewerSeat: 0),
            .sealed
        )
    }

    // MARK: - Decoding

    func test_turn_decodesAnRPCResultWithItsServerClock() throws {
        let turn = try decode(AuctionTurn.self, """
        {"match_id": "1B2F1C0E-0000-4000-8000-000000000001", "lot_count": 20, "current_lot": 3,
         "turn_seat": 1, "opener_seat": 2, "turn_deadline": "2026-09-24T12:00:20.123456+00:00",
         "server_now": "2026-09-24T12:00:00.5+00:00", "phase": "bidding", "phase_deadline": null,
         "free_fallback_seat": null, "stuck_seat": 1}
        """)

        XCTAssertEqual(turn.lotCount, 20)
        XCTAssertEqual(turn.turnSeat, 1)
        XCTAssertEqual(turn.stuckSeat, 1)
        XCTAssertEqual(turn.phase, .bidding)
        XCTAssertNotNil(turn.serverNow)
        XCTAssertEqual(turn.activeDeadline, turn.turnDeadline)
    }

    func test_turn_aReplicatedRowCarriesNoServerClock() throws {
        let turn = try decode(AuctionTurn.self, """
        {"match_id": "1B2F1C0E-0000-4000-8000-000000000001", "lot_count": 20, "current_lot": 4,
         "turn_seat": null, "opener_seat": 3, "turn_deadline": null, "phase": "lot_preview",
         "phase_deadline": "2026-09-24T12:00:05+00:00", "free_fallback_seat": null, "stuck_seat": null,
         "purse": 25, "token_count": 1}
        """)

        XCTAssertNil(turn.serverNow)
        XCTAssertEqual(turn.phase, .lotPreview)
        XCTAssertEqual(turn.activeDeadline, turn.phaseDeadline)
    }

    func test_lot_decodesNumericPointsFromAStringAndHiddenOnesAsNil() throws {
        let revealed = try decode(AuctionLot.self, """
        {"seq": 1, "display_name": "Josh Allen", "headshot_url": "https://example.com/a.png",
         "position": "QB", "season": 2020, "team": "BUF", "week": 4, "opponent": "LV",
         "points": "27.14", "price": 12, "slot": "QB", "winner_id": "1B2F1C0E-0000-4000-8000-000000000001",
         "match_id": "1B2F1C0E-0000-4000-8000-000000000002", "player_id": "00-0034857"}
        """)
        XCTAssertEqual(revealed.points, 27.14)
        XCTAssertEqual(revealed.price, 12)
        XCTAssertEqual(revealed.headshotURL, URL(string: "https://example.com/a.png"))
        XCTAssertTrue(revealed.isWeekly)

        let hidden = try decode(AuctionLot.self, """
        {"seq": 2, "display_name": "Saquon Barkley", "headshot_url": null, "position": "RB", "season": 2018,
         "team": "NYG", "week": null, "opponent": null, "points": null, "price": null, "slot": null,
         "winner_id": null}
        """)
        XCTAssertNil(hidden.points)
        XCTAssertNil(hidden.winnerId)
        XCTAssertFalse(hidden.isWeekly)
    }

    func test_lot_aSkippedSpareWasNeverPresentedAndASettledLotWas() throws {
        let skipped = try decode(AuctionLot.self, """
        {"seq": 3, "display_name": "Spare", "position": "WR", "season": 2018, "team": "KC",
         "week": 4, "opponent": "LV", "points": null, "price": null, "slot": null, "winner_id": null,
         "resolved_at": null}
        """)
        XCTAssertFalse(skipped.wasPresented)

        // Unsold but put up: `resolve` still stamps it.
        let unsold = try decode(AuctionLot.self, """
        {"seq": 4, "display_name": "Declined", "position": "WR", "season": 2018, "team": "KC",
         "week": 4, "opponent": "LV", "points": 6.5, "price": null, "slot": null, "winner_id": null,
         "resolved_at": "2026-09-24T12:00:00.5+00:00"}
        """)
        XCTAssertTrue(unsold.wasPresented)
    }

    func test_seat_decodesItsProfile_andAReplicatedRowTakesTheExistingIdentity() throws {
        let seat = try decode(AuctionSeat.self, """
        {"match_id": "1B2F1C0E-0000-4000-8000-000000000002", "user_id": "1B2F1C0E-0000-4000-8000-000000000001",
         "seat": 2, "budget": 14, "used_pass_token": false, "used_scout_token": true, "used_seal_token": false,
         "profiles": {"display_name": "Avery", "avatar_url": "https://example.com/avery.png"}}
        """)
        XCTAssertEqual(seat.name, "Avery")
        XCTAssertEqual(seat.avatarURL, URL(string: "https://example.com/avery.png"))
        XCTAssertTrue(seat.usedScoutToken)

        let replicated = try decode(AuctionSeat.self, """
        {"match_id": "1B2F1C0E-0000-4000-8000-000000000002", "user_id": "1B2F1C0E-0000-4000-8000-000000000001",
         "seat": 2, "budget": 9, "used_pass_token": false, "used_scout_token": true, "used_seal_token": true}
        """)
        XCTAssertEqual(replicated.name, "Unknown player")
        let merged = replicated.named(like: seat)
        XCTAssertEqual(merged.name, "Avery")
        XCTAssertEqual(merged.budget, 9)
    }

    func test_format_decodesTheSnapshotAndNamesItsEra() throws {
        let format = try decode(AuctionFormat.self, """
        {"scoring_mode": "season_total", "roster_preset": "full", "qb_slots": 1, "rb_slots": 2, "wr_slots": 2,
         "te_slots": 1, "flex_slots": 1, "purse": 35, "season_from": 2015, "season_to": 2025, "token_count": 3}
        """)
        XCTAssertEqual(format.eraLabel, "2015-2025")
        XCTAssertEqual(format.scoringLabel, "Season total")
        XCTAssertEqual(AuctionRules.rosterSlots(format).count, 7)
    }

    func test_format_aBoardFromBeforeRosterFormatsFailsToDecodeSoTheScreenKeepsTheOriginalShape() {
        XCTAssertThrowsError(try decode(AuctionFormat.self, """
        {"scoring_mode": null, "roster_preset": null, "qb_slots": null, "rb_slots": null, "wr_slots": null,
         "te_slots": null, "flex_slots": null, "purse": null, "season_from": null, "season_to": null,
         "token_count": 0}
        """))
    }

    func test_era_decodesTheBoundsAndTheDealersMinimumWindow() throws {
        let era = try decode(AuctionEra.self, #"{"season_min": 2010, "season_max": 2025, "min_span": 4}"#)
        XCTAssertEqual(era, AuctionEra(seasonMin: 2010, seasonMax: 2025, minSpan: 4))
    }
}
