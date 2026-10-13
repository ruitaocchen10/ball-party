import Foundation
@testable import BallParty
import XCTest

/// The `prompts` wire shapes in `docs/architecture/game-runtime.md`, decoded the
/// way PostgREST actually prints them — the hand-maintained mirrors are the
/// only thing standing between a server column change and a feed that silently
/// shows nothing, so they are pinned against realistic payloads.
final class PromptModelsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func test_postRow_decodesMicrosecondTimestampsAndAnOpinionFlag() throws {
        let row = try decode(PromptPostRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "template_kind": "picks", "template_name": "Weekly picks",
         "author_id": "1A2B3C4D-0000-4000-8000-000000000001", "caption": "Week 3", "prompt_text": "Who wins?",
         "resolution_criteria": "Final score.", "lock_at": "2026-09-20T17:00:00+00:00",
         "created_at": "2026-09-17T12:00:00.123456+00:00", "status": "open", "void_reason": null, "is_opinion": false}
        """)

        XCTAssertEqual(row.promptText, "Who wins?")
        XCTAssertEqual(row.status, "open")
        XCTAssertNil(row.voidReason)
        XCTAssertEqual(row.lockAt.timeIntervalSince1970, 1_789_923_600, accuracy: 0.001)
        XCTAssertEqual(row.createdAt.timeIntervalSince1970, 1_789_646_400.123, accuracy: 0.001)
    }

    func test_profileRow_decodesAnAvatarWhenThereIsOneAndNoneWhenThereIsNot() throws {
        let with = try decode(PromptProfileRow.self, """
        {"id": "1A2B3C4D-0000-4000-8000-000000000001", "display_name": "Tasha", "avatar_url": "https://example.test/tasha.png"}
        """)
        let without = try decode(PromptProfileRow.self, """
        {"id": "1A2B3C4D-0000-4000-8000-000000000002", "display_name": "Kai", "avatar_url": null}
        """)

        XCTAssertEqual(with.avatarUrl, "https://example.test/tasha.png")
        XCTAssertNil(without.avatarUrl)
    }

    func test_postRow_decodesAWeeklyAwardsPostAsAKindThisBuildPlays() throws {
        let row = try decode(PromptPostRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "template_kind": "weekly_awards", "template_name": "Weekly Awards",
         "author_id": "1A2B3C4D-0000-4000-8000-000000000001", "caption": "", "prompt_text": "Hand out the hardware",
         "resolution_criteria": "Opinion.", "lock_at": "2026-09-20T17:00:00+00:00",
         "created_at": "2026-09-17T12:00:00+00:00", "status": "open", "void_reason": null, "is_opinion": true}
        """)

        XCTAssertEqual(row.templateKind, "weekly_awards")
        XCTAssertFalse(PromptPost.isUnsupportedKind("weekly_awards"))
        XCTAssertFalse(PromptPost.isUnsupportedKind("bold_predictions"))
        XCTAssertTrue(PromptPost.isFeedKind("bold_predictions"))
        XCTAssertTrue(PromptPost.isUnsupportedKind("hot_takes_2027"))
        XCTAssertTrue(PromptPost.isFeedKind("hot_takes_2027"))
    }

    func test_kinds_knownOnesAreNeverPlaceholdersAndAdminOnlyOnesStayOffTheFeed() {
        for kind in ["picks", "game_pick", "weekly_picks", "power_rankings", "weekly_awards", "bold_predictions"] {
            XCTAssertFalse(PromptPost.isUnsupportedKind(kind), kind)
            XCTAssertTrue(PromptPost.isFeedKind(kind), kind)
        }
        for kind in ["stat_leader", "ranking", "custom_multi"] {
            XCTAssertFalse(PromptPost.isUnsupportedKind(kind), kind)
            XCTAssertFalse(PromptPost.isFeedKind(kind), kind)
        }
    }

    func test_postRow_decodesAPowerRankingsCover() throws {
        let row = try decode(PromptPostRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "template_kind": "power_rankings", "template_name": "Power Rankings",
         "author_id": "1A2B3C4D-0000-4000-8000-000000000001", "caption": "", "prompt_text": "Rank the NFL",
         "resolution_criteria": "Opinion.", "lock_at": "2026-09-20T17:00:00+00:00",
         "created_at": "2026-09-17T12:00:00+00:00", "status": "open", "void_reason": null, "is_opinion": true,
         "cover_team_codes": ["KC", "BUF", "PHI", "BAL", "DET", "SF"]}
        """)
        let plain = try decode(PromptPostRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "template_kind": "picks", "template_name": "Picks",
         "author_id": "1A2B3C4D-0000-4000-8000-000000000001", "caption": "", "prompt_text": "Who wins?",
         "resolution_criteria": "Final.", "lock_at": "2026-09-20T17:00:00+00:00",
         "created_at": "2026-09-17T12:00:00+00:00", "status": "open", "void_reason": null, "is_opinion": false,
         "cover_team_codes": null}
        """)

        XCTAssertEqual(row.coverTeamCodes, ["KC", "BUF", "PHI", "BAL", "DET", "SF"])
        XCTAssertNil(plain.coverTeamCodes)
    }

    func test_powerTopFiveRow_takesItsCountsAsNumbersOrStrings() throws {
        let asNumbers = try decode(PromptPowerTopFiveRow.self, """
        {"option_id": "2B3C4D5E-0000-4000-8000-000000000002", "top_five_count": 3, "average_rank": 1.7}
        """)
        let asStrings = try decode(PromptPowerTopFiveRow.self, """
        {"option_id": "2B3C4D5E-0000-4000-8000-000000000002", "top_five_count": "3", "average_rank": "1.7"}
        """)

        XCTAssertEqual(asNumbers.topFiveCount, 3)
        XCTAssertEqual(asNumbers.averageRank, 1.7)
        XCTAssertEqual(asStrings, asNumbers)
    }

    func test_powerRankingMovement_readsPlacesGainedLostOrNew() {
        XCTAssertEqual(PowerRankingMovement(previous: 5, current: 2), .up(3))
        XCTAssertEqual(PowerRankingMovement(previous: 2, current: 5), .down(3))
        XCTAssertEqual(PowerRankingMovement(previous: 4, current: 4), .unchanged)
        XCTAssertEqual(PowerRankingMovement(previous: nil, current: 1), .new)
    }

    func test_slotRow_decodesACorrectAnswerArrayAndItsAbsence() throws {
        let resolved = try decode(PromptSlotRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Chiefs vs Bills", "shape": "pick", "pick_count": null, "points": 10, "sort_order": 0,
         "correct_option_ids": ["2B3C4D5E-0000-4000-8000-000000000002"]}
        """)
        let open = try decode(PromptSlotRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Chiefs vs Bills", "shape": "pick_set", "pick_count": 2, "points": 10, "sort_order": 0,
         "correct_option_ids": null}
        """)

        XCTAssertEqual(resolved.correctOptionIds, [UUID(uuidString: "2B3C4D5E-0000-4000-8000-000000000002")!])
        XCTAssertNil(open.correctOptionIds)
        XCTAssertEqual(open.pickCount, 2)
    }

    func test_optionRow_decodesNullableColumns() throws {
        let row = try decode(PromptOptionRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "slot_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Chiefs", "sublabel": null, "team_code": "KC", "headshot_url": null, "sort_order": 1}
        """)

        XCTAssertEqual(row.teamCode, "KC")
        XCTAssertNil(row.sublabel)
        XCTAssertNil(row.headshotUrl)
    }

    func test_commentRow_decodesATopLevelTakeAndAReply() throws {
        let take = try decode(PromptCommentRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "author_id": "2B3C4D5E-0000-4000-8000-000000000002", "body": "Chiefs", "posted_with_pick": true,
         "parent_comment_id": null, "created_at": "2026-09-17T12:00:00.5+00:00"}
        """)
        let reply = try decode(PromptCommentRow.self, """
        {"id": "9F1A3D4B-6B57-4E10-A8B1-6D0E5B6C7A11", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "author_id": "2B3C4D5E-0000-4000-8000-000000000002", "body": "Nope", "posted_with_pick": false,
         "parent_comment_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "created_at": "2026-09-17T12:01:00+00:00"}
        """)

        XCTAssertNil(take.parentCommentId)
        XCTAssertTrue(take.postedWithPick)
        XCTAssertEqual(reply.parentCommentId, take.id)
    }

    func test_responseRow_decodesAnUnpaidResponseAndAPaidOne() throws {
        let unpaid = try decode(PromptResponseRow.self, """
        {"post_id": "1A2B3C4D-0000-4000-8000-000000000001", "slot_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11",
         "chosen_option_ids": ["2B3C4D5E-0000-4000-8000-000000000002"], "points_earned": null}
        """)
        let paid = try decode(PromptResponseRow.self, """
        {"post_id": "1A2B3C4D-0000-4000-8000-000000000001", "slot_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11",
         "chosen_option_ids": ["2B3C4D5E-0000-4000-8000-000000000002"], "points_earned": 10}
        """)

        XCTAssertNil(unpaid.pointsEarned)
        XCTAssertEqual(paid.pointsEarned, 10)
    }

    func test_aggregateRow_takesANumericPercentAsANumberOrAsAString() throws {
        let asNumber = try decode(PromptAggregateRow.self, """
        {"slot_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "option_id": "2B3C4D5E-0000-4000-8000-000000000002",
         "pct": 62.5, "total_responses": 8}
        """)
        let asString = try decode(PromptAggregateRow.self, """
        {"slot_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "option_id": "2B3C4D5E-0000-4000-8000-000000000002",
         "pct": "62", "total_responses": 8}
        """)

        XCTAssertEqual(asNumber.pct, 62.5)
        XCTAssertEqual(asString.pct, 62)
        XCTAssertEqual(asString.totalResponses, 8)
    }

    func test_aggregateRow_aSlotNobodyHasAnsweredHasNoPercent() throws {
        let row = try decode(PromptAggregateRow.self, """
        {"slot_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "option_id": "2B3C4D5E-0000-4000-8000-000000000002",
         "pct": null, "total_responses": 0}
        """)

        XCTAssertNil(row.pct)
        XCTAssertEqual(row.totalResponses, 0)
    }

    func test_revealedResponseRow_decodesAWholeTicketForOneSlot() throws {
        let row = try decode(PromptRevealedResponseRow.self, """
        {"profile_id": "2B3C4D5E-0000-4000-8000-000000000002", "slot_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11",
         "chosen_option_ids": ["3C4D5E6F-0000-4000-8000-000000000003", "4D5E6F70-0000-4000-8000-000000000004"]}
        """)

        XCTAssertEqual(row.chosenOptionIds.count, 2)
    }

    func test_profileRow_decodesAnAuthorsName() throws {
        let row = try decode(PromptProfileRow.self, """
        {"id": "2B3C4D5E-0000-4000-8000-000000000002", "display_name": "Sam"}
        """)

        XCTAssertEqual(row.displayName, "Sam")
    }

    // MARK: - What goes to the server

    /// `submit_response` looks each slot's answer up by `p_choices -> slot_id::text`,
    /// and Postgres prints uuids lowercase while Swift's `UUID.uuidString` is
    /// uppercase — a jsonb key match is case-sensitive, so an uppercase key
    /// reads as "no answer for this slot" (`incomplete_slot`) for every slot.
    /// Confirmed against a live server, which is why it is pinned here.
    func test_submitResponseParams_keyEachSlotsChoicesByItsLowercaseId() throws {
        let slot = UUID(uuidString: "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11")!
        let option = UUID(uuidString: "2B3C4D5E-0000-4000-8000-000000000002")!

        let params = SubmitResponseParams(postId: UUID(), choices: [slot: [option]], comment: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])

        let choices = try XCTUnwrap(json["p_choices"] as? [String: [String]])
        XCTAssertEqual(Array(choices.keys), ["8e0f2c3a-6b57-4e10-a8b1-6d0e5b6c7a11"])
        XCTAssertEqual(choices.values.first?.map { $0.lowercased() }, ["2b3c4d5e-0000-4000-8000-000000000002"])
    }

    func test_submitResponseParams_leaveOutTheCommentWhenThereIsNone() throws {
        let params = SubmitResponseParams(postId: UUID(), choices: [:], comment: nil)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])

        XCTAssertNil(json["p_comment"], "left out, as the web does, rather than sent as null")
    }

    func test_submitResponseParams_sendTheCommentWhenThereIsOne() throws {
        let params = SubmitResponseParams(postId: UUID(), choices: [:], comment: "Chiefs")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])

        XCTAssertEqual(json["p_comment"] as? String, "Chiefs")
    }

    // MARK: - Weekly Awards and Bold Predictions

    func test_slotRow_readsWhetherASlotIsAPlayerSearch() throws {
        let search = try decode(PromptSlotRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Offensive player", "shape": "pick", "pick_count": null, "points": 10, "sort_order": 3,
         "correct_option_ids": null, "source_game_id": null, "player_search": true}
        """)
        let plain = try decode(PromptSlotRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A12", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Game 1", "shape": "pick", "pick_count": null, "points": 10, "sort_order": 0,
         "correct_option_ids": null, "source_game_id": "2026_03_KC_BUF"}
        """)

        XCTAssertTrue(search.playerSearch)
        XCTAssertFalse(plain.playerSearch, "a payload from before 0175 has no such column")
    }

    func test_option_aBestGameKeepsItsClubsInTheSublabel() {
        let game = PromptOption(id: UUID(), label: "Chiefs @ Bills", sublabel: "KC @ BUF", teamCode: nil, headshotURL: nil)
        XCTAssertEqual(game.gameTeamCodes?.away, "KC")
        XCTAssertEqual(game.gameTeamCodes?.home, "BUF")

        for sublabel in [nil, "QB · KC", "kc @ buf", "KC @ BUF @ DAL", "KC @ "] as [String?] {
            let other = PromptOption(id: UUID(), label: "Patrick Mahomes", sublabel: sublabel, teamCode: "KC", headshotURL: nil)
            XCTAssertNil(other.gameTeamCodes, sublabel ?? "nil")
        }
    }

    func test_player_decodesADirectoryRowAndNamesAnInactiveStatus() throws {
        let player = try decode(NFLPlayer.self, """
        {"player_id": "00-0033873", "display_name": "Patrick Mahomes", "position": "QB", "team": "KC",
         "headshot_url": "https://example.com/mahomes.png", "status": "ACT"}
        """)
        XCTAssertEqual(player.id, "00-0033873")
        XCTAssertEqual(player.name, "Patrick Mahomes")
        XCTAssertEqual(player.summary, "QB · KC")
        XCTAssertEqual(player.headshotURL, URL(string: "https://example.com/mahomes.png"))
        XCTAssertNil(player.statusLabel)

        let reserve = try decode(NFLPlayer.self, """
        {"player_id": "00-0000001", "display_name": "Some Player", "position": "WR", "team": "BUF",
         "headshot_url": null, "status": "RES"}
        """)
        XCTAssertNil(reserve.headshotURL)
        XCTAssertEqual(reserve.statusLabel, "Reserve list")
    }

    func test_submitResponseParams_answerAPlayerSlotWithTheDirectoryId() throws {
        let teamSlot = UUID(uuidString: "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11")!
        let playerSlot = UUID(uuidString: "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A12")!
        let option = UUID(uuidString: "2B3C4D5E-0000-4000-8000-000000000002")!

        let params = SubmitResponseParams(
            postId: UUID(), choices: [teamSlot: [option]], players: [playerSlot: "00-0033873"], comment: nil
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(params)) as? [String: Any])
        let choices = try XCTUnwrap(json["p_choices"] as? [String: [String]])

        XCTAssertEqual(choices["8e0f2c3a-6b57-4e10-a8b1-6d0e5b6c7a12"], ["00-0033873"], "the id itself, under a lowercase slot key")
        XCTAssertEqual(choices["8e0f2c3a-6b57-4e10-a8b1-6d0e5b6c7a11"]?.map { $0.lowercased() }, ["2b3c4d5e-0000-4000-8000-000000000002"])
    }

    func test_boldPredictionRow_decodesWhatTheRpcReturns() throws {
        let row = try decode(BoldPredictionRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "post_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "author_id": "1A2B3C4D-0000-4000-8000-000000000002", "body": "Bills go 17-0",
         "target_type": "team", "target_id": "BUF", "created_at": "2026-09-17T12:00:00.123456+00:00"}
        """)
        XCTAssertEqual(row.body, "Bills go 17-0")
        XCTAssertEqual(row.targetType, "team")
        XCTAssertEqual(row.targetId, "BUF")
    }

    func test_boldPredictionCount_aBigintMayArriveAsAString() throws {
        let rows = try decode([BoldPredictionCountRow].self, """
        [{"post_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "prediction_count": 12, "author_count": 4},
         {"post_id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A12", "prediction_count": "7", "author_count": "3"}]
        """)
        XCTAssertEqual(rows.map(\.predictionCount), [12, 7])
    }

    func test_boldTarget_isDescribedByItsKind() {
        let mahomes = NFLPlayer(id: "00-0033873", name: "Patrick Mahomes", position: "QB", team: "KC")
        let board = BoldBoardData(
            weekGames: [NFLScheduleGame(id: "2026_03_KC_BUF", away: "KC", home: "BUF")],
            players: [mahomes.id: mahomes]
        )

        let team = BoldTargetDescription(BoldTarget(type: .team, id: "BUF"), board: board)
        XCTAssertEqual(team.label, "Bills")
        XCTAssertEqual(team.teamCodes, ["BUF"])

        let game = BoldTargetDescription(BoldTarget(type: .matchup, id: "2026_03_KC_BUF"), board: board)
        XCTAssertEqual(game.label, "Chiefs @ Bills")
        XCTAssertEqual(game.teamCodes, ["KC", "BUF"])

        let player = BoldTargetDescription(BoldTarget(type: .player, id: mahomes.id), board: board)
        XCTAssertEqual(player.label, "Patrick Mahomes")
        XCTAssertEqual(player.player, mahomes)

        // A tag it can't resolve still reads as something.
        XCTAssertEqual(BoldTargetDescription(BoldTarget(type: .matchup, id: "gone"), board: board).label, "Matchup")
        XCTAssertEqual(BoldTargetDescription(BoldTarget(type: .player, id: "gone"), board: board).label, "Player")
    }

    func test_weeklyAwardsResults_listTheLeadersHighestShareFirst() {
        func option(_ label: String) -> PromptOption { PromptOption(id: UUID(), label: label, sublabel: nil, teamCode: nil, headshotURL: nil) }
        let (a, b, c, d, e) = (option("Bills"), option("Chiefs"), option("Eagles"), option("Ravens"), option("Jets"))
        let slot = PromptSlot(
            id: UUID(), label: "Biggest winner", shape: .pick, pickCount: nil, points: 10, correctOptionIds: nil,
            options: [a, b, c, d, e]
        )

        let leaders = WeeklyAwardsResults.topPicks(
            in: slot, shares: [a.id: 20, b.id: 40, c.id: 20, d.id: 15, e.id: 0]
        )

        XCTAssertEqual(leaders.map(\.option.label), ["Chiefs", "Bills", "Eagles"], "three at most, ties alphabetical, no zeros")
        XCTAssertEqual(leaders.map(\.percent), [40, 20, 20])
        XCTAssertTrue(WeeklyAwardsResults.topPicks(in: slot, shares: nil).isEmpty)
    }

    func test_powerRankingCrowdLine_countsTheCrowdsTopFiveThatABallotAlsoRanksInItsOwnTopFive() {
        let ids = (0..<7).map { _ in UUID() }
        let crowd = Array(ids.prefix(5))
        let ballot = [ids[0], ids[5], ids[2], ids[6], ids[4], ids[1]]

        XCTAssertEqual(PowerRankingCrowdLine.matched(crowd: crowd, ranked: ballot), 3, "ids[1] is sixth on the ballot, so it does not count")
        XCTAssertEqual(PowerRankingCrowdLine.matched(crowd: [], ranked: ballot), 0)
    }

    func test_optionRow_readsAGamePicksMarginAndTreatsAnOlderRowAsHavingNone() throws {
        let withMargin = try decode(PromptOptionRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "slot_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Chiefs by 7+", "sublabel": "Wins by 7 or more", "team_code": "KC", "headshot_url": null,
         "sort_order": 1, "margin": "7_plus"}
        """)
        let without = try decode(PromptOptionRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A12", "slot_id": "1A2B3C4D-0000-4000-8000-000000000001",
         "label": "Chiefs", "sublabel": "Away", "team_code": "KC", "headshot_url": null, "sort_order": 0, "margin": null}
        """)

        XCTAssertEqual(withMargin.margin, "7_plus")
        XCTAssertNil(without.margin)
    }
}

