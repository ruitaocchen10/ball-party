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

    func test_feed_showsPicksPostsOnly_likeTheWebHome() async throws {
        client.addPost("A picks post")
        client.addPost("A ranking post", kind: "ranking")
        client.addPost("A stat leader post", kind: "stat_leader")
        client.addPost("A legacy game pick", kind: "game_pick")
        client.addPost("A status from the future", status: "postponed")

        await viewModel.load()

        XCTAssertEqual(Set(viewModel.posts.map(\.promptText)), ["A picks post", "A legacy game pick"])
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

    func test_lockIn_withoutATakeSendsNoComment() async throws {
        let post = client.addPost("One game")
        await viewModel.load()
        viewModel.toggle(post.options[0], in: post.slotId, of: post.id)
        viewModel.setTakeDraft("   ", for: post.id)

        await viewModel.submitAnswer(post.id)

        XCTAssertEqual(client.submissions.map(\.comment), [nil])
        XCTAssertTrue(try onlyPost().comments.isEmpty)
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
}
