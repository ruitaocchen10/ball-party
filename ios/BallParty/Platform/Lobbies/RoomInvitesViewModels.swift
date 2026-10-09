import Foundation

/// The "Invite friends" sheet in a room. Friends are read when the sheet
/// opens, so a friendship made a moment ago is already listed. Each friend
/// shows the server's answer to inviting them; nothing is decided here.
@MainActor
final class InviteFriendsViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading, loaded
        case failed(String)
    }

    /// Per friend: asking, answered by the server, or failed to ask.
    enum Attempt: Equatable {
        case sending
        case result(InviteResult)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var attempts: [UUID: Attempt] = [:]

    private let lobbyId: UUID
    private let friendsClient: FriendsClient
    private let invitesClient: RoomInvitesClient

    init(lobbyId: UUID, friendsClient: FriendsClient, invitesClient: RoomInvitesClient) {
        self.lobbyId = lobbyId
        self.friendsClient = friendsClient
        self.invitesClient = invitesClient
    }

    func load() async {
        do {
            friends = try await friendsClient.friends()
            phase = .loaded
        } catch {
            phase = .failed("Couldn’t load your friends. Try again in a moment.")
        }
    }

    func invite(_ friend: Friend) async {
        switch attempts[friend.id] {
        case .sending: return
        case .result(let result) where result.isSettled: return
        default: break
        }
        attempts[friend.id] = .sending
        do {
            attempts[friend.id] = .result(try await invitesClient.invite(friendId: friend.id, to: lobbyId))
        } catch {
            attempts[friend.id] = .failed(RoomInviteCopy.errorMessage(error))
        }
    }
}

/// "Room invites" at the top of the Party tab: pending invites from friends.
/// Read on appear and on pull-to-refresh, and re-read whenever Realtime reports
/// a change to the viewer's invites (`observe`), so a new invite shows up
/// without a refresh.
@MainActor
final class RoomInvitesInboxViewModel: ObservableObject {
    enum Action: Equatable { case accept, decline }

    @Published private(set) var invites: [RoomInvite] = []
    @Published private(set) var busyInviteId: UUID?
    @Published private(set) var busyAction: Action?
    @Published private(set) var errors: [UUID: String] = [:]

    private let client: RoomInvitesClient
    /// How long a dead invite's message stays up before the row is dropped.
    var deadInviteDelay: Duration = .milliseconds(2500)

    init(client: RoomInvitesClient) {
        self.client = client
    }

    var isBusy: Bool { busyInviteId != nil }

    /// A failed read keeps whatever was listed; the next pull tries again.
    func load() async {
        guard !isBusy else { return }
        guard let fresh = try? await client.invites() else { return }
        invites = fresh
        errors = errors.filter { id, _ in fresh.contains { $0.id == id } }
    }

    /// Keeps the list current for as long as the calling task lives (attach it
    /// with `.task`). Every event is just "read again": `load()` is the only
    /// thing that decides what is listed, so the stream cannot show an invite
    /// the server would not.
    func observe(recipientId: UUID) async {
        for await _ in client.events(recipientId: recipientId) {
            await load()
        }
    }

    /// Joins the room. Returns it so the Party tab can step inside, or `nil`
    /// when the server refused (the reason is shown on the row).
    func accept(_ invite: RoomInvite) async -> Lobby? {
        guard !isBusy else { return nil }
        begin(invite, .accept)
        defer { finish() }
        do {
            let lobby = try await client.accept(invite.id)
            invites.removeAll { $0.id == invite.id }
            return lobby
        } catch {
            errors[invite.id] = RoomInviteCopy.errorMessage(error)
            // A dead invite (expired, room closed, unfriended) never works
            // later, so it is dropped once its message has been seen.
            if (error as? LobbyServerError)?.message == "invite_not_found" {
                try? await Task.sleep(for: deadInviteDelay)
                invites.removeAll { $0.id == invite.id }
            }
            return nil
        }
    }

    func decline(_ invite: RoomInvite) async {
        guard !isBusy else { return }
        begin(invite, .decline)
        defer { finish() }
        do {
            try await client.decline(invite.id)
            invites.removeAll { $0.id == invite.id }
        } catch {
            errors[invite.id] = RoomInviteCopy.errorMessage(error)
        }
    }

    private func begin(_ invite: RoomInvite, _ action: Action) {
        busyInviteId = invite.id
        busyAction = action
        errors[invite.id] = nil
    }

    private func finish() {
        busyInviteId = nil
        busyAction = nil
    }
}
