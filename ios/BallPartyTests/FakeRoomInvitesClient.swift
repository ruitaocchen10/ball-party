import Foundation
@testable import BallParty

/// Scripts the room-invite RPCs so the invite sheet and inbox view models run
/// without the network.
final class FakeRoomInvitesClient: RoomInvitesClient, @unchecked Sendable {
    var inviteResults: [UUID: InviteResult] = [:]
    var defaultResult: InviteResult = .invited
    var inviteRows: [RoomInvite] = []
    var acceptedLobby = Lobby(id: UUID(), code: "QRTZW", hostId: UUID())
    /// Raised by the named call (`invite`, `accept`, `decline`).
    var failures: [String: LobbyServerError] = [:]
    var offline = false

    private(set) var calls: [String] = []

    func invite(friendId: UUID, to lobbyId: UUID) async throws -> InviteResult {
        calls.append("invite:\(friendId):\(lobbyId)")
        try check("invite")
        return inviteResults[friendId] ?? defaultResult
    }

    func invites() async throws -> [RoomInvite] {
        calls.append("invites")
        if offline { throw FakeFriendsClient.Offline() }
        return inviteRows
    }

    func accept(_ inviteId: UUID) async throws -> Lobby {
        calls.append("accept:\(inviteId)")
        try check("accept")
        return acceptedLobby
    }

    func decline(_ inviteId: UUID) async throws {
        calls.append("decline:\(inviteId)")
        try check("decline")
    }

    private var eventContinuation: AsyncStream<RoomInviteEvent>.Continuation?

    /// How many times `events` has been asked for a stream.
    private(set) var eventsOpened = 0

    func events(recipientId: UUID) -> AsyncStream<RoomInviteEvent> {
        eventsOpened += 1
        return AsyncStream { continuation in
            self.eventContinuation = continuation
            continuation.onTermination = { _ in self.eventContinuation = nil }
        }
    }

    /// Plays an event through the stream `events` handed out.
    func emit(_ event: RoomInviteEvent) { eventContinuation?.yield(event) }

    /// Ends the stream, the way cancelling the observing task would.
    func finishEvents() { eventContinuation?.finish() }

    private func check(_ name: String) throws {
        if let failure = failures[name] { throw failure }
    }
}
