import Foundation
import Supabase

/// The leaderboard's two reads, named as their own protocol so tests can
/// substitute a fake instead of hitting the network.
protocol LeaderboardClient: Sendable {
    /// `ball_knower_leaderboard` — the top of the board for a window.
    func leaderboard(window: LeaderboardWindow) async throws -> [LeaderboardRow]
    /// `my_ball_knower_standing` — the caller's own place, and why.
    func standing(window: LeaderboardWindow) async throws -> LeaderboardStanding
}

struct SupabaseLeaderboardClient: LeaderboardClient {
    let client: SupabaseClient

    private struct Params: Encodable, Sendable { let p_window: String }

    func leaderboard(window: LeaderboardWindow) async throws -> [LeaderboardRow] {
        try await client.rpc("ball_knower_leaderboard", params: Params(p_window: window.rawValue)).execute().value
    }

    func standing(window: LeaderboardWindow) async throws -> LeaderboardStanding {
        let rows: [LeaderboardStanding] = try await client
            .rpc("my_ball_knower_standing", params: Params(p_window: window.rawValue))
            .execute()
            .value
        guard let row = rows.first else { throw LeaderboardError.missingStanding }
        return row
    }
}

enum LeaderboardError: Error { case missingStanding }

/// What the Ball Knower leaderboard shows for the selected window.
@MainActor
final class LeaderboardViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The read failed and there is nothing to show for this window.
        case failed
    }

    @Published private(set) var rows: [LeaderboardRow] = []
    @Published private(set) var standing: LeaderboardStanding?
    @Published private(set) var phase: Phase = .loading
    /// UI-only state the screen binds directly to; the screen reloads when it changes.
    @Published var window: LeaderboardWindow

    private let client: LeaderboardClient

    init(client: LeaderboardClient, window: LeaderboardWindow = .week) {
        self.client = client
        self.window = window
    }

    /// Reads the board for the current window. A response for a window the
    /// player has already moved off is dropped, so a slow week read can never
    /// overwrite the month they switched to.
    func load() async {
        let requested = window
        phase = .loading
        do {
            async let board = client.leaderboard(window: requested)
            async let place = client.standing(window: requested)
            let (freshRows, freshStanding) = try await (board, place)
            guard requested == window else { return }
            rows = freshRows
            standing = freshStanding
            phase = .loaded
        } catch {
            guard requested == window else { return }
            rows = []
            standing = nil
            phase = .failed
        }
    }
}
