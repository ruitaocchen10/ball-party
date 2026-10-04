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

    func test_postRow_decodesAnUnknownTemplateKindAndSelectsThePlaceholder() throws {
        let row = try decode(PromptPostRow.self, """
        {"id": "8E0F2C3A-6B57-4E10-A8B1-6D0E5B6C7A11", "template_kind": "weekly_awards", "template_name": "Weekly Awards",
         "author_id": "1A2B3C4D-0000-4000-8000-000000000001", "caption": "", "prompt_text": "Hand out the hardware",
         "resolution_criteria": "Opinion.", "lock_at": "2026-09-20T17:00:00+00:00",
         "created_at": "2026-09-17T12:00:00+00:00", "status": "open", "void_reason": null, "is_opinion": true}
        """)

        XCTAssertEqual(row.templateKind, "weekly_awards")
        XCTAssertTrue(PromptPost.isUnsupportedKind("weekly_awards"))
        XCTAssertTrue(PromptPost.isUnsupportedKind("bold_predictions"))
        XCTAssertTrue(PromptPost.isFeedKind("bold_predictions"))
    }

    func test_kinds_knownOnesAreNeverPlaceholdersAndAdminOnlyOnesStayOffTheFeed() {
        for kind in ["picks", "game_pick", "weekly_picks", "power_rankings"] {
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
}
