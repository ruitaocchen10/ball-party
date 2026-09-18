import Foundation
import Supabase

// The subscription lifecycle every screen's channel shares, in one place —
// `docs/architecture/architecture.md` gives this module "subscription
// lifecycle, presence, reconnect", and `docs/architecture/realtime.md`
// describes the shape as identical everywhere it is used. Written once here so
// a game's channel and the lobby's cannot drift apart in the ways that matter:
// authenticating the socket before joining, and reconciling on every subscribe.

/// Opens one or more Realtime channels for a screen and merges everything they
/// deliver into a single stream. Cancelling the consuming task tears them down.
///
/// - Parameters:
///   - client: the Supabase client whose socket the channels ride on.
///   - topics: channel topics, without the `realtime:` prefix.
///   - subscribed: the event to emit whenever a channel reports a successful
///     join. This arrives on the first connect *and* on every resubscribe the
///     SDK performs after a dropped connection — there is no separate
///     "reconnected" signal and none is needed, because a full reconcile is
///     the right answer either way.
///   - register: registers the per-table callbacks on the channels, in the
///     order their topics were given, and returns one job per stream to run
///     for as long as the subscription lives. Callbacks must be registered
///     before the join, which is why this is a closure rather than something
///     the caller does afterwards.
func realtimeEvents<Event: Sendable>(
    client: SupabaseClient,
    topics: [String],
    subscribed: Event,
    register: @escaping @Sendable (
        _ channels: [RealtimeChannelV2],
        _ yield: @escaping @Sendable (Event) -> Void
    ) -> [@Sendable () async -> Void]
) -> AsyncStream<Event> {
    AsyncStream { continuation in
        let task = Task {
            let channels = topics.map { client.realtimeV2.channel($0) }
            let jobs = register(channels) { continuation.yield($0) }
            let statuses = channels.map(\.statusChange)

            await withTaskGroup(of: Void.self) { group in
                for job in jobs {
                    group.addTask { await job() }
                }
                for stream in statuses {
                    group.addTask {
                        for await status in stream where status == .subscribed {
                            continuation.yield(subscribed)
                        }
                    }
                }
                group.addTask {
                    // The token has to reach the socket *before* the join. A
                    // subscription is registered with whatever claims the
                    // socket holds at join time, and every table streamed here
                    // gates `select` on `auth.uid()` — so an unauthenticated
                    // socket matches zero rows and nothing errors, the events
                    // just never arrive (`realtime.md`). That is the worst
                    // shape this bug can take, which is why it is not left to
                    // the client library's own timing.
                    await client.realtimeV2.setAuth(try? await client.auth.session.accessToken)
                    for channel in channels {
                        try? await channel.subscribeWithError()
                    }
                }
            }

            for channel in channels {
                await client.realtimeV2.removeChannel(channel)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// A Realtime payload that carries the row as it now stands.
protocol CarriesRow {
    func row<T: Decodable>(as type: T.Type) -> T?
}

extension InsertAction: CarriesRow {
    public func row<T: Decodable>(as type: T.Type) -> T? {
        try? decodeRecord(as: type, decoder: JSONDecoder())
    }
}

extension UpdateAction: CarriesRow {
    public func row<T: Decodable>(as type: T.Type) -> T? {
        try? decodeRecord(as: type, decoder: JSONDecoder())
    }
}

extension AnyAction: CarriesRow {
    /// A delete carries only the row as it *was*. Nothing streamed by this app
    /// deletes mid-match — the tables are append-only or updated in place — so
    /// there is no new row to apply and nothing to do.
    public func row<T: Decodable>(as type: T.Type) -> T? {
        switch self {
        case .insert(let action): action.row(as: type)
        case .update(let action): action.row(as: type)
        case .delete: nil
        }
    }
}

/// Decodes each payload into the row type `event` expects and hands the result
/// to `yield`.
///
/// A payload that fails to decode is dropped rather than throwing: the screen
/// stays on its last good state, and the next reconcile — from the watchdog, a
/// foreground, or a resubscribe — repairs it from the server.
func forwardRows<Action: CarriesRow & Sendable, Row: Decodable, Event>(
    _ payloads: AsyncStream<Action>,
    to yield: @escaping @Sendable (Event) -> Void,
    as event: @escaping @Sendable (Row) -> Event
) async {
    for await payload in payloads {
        guard let row = payload.row(as: Row.self) else { continue }
        yield(event(row))
    }
}
