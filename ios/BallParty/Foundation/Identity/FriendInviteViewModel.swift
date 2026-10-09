import Foundation
import Supabase

/// The screen behind a friend invite link: who invited you, and the button
/// that sends the request. Mirrors the web's `FriendInviteCard`; every rule
/// (is the code real, is it yours, did the owner block you) is answered by
/// `lookup_friend_code` and `redeem_friend_code`, never decided here.
@MainActor
final class FriendInviteViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        /// Unknown or expired code, your own, or an owner who blocked you:
        /// one answer for all of them, as on the web.
        case unavailable
        case failed(String)
        case loaded(UserSearchResult)
    }

    static let unavailableTitle = "Invite isn’t available"
    static let unavailableMessage = "This link may have expired, been reset, or be your own. Ask your friend for a fresh one."
    static let genericError = "Something went wrong. Try again."

    @Published private(set) var phase: Phase = .loading
    /// What redeeming answered, or the state the lookup already implies.
    @Published private(set) var result: SendRequestResult?
    @Published private(set) var isSending = false
    @Published private(set) var error: String?

    let code: String
    private let client: FriendsClient

    init(client: FriendsClient, code: String) {
        self.client = client
        self.code = code
    }

    /// The line shown in place of the button once there is an outcome. Same
    /// copy as the web's `SEND_RESULT_COPY`.
    static func copy(for result: SendRequestResult) -> String {
        switch result {
        case .requested: "Friend request sent."
        case .accepted: "You’re now friends."
        case .alreadyRequested: "You’ve already sent a request."
        case .alreadyFriends: "You’re already friends."
        case .unavailable: "Couldn’t add that player."
        }
    }

    /// Same table as the web's `friendErrorMessage`.
    static func errorMessage(for error: Error) -> String {
        switch (error as? PostgrestError)?.message {
        case "guests_cannot_have_friends": return "Friends need a real account."
        case "not_authenticated": return "Sign in first."
        case "rate_limited": return "Too many tries. Wait a bit and try again."
        default: return genericError
        }
    }

    func load() async {
        phase = .loading
        error = nil
        do {
            guard let owner = try await client.lookupInviteCode(code) else {
                phase = .unavailable
                return
            }
            switch owner.relationship {
            case .friends: result = .alreadyFriends
            case .outgoing: result = .alreadyRequested
            default: result = nil
            }
            phase = .loaded(owner)
        } catch {
            phase = .failed(Self.errorMessage(for: error))
        }
    }

    func addFriend() async {
        guard case .loaded = phase, result == nil, !isSending else { return }
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            result = try await client.redeemInviteCode(code)
        } catch {
            self.error = Self.errorMessage(for: error)
        }
    }
}
