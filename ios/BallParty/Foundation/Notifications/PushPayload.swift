import Foundation

/// What a push tells the app when it is tapped. The sender (the `send-push`
/// Edge Function) puts these keys beside `aps`. A push carries only the kind and
/// ids; the app finds out what it is about from the inbox, so no names or text
/// ride on a lock screen.
///
///     kind      friend_request | take_reply | room_invite | new_prompt
///     item_key  the inbox item (`n:<uuid>` / `i:<uuid>`); not sent for new_prompt
///     post_id   new_prompt: the prompt post
struct PushPayload: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case item(InboxKind)
        case newPrompt
    }

    let kind: Kind
    let itemKey: String?
    let postId: UUID?

    init?(userInfo: [AnyHashable: Any]) {
        guard let raw = userInfo["kind"] as? String else { return nil }
        if raw == "new_prompt" {
            kind = .newPrompt
        } else if let item = InboxKind(rawValue: raw) {
            kind = .item(item)
        } else {
            return nil
        }
        itemKey = userInfo["item_key"] as? String
        postId = (userInfo["post_id"] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// A tapped push, waiting for the signed-in tab shell to act on it.
struct PushRoute: Equatable, Sendable {
    let kind: PushPayload.Kind
    let itemKey: String?
}
