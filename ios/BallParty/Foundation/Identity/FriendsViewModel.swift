import Foundation

/// One thing a player can do about another player. The friends screen, the
/// search result and the other-user profile all go through this, so each
/// action means the same wherever it is offered.
enum RelationshipAction: Equatable, Sendable {
    case send, accept, decline, cancel, remove, block, unblock

    /// Runs the action and returns the line to show, if any. Whether it
    /// worked, and what a request turned into, is the server's call.
    func perform(on player: PlayerIdentity, client: FriendsClient) async throws -> String? {
        switch self {
        case .send: return try await client.sendRequest(username: player.username).message
        case .accept: _ = try await client.accept(player.profileId); return nil
        case .decline: _ = try await client.decline(player.profileId); return nil
        case .cancel: _ = try await client.cancel(player.profileId); return nil
        case .remove: _ = try await client.remove(player.profileId); return nil
        case .block: _ = try await client.block(player.profileId); return nil
        case .unblock: _ = try await client.unblock(player.profileId); return nil
        }
    }

    /// The button an unblocked, not-yet-friends relationship offers, if any.
    static func primary(for relationship: FriendRelationship) -> (action: RelationshipAction, title: String)? {
        switch relationship {
        case .none: (.send, "Add friend")
        case .incoming: (.accept, "Accept request")
        case .outgoing: (.cancel, "Cancel request")
        case .blocked: (.unblock, "Unblock")
        case .friends, .selfUser, .unknown: nil
        }
    }
}

/// The Friends screen: friends, requests, blocked players, finding a player by
/// username, and the invite link. Every rule is the server's; this holds what
/// it said and re-reads after each change.
@MainActor
final class FriendsViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading, loaded
        /// The lists couldn't be read and there is nothing to show.
        case failed
    }

    enum SearchPhase: Equatable {
        case idle
        case searching
        case found(UserSearchResult)
        /// An exact match found nobody. Also what a blocked or missing player
        /// looks like, so it says nothing about why.
        case notFound
        case invalid(String)
        case failed
    }

    static let genericFailure = "Something went wrong. Please try again."

    @Published private(set) var friends: [Friend] = []
    @Published private(set) var requests: [FriendRequest] = []
    @Published private(set) var blocked: [BlockedUser] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var searchPhase: SearchPhase = .idle
    @Published private(set) var inviteCode: String?
    /// The last action's outcome, shown once; cleared by the next action.
    @Published var notice: String?
    /// UI-only state the screen binds directly to.
    @Published var query = ""

    private let client: FriendsClient

    init(client: FriendsClient) {
        self.client = client
    }

    var incoming: [FriendRequest] { requests.filter { $0.direction == .incoming } }
    var outgoing: [FriendRequest] { requests.filter { $0.direction == .outgoing } }

    var inviteURL: URL? { inviteCode.map { FriendInviteLink.url(code: $0) } }

    /// Reads the three lists. Keeps what is on screen if a refresh fails.
    func load() async {
        if friends.isEmpty && requests.isEmpty && blocked.isEmpty { phase = .loading }
        do {
            async let friendRows = client.friends()
            async let requestRows = client.requests()
            async let blockedRows = client.blocked()
            let (fresh, asked, blockedFresh) = try await (friendRows, requestRows, blockedRows)
            friends = fresh
            requests = asked
            blocked = blockedFresh
            phase = .loaded
        } catch {
            if friends.isEmpty && requests.isEmpty && blocked.isEmpty { phase = .failed }
        }
    }

    /// Runs one action against `player`, then re-reads everything it could
    /// have changed, including the open search result.
    func perform(_ action: RelationshipAction, on player: PlayerIdentity) async {
        notice = nil
        do {
            notice = try await action.perform(on: player, client: client)
        } catch {
            notice = Self.genericFailure
        }
        await load()
        if case .found(let result) = searchPhase, result.player.profileId == player.profileId {
            await refreshSearch(username: result.player.username)
        }
    }

    // MARK: Search

    /// Exact-username lookup. Format is checked here first only to skip a
    /// pointless call; the server stays authoritative.
    func search() async {
        notice = nil
        switch IdentityConstants.validateUsername(query) {
        case .invalid(let message):
            searchPhase = .invalid(message)
        case .valid(let username):
            searchPhase = .searching
            await refreshSearch(username: username)
        }
    }

    private func refreshSearch(username: String) async {
        do {
            if let result = try await client.search(username: username) {
                searchPhase = .found(result)
            } else {
                searchPhase = .notFound
            }
        } catch {
            searchPhase = .failed
        }
    }

    // MARK: Invite link

    func loadInviteCode() async {
        guard inviteCode == nil else { return }
        inviteCode = try? await client.inviteCode()
    }

    /// Makes a new code; links shared before stop working.
    func resetInviteCode() async {
        notice = nil
        do {
            inviteCode = try await client.resetInviteCode()
            notice = "Your old invite link no longer works."
        } catch {
            notice = Self.genericFailure
        }
    }
}
