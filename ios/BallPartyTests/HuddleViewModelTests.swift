import Foundation
@testable import BallParty
import XCTest

/// `HuddleViewModel` against `FakeHuddleClient` — the one network seam Huddle
/// touches. Every assertion is on what a screen would show or what the app
/// asked the server for.
@MainActor
final class HuddleViewModelTests: XCTestCase {
    private var viewerId = UUID()
    private var client: FakeHuddleClient!
    private var viewModel: HuddleViewModel!

    override func setUp() async throws {
        viewerId = UUID()
        client = FakeHuddleClient(viewerId: viewerId)
        viewModel = HuddleViewModel(client: client, viewerId: viewerId, now: { [client] in client!.epoch })
    }

    /// The one post a test loaded, or a failure rather than a crash.
    private func onlyPost(file: StaticString = #filePath, line: UInt = #line) throws -> PromptPost {
        try XCTUnwrap(viewModel.posts.first, "the feed is empty", file: file, line: line)
    }

    // MARK: - Browsing the feed

    func test_feed_listsPostsNewestFirstWithTheirOptionsInDisplayOrder() async throws {
        let sam = client.addProfile(named: "Sam")
        client.addPost("Older prompt", by: sam, age: 7200)
        client.addPost("Newer prompt", by: sam, age: 60, slots: [["Chiefs", "Bills"]])

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.posts.map(\.promptText), ["Newer prompt", "Older prompt"])
        XCTAssertEqual(viewModel.posts.first?.author, "Sam")
        XCTAssertEqual(viewModel.posts.first?.slots.first?.options.map(\.label), ["Chiefs", "Bills"])
    }

    func test_aTakeCarriesItsAuthorsUsername() async throws {
        let sam = client.addProfile(named: "Sam", username: "sam_k")
        let nobody = client.addProfile(named: "Nobody")
        let post = client.addPost("A prompt", by: sam)
        client.anotherPlayerPosts("Chiefs", on: post, by: sam)
        client.anotherPlayerPosts("Bills", on: post, by: nobody)

        await viewModel.load()

        let takes = try XCTUnwrap(viewModel.posts.first).comments
        XCTAssertEqual(takes.first { $0.author == "Sam" }?.authorUsername, "sam_k")
        XCTAssertNil(takes.first { $0.author == "Nobody" }?.authorUsername)
    }

    func test_feed_showsTheKindsTheWebHomeShows() async throws {
        client.addPost("A picks post")
        client.addPost("A ranking post", kind: "ranking")
        client.addPost("A stat leader post", kind: "stat_leader")
        client.addPost("A legacy game pick", kind: "game_pick")
        client.addPost("A status from the future", status: "postponed")
        client.addPowerRankingsPost("A power rankings post", teams: ["KC", "BUF"])
        client.addWeeklyAwardsPost("A weekly awards post")
        client.addBoldPredictionsPost("A bold predictions post")

        await viewModel.load()

        XCTAssertEqual(
            Set(viewModel.posts.map(\.promptText)),
            ["A picks post", "A legacy game pick", "A power rankings post", "A weekly awards post", "A bold predictions post"]
        )
    }

    func test_feed_aKindFromANewerRelease_showsAsAnUpdatePlaceholderNotAnAnswerForm() async throws {
        client.addPost("Something new", kind: "hot_takes_2027")
        client.addPost("A picks post")

        await viewModel.load()

        let newer = try XCTUnwrap(viewModel.posts.first { $0.templateKind == "hot_takes_2027" })
        XCTAssertEqual(viewModel.posts.count, 2)
        XCTAssertTrue(newer.isUnsupported)
        XCTAssertTrue(newer.slots.isEmpty)
        XCTAssertFalse(viewModel.canAnswer(newer.id))
        XCTAssertEqual(viewModel.callToAction(for: newer.id), .updateApp)
        XCTAssertEqual(viewModel.callToAction(for: newer.id).label, "Update to play")

        let picks = try XCTUnwrap(viewModel.posts.first { $0.promptText == "A picks post" })
        XCTAssertFalse(picks.isUnsupported)
        XCTAssertEqual(viewModel.callToAction(for: picks.id), .makePicks)
    }

    func test_feed_failingToLoadSaysWhy() async throws {
        client.failures["feed_rows"] = HuddleServerError(message: "post_not_found")

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .failed("This prompt no longer exists."))
        XCTAssertTrue(viewModel.posts.isEmpty)
    }

    func test_feed_aNetworkFailureIsNotShownAsARawError() async throws {
        struct Offline: Error {}
        client.failures["feed_rows"] = Offline()

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .failed("Something went wrong. Check your connection and try again."))
    }

    // MARK: - Seeing how everyone answered

    func test_aggregates_stayHiddenOnAnOpenPostTheViewerHasNotAnswered() async throws {
        let post = client.addPost("Open and unanswered")

        await viewModel.load()

        XCTAssertNil(try onlyPost().aggregate)
        XCTAssertTrue(client.aggregateRequests.isEmpty, "asking for them would show the crowd's picks before the viewer commits")
        _ = post
    }

    func test_aggregates_showOnceAPostHasLocked_withTheSlotsRespondentCount() async throws {
        let post = client.addPost("Locked", status: "locked", locksIn: -60)
        client.setAggregate(for: post, [
            PromptAggregateRow(slotId: post.slotId, optionId: post.options[0], pct: 70, totalResponses: 10),
            PromptAggregateRow(slotId: post.slotId, optionId: post.options[1], pct: 30, totalResponses: 10),
        ])

        await viewModel.load()

        let loaded = try onlyPost()
        XCTAssertEqual(loaded.aggregate?[post.slotId]?[post.options[0]], 70)
        XCTAssertEqual(loaded.aggregate?[post.slotId]?[post.options[1]], 30)
        XCTAssertEqual(loaded.responseCount, 10)
    }

    func test_aggregates_showOnAnOpenPostAsSoonAsTheViewerHasAnswered() async throws {
        let post = client.addPost("Open")
        client.viewerAlreadyAnswered(post, choosing: [post.slotId: [post.options[0]]])
        client.setAggregate(for: post, [
            PromptAggregateRow(slotId: post.slotId, optionId: post.options[0], pct: 100, totalResponses: 1),
            PromptAggregateRow(slotId: post.slotId, optionId: post.options[1], pct: 0, totalResponses: 1),
        ])

        await viewModel.load()

        XCTAssertEqual(try onlyPost().aggregate?[post.slotId]?[post.options[0]], 100)
    }

    func test_aggregates_aSlotWithNoResponsesYetReadsAsZeroPercent() async throws {
        let post = client.addPost("Locked, nobody answered", status: "locked", locksIn: -60)
        client.setAggregate(for: post, [
            PromptAggregateRow(slotId: post.slotId, optionId: post.options[0], pct: nil, totalResponses: 0),
            PromptAggregateRow(slotId: post.slotId, optionId: post.options[1], pct: nil, totalResponses: 0),
        ])

        await viewModel.load()

        XCTAssertEqual(try onlyPost().aggregate?[post.slotId]?[post.options[0]], 0)
        XCTAssertEqual(try onlyPost().responseCount, 0)
    }

    // MARK: - The viewer's own ticket

    func test_answeredPost_carriesTheViewersOwnTicket() async throws {
        let post = client.addPost("Two games", slots: [["Chiefs", "Bills"], ["Eagles", "Cowboys"]])
        client.viewerAlreadyAnswered(post, choosing: [
            post.slotIds[0]: [post.optionIds[0][1]],
            post.slotIds[1]: [post.optionIds[1][0]],
        ])

        await viewModel.load()

        let loaded = try onlyPost()
        XCTAssertTrue(loaded.viewerAnswered)
        XCTAssertEqual(loaded.viewerResponse, [
            post.slotIds[0]: [post.optionIds[0][1]],
            post.slotIds[1]: [post.optionIds[1][0]],
        ])
        XCTAssertNil(loaded.viewerPointsAwarded, "nothing is paid out before a post resolves")
    }

    func test_resolvedPost_showsThePointsTheServerPaidAndTheCorrectAnswers() async throws {
        let post = client.addPost("Two games", slots: [["Chiefs", "Bills"], ["Eagles", "Cowboys"]])
        client.viewerAlreadyAnswered(post, choosing: [
            post.slotIds[0]: [post.optionIds[0][0]],
            post.slotIds[1]: [post.optionIds[1][0]],
        ])
        client.resolve(post, correct: [post.optionIds[0][0]], pointsAwarded: 10)

        await viewModel.load()

        let loaded = try onlyPost()
        XCTAssertEqual(loaded.status, .resolved)
        // Two slots, each paid 10 — summed from what the server wrote, not
        // recomputed from the rules on the phone.
        XCTAssertEqual(loaded.viewerPointsAwarded, 20)
        XCTAssertEqual(loaded.slots.first?.correctOptionIds, [post.optionIds[0][0]])
    }

    func test_unansweredPost_hasNoTicket() async throws {
        client.addPost("Nobody home")

        await viewModel.load()

        XCTAssertFalse(try onlyPost().viewerAnswered)
        XCTAssertNil(try onlyPost().viewerResponse)
    }

    // MARK: - Takes and replies

    func test_takes_areNestedOneLevelDeepAndOrderedOldestFirst() async throws {
        let sam = client.addProfile(named: "Sam")
        let dana = client.addProfile(named: "Dana")
        let post = client.addPost("Chat", status: "locked", locksIn: -60)
        let first = client.anotherPlayerPosts("Chiefs all day", on: post, by: sam)
        client.anotherPlayerPosts("Bills in a walk", on: post, by: dana)
        client.anotherPlayerPosts("You're joking", on: post, by: dana, withPick: false, replyingTo: first)
        client.anotherPlayerPosts("Not joking", on: post, by: sam, withPick: false, replyingTo: first)

        await viewModel.load()

        let takes = try onlyPost().comments
        XCTAssertEqual(takes.map(\.body), ["Chiefs all day", "Bills in a walk"])
        XCTAssertEqual(takes.map(\.author), ["Sam", "Dana"])
        XCTAssertEqual(takes.first?.replies.map(\.body), ["You're joking", "Not joking"])
        XCTAssertEqual(takes.last?.replies.isEmpty, true)
    }

    func test_takes_knowWhichOnesAreTheViewers() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat", status: "locked", locksIn: -60)
        client.anotherPlayerPosts("Mine", on: post, by: viewerId)
        client.anotherPlayerPosts("Theirs", on: post, by: sam)

        await viewModel.load()

        XCTAssertEqual(try onlyPost().comments.map(\.isViewer), [true, false])
    }

    func test_takes_areAlwaysReadFromTheServerNotJustTheOnesTheViewerMade() async throws {
        // The reader hasn't answered, so the screen won't show these — but the
        // read model holds them; who sees what is decided a layer up.
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat")
        client.anotherPlayerPosts("Hot take", on: post, by: sam)

        await viewModel.load()

        XCTAssertEqual(try onlyPost().comments.map(\.body), ["Hot take"])
    }

    func test_takes_aReplyWhoseParentIsGoneStandsAloneInsteadOfVanishing() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat", status: "locked", locksIn: -60)
        client.anotherPlayerPosts("Orphaned", on: post, by: sam, withPick: false, replyingTo: UUID())

        await viewModel.load()

        XCTAssertEqual(try onlyPost().comments.map(\.body), ["Orphaned"])
    }

    // MARK: - The Profile tab's take history

    func test_myTakes_isTheViewersOwnTopLevelTakesAcrossEveryPost_newestFirst() async throws {
        let sam = client.addProfile(named: "Sam")
        let older = client.addPost("Older prompt", status: "locked", age: 7200, locksIn: -60)
        let newer = client.addPost("Newer prompt", status: "locked", age: 60, locksIn: -60)
        client.anotherPlayerPosts("On the older one", on: older, by: viewerId)
        client.anotherPlayerPosts("Not mine", on: older, by: sam)
        client.anotherPlayerPosts("On the newer one", on: newer, by: viewerId)

        await viewModel.load()

        let mine = PromptFeed.myTakes(in: viewModel.posts)
        XCTAssertEqual(mine.map(\.comment.body), ["On the newer one", "On the older one"])
        XCTAssertEqual(mine.map(\.post.promptText), ["Newer prompt", "Older prompt"])
    }

    func test_myTakes_excludesReplies() async throws {
        let post = client.addPost("Chat", status: "locked", locksIn: -60)
        let take = client.anotherPlayerPosts("A take", on: post, by: viewerId)
        client.anotherPlayerPosts("A reply", on: post, by: viewerId, withPick: false, replyingTo: take)

        await viewModel.load()

        XCTAssertEqual(PromptFeed.myTakes(in: viewModel.posts).map(\.comment.body), ["A take"])
    }

    // MARK: - Other players' tickets

    func test_tickets_showBesideATake_onceThePostHasLocked() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Two games", status: "locked", locksIn: -60, slots: [["Chiefs", "Bills"], ["Eagles", "Cowboys"]])
        client.anotherPlayerPosts("Both home teams", on: post, by: sam)
        client.setRevealed(for: post, [
            PromptRevealedResponseRow(profileId: sam, slotId: post.slotIds[0], chosenOptionIds: [post.optionIds[0][0]]),
            PromptRevealedResponseRow(profileId: sam, slotId: post.slotIds[1], chosenOptionIds: [post.optionIds[1][1]]),
        ])

        await viewModel.load()

        XCTAssertEqual(viewModel.posts.first?.comments.first?.response, [
            post.slotIds[0]: [post.optionIds[0][0]],
            post.slotIds[1]: [post.optionIds[1][1]],
        ])
    }

    func test_answers_withoutWords_listAfterTakesWithWords_friendsFirst() async throws {
        let sam = client.addProfile(named: "Sam")
        let quiet = client.addProfile(named: "Quiet")
        let post = client.addPost("Locked", status: "locked", locksIn: -60)
        client.anotherPlayerPosts("Loud take", on: post, by: sam)
        client.anotherPlayerPosts("", on: post, by: quiet)
        await viewModel.load()

        XCTAssertEqual(viewModel.otherTakes(on: post.id).map(\.author), ["Sam"])
        XCTAssertEqual(viewModel.otherAnswers(on: post.id).map(\.author), ["Quiet"])
        XCTAssertTrue(viewModel.friendAnswers(on: post.id).isEmpty)
    }

    func test_tickets_stayHiddenWhileAPostIsStillOpen() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Still open")
        client.anotherPlayerPosts("Trust me", on: post, by: sam)
        client.setRevealed(for: post, [
            PromptRevealedResponseRow(profileId: sam, slotId: post.slotId, chosenOptionIds: [post.options[0]]),
        ])

        await viewModel.load()

        XCTAssertNil(viewModel.posts.first?.comments.first?.response)
        XCTAssertTrue(client.revealedRequests.isEmpty, "an open post's picks must never be asked for — a later player could copy them")
    }

    func test_tickets_aResolvedPostRevealsEvenIfItsLockTimeHasNotPassedOnThisPhone() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Resolved early", locksIn: 3600)
        client.resolve(post, correct: [post.options[0]], pointsAwarded: 0)
        client.anotherPlayerPosts("Called it", on: post, by: sam)
        client.setRevealed(for: post, [
            PromptRevealedResponseRow(profileId: sam, slotId: post.slotId, chosenOptionIds: [post.options[0]]),
        ])

        await viewModel.load()

        XCTAssertEqual(viewModel.posts.first?.comments.first?.response, [post.slotId: [post.options[0]]])
    }

    func test_tickets_aReplyNeverCarriesOne() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat", status: "locked", locksIn: -60)
        let take = client.anotherPlayerPosts("Take", on: post, by: sam)
        client.anotherPlayerPosts("Reply", on: post, by: sam, withPick: false, replyingTo: take)
        client.setRevealed(for: post, [
            PromptRevealedResponseRow(profileId: sam, slotId: post.slotId, chosenOptionIds: [post.options[0]]),
        ])

        await viewModel.load()

        XCTAssertNotNil(try onlyPost().comments.first?.response)
        XCTAssertNil(viewModel.posts.first?.comments.first?.replies.first?.response)
    }

    func test_tickets_aPhoneClockRunningBehindTheServerDoesNotBreakTheFeed() async throws {
        // The phone thinks the post is locked; the server, on its own clock,
        // says not yet. That refusal is "nothing to reveal", not a failure.
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Locking now", locksIn: 0)
        client.anotherPlayerPosts("Early", on: post, by: sam)
        client.failures["revealed_responses"] = HuddleServerError(message: HuddleServerError.picksNotRevealed)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertNil(viewModel.posts.first?.comments.first?.response)
    }

    func test_tickets_anyOtherRevealFailureStillFailsTheLoadRatherThanHidingIt() async throws {
        let post = client.addPost("Locked", status: "locked", locksIn: -60)
        _ = post
        client.failures["revealed_responses"] = HuddleServerError(message: "boom")

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .failed("boom"))
    }

    func test_feed_aPostWithASlotShapeThisAppDoesNotKnowIsLeftOut() async throws {
        client.addPost("From the future", shape: "tournament_bracket")
        client.addPost("Ordinary")

        await viewModel.load()

        XCTAssertEqual(viewModel.posts.map(\.promptText), ["Ordinary"])
    }

    func test_feed_aRefreshThatFailsKeepsWhatWasAlreadyOnScreen() async throws {
        client.addPost("Already here")
        await viewModel.load()

        client.failures["feed_rows"] = HuddleServerError(message: "boom")
        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.posts.map(\.promptText), ["Already here"])
        XCTAssertEqual(viewModel.errorMessage, "boom")
    }

    // MARK: - Making picks

    func test_picking_aPickSlotHoldsOneOptionAndTappingAnotherReplacesIt() async throws {
        let post = client.addPost("One game")
        await viewModel.load()

        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [post.options[0]])

        viewModel.toggle(post.options[1], in: post.slotId, of: post.id)
        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [post.options[1]])
    }

    func test_picking_tappingTheChosenOptionAgainClearsIt() async throws {
        let post = client.addPost("One game")
        await viewModel.load()

        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)

        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [])
    }

    func test_picking_aSetStopsAtItsPickCount() async throws {
        let post = client.addPost("Pick two", slots: [["A", "B", "C"]], shape: "pick_set", pickCount: 2)
        await viewModel.load()

        for option in post.options { viewModel.toggle(option, in: post.slotId, of: post.id) }

        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [post.options[0], post.options[1]])
    }

    func test_picking_aRankingKeepsTheOrderItWasTappedIn() async throws {
        let post = client.addPost("Rank two", slots: [["A", "B", "C"]], shape: "rank", pickCount: 2)
        await viewModel.load()

        viewModel.toggle(post.options[2], in: post.slotId, of: post.id)
        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)

        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [post.options[2], post.options[0]])
    }

    func test_picking_lockInWaitsUntilEverySlotIsFilled() async throws {
        let post = client.addPost("Two games", slots: [["Chiefs", "Bills"], ["Eagles", "Cowboys"]])
        await viewModel.load()
        XCTAssertFalse(viewModel.canSubmit(post.id))

        viewModel.toggle(post.optionIds[0][0], in: post.slotIds[0], of: post.id)
        XCTAssertFalse(viewModel.canSubmit(post.id))

        viewModel.toggle(post.optionIds[1][1], in: post.slotIds[1], of: post.id)
        XCTAssertTrue(viewModel.canSubmit(post.id))
    }

    func test_picking_aPostThatHasLockedCannotBeAnswered() async throws {
        let locked = client.addPost("Closed", status: "locked", locksIn: -60)
        let pastItsLockTime = client.addPost("Still marked open", locksIn: -1)
        await viewModel.load()

        XCTAssertFalse(viewModel.canAnswer(locked.id))
        XCTAssertFalse(viewModel.canAnswer(pastItsLockTime.id))
    }

    func test_picking_anAnsweredPostCannotBeAnsweredAgain() async throws {
        let post = client.addPost("Done")
        client.viewerAlreadyAnswered(post, choosing: [post.slotId: [post.options[0]]])
        await viewModel.load()

        XCTAssertFalse(viewModel.canAnswer(post.id))
        XCTAssertFalse(viewModel.canSubmit(post.id))
    }

    // MARK: - Power Rankings

    private let league = ["KC", "BUF", "PHI", "BAL", "DET", "SF"]

    func test_powerRankings_carryTheirCoverTeamsAndAreToldApartFromPicks() async throws {
        client.addPowerRankingsPost("Rank the NFL", teams: league, cover: ["KC", "BUF", "PHI", "BAL", "DET", "SF"])
        client.addPost("A picks post", age: 60)

        await viewModel.load()

        let power = try XCTUnwrap(viewModel.posts.first { $0.isPowerRankings })
        XCTAssertEqual(power.coverTeamCodes, ["KC", "BUF", "PHI", "BAL", "DET", "SF"])
        XCTAssertTrue(power.isOpinion)
        XCTAssertFalse(try XCTUnwrap(viewModel.posts.first { !$0.isPowerRankings }).isPowerRankings)
    }

    func test_powerRankings_aBallotMayHoldFiveTenOrAll32_defaultingToFive() async throws {
        let post = client.addPowerRankingsPost("Rank the NFL", teams: league)
        await viewModel.load()

        XCTAssertEqual(viewModel.rankDepth(for: post.id), 5)
        viewModel.setRankDepth(10, for: post.id)
        XCTAssertEqual(viewModel.rankDepth(for: post.id), 10)
        viewModel.setRankDepth(7, for: post.id)
        XCTAssertEqual(viewModel.rankDepth(for: post.id), 10, "only 5, 10 and 32 are ballots the server accepts")
    }

    func test_powerRankings_theBallotFillsToTheChosenDepthNotTheSlotsCountOf32() async throws {
        let post = client.addPowerRankingsPost("Rank the NFL", teams: ["A", "B", "C", "D", "E", "F", "G"])
        await viewModel.load()

        for option in post.options { viewModel.toggle(option, in: post.slotId, of: post.id) }

        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), Array(post.options.prefix(5)))
        XCTAssertTrue(viewModel.canSubmit(post.id), "five of the default five is a complete ballot")
    }

    func test_powerRankings_aBallotShortOfItsDepthCannotBeSubmitted() async throws {
        let post = client.addPowerRankingsPost("Rank the NFL", teams: ["A", "B", "C", "D", "E", "F", "G"])
        await viewModel.load()
        for option in post.options.prefix(4) { viewModel.toggle(option, in: post.slotId, of: post.id) }
        XCTAssertFalse(viewModel.canSubmit(post.id))

        viewModel.toggle(post.options[4], in: post.slotId, of: post.id)
        XCTAssertTrue(viewModel.canSubmit(post.id))
        viewModel.setRankDepth(10, for: post.id)
        XCTAssertFalse(viewModel.canSubmit(post.id), "five teams no longer fill a top-10 ballot")
    }

    func test_powerRankings_goingShallowerDropsTheLowestRankedTeams() async throws {
        let post = client.addPowerRankingsPost("Rank the NFL", teams: (1...12).map { "T\($0)" })
        await viewModel.load()
        viewModel.setRankDepth(10, for: post.id)
        for option in post.options.prefix(10) { viewModel.toggle(option, in: post.slotId, of: post.id) }

        viewModel.setRankDepth(5, for: post.id)

        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), Array(post.options.prefix(5)))
        XCTAssertTrue(viewModel.canSubmit(post.id))
    }

    func test_powerRankings_draggingARowReordersTheBallot() async throws {
        let post = client.addPowerRankingsPost("Rank the NFL", teams: ["A", "B", "C", "D", "E"])
        await viewModel.load()
        for option in post.options { viewModel.toggle(option, in: post.slotId, of: post.id) }
        let o = post.options

        viewModel.moveRanked(from: 4, to: 0, in: post.slotId, of: post.id)
        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [o[4], o[0], o[1], o[2], o[3]])

        viewModel.moveRanked(from: 0, to: 2, in: post.slotId, of: post.id)
        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [o[0], o[1], o[4], o[2], o[3]])

        viewModel.moveRanked(from: 9, to: 0, in: post.slotId, of: post.id)
        XCTAssertEqual(
            viewModel.selection(in: post.slotId, of: post.id), [o[0], o[1], o[4], o[2], o[3]], "out of range is ignored"
        )
    }

    func test_powerRankings_lockInSendsTheBallotInRankOrder() async throws {
        let post = client.addPowerRankingsPost("Rank the NFL", teams: ["A", "B", "C", "D", "E", "F"])
        await viewModel.load()
        for option in post.options.prefix(5).reversed() { viewModel.toggle(option, in: post.slotId, of: post.id) }

        await viewModel.submitAnswer(post.id)

        XCTAssertEqual(client.submissions.first?.choices, [post.slotId: Array(post.options.prefix(5).reversed())])
        XCTAssertTrue(try onlyPost().viewerAnswered)
    }

    func test_powerRankings_aLockedPostCannotBeRanked() async throws {
        let post = client.addPowerRankingsPost("Rank the NFL", teams: league, status: "locked", locksIn: -60)
        await viewModel.load()

        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        viewModel.setRankDepth(10, for: post.id)

        XCTAssertTrue(viewModel.selection(in: post.slotId, of: post.id).isEmpty)
        XCTAssertEqual(viewModel.rankDepth(for: post.id), 5)
    }

    func test_powerRankings_theConsensusIsAskedForOnlyOnceRevealed() async throws {
        let open = client.addPowerRankingsPost("Open", teams: league, age: 60)
        let locked = client.addPowerRankingsPost("Locked", teams: league, status: "locked", age: 120, locksIn: -60)
        client.setPowerTopFive(for: locked, [
            PromptPowerTopFiveRow(optionId: locked.options[1], topFiveCount: 3, averageRank: 1.7),
            PromptPowerTopFiveRow(optionId: locked.options[0], topFiveCount: 2, averageRank: 2.5),
        ])

        await viewModel.load()

        XCTAssertEqual(client.powerTopFiveRequests, [locked.id], "an open, unanswered post must not leak the crowd's favourites")
        XCTAssertEqual(viewModel.post(locked.id)?.powerRankingTopFive.map(\.optionId), [locked.options[1], locked.options[0]])
        XCTAssertEqual(viewModel.post(locked.id)?.powerRankingTopFive.first?.topFiveCount, 3)
        XCTAssertEqual(viewModel.post(open.id)?.powerRankingTopFive, [])
    }

    func test_powerRankings_aFailedConsensusReadCostsThePostItsPanelNotTheFeed() async throws {
        let locked = client.addPowerRankingsPost("Locked", teams: league, status: "locked", locksIn: -60)
        client.addPost("A picks post", age: 60)
        client.failures["power_ranking_top_five"] = HuddleServerError(message: "boom")

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertEqual(viewModel.posts.count, 2)
        XCTAssertEqual(viewModel.post(locked.id)?.powerRankingTopFive, [])
    }

    func test_powerRankings_movementIsMeasuredAgainstTheLastEarlierBallot_byTeamCode() async throws {
        // Option ids differ from week to week, and so does the pool's order:
        // only the team code can tie one week's ballot to the next.
        let week1 = client.addPowerRankingsPost("Week 1", teams: league, status: "locked", age: 300, locksIn: -200)
        let week2 = client.addPowerRankingsPost("Week 2", teams: league.reversed(), status: "locked", age: 200, locksIn: -100)
        let week3 = client.addPowerRankingsPost("Week 3", teams: league, age: 10)
        func option(_ team: String, in post: FakeHuddleClient.AddedPost, teams: [String]) -> UUID {
            post.options[teams.firstIndex(of: team)!]
        }
        client.viewerAlreadyAnswered(week1, choosing: [week1.slotId: ["KC", "BUF", "PHI"].map { option($0, in: week1, teams: league) }])
        client.viewerAlreadyAnswered(week2, choosing: [week2.slotId: ["BUF", "KC", "DET", "PHI", "SF"].map { option($0, in: week2, teams: league.reversed()) }])

        await viewModel.load()

        XCTAssertEqual(viewModel.post(week1.id)?.previousRankByTeam, [:], "there is nothing before the first week")
        XCTAssertEqual(viewModel.post(week2.id)?.previousRankByTeam, ["KC": 1, "BUF": 2, "PHI": 3])
        XCTAssertEqual(
            viewModel.post(week3.id)?.previousRankByTeam,
            ["BUF": 1, "KC": 2, "DET": 3, "PHI": 4, "SF": 5],
            "the newest week compares against the most recent ballot, not the first"
        )
    }

    func test_powerRankings_aWeekTheViewerSkippedLeavesTheOlderBallotInForce() async throws {
        let week1 = client.addPowerRankingsPost("Week 1", teams: league, status: "locked", age: 300, locksIn: -200)
        let week2 = client.addPowerRankingsPost("Week 2", teams: league, status: "locked", age: 200, locksIn: -100)
        let week3 = client.addPowerRankingsPost("Week 3", teams: league, age: 10)
        client.viewerAlreadyAnswered(week1, choosing: [week1.slotId: [week1.options[2], week1.options[0]]])

        await viewModel.load()

        XCTAssertEqual(viewModel.post(week2.id)?.previousRankByTeam, ["PHI": 1, "KC": 2])
        XCTAssertEqual(viewModel.post(week3.id)?.previousRankByTeam, ["PHI": 1, "KC": 2])
    }

    // MARK: - Locking in

    func test_lockIn_sendsTheTicketAndTheTakeTogether_thenShowsThePostAnswered() async throws {
        let post = client.addPost("Two games", slots: [["Chiefs", "Bills"], ["Eagles", "Cowboys"]])
        client.setAggregate(for: post, [
            PromptAggregateRow(slotId: post.slotIds[0], optionId: post.optionIds[0][0], pct: 100, totalResponses: 1),
        ])
        await viewModel.load()
        viewModel.toggle(post.optionIds[0][0], in: post.slotIds[0], of: post.id)
        viewModel.toggle(post.optionIds[1][1], in: post.slotIds[1], of: post.id)
        viewModel.setTakeDraft("  Home teams cover  ", for: post.id)

        await viewModel.submitAnswer(post.id)

        XCTAssertEqual(client.submissions, [
            .init(
                postId: post.id,
                choices: [post.slotIds[0]: [post.optionIds[0][0]], post.slotIds[1]: [post.optionIds[1][1]]],
                comment: "Home teams cover"
            ),
        ])
        let after = try onlyPost()
        XCTAssertTrue(after.viewerAnswered)
        XCTAssertEqual(after.comments.map(\.body), ["Home teams cover"])
        XCTAssertEqual(after.comments.first?.isViewer, true)
        XCTAssertNotNil(after.aggregate, "answering is what unlocks how everyone else picked")
        XCTAssertNil(viewModel.errorMessage)
    }

    func test_lockIn_withoutWordsSendsNoCommentAndLeavesAnEmptyTake() async throws {
        let post = client.addPost("One game")
        await viewModel.load()
        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        viewModel.setTakeDraft("   ", for: post.id)

        await viewModel.submitAnswer(post.id)

        XCTAssertEqual(client.submissions.map(\.comment), [nil])
        // The server still leaves a take for the answer (0208), with nothing written.
        XCTAssertEqual(try onlyPost().comments.map(\.body), [""])
        XCTAssertEqual(viewModel.yourTake(on: post.id)?.hasWords, false)
    }

    func test_lockIn_clearsTheDraftOnceItLands() async throws {
        let post = client.addPost("One game")
        await viewModel.load()
        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        viewModel.setTakeDraft("Chiefs", for: post.id)

        await viewModel.submitAnswer(post.id)

        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [])
        XCTAssertEqual(viewModel.takeDraft(for: post.id), "")
    }

    func test_lockIn_whenTheServerRefusesTheDraftSurvivesAndTheReasonShows() async throws {
        let post = client.addPost("One game")
        await viewModel.load()
        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        viewModel.setTakeDraft("Chiefs", for: post.id)
        client.failures["submit_response"] = HuddleServerError(message: "post_locked")

        await viewModel.submitAnswer(post.id)

        XCTAssertEqual(viewModel.errorMessage, "This prompt has locked — no more picks.")
        XCTAssertEqual(viewModel.selection(in: post.slotId, of: post.id), [post.options[0]])
        XCTAssertEqual(viewModel.takeDraft(for: post.id), "Chiefs")
        XCTAssertFalse(try onlyPost().viewerAnswered)
        XCTAssertFalse(viewModel.isSending)
    }

    func test_lockIn_doesNothingWhileThePicksAreIncomplete() async throws {
        let post = client.addPost("Two games", slots: [["Chiefs", "Bills"], ["Eagles", "Cowboys"]])
        await viewModel.load()
        viewModel.toggle(post.optionIds[0][0], in: post.slotIds[0], of: post.id)

        await viewModel.submitAnswer(post.id)

        XCTAssertTrue(client.submissions.isEmpty)
    }

    func test_lockIn_aTakeIsCappedAtTheServersLimit() async throws {
        let post = client.addPost("One game")
        await viewModel.load()

        viewModel.setTakeDraft(String(repeating: "x", count: 400), for: post.id)

        XCTAssertEqual(viewModel.takeDraft(for: post.id).count, 280)
    }

    // MARK: - Who sees which takes

    func test_takesOnScreen_otherPlayersTakesStayLockedUntilTheViewerAnswers() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat")
        client.anotherPlayerPosts("Hot take", on: post, by: sam)
        await viewModel.load()

        XCTAssertEqual(viewModel.otherTakes(on: post.id), [])

        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        await viewModel.submitAnswer(post.id)

        XCTAssertEqual(viewModel.otherTakes(on: post.id).map(\.body), ["Hot take"])
    }

    func test_takesOnScreen_aLockedPromptShowsOtherPlayersTakesToSomeoneWhoSkippedIt() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Locked chat", status: "locked", locksIn: -60)
        client.anotherPlayerPosts("Hot take", on: post, by: sam)
        await viewModel.load()

        XCTAssertFalse(viewModel.posts.first?.viewerAnswered ?? true)
        XCTAssertEqual(viewModel.otherTakes(on: post.id).map(\.body), ["Hot take"])
    }

    func test_takesOnScreen_theViewersOwnTakeIsSeparateFromTheOthers() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat")
        client.anotherPlayerPosts("Theirs", on: post, by: sam)
        await viewModel.load()
        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        viewModel.setTakeDraft("Mine", for: post.id)
        await viewModel.submitAnswer(post.id)

        XCTAssertEqual(viewModel.yourTake(on: post.id)?.body, "Mine")
        XCTAssertEqual(viewModel.otherTakes(on: post.id).map(\.body), ["Theirs"])
    }

    // MARK: - Replying

    func test_reply_isPostedUnderTheTakeAndShowsInItsThread() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat")
        let take = client.anotherPlayerPosts("Hot take", on: post, by: sam)
        client.viewerAlreadyAnswered(post, choosing: [post.slotId: [post.options[0]]])
        await viewModel.load()
        viewModel.setReplyDraft("  Disagree  ", for: take)

        await viewModel.sendReply(to: take, on: post.id)

        XCTAssertEqual(client.postedComments, [.init(postId: post.id, body: "Disagree", parentCommentId: take)])
        let replies = try XCTUnwrap(viewModel.otherTakes(on: post.id).first?.replies)
        XCTAssertEqual(replies.map(\.body), ["Disagree"])
        XCTAssertEqual(replies.first?.isViewer, true)
        XCTAssertEqual(viewModel.replyDraft(for: take), "")
    }

    func test_reply_anEmptyReplyIsNotSent() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat")
        let take = client.anotherPlayerPosts("Hot take", on: post, by: sam)
        client.viewerAlreadyAnswered(post, choosing: [post.slotId: [post.options[0]]])
        await viewModel.load()
        viewModel.setReplyDraft("   ", for: take)

        await viewModel.sendReply(to: take, on: post.id)

        XCTAssertTrue(client.postedComments.isEmpty)
    }

    func test_reply_whenTheServerRefusesTheDraftSurvivesAndTheReasonShows() async throws {
        let sam = client.addProfile(named: "Sam")
        let post = client.addPost("Chat")
        let take = client.anotherPlayerPosts("Hot take", on: post, by: sam)
        client.viewerAlreadyAnswered(post, choosing: [post.slotId: [post.options[0]]])
        await viewModel.load()
        viewModel.setReplyDraft("Disagree", for: take)
        client.failures["post_comment"] = HuddleServerError(message: "parent_not_found")

        await viewModel.sendReply(to: take, on: post.id)

        XCTAssertEqual(viewModel.errorMessage, "That take isn't available anymore. Refresh and try again.")
        XCTAssertEqual(viewModel.replyDraft(for: take), "Disagree")
    }

    // MARK: - A post past its lock time that the server still calls open

    // Nothing on the server ever writes `status = 'locked'` (see `0096`):
    // `lock_at` is checked live, so a post stays `open` past it until it is
    // resolved. That is the ordinary state of every game in progress.

    func test_pastLockTime_anUnansweredPostStillShowsHowEveryoneAnswered() async throws {
        let post = client.addPost("Kicked off", locksIn: -60)
        client.setAggregate(for: post, [
            PromptAggregateRow(slotId: post.slotId, optionId: post.options[0], pct: 60, totalResponses: 5),
            PromptAggregateRow(slotId: post.slotId, optionId: post.options[1], pct: 40, totalResponses: 5),
        ])

        await viewModel.load()

        let loaded = try onlyPost()
        XCTAssertFalse(viewModel.canAnswer(post.id))
        XCTAssertEqual(loaded.aggregate?[post.slotId]?[post.options[0]], 60)
        XCTAssertEqual(loaded.responseCount, 5)
    }

    func test_pastLockTime_theFeedOffersResultsNotPicks() async {
        let post = client.addPost("Kicked off", locksIn: -60)
        await viewModel.load()

        XCTAssertEqual(viewModel.callToAction(for: post.id), .seeResults)
    }

    // MARK: - What a prompt's card invites you to do

    func test_callToAction_anOpenPromptYouHaveNotAnsweredInvitesPicks() async {
        let post = client.addPost("Open")
        await viewModel.load()

        XCTAssertEqual(viewModel.callToAction(for: post.id), .makePicks)
    }

    func test_callToAction_anOpenPromptYouAnsweredLetsYouReviewYourPicks() async {
        let post = client.addPost("Open")
        client.viewerAlreadyAnswered(post, choosing: [post.slotId: [post.options[0]]])
        await viewModel.load()

        XCTAssertEqual(viewModel.callToAction(for: post.id), .viewPicks)
    }

    func test_callToAction_aClosedPromptYouAnsweredLeadsToTheTakes() async {
        let post = client.addPost("Closed", status: "resolved", locksIn: -60)
        client.viewerAlreadyAnswered(post, choosing: [post.slotId: [post.options[0]]])
        await viewModel.load()

        XCTAssertEqual(viewModel.callToAction(for: post.id), .seeTakes)
    }

    func test_callToAction_aClosedPromptYouSkippedLeadsToTheResults() async {
        let post = client.addPost("Closed", status: "resolved", locksIn: -60)
        await viewModel.load()

        XCTAssertEqual(viewModel.callToAction(for: post.id), .seeResults)
    }

    // MARK: - Overlapping and cancelled reads

    func test_load_aCancelledReadIsNotAnError() async {
        client.addPost("Here")
        await viewModel.load()

        client.failures["feed_rows"] = CancellationError()
        await viewModel.load()

        XCTAssertNil(viewModel.errorMessage, "a pull-to-refresh that was let go of is not a failure")
        XCTAssertEqual(viewModel.phase, .loaded)
    }

    func test_load_aCancelledFirstReadDoesNotLeaveTheScreenFailed() async {
        client.failures["feed_rows"] = URLError(.cancelled)

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .loading)
    }

    func test_load_aSlowEarlierReadNeverOverwritesANewerOne() async throws {
        client.addPost("Old")
        client.holdNextFeedRead()
        let slow = Task { await viewModel.load() }
        for _ in 0..<500 where client.heldFeedReads == 0 { await Task.yield() }
        XCTAssertEqual(client.heldFeedReads, 1, "the first read never parked")

        client.addPost("New")
        await viewModel.load()
        client.releaseHeldFeedReads()
        await slow.value

        XCTAssertEqual(Set(viewModel.posts.map(\.promptText)), ["Old", "New"], "the late answer, which predates New, won")
    }

    // MARK: - Weekly Awards

    private let mahomes = NFLPlayer(id: "00-0033873", name: "Patrick Mahomes", position: "QB", team: "KC")
    private let allen = NFLPlayer(id: "00-0034857", name: "Josh Allen", position: "QB", team: "BUF")

    /// Answers every Weekly Awards slot of `post`: the first option of the team
    /// and game slots, and `player` for the three search slots.
    private func answerEverySlot(of post: FakeHuddleClient.AddedPost, with player: NFLPlayer) {
        for index in 0..<3 { viewModel.toggle(post.optionIds[index][0], in: post.slotIds[index], of: post.id) }
        for index in 3..<6 { viewModel.setPlayer(player, in: post.slotIds[index], of: post.id) }
    }

    func test_weeklyAwards_isAPlayablePostWithThreePlayerSlots() async throws {
        client.addWeeklyAwardsPost()
        await viewModel.load()

        let post = try onlyPost()
        XCTAssertFalse(post.isUnsupported)
        XCTAssertTrue(post.isWeeklyAwards)
        XCTAssertEqual(post.slots.map(\.playerSearch), [false, false, false, true, true, true])
        XCTAssertEqual(post.slots[2].options.compactMap { $0.gameTeamCodes?.away }, ["KC", "PHI"])
        XCTAssertTrue(viewModel.canAnswer(post.id))
        XCTAssertEqual(viewModel.callToAction(for: post.id), .makePicks)
    }

    func test_weeklyAwards_needsAllSixAnswersBeforeItCanBeLockedIn() async throws {
        let added = client.addWeeklyAwardsPost()
        client.addPlayers([mahomes])
        await viewModel.load()

        XCTAssertFalse(viewModel.canSubmit(added.id))
        for index in 0..<3 { viewModel.toggle(added.optionIds[index][0], in: added.slotIds[index], of: added.id) }
        XCTAssertFalse(viewModel.canSubmit(added.id), "the players are still missing")

        viewModel.setPlayer(mahomes, in: added.slotIds[3], of: added.id)
        viewModel.setPlayer(mahomes, in: added.slotIds[4], of: added.id)
        XCTAssertFalse(viewModel.canSubmit(added.id))

        viewModel.setPlayer(mahomes, in: added.slotIds[5], of: added.id)
        XCTAssertTrue(viewModel.canSubmit(added.id))

        viewModel.setPlayer(nil, in: added.slotIds[5], of: added.id)
        XCTAssertFalse(viewModel.canSubmit(added.id), "clearing a player takes the answer back")
    }

    func test_weeklyAwards_aPlayerCanOnlyBeChosenForASearchSlotAndAnOptionOnlyForTheOthers() async throws {
        let added = client.addWeeklyAwardsPost()
        await viewModel.load()

        viewModel.setPlayer(mahomes, in: added.slotIds[0], of: added.id)
        XCTAssertNil(viewModel.player(in: added.slotIds[0], of: added.id), "a team slot takes no player")

        viewModel.toggle(UUID(), in: added.slotIds[3], of: added.id)
        XCTAssertTrue(viewModel.selection(in: added.slotIds[3], of: added.id).isEmpty, "a search slot takes no option")

        viewModel.toggle(added.optionIds[0][1], in: added.slotIds[0], of: added.id)
        viewModel.toggle(added.optionIds[0][0], in: added.slotIds[0], of: added.id)
        XCTAssertEqual(viewModel.selection(in: added.slotIds[0], of: added.id), [added.optionIds[0][0]], "a second tap elsewhere replaces")
        viewModel.toggle(added.optionIds[0][0], in: added.slotIds[0], of: added.id)
        XCTAssertTrue(viewModel.selection(in: added.slotIds[0], of: added.id).isEmpty, "a tap on the chosen team clears it")
    }

    func test_weeklyAwards_lockingInSendsPlayersAsIdsAndTeamsAsOptions() async throws {
        let added = client.addWeeklyAwardsPost()
        client.addPlayers([mahomes])
        await viewModel.load()
        answerEverySlot(of: added, with: mahomes)
        viewModel.setTakeDraft("Chiefs all day", for: added.id)

        await viewModel.submitAnswer(added.id)

        let sent = try XCTUnwrap(client.submissions.first)
        XCTAssertEqual(Set(sent.choices.keys), Set(added.slotIds.prefix(3)))
        XCTAssertEqual(sent.players, [added.slotIds[3]: mahomes.id, added.slotIds[4]: mahomes.id, added.slotIds[5]: mahomes.id])
        XCTAssertEqual(sent.comment, "Chiefs all day")
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.player(in: added.slotIds[3], of: added.id), "the draft is cleared once it is in")

        // Read back, the ballot's player slots hold the options the server made.
        let post = try XCTUnwrap(viewModel.post(added.id))
        XCTAssertTrue(post.viewerAnswered)
        let chosen = try XCTUnwrap(post.viewerResponse?[added.slotIds[3]]?.first)
        XCTAssertEqual(post.slots[3].options.first { $0.id == chosen }?.label, "Patrick Mahomes")
        XCTAssertEqual(viewModel.callToAction(for: added.id), .viewPicks)
    }

    func test_weeklyAwards_aRefusedBallotKeepsEveryAnswer() async throws {
        let added = client.addWeeklyAwardsPost()
        client.addPlayers([mahomes])
        await viewModel.load()
        answerEverySlot(of: added, with: mahomes)
        client.failures["submit_response"] = HuddleServerError(message: "invalid_option")

        await viewModel.submitAnswer(added.id)

        XCTAssertEqual(viewModel.errorMessage, "One of those picks isn't valid anymore. Refresh and try again.")
        XCTAssertEqual(viewModel.player(in: added.slotIds[3], of: added.id), mahomes)
        XCTAssertEqual(viewModel.selection(in: added.slotIds[0], of: added.id), [added.optionIds[0][0]])
        XCTAssertTrue(viewModel.canSubmit(added.id))
    }

    func test_weeklyAwards_playerSearchGoesToTheDirectory() async throws {
        client.addPlayers([mahomes, allen])
        let found = try await viewModel.searchPlayers("josh")

        XCTAssertEqual(found, [allen])
        XCTAssertEqual(client.playerSearches, ["josh"])
    }

    func test_weeklyAwards_aLockedPostTakesNoPlayers() async throws {
        let added = client.addWeeklyAwardsPost(locksIn: -60)
        await viewModel.load()

        viewModel.setPlayer(mahomes, in: added.slotIds[3], of: added.id)

        XCTAssertNil(viewModel.player(in: added.slotIds[3], of: added.id))
        XCTAssertFalse(viewModel.canAnswer(added.id))
    }

    // MARK: - Bold Predictions

    private let chiefs = BoldTarget(type: .team, id: "KC")

    func test_bold_isAPlayablePostWithNoSlots() async throws {
        client.addBoldPredictionsPost()
        await viewModel.load()

        let post = try onlyPost()
        XCTAssertFalse(post.isUnsupported)
        XCTAssertTrue(post.isBoldPredictions)
        XCTAssertTrue(post.slots.isEmpty)
        XCTAssertNil(post.aggregate, "there is nothing to aggregate")
        XCTAssertFalse(post.viewerAnswered)
        XCTAssertTrue(viewModel.canAnswer(post.id))
        XCTAssertTrue(client.aggregateRequests.isEmpty)
        XCTAssertTrue(client.revealedRequests.isEmpty)
    }

    func test_bold_theCardInvitesPredictionsWhileOpenAndShowsThemOnceLocked() async throws {
        let open = client.addBoldPredictionsPost("Open", locksIn: 3600)
        let locked = client.addBoldPredictionsPost("Locked", locksIn: -60)
        await viewModel.load()

        XCTAssertEqual(viewModel.callToAction(for: open.id), .makePredictions)
        XCTAssertEqual(viewModel.callToAction(for: open.id).label, "Make your predictions")
        XCTAssertEqual(viewModel.callToAction(for: locked.id), .seePredictions)
        XCTAssertEqual(viewModel.callToAction(for: locked.id).label, "See predictions")
    }

    func test_bold_draftsAreKeptTrimmedAndCappedAtFive() async throws {
        let added = client.addBoldPredictionsPost()
        await viewModel.load()

        XCTAssertFalse(viewModel.addPrediction(BoldDraft(body: "   ", target: chiefs), to: added.id), "words are required")
        XCTAssertFalse(viewModel.addPrediction(BoldDraft(body: String(repeating: "a", count: 281), target: chiefs), to: added.id))
        XCTAssertTrue(viewModel.addPrediction(BoldDraft(body: String(repeating: "a", count: 280), target: chiefs), to: added.id))
        XCTAssertTrue(viewModel.addPrediction(BoldDraft(body: "  Chiefs go 17-0  ", target: chiefs), to: added.id))
        XCTAssertEqual(viewModel.boldDraftList(for: added.id)[1].body, "Chiefs go 17-0")

        for number in 3...5 {
            XCTAssertTrue(viewModel.addPrediction(BoldDraft(body: "Call \(number)", target: chiefs), to: added.id))
        }
        XCTAssertFalse(viewModel.canAddPrediction(to: added.id))
        XCTAssertFalse(viewModel.addPrediction(BoldDraft(body: "One too many", target: chiefs), to: added.id))
        XCTAssertEqual(viewModel.boldDraftList(for: added.id).count, 5)
    }

    func test_bold_aDraftCanBeEditedAndRemovedBeforeLockingIn() async throws {
        let added = client.addBoldPredictionsPost()
        await viewModel.load()
        viewModel.addPrediction(BoldDraft(body: "First", target: chiefs), to: added.id)
        viewModel.addPrediction(BoldDraft(body: "Second", target: chiefs), to: added.id)

        let bills = BoldTarget(type: .team, id: "BUF")
        XCTAssertTrue(viewModel.replacePrediction(at: 0, with: BoldDraft(body: "  Edited ", target: bills), in: added.id))
        XCTAssertFalse(viewModel.replacePrediction(at: 0, with: BoldDraft(body: "", target: bills), in: added.id))
        XCTAssertFalse(viewModel.replacePrediction(at: 9, with: BoldDraft(body: "Nope", target: bills), in: added.id))
        XCTAssertEqual(viewModel.boldDraftList(for: added.id).map(\.body), ["Edited", "Second"])
        XCTAssertEqual(viewModel.boldDraftList(for: added.id)[0].target, bills)

        viewModel.removePrediction(at: 0, from: added.id)
        XCTAssertEqual(viewModel.boldDraftList(for: added.id).map(\.body), ["Second"])
    }

    func test_bold_lockingInNeedsAtLeastOnePrediction() async throws {
        let added = client.addBoldPredictionsPost()
        await viewModel.load()
        XCTAssertFalse(viewModel.canLockInPredictions(added.id))

        await viewModel.lockInPredictions(added.id)
        XCTAssertTrue(client.boldSubmissions.isEmpty)

        viewModel.addPrediction(BoldDraft(body: "Chiefs go 17-0", target: chiefs), to: added.id)
        XCTAssertTrue(viewModel.canLockInPredictions(added.id))
    }

    func test_bold_lockingInSendsTheWholeResponseAndRevealsEveryoneElses() async throws {
        let added = client.addBoldPredictionsPost()
        let sam = client.addProfile(named: "Sam", username: "sam_k")
        client.anotherPlayerPredicts("Jets win the division", on: added, by: sam, tagging: BoldTarget(type: .team, id: "NYJ"), secondsAfterEpoch: 30)
        await viewModel.load()

        var post = try onlyPost()
        XCTAssertTrue(post.boldPredictions.isEmpty, "before answering, only your own predictions are readable")
        XCTAssertEqual(post.predictionCount, 1, "but how many have been made is public")

        viewModel.addPrediction(BoldDraft(body: "Chiefs go 17-0", target: chiefs), to: added.id)
        viewModel.addPrediction(BoldDraft(body: "Mahomes wins MVP", target: BoldTarget(type: .player, id: mahomes.id)), to: added.id)
        await viewModel.lockInPredictions(added.id)

        XCTAssertEqual(client.boldSubmissions, [
            .init(postId: added.id, predictions: [
                BoldDraft(body: "Chiefs go 17-0", target: chiefs),
                BoldDraft(body: "Mahomes wins MVP", target: BoldTarget(type: .player, id: mahomes.id)),
            ])
        ])
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.boldDraftList(for: added.id).isEmpty, "the drafts are cleared once they are in")

        post = try onlyPost()
        XCTAssertTrue(post.viewerAnswered)
        XCTAssertFalse(viewModel.canAnswer(added.id), "the response is final")
        XCTAssertEqual(post.predictionCount, 3)
        // Oldest first: the viewer's two were written at +0s and +1s, Sam's at +30s.
        XCTAssertEqual(post.boldPredictions.map(\.body), ["Chiefs go 17-0", "Mahomes wins MVP", "Jets win the division"])
        let others = post.boldPredictions.filter { !$0.isViewer }
        XCTAssertEqual(others.map(\.author), ["Sam"])
        XCTAssertEqual(others.first?.authorUsername, "sam_k")
        XCTAssertEqual(others.first?.target, BoldTarget(type: .team, id: "NYJ"))
    }

    func test_bold_aRefusedResponseKeepsTheDraftsAndSaysWhy() async throws {
        let added = client.addBoldPredictionsPost()
        await viewModel.load()
        viewModel.addPrediction(BoldDraft(body: "Chiefs go 17-0", target: chiefs), to: added.id)
        client.failures["submit_bold_predictions"] = HuddleServerError(message: "invalid_target")

        await viewModel.lockInPredictions(added.id)

        XCTAssertEqual(viewModel.errorMessage, "That tag isn't valid for this post anymore. Pick another.")
        XCTAssertEqual(viewModel.boldDraftList(for: added.id).count, 1)
        XCTAssertFalse(try onlyPost().viewerAnswered)
    }

    func test_bold_aSecondResponseIsRefusedByTheServer() async throws {
        let added = client.addBoldPredictionsPost()
        // A second phone that read the feed before the first one answered.
        let stale = HuddleViewModel(client: client, viewerId: viewerId, now: { [client] in client!.epoch })
        await stale.load()
        await viewModel.load()
        viewModel.addPrediction(BoldDraft(body: "First response", target: chiefs), to: added.id)
        await viewModel.lockInPredictions(added.id)

        XCTAssertTrue(stale.canAnswer(added.id), "it has not heard yet")
        stale.addPrediction(BoldDraft(body: "Second response", target: chiefs), to: added.id)
        await stale.lockInPredictions(added.id)

        XCTAssertEqual(stale.errorMessage, "You've already locked in your predictions.")
        XCTAssertEqual(client.boldSubmissions.count, 1)
        XCTAssertEqual(stale.boldDraftList(for: added.id).count, 1, "the refused draft stays where it was")
    }

    func test_bold_theBoardReadsTheWeeksGamesAndTheTaggedPlayers() async throws {
        let added = client.addBoldPredictionsPost()
        client.addPlayers([mahomes, allen])
        client.setWeekGames([NFLScheduleGame(id: "2026_03_KC_BUF", away: "KC", home: "BUF")])
        await viewModel.load()
        viewModel.addPrediction(BoldDraft(body: "Mahomes wins MVP", target: BoldTarget(type: .player, id: mahomes.id)), to: added.id)
        await viewModel.lockInPredictions(added.id)

        let board = viewModel.boldBoard(for: added.id)
        XCTAssertEqual(board.weekGames.map(\.id), ["2026_03_KC_BUF"])
        XCTAssertEqual(board.players[mahomes.id], mahomes, "a tagged player is looked up so the tag can show a name and headshot")
        XCTAssertNil(board.players[allen.id])
    }

    func test_bold_aScheduleOutageCostsTheTagsTheirArtNotThePost() async throws {
        let added = client.addBoldPredictionsPost()
        client.failures["week_games"] = HuddleServerError(message: "boom")
        await viewModel.load()

        await viewModel.loadBoldBoard(added.id)

        XCTAssertEqual(viewModel.phase, .loaded)
        XCTAssertTrue(viewModel.boldBoard(for: added.id).weekGames.isEmpty)
        XCTAssertNotNil(viewModel.boldBoards[added.id], "loaded, just empty — so the picker says so instead of spinning")
    }

    // MARK: - Winner and margin

    func test_gamePick_aGameWithMarginChoicesIsDrawnAsAGameAndAnsweredWithOneChoice() async throws {
        let added = client.addMarginPost("Who wins Chiefs @ Bills?")
        await viewModel.load()

        let post = try onlyPost()
        XCTAssertTrue(post.isMatchupPost, "it gets the game cover, not the generic option strip")
        XCTAssertNotNil(post.slots[0].marginGame)
        XCTAssertEqual(post.slots[0].matchup?.away.label, "Chiefs")
        XCTAssertFalse(viewModel.canSubmit(added.id))

        // Chiefs by 7+, then a second tap elsewhere replaces it.
        viewModel.toggle(added.optionIds[0][1], in: added.slotId, of: added.id)
        viewModel.toggle(added.optionIds[0][2], in: added.slotId, of: added.id)
        XCTAssertEqual(viewModel.selection(in: added.slotId, of: added.id), [added.optionIds[0][2]])
        XCTAssertTrue(viewModel.canSubmit(added.id))

        await viewModel.submitAnswer(added.id)

        XCTAssertEqual(client.submissions.first?.choices, [added.slotId: [added.optionIds[0][2]]])
        XCTAssertEqual(try onlyPost().viewerResponse?[added.slotId], [added.optionIds[0][2]])
    }

    func test_weeklyPicks_everyGameWithMarginChoicesNeedsOne() async throws {
        let added = client.addMarginPost(
            "Week 3", games: [(("Chiefs", "KC"), ("Bills", "BUF")), (("Eagles", "PHI"), ("Cowboys", "DAL"))]
        )
        await viewModel.load()

        XCTAssertTrue(try onlyPost().hasMarginGames)
        viewModel.toggle(added.optionIds[0][0], in: added.slotIds[0], of: added.id)
        XCTAssertFalse(viewModel.canSubmit(added.id), "the second game is still open")
        viewModel.toggle(added.optionIds[1][3], in: added.slotIds[1], of: added.id)
        XCTAssertTrue(viewModel.canSubmit(added.id))
    }
}

