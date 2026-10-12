import Foundation

/// The notification inbox behind the bell: friend requests, replies to your
/// takes and room invites, in the order and state the server gives them. Read
/// on appear and on pull-to-refresh, and re-read whenever Realtime reports a
/// change (`observe`), so `load()` is the only thing that decides what is
/// listed. Held by the tab shell so every tab's bell shows the same count.
@MainActor
final class InboxViewModel: ObservableObject {
    @Published private(set) var items: [InboxItem] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var busyKey: String?
    @Published private(set) var errors: [String: String] = [:]

    private let client: InboxClient
    private let friends: FriendsClient
    private let invites: RoomInvitesClient

    init(client: InboxClient, friends: FriendsClient, invites: RoomInvitesClient) {
        self.client = client
        self.friends = friends
        self.invites = invites
    }

    var isBusy: Bool { busyKey != nil }

    /// A failed read keeps whatever was listed; the next event or pull tries again.
    func load() async {
        async let list = try? client.items()
        async let count = try? client.unreadCount()
        guard let fresh = await list else { return }
        items = fresh
        if let count = await count { unreadCount = count }
        errors = errors.filter { key, _ in fresh.contains { $0.key == key } }
    }

    func observe(recipientId: UUID) async {
        for await _ in client.events(recipientId: recipientId) {
            await load()
        }
    }

    /// Accepts a friend request (returns nil), or joins the room an invite
    /// points at and returns it so the Party tab can step inside. Nil also
    /// means the server refused; the reason is shown on the row.
    func accept(_ item: InboxItem) async -> Lobby? {
        guard !isBusy, item.hasActions else { return nil }
        begin(item)
        defer { busyKey = nil }
        do {
            switch item.kind {
            case .friendRequest:
                _ = try await friends.accept(item.actorId)
                await markRead(item)
                await load()
                return nil
            case .roomInvite:
                let lobby = try await invites.accept(item.refId)
                await load()
                return lobby
            case .takeReply:
                return nil
            }
        } catch {
            errors[item.key] = Self.message(for: item, error)
            await load()
            return nil
        }
    }

    func decline(_ item: InboxItem) async {
        guard !isBusy, item.hasActions else { return }
        begin(item)
        defer { busyKey = nil }
        do {
            switch item.kind {
            case .friendRequest: _ = try await friends.decline(item.actorId)
            case .roomInvite: try await invites.decline(item.refId)
            case .takeReply: return
            }
            await load()
        } catch {
            errors[item.key] = Self.message(for: item, error)
            await load()
        }
    }

    /// An item is read when it is tapped or acted on, not when the list is merely shown.
    func markRead(_ item: InboxItem) async {
        guard item.isStored, item.isUnread else { return }
        try? await client.markRead(key: item.key)
        await load()
    }

    /// A tapped push counts as the row being tapped: the item it was for is read,
    /// and where the row would go is returned. Nil when the item is gone or has no
    /// page of its own (a room invite), and the inbox simply opens.
    func openItem(key: String) async -> InboxDestination? {
        await load()
        guard let item = items.first(where: { $0.key == key }) else { return nil }
        await markRead(item)
        return item.destination
    }

    func markAllRead() async {
        try? await client.markAllRead()
        await load()
    }

    private func begin(_ item: InboxItem) {
        busyKey = item.key
        errors[item.key] = nil
    }

    private static func message(for item: InboxItem, _ error: Error) -> String {
        if item.kind == .roomInvite { return RoomInviteCopy.errorMessage(error) }
        return FriendInviteViewModel.errorMessage(for: error)
    }
}
