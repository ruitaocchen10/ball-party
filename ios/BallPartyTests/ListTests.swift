import Foundation
import SwiftUI
@testable import BallParty
import XCTest

/// The pure rules of ranking lists: movement marks, moving, resizing, titles and the
/// words for the server's refusals. Mirrors `webapp/lib/foundation/lists/lists.test.ts`.
final class ListLogicTests: XCTestCase {
    func testMoveItemShiftsTheOnesBetween() {
        XCTAssertEqual(ListLogic.moveItem(["a", "b", "c", "d"], from: 3, to: 0), ["d", "a", "b", "c"])
        XCTAssertEqual(ListLogic.moveItem(["a", "b", "c"], from: 0, to: 2), ["b", "c", "a"])
        XCTAssertEqual(ListLogic.moveItem(["a", "b"], from: 0, to: 5), ["a", "b"])
    }

    func testPlaceChangeIsPositiveWhenAnItemClimbed() {
        let previous = ["a", "b", "c"]
        XCTAssertEqual(ListLogic.placeChange(previous: previous, items: ["c", "a", "b"], index: 0), 2)
        XCTAssertEqual(ListLogic.placeChange(previous: previous, items: ["c", "a", "b"], index: 1), -1)
        XCTAssertEqual(ListLogic.placeChange(previous: previous, items: previous, index: 1), 0)
        XCTAssertNil(ListLogic.placeChange(previous: previous, items: ["x", "a", "b"], index: 0))
        XCTAssertNil(ListLogic.placeChange(previous: nil, items: previous, index: 0))
    }

    func testMovementReadsDashForNewAndUnchanged() {
        XCTAssertEqual(ListMovement(change: nil).text, "–")
        XCTAssertEqual(ListMovement(change: 0).text, "–")
        XCTAssertEqual(ListMovement(change: 3).text, "+3")
        XCTAssertEqual(ListMovement(change: -2).text, "−2")
        XCTAssertEqual(ListMovement(change: nil).spoken, "New")
        XCTAssertEqual(ListMovement(change: 0).spoken, "Did not move")
    }

    func testMovedCountCountsPlacesHoldingADifferentItem() {
        XCTAssertEqual(ListLogic.movedCount(previous: ["a", "b", "c"], items: ["a", "c", "b"]), 2)
        XCTAssertEqual(ListLogic.movedCount(previous: nil, items: ["a", "b"]), 2)
    }

    func testTheRamsAreLARNeverLA() {
        XCTAssertTrue(ListLogic.teamCodes.contains("LAR"))
        XCTAssertFalse(ListLogic.teamCodes.contains("LA"))
        XCTAssertEqual(ListLogic.teamName("LAR"), "Rams")
    }

    func testResizeCutsFromTheBottomOrFillsFromTheBench() {
        XCTAssertEqual(ListLogic.resizeTeams(["KC", "BUF", "DET"], to: 2), ["KC", "BUF"])
        let filled = ListLogic.resizeTeams(["KC"], to: 3)
        XCTAssertEqual(filled, ["KC", "ARI", "ATL"])
        XCTAssertEqual(ListLogic.resizeTeams([], to: 32).count, 32)
        XCTAssertEqual(Set(ListLogic.teamCodes).count, 32)
    }

    func testTitlesAndSizes() {
        XCTAssertEqual(ListLogic.title(kind: "power_rankings", itemKind: .team, size: 32, versionNo: 2), "My power rankings - V2")
        XCTAssertEqual(ListLogic.title(kind: "qb", itemKind: .player, size: 10, versionNo: 3), "My top 10 QBs - V3")
        XCTAssertEqual(ListLogic.title(kind: "qb", itemKind: .player, size: 10), "My top 10 QBs")
        XCTAssertEqual(ListLogic.sizeLabel(32, itemKind: .team), "All 32")
        XCTAssertEqual(ListLogic.sizeLabel(10, itemKind: .player), "Top 10")
        XCTAssertEqual(ListLogic.surname("Amon-Ra St. Brown"), "St. Brown")
        XCTAssertEqual(ListLogic.surname("Mahomes"), "Mahomes")
    }

    func testGridFillsDownColumnsFirst() {
        XCTAssertEqual(ListGrid<EmptyView>.columns(for: 5), 1)
        XCTAssertEqual(ListGrid<EmptyView>.columns(for: 10), 2)
        XCTAssertEqual(ListGrid<EmptyView>.columns(for: 32), 4)
    }

    func testSaveErrorsAreInThePlayersWords() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = ISO8601DateFormatter().string(from: now.addingTimeInterval(3 * 3600 + 10))
        XCTAssertEqual(
            ListLogic.saveErrorMessage(ListsServerError(message: "edit_limit", detail: soon), now: now),
            "You saved this list in the last 24 hours. You can save again in 3 hours."
        )
        XCTAssertEqual(
            ListLogic.saveErrorMessage(ListsServerError(message: "edit_limit", detail: nil), now: now),
            "You saved this list in the last 24 hours. Try again later."
        )
        XCTAssertEqual(
            ListLogic.saveErrorMessage(ListsServerError(message: "no_change", detail: nil)),
            "That's the same as your saved list. Move something first."
        )
        XCTAssertEqual(
            ListLogic.saveErrorMessage(ListsServerError(message: "prompt_open", detail: "x")),
            "This week's prompt for this list is open. Answer it to update your list."
        )
    }
}

@MainActor
final class ListEditorViewModelTests: XCTestCase {
    private let teams = ListKind(id: "power_rankings", label: "Power Rankings", itemKind: .team, sizes: [5, 10, 32])
    private let qbs = ListKind(id: "qb", label: "QBs", itemKind: .player, sizes: [10])

    private func editor(
        _ kind: ListKind, saved: [String] = [], prompt: UUID? = nil, client: FakeListsClient = FakeListsClient(),
        onSaved: @escaping () -> Void = {}
    ) -> ListEditorViewModel {
        ListEditorViewModel(client: client, kind: kind, saved: saved, players: [:], openPromptId: prompt, onSaved: onSaved)
    }

    func testANewTeamListStartsFromAll32AndCanBeSavedAsIs() {
        let model = editor(teams)
        XCTAssertEqual(model.items.count, 32)
        XCTAssertEqual(model.size, 32)
        XCTAssertTrue(model.complete)
        XCTAssertTrue(model.dirty, "with nothing saved, the first save is a change even in the default order")
        XCTAssertNil(model.change(at: 0), "and there is nothing to show movement against")
    }

    func testDroppingARowOnAnotherPlaceMovesItThere() {
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"])
        model.drop("PHI", onto: 0)
        XCTAssertEqual(model.items, ["PHI", "KC", "BUF", "DET", "BAL"])
        XCTAssertTrue(model.dirty)
        XCTAssertEqual(model.change(at: 0), .up(3))
        XCTAssertEqual(model.change(at: 1), .down(1))
    }

    func testDroppingARowOnItsOwnPlaceChangesNothing() {
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"])
        model.drop("BUF", onto: 1)
        XCTAssertFalse(model.dirty)
    }

    func testNudgeStepsOneRowAndStopsAtTheEnds() {
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"])
        model.nudge(1, by: 1)
        XCTAssertEqual(model.items, ["KC", "DET", "BUF", "PHI", "BAL"])
        model.nudge(0, by: -1)
        model.nudge(4, by: 1)
        XCTAssertEqual(model.items, ["KC", "DET", "BUF", "PHI", "BAL"])
    }

    func testABenchTeamDroppedInTakesTheSpotAndTheLastDropsOff() {
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"])
        model.drop("SF", onto: 1)
        XCTAssertEqual(model.items, ["KC", "SF", "BUF", "DET", "PHI"])
        XCTAssertTrue(model.bench.contains("BAL"))
    }

    func testSomethingThatIsNotATeamIsNotDroppedIn() {
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"])
        model.drop("NOPE", onto: 1)
        XCTAssertEqual(model.items, ["KC", "BUF", "DET", "PHI", "BAL"])
    }

    func testResizingTeamsCutsAndRefills() {
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"])
        model.changeSize(10)
        XCTAssertEqual(model.items.count, 10)
        XCTAssertEqual(Array(model.items.prefix(5)), ["KC", "BUF", "DET", "PHI", "BAL"])
        model.changeSize(5)
        XCTAssertEqual(model.items, ["KC", "BUF", "DET", "PHI", "BAL"])
    }

    func testPositionListsStartEmptyAndFillFromSearch() {
        let model = editor(qbs)
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertFalse(model.complete)
        model.add(NFLPlayer(id: "00-1", name: "Pat Mahomes", position: "QB", team: "KC"))
        model.add(NFLPlayer(id: "00-1", name: "Pat Mahomes", position: "QB", team: "KC"))
        XCTAssertEqual(model.items, ["00-1"])
        XCTAssertEqual(model.name(of: "00-1"), "Pat Mahomes")
        model.remove("00-1")
        XCTAssertTrue(model.items.isEmpty)
    }

    func testSearchOffersOnlyThePositionNotAlreadyInTheList() async throws {
        let client = FakeListsClient()
        client.searchResults = [
            NFLPlayer(id: "a", name: "A", position: "QB", team: "KC"),
            NFLPlayer(id: "b", name: "B", position: "RB", team: "KC"),
            NFLPlayer(id: "c", name: "C", position: "QB", team: "BUF"),
        ]
        let model = editor(qbs, client: client)
        model.add(NFLPlayer(id: "c", name: "C", position: "QB", team: "BUF"))
        let found = try await model.search("x")
        XCTAssertEqual(found.map(\.id), ["a"])
    }

    func testSaveSendsTheListTheNoteAndWhetherToShare() async {
        let client = FakeListsClient()
        var savedCalls = 0
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"], client: client, onSaved: { savedCalls += 1 })
        model.drop("BAL", onto: 0)
        model.note = "  Ravens rise  "
        model.share = false

        await model.save()

        XCTAssertEqual(client.saves, [.init(kind: "power_rankings", items: ["BAL", "KC", "BUF", "DET", "PHI"], note: "  Ravens rise  ", publish: false)])
        XCTAssertEqual(savedCalls, 1)
        XCTAssertFalse(model.dirty)
        XCTAssertEqual(model.note, "")
        XCTAssertTrue(model.saved)
    }

    func testARefusalShowsTheServersWordsAndKeepsTheEdit() async {
        let client = FakeListsClient()
        client.saveError = ListsServerError(message: "edit_limit", detail: nil)
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"], client: client)
        model.drop("BAL", onto: 0)

        await model.save()

        XCTAssertEqual(model.error, "You saved this list in the last 24 hours. Try again later.")
        XCTAssertTrue(model.dirty)
    }

    func testAnOpenPromptMakesTheListReadOnly() async {
        let client = FakeListsClient()
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"], prompt: UUID(), client: client)
        model.drop("BAL", onto: 0)
        XCTAssertEqual(model.items.first, "KC")
        model.changeSize(10)
        XCTAssertEqual(model.items.count, 5)
        XCTAssertFalse(model.canSave)
        await model.save()
        XCTAssertTrue(client.saves.isEmpty)
    }

    func testUndoGoesBackToTheSavedList() {
        let model = editor(teams, saved: ["KC", "BUF", "DET", "PHI", "BAL"])
        model.drop("BAL", onto: 0)
        model.undo()
        XCTAssertEqual(model.items, ["KC", "BUF", "DET", "PHI", "BAL"])
        XCTAssertFalse(model.dirty)
    }
}

@MainActor
final class ListsViewModelTests: XCTestCase {
    private let when = Date(timeIntervalSince1970: 1_800_000_000)

    private func fixture() -> FakeListsClient {
        let client = FakeListsClient()
        client.kindRows = [
            ListKind(id: "power_rankings", label: "Power Rankings", itemKind: .team, sizes: [5, 10, 32]),
            ListKind(id: "qb", label: "QBs", itemKind: .player, sizes: [10]),
            ListKind(id: "rb", label: "RBs", itemKind: .player, sizes: [10]),
        ]
        client.listRows = [
            ListSummary(kind: "power_rankings", label: "Power Rankings", itemKind: .team, versionNo: 2, savedAt: when, versionCount: 2, items: ["KC", "BUF"]),
            ListSummary(kind: "qb", label: "QBs", itemKind: .player, versionNo: 1, savedAt: when.addingTimeInterval(60), versionCount: 1, items: ["p1"]),
        ]
        client.playerRows = [
            "p1": ListPlayer(id: "p1", name: "Pat Mahomes", position: "QB", team: "KC"),
            "r1": ListPlayer(id: "r1", name: "Saquon Barkley", position: "RB", team: "PHI"),
        ]
        return client
    }

    func testLoadsKindsListsAndFacesNewestFirst() async {
        let model = ListsViewModel(client: fixture(), username: "sam")
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.lists.map(\.kind), ["qb", "power_rankings"])
        XCTAssertEqual(model.players["p1"]?.name, "Pat Mahomes")
        XCTAssertTrue(model.coverPlayers.isEmpty, "visitors and profile tabs never need covers")
    }

    func testTheTabLoadsCoverFacesOnlyForListsNotStarted() async {
        let client = fixture()
        let model = ListsViewModel(client: client, owner: { ListOwner(username: "me", displayName: "Me", avatarURL: nil) }, showsCovers: true)
        await model.load()
        XCTAssertNil(model.coverPlayers["qb"])
        XCTAssertNotNil(model.coverPlayers["rb"], "the RB list is not started, so it gets a cover")
        XCTAssertEqual(model.owner?.username, "me")
    }

    func testAFailedReadIsAFailedPhase() async {
        let client = fixture()
        client.failing = true
        let model = ListsViewModel(client: client, username: "sam")
        await model.load()
        XCTAssertEqual(model.phase, .failed)
    }

    func testAnOwnerWithoutAProfileFails() async {
        let model = ListsViewModel(client: fixture(), owner: { nil })
        await model.load()
        XCTAssertEqual(model.phase, .failed)
    }
}

@MainActor
final class ListUpdatesViewModelTests: XCTestCase {
    private func update(_ minutes: Int) -> ListUpdate {
        ListUpdate(kind: "power_rankings", label: "Power Rankings", itemKind: .team, versionNo: minutes, savedAt: Date(timeIntervalSince1970: 1_800_000_000 - Double(minutes) * 60), items: ["KC", "BUF"])
    }

    func testPagesWithBeforeAndStopsWhenAPageIsShort() async {
        let client = FakeListsClient()
        client.updateRows = (1...25).map(update)
        let model = ListUpdatesViewModel(client: client, viewerId: UUID())

        await model.load()
        XCTAssertEqual(model.updates.count, 20)
        XCTAssertTrue(model.hasMore)

        await model.loadMore()
        XCTAssertEqual(model.updates.count, 25)
        XCTAssertFalse(model.hasMore)
        XCTAssertEqual(client.updateRequests.count, 2)
        XCTAssertNotNil(client.updateRequests.last ?? nil)
    }

    func testAFailedReadLeavesTheFeedWithoutUpdateCards() async {
        let client = FakeListsClient()
        client.failing = true
        let model = ListUpdatesViewModel(client: client, viewerId: UUID())
        await model.load()
        XCTAssertTrue(model.updates.isEmpty)
    }

    func testTheFeedMergesUpdatesByTimeAndTheListsPillShowsOnlyThem() {
        let old = update(120)
        let new = update(1)
        let entries = HomeFeed.build(posts: [], answerers: [:], moments: [], filter: .all, hasMoreMoments: false, listUpdates: [old, new])
        XCTAssertEqual(entries.map(\.id), ["list-\(new.postId)", "list-\(old.postId)"])
        XCTAssertEqual(HomeFeed.build(posts: [], answerers: [:], moments: [], filter: .lists, hasMoreMoments: false, listUpdates: [old, new]).count, 2)
        XCTAssertTrue(HomeFeed.build(posts: [], answerers: [:], moments: [], filter: .prompts, hasMoreMoments: false, listUpdates: [old, new]).isEmpty)
    }
}

@MainActor
final class ListUpdateViewModelTests: XCTestCase {
    func testAnUpdateTheViewerMayNotSeeIsNotFound() async {
        let model = ListUpdateViewModel(client: FakeListsClient(), postId: UUID(), viewerId: UUID())
        await model.load()
        XCTAssertEqual(model.phase, .notFound)
    }

    func testReplyingPostsUnderTheNoteAndClearsTheDraft() async {
        let client = FakeListsClient()
        let card = ListUpdate(kind: "power_rankings", label: "Power Rankings", itemKind: .team, versionNo: 2, savedAt: Date(), items: ["KC"])
        client.updateRows = [card]
        client.threadResult = ListThread(takeId: UUID(), replies: [])
        let model = ListUpdateViewModel(client: client, postId: card.postId, viewerId: UUID())
        await model.load()
        XCTAssertFalse(model.canReply)

        model.draft = "  Agree on KC  "
        XCTAssertTrue(model.canReply)
        await model.sendReply()

        XCTAssertEqual(client.replies, ["Agree on KC"])
        XCTAssertEqual(model.draft, "")
    }
}
