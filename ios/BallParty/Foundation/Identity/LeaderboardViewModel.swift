import Foundation
import Supabase

/// The leaderboard's two reads, named as their own protocol so tests can
/// substitute a fake instead of hitting the network.
protocol LeaderboardClient: Sendable {
    /// `ball_knower_leaderboard` — the top of the board for a window and scope.
    func leaderboard(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> [LeaderboardRow]
    /// `my_ball_knower_standing` — the caller's own place, and why.
    func standing(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> LeaderboardStanding
}

struct SupabaseLeaderboardClient: LeaderboardClient {
    let client: SupabaseClient

    private struct Params: Encodable, Sendable {
        let p_window: String
        let p_scope: String
    }

    func leaderboard(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> [LeaderboardRow] {
        try await client
            .rpc("ball_knower_leaderboard", params: Params(p_window: window.rawValue, p_scope: scope.rawValue))
            .execute().value
    }

    func standing(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> LeaderboardStanding {
        let rows: [LeaderboardStanding] = try await client
            .rpc("my_ball_knower_standing", params: Params(p_window: window.rawValue, p_scope: scope.rawValue))
            .execute()
            .value
        guard let row = rows.first else { throw LeaderboardError.missingStanding }
        return row
    }
}

enum LeaderboardError: Error { case missingStanding }

/// What the Ball Knower leaderboard shows for the selected window and scope.
@MainActor
final class LeaderboardViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The read failed and there is nothing to show for this window.
        case failed
    }

    /// The window and scope a read is for; the screen reloads when it changes.
    struct Selection: Equatable, Sendable {
        let window: LeaderboardWindow
        let scope: LeaderboardScope
    }

    @Published private(set) var rows: [LeaderboardRow] = []
    @Published private(set) var standing: LeaderboardStanding?
    @Published private(set) var phase: Phase = .loading
    /// UI-only state the screen binds directly to; the screen reloads when it changes.
    @Published var window: LeaderboardWindow
    @Published var scope: LeaderboardScope

    private let client: LeaderboardClient

    init(client: LeaderboardClient, window: LeaderboardWindow = .week, scope: LeaderboardScope = .all) {
        self.client = client
        self.window = window
        self.scope = scope
    }

    var selection: Selection { Selection(window: window, scope: scope) }

    /// A friends board with nobody else on it: the caller may be ranked alone,
    /// but there is no board to compare against yet.
    var friendsBoardIsEmpty: Bool {
        scope == .friends && !rows.contains { !$0.isMe }
    }

    /// Reads the board for the current window and scope. A response for a
    /// selection the player has already moved off is dropped, so a slow week
    /// read can never overwrite the month they switched to.
    func load() async {
        let requested = selection
        phase = .loading
        do {
            async let board = client.leaderboard(window: requested.window, scope: requested.scope)
            async let place = client.standing(window: requested.window, scope: requested.scope)
            let (freshRows, freshStanding) = try await (board, place)
            guard requested == selection else { return }
            rows = freshRows
            standing = freshStanding
            phase = .loaded
        } catch {
            guard requested == selection else { return }
            rows = []
            standing = nil
            phase = .failed
        }
    }
}
