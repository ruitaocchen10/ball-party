import Foundation
import Supabase

/// The Gamer and solo leaderboards' four reads, named as their own protocol so
/// tests can substitute a fake instead of hitting the network.
protocol GamerLeaderboardClient: Sendable {
    /// `gamer_leaderboard` — multiplayer wins for a window and scope.
    func gamerBoard(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> [GamerRow]
    /// `my_gamer_standing` — the caller's own place on it.
    func gamerStanding(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> GamerStanding
    /// `solo_leaderboard` — one solo game's all-time best runs. `mode` is QB Season Builder's, nil otherwise.
    func soloBoard(game: SoloGame, mode: QbRatingMode?, scope: LeaderboardScope) async throws -> [SoloRow]
    /// `my_solo_standing` — the caller's own place on it.
    func soloStanding(game: SoloGame, mode: QbRatingMode?, scope: LeaderboardScope) async throws -> SoloStanding
}

struct SupabaseGamerLeaderboardClient: GamerLeaderboardClient {
    let client: SupabaseClient

    private struct GamerParams: Encodable, Sendable {
        let p_window: String
        let p_scope: String
    }

    /// A nil `p_mode` is left out of the body, so the RPC's default (null) applies.
    private struct SoloParams: Encodable, Sendable {
        let p_game: String
        let p_mode: String?
        let p_scope: String
    }

    func gamerBoard(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> [GamerRow] {
        try await client
            .rpc("gamer_leaderboard", params: GamerParams(p_window: window.rawValue, p_scope: scope.rawValue))
            .execute().value
    }

    func gamerStanding(window: LeaderboardWindow, scope: LeaderboardScope) async throws -> GamerStanding {
        let rows: [GamerStanding] = try await client
            .rpc("my_gamer_standing", params: GamerParams(p_window: window.rawValue, p_scope: scope.rawValue))
            .execute().value
        guard let row = rows.first else { throw LeaderboardError.missingStanding }
        return row
    }

    func soloBoard(game: SoloGame, mode: QbRatingMode?, scope: LeaderboardScope) async throws -> [SoloRow] {
        try await client
            .rpc("solo_leaderboard", params: SoloParams(p_game: game.rawValue, p_mode: mode?.rawValue, p_scope: scope.rawValue))
            .execute().value
    }

    func soloStanding(game: SoloGame, mode: QbRatingMode?, scope: LeaderboardScope) async throws -> SoloStanding {
        let rows: [SoloStanding] = try await client
            .rpc("my_solo_standing", params: SoloParams(p_game: game.rawValue, p_mode: mode?.rawValue, p_scope: scope.rawValue))
            .execute().value
        guard let row = rows.first else { throw LeaderboardError.missingStanding }
        return row
    }
}

/// What the wins board or one solo board shows for the selected scope (and
/// window, or mode). Ball Knower keeps its own `LeaderboardViewModel`.
@MainActor
final class GamerLeaderboardViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        /// The read failed and there is nothing to show for this selection.
        case failed
    }

    /// What a read is for; the screen reloads when it changes.
    struct Selection: Equatable, Sendable {
        let window: LeaderboardWindow
        let scope: LeaderboardScope
        let mode: QbRatingMode
    }

    /// Which board this reads: the multiplayer wins, or one solo game's best runs.
    enum Source: Equatable, Sendable {
        case wins
        case solo(SoloBoard)
    }

    let source: Source

    @Published private(set) var rows: [BoardEntry] = []
    @Published private(set) var standing: BoardStanding?
    @Published private(set) var phase: Phase = .loading
    /// UI-only state the screen binds directly to; the screen reloads when it changes.
    @Published var window: LeaderboardWindow
    @Published var scope: LeaderboardScope
    @Published var mode: QbRatingMode

    private let client: GamerLeaderboardClient

    init(
        source: Source,
        client: GamerLeaderboardClient,
        window: LeaderboardWindow = .week,
        scope: LeaderboardScope = .all,
        mode: QbRatingMode = .visible
    ) {
        self.source = source
        self.client = client
        self.window = window
        self.scope = scope
        self.mode = mode
    }

    var selection: Selection { Selection(window: window, scope: scope, mode: mode) }

    /// A friends board with nobody else on it: the caller may be ranked alone,
    /// but there is no board to compare against yet.
    var friendsBoardIsEmpty: Bool {
        scope == .friends && !rows.contains { !$0.isMe }
    }

    /// Reads the board for the current selection. A response for a selection
    /// the player has already moved off is dropped, so a slow read can never
    /// overwrite the one they switched to.
    func load() async {
        let requested = selection
        phase = .loading
        do {
            let (freshRows, freshStanding) = try await read(requested)
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

    private func read(_ requested: Selection) async throws -> ([BoardEntry], BoardStanding) {
        switch source {
        case .solo(let board):
            // Only QB Season Builder has modes; the RPC refuses one for any other game.
            let mode: QbRatingMode? = board == .qbSeasonBuilder ? requested.mode : nil
            async let rows = client.soloBoard(game: board.game, mode: mode, scope: requested.scope)
            async let place = client.soloStanding(game: board.game, mode: mode, scope: requested.scope)
            let (freshRows, freshStanding) = try await (rows, place)
            return (freshRows.map { BoardEntry($0, board: board) }, BoardStanding(freshStanding, board: board, scope: requested.scope))
        case .wins:
            async let rows = client.gamerBoard(window: requested.window, scope: requested.scope)
            async let place = client.gamerStanding(window: requested.window, scope: requested.scope)
            let (freshRows, freshStanding) = try await (rows, place)
            return (freshRows.map(BoardEntry.init), BoardStanding(freshStanding, scope: requested.scope))
        }
    }
}
