import Foundation
@testable import BallParty

/// Scripts the inbox RPCs so the inbox view model runs without the network.
final class FakeInboxClient: InboxClient, @unchecked Sendable {
    var rows: [InboxItem] = []
    var unread = 0
    var offline = false

    private let lock = NSLock()
    private var recorded: [String] = []
    /// `load()` reads the list and the count concurrently, so recording is locked.
    var calls: [String] { lock.withLock { recorded } }
    private func record(_ call: String) { lock.withLock { recorded.append(call) } }

    func items() async throws -> [InboxItem] {
        record("items")
        if offline { throw FakeFriendsClient.Offline() }
        return rows
    }

    func unreadCount() async throws -> Int {
        record("unreadCount")
        if offline { throw FakeFriendsClient.Offline() }
        return unread
    }

    func markRead(key: String) async throws { record("markRead:\(key)") }
    func markAllRead() async throws { record("markAllRead") }

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
