import Foundation
import Supabase
import SwiftUI

/// When play begins in a group match, and the server's clock as of asking.
///
/// A room match opens with a three-second countdown the *server* owns: the
/// match carries `play_starts_at`, and every deadline the game set is already
/// pushed back by the same three seconds (`private.begin_match_countdown`). The
/// screen only has to count down to that instant, so every player sees the same
/// numbers, the first phase is full-length once they reach zero, and someone who
/// opens the match late sees what is left.
struct MatchPlayStart: Equatable, Sendable, Decodable {
    /// `nil` when there is nothing to wait for — a solo run.
    let playStartsAt: Date?
    let serverNow: Date

    private enum CodingKeys: String, CodingKey {
        case playStartsAt = "play_starts_at"
        case serverNow = "server_now"
    }

    init(playStartsAt: Date?, serverNow: Date) {
        self.playStartsAt = playStartsAt
        self.serverNow = serverNow
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        playStartsAt = try container.decodeTimestampIfPresent(forKey: .playStartsAt)
        serverNow = try container.decodeTimestamp(forKey: .serverNow)
    }

    /// Seconds until play begins by the server's clock, given that this answer
    /// was fetched at `fetchedAt` on the device and it is `now` there. Measured
    /// against the server's "now" plus the time that has passed locally since,
    /// never the device's own idea of the time. `nil` when there is no
    /// countdown.
    func secondsUntilPlay(fetchedAt: Date, now: Date) -> TimeInterval? {
        guard let playStartsAt else { return nil }
        return playStartsAt.timeIntervalSince(serverNow.addingTimeInterval(now.timeIntervalSince(fetchedAt)))
    }
}

/// The match-start read, as the app sees it. The platform's, not any one
/// game's: every room game counts down the same way.
protocol MatchStartClient: Sendable {
    func playStart(matchId: UUID) async throws -> MatchPlayStart
}

struct SupabaseMatchStartClient: MatchStartClient {
    let client: SupabaseClient

    func playStart(matchId: UUID) async throws -> MatchPlayStart {
        struct Params: Encodable, Sendable { let p_match_id: UUID }
        return try await client.rpc("match_play_start", params: Params(p_match_id: matchId)).execute().value
    }
}

// MARK: - The 3-2-1

/// Plays the start countdown over a match screen until the server's
/// `play_starts_at`. Asks once, as the screen appears; a failed read just means
/// no countdown, since the match is already running underneath.
private struct MatchStartCountdown: ViewModifier {
    let game: MatchGame
    let matchId: UUID
    let client: MatchStartClient

    /// The length of the lead; sets the ring's full circle.
    private static let total = 3

    @State private var count: Int?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let count {
                    StartCountdownView(count: count, total: Self.total, game: game)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: count == nil)
            .task(id: matchId) { await run() }
    }

    private func run() async {
        guard let start = try? await client.playStart(matchId: matchId) else { return }
        let fetchedAt = Date()
        var shown: Int?
        while let remaining = start.secondsUntilPlay(fetchedAt: fetchedAt, now: Date()), remaining > 0 {
            let number = min(Self.total, Int(remaining.rounded(.up)))
            if number != shown {
                shown = number
                count = number
                UIAccessibility.post(notification: .announcement, argument: "\(number)")
            }
            // Wake as the next number is due.
            let untilNext = remaining - Double(number - 1)
            try? await Task.sleep(for: .seconds(max(0.05, untilNext)))
            if Task.isCancelled { return }
        }
        count = nil
    }
}

extension View {
    /// Plays the server-owned 3-2-1 over this screen when the match has one
    /// still to run. See `MatchStartCountdown`.
    func matchStartCountdown(
        game: MatchGame,
        matchId: UUID,
        client: MatchStartClient = SupabaseMatchStartClient(client: SupabaseConfig.client)
    ) -> some View {
        modifier(MatchStartCountdown(game: game, matchId: matchId, client: client))
    }
}
