import Foundation
import Supabase

/// The activity feed's one read, named as its own protocol so tests can
/// substitute a fake.
protocol FriendActivityClient: Sendable {
    /// `friend_activity`: newest first, at most `limit` events strictly older
    /// than `before` (an `occurred_at` exactly as the server printed it).
    func activity(limit: Int, before: String?) async throws -> [FriendActivityEvent]
}

struct SupabaseFriendActivityClient: FriendActivityClient {
    let client: SupabaseClient

    private struct Params: Encodable, Sendable {
        let p_limit: Int
        let p_before: String?
    }

    func activity(limit: Int, before: String?) async throws -> [FriendActivityEvent] {
        let page: FriendActivityPage = try await client
            .rpc("friend_activity", params: Params(p_limit: limit, p_before: before))
            .execute().value
        return page.events
    }
}

/// The feed of what friends have been up to. The server picks the friends and
/// the window (30 days); this pages through it newest-first.
@MainActor
final class FriendActivityViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading, loaded
        /// The first page couldn't be read and there is nothing to show.
        case failed
    }

    /// Matches the RPC's default; the server caps a page at 50.
    static let pageSize = 30

    @Published private(set) var events: [FriendActivityEvent] = []
    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isLoadingMore = false
    @Published private(set) var loadMoreFailed = false
    /// False once a page comes back short: nothing older to ask for.
    @Published private(set) var hasMore = false

    private let client: FriendActivityClient
    private let pageSize: Int

    init(client: FriendActivityClient, pageSize: Int = FriendActivityViewModel.pageSize) {
        self.client = client
        self.pageSize = pageSize
    }

    /// Reads the newest page, replacing what is shown. A failed refresh keeps
    /// the events already on screen.
    func load() async {
        if events.isEmpty { phase = .loading }
        do {
            let page = try await client.activity(limit: pageSize, before: nil)
            events = page
            hasMore = page.count >= pageSize
            loadMoreFailed = false
            phase = .loaded
        } catch {
            if events.isEmpty { phase = .failed }
        }
    }

    /// Reads the page older than the oldest event shown.
    func loadMore() async {
        guard hasMore, !isLoadingMore, let oldest = events.last else { return }
        isLoadingMore = true
        loadMoreFailed = false
        defer { isLoadingMore = false }
        do {
            let page = try await client.activity(limit: pageSize, before: oldest.occurredAtRaw)
            let known = Set(events.map(\.id))
            events += page.filter { !known.contains($0.id) }
            hasMore = page.count >= pageSize
        } catch {
            loadMoreFailed = true
        }
    }
}
