import Foundation
@testable import BallParty

/// Scripts the inbox RPCs so the inbox view model runs without the network.
final class FakeInboxClient: InboxClient, @unchecked Sendable {
    var rows: [InboxItem] = []
    var unread = 0
    var offline = false

    private(set) var calls: [String] = []

    func items() async throws -> [InboxItem] {
        calls.append("items")
        if offline { throw FakeFriendsClient.Offline() }
        return rows
    }

    func unreadCount() async throws -> Int {
        calls.append("unreadCount")
        if offline { throw FakeFriendsClient.Offline() }
        return unread
    }

    func markRead(key: String) async throws { calls.append("markRead:\(key)") }
    func markAllRead() async throws { calls.append("markAllRead") }

    private var eventContinuation: AsyncStream<InboxEvent>.Continuation?

    func events(recipientId: UUID) -> AsyncStream<InboxEvent> {
        AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { _ in self.eventContinuation = nil }
        }
    }

    func emit(_ event: InboxEvent) { eventContinuation?.yield(event) }
    func finishEvents() { eventContinuation?.finish() }
}
