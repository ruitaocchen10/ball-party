import Foundation
import Supabase

/// Which APNs host a device token is good for. A debug build's token is only
/// accepted by the sandbox, a TestFlight or App Store build's only by production,
/// so the server stores which one it is and the sender (#172) picks the host.
enum PushEnvironment: String, Sendable {
    case sandbox, production

    static var current: PushEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }
}

/// The device-token network seam (migration 0205). Which devices a user can be
/// pushed to is the server's record; the app only reports its own token.
protocol DeviceTokenClient: Sendable {
    /// `register_device_token`: also a refresh, and it moves the token to this
    /// account if another account had it.
    func register(token: String, environment: PushEnvironment) async throws
    /// `unregister_device_token`: removes this account's row for the token.
    func unregister(token: String) async throws
}

struct SupabaseDeviceTokenClient: DeviceTokenClient {
    let client: SupabaseClient

    private struct RegisterParams: Encodable, Sendable {
        let p_token: String
        let p_environment: String
    }

    private struct UnregisterParams: Encodable, Sendable { let p_token: String }

    func register(token: String, environment: PushEnvironment) async throws {
        _ = try await client.rpc(
            "register_device_token", params: RegisterParams(p_token: token, p_environment: environment.rawValue)
        ).execute()
    }

    func unregister(token: String) async throws {
        _ = try await client.rpc("unregister_device_token", params: UnregisterParams(p_token: token)).execute()
    }
}
