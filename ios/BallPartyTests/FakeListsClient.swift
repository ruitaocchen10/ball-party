import Foundation
@testable import BallParty

/// Plays the `ListsClient` seam in memory: scripted reads, and a save that
/// either succeeds or raises the error a test sets, recording what was sent.
final class FakeListsClient: ListsClient, @unchecked Sendable {
    struct Offline: Error {}
    struct Saved: Equatable { let kind: String; let items: [String]; let note: String?; let publish: Bool }

    var kindRows: [ListKind] = []
    var listRows: [ListSummary] = []
    var historyRows: [ListVersion] = []
    var playerRows: [String: ListPlayer] = [:]
    var openPromptId: UUID?
    var updateRows: [ListUpdate] = []
    var threadResult = ListThread(takeId: nil, replies: [])
    var searchResults: [NFLPlayer] = []
    var saveError: Error?
    var failing = false

    private(set) var saves: [Saved] = []
    private(set) var replies: [String] = []
    private(set) var updateRequests: [Date?] = []

    func kinds() async throws -> [ListKind] {
        if failing { throw Offline() }
        return kindRows
    }

    func lists(username: String) async throws -> [ListSummary] {
        if failing { throw Offline() }
        return listRows
    }

    func history(username: String, kind: String) async throws -> [ListVersion] {
        if failing { throw Offline() }
        return historyRows
    }

    func players(ids: [String]) async throws -> [String: ListPlayer] {
        playerRows.filter { ids.contains($0.key) }
    }

    func openPrompt(kind: String) async throws -> UUID? { openPromptId }

    func save(kind: String, items: [String], note: String?, publish: Bool) async throws {
        if let saveError { throw saveError }
        saves.append(Saved(kind: kind, items: items, note: note, publish: publish))
    }

    func updates(limit: Int, before: Date?) async throws -> [ListUpdate] {
        updateRequests.append(before)
        if failing { throw Offline() }
        return updateRows.filter { before == nil || $0.savedAt < before! }.prefix(limit).map { $0 }
    }

    func update(postId: UUID) async throws -> ListUpdate? { updateRows.first { $0.postId == postId } }

    func thread(postId: UUID, viewerId: UUID) async throws -> ListThread { threadResult }

    func reply(postId: UUID, takeId: UUID, body: String) async throws {
        if failing { throw Offline() }
        replies.append(body)
    }

    func searchPlayers(query: String) async throws -> [NFLPlayer] { searchResults }
}
