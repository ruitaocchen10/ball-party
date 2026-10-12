import Foundation

/// What a push tells the app when it is tapped. The sender (#172) puts these
/// keys beside `aps`, and they are the same facts the inbox row is built from,
/// so a tap and a row tap land in the same place (`InboxDestination.resolve`).
///
///     kind      friend_request | take_reply | room_invite
///     item_key  the inbox item's key, so the tap can mark it read
///     username  friend_request: the requester's username
///     post_id   take_reply: the prompt post the take is on
///     ref_id    take_reply: the take (`prompt_comments.id`)
struct PushPayload: Equatable, Sendable {
    let kind: InboxKind
    let itemKey: String?
    let username: String?
    let postId: UUID?
    let refId: UUID?

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["kind"] as? String, let kind = InboxKind(rawValue: raw) else { return nil }
        self.kind = kind
        itemKey = userInfo["item_key"] as? String
        username = userInfo["username"] as? String
        postId = (userInfo["post_id"] as? String).flatMap(UUID.init(uuidString:))
        refId = (userInfo["ref_id"] as? String).flatMap(UUID.init(uuidString:))
    }

    /// Where a tap goes: the page the row opens, or nil for the inbox itself
    /// (a room invite has no page of its own, and neither does a payload we can't read).
    var destination: InboxDestination? {
        InboxDestination.resolve(kind: kind, username: username, postId: postId, refId: refId)
    }
}

/// A tapped push, waiting for the signed-in tab shell to act on it.
struct PushRoute: Equatable, Sendable {
    let destination: InboxDestination?
    let itemKey: String?
}
