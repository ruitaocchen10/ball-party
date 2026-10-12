import Foundation
import OSLog
import UIKit
import UserNotifications

enum PushAuthorization: Sendable { case notDetermined, denied, authorized }

/// The system's side of push, behind a seam so the permission flow runs in tests
/// without a real prompt or APNs.
@MainActor
protocol PushSystem: AnyObject {
    func authorization() async -> PushAuthorization
    /// Shows the system prompt. iOS shows it once per install; after that this
    /// returns the earlier answer without asking.
    func requestAuthorization() async -> Bool
    func registerForRemoteNotifications()
    func unregisterForRemoteNotifications()
    func setBadge(_ count: Int) async
}

@MainActor
final class SystemPush: PushSystem {
    func authorization() async -> PushAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func registerForRemoteNotifications() { UIApplication.shared.registerForRemoteNotifications() }
    func unregisterForRemoteNotifications() { UIApplication.shared.unregisterForRemoteNotifications() }

    func setBadge(_ count: Int) async {
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}

/// Everything about push on the device: when to ask, registering with APNs,
/// telling the server which device is this user's, and routing a tapped push.
///
/// Permission is asked after the player's first meaningful action (locking in a
/// pick, making or joining a room, adding a friend), never at launch, and behind
/// a short pre-prompt: iOS shows its own prompt once, so we only spend it on
/// someone who has said yes to the idea. "Not now" costs nothing and is asked
/// again after `deferral`.
@MainActor
final class PushCoordinator: ObservableObject {
    static let shared = PushCoordinator()

    /// The pre-prompt sheet is up.
    @Published var showingPrePrompt = false
    /// A tapped push that the signed-in tab shell has not acted on yet.
    @Published private(set) var pendingRoute: PushRoute?

    static let deferral: TimeInterval = 14 * 24 * 60 * 60
    private static let tokenKey = "push.deviceToken"
    private static let deferredUntilKey = "push.prePromptDeferredUntil"

    private let system: PushSystem
    private let client: DeviceTokenClient
    private let defaults: UserDefaults
    private let environment: PushEnvironment
    private let now: () -> Date
    private let log = Logger(subsystem: "com.ballparty.app", category: "push")
    private var isSignedIn = false

    init(
        system: PushSystem = SystemPush(),
        client: DeviceTokenClient = SupabaseDeviceTokenClient(client: SupabaseConfig.client),
        defaults: UserDefaults = .standard,
        environment: PushEnvironment = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.system = system
        self.client = client
        self.defaults = defaults
        self.environment = environment
        self.now = now
    }

    /// The token last handed to us by APNs, kept so sign-out can remove it.
    var storedToken: String? { defaults.string(forKey: Self.tokenKey) }

    // MARK: Signed-in lifecycle

    /// Called when the tab shell appears with a session. Someone who already
    /// allowed notifications (an earlier install, Settings) re-registers on every
    /// launch, which is also how a rotated token reaches the server. Someone who
    /// has since turned them off in Settings is taken off the server's list.
    func sessionStarted() async {
        isSignedIn = true
        switch await system.authorization() {
        case .authorized: system.registerForRemoteNotifications()
        case .denied: await removeStoredToken()
        case .notDetermined: break
        }
    }

    /// Before the session ends, while the server can still tell who is asking:
    /// the next person to sign in on this device must not receive this person's pushes.
    func willSignOut() async {
        isSignedIn = false
        await removeStoredToken()
        system.unregisterForRemoteNotifications()
        await system.setBadge(0)
        pendingRoute = nil
    }

    private func removeStoredToken() async {
        guard let token = storedToken else { return }
        do {
            try await client.unregister(token: token)
            defaults.removeObject(forKey: Self.tokenKey)
        } catch {
            // Kept so the next launch can try again; registering the token from
            // another account moves it in any case.
            log.error("could not remove the device token: \(error.localizedDescription)")
        }
    }

    // MARK: APNs callbacks

    func didRegister(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(token, forKey: Self.tokenKey)
        guard isSignedIn else { return }
        do {
            try await client.register(token: token, environment: environment)
        } catch {
            // The next launch registers again.
            log.error("could not upload the device token: \(error.localizedDescription)")
        }
    }

    /// APNs refused (no network, no entitlement in a simulator or an unsigned
    /// build). Nothing to undo: there is no token, so there is nothing to upload.
    func didFailToRegister(_ error: Error) {
        log.error("APNs registration failed: \(error.localizedDescription)")
    }

    // MARK: Permission flow

    /// Called when the player finishes something that matters to them. Shows the
    /// pre-prompt at most once per `deferral`, and only while the system prompt
    /// is still unspent.
    func meaningfulActionCompleted() async {
        guard !showingPrePrompt, isSignedIn else { return }
        if let until = defaults.object(forKey: Self.deferredUntilKey) as? Date, until > now() { return }
        guard await system.authorization() == .notDetermined else { return }
        showingPrePrompt = true
    }

    /// "Turn on notifications": the only place the system prompt is shown.
    func acceptPrePrompt() async {
        showingPrePrompt = false
        if await system.requestAuthorization() { system.registerForRemoteNotifications() }
    }

    func deferPrePrompt() {
        showingPrePrompt = false
        defaults.set(now().addingTimeInterval(Self.deferral), forKey: Self.deferredUntilKey)
    }

    // MARK: Taps and the badge

    func didTap(_ payload: PushPayload) {
        pendingRoute = PushRoute(kind: payload.kind, itemKey: payload.itemKey)
    }

    func consumeRoute() -> PushRoute? {
        defer { pendingRoute = nil }
        return pendingRoute
    }

    /// The app icon's badge is the inbox's unread count.
    func setBadge(_ count: Int) async {
        guard isSignedIn else { return }
        await system.setBadge(count)
    }
}
