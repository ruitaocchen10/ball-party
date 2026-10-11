import Foundation
import Supabase

/// Something happened to the viewer's inbox, or the channel (re)joined. Neither
/// carries data: the inbox re-reads `list_inbox`, which is where state is resolved.
enum InboxEvent: Sendable { case changed, subscribed }

/// The inbox's network seam (migration 0204). Every rule about what is listed,
/// and what state it is in, is the server's.
protocol InboxClient: Sendable {
    /// `list_inbox`, newest activity first.
    func items() async throws -> [InboxItem]
    /// `inbox_unread_count`: what the bell's badge shows.
    func unreadCount() async throws -> Int
    /// `mark_notification_read`.
    func markRead(key: String) async throws
    /// `mark_all_notifications_read`.
    func markAllRead() async throws
    /// Changes to the caller's own `notifications` and `room_invites` rows, plus
    /// a `.subscribed` on every join so anything that arrived while the socket
    /// was down is read again. Ends when the consuming task is cancelled.
    func events(recipientId: UUID) -> AsyncStream<InboxEvent>
}

struct SupabaseInboxClient: InboxClient {
    let client: SupabaseClient

    private struct KeyParams: Encodable, Sendable { let p_item_key: String }

    func items() async throws -> [InboxItem] {
        let response = try await client.rpc("list_inbox").execute()
        return try InboxItem.list(from: response.data)
    }

    func unreadCount() async throws -> Int {
        try await client.rpc("inbox_unread_count").execute().value
    }

    func markRead(key: String) async throws {
        _ = try await client.rpc("mark_notification_read", params: KeyParams(p_item_key: key)).execute()
    }

    func markAllRead() async throws {
        _ = try await client.rpc("mark_all_notifications_read").execute()
    }

    func events(recipientId: UUID) -> AsyncStream<InboxEvent> {
        realtimeEvents(
            client: client, topics: ["inbox:\(recipientId)"], subscribed: .subscribed
        ) { channels, yield in
            let notifications = channels[0].postgresChange(
                AnyAction.self, table: "notifications", filter: .eq("recipient_id", value: recipientId)
            )
            let invites = channels[0].postgresChange(
                AnyAction.self, table: "room_invites", filter: .eq("recipient_id", value: recipientId)
            )
            // No payload is decoded: a row is only ever the fact that the list changed.
            return [
                { for await _ in notifications { yield(.changed) } },
                { for await _ in invites { yield(.changed) } },
            ]
        }
    }
}
