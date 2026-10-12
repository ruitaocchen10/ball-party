import UIKit
import UserNotifications

/// UIKit's push callbacks have no SwiftUI equivalent, so they come in through
/// an app delegate and go straight to `PushCoordinator`.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in await PushCoordinator.shared.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushCoordinator.shared.didFailToRegister(error) }
    }

    /// A push that arrives while the app is open: the inbox already updates over
    /// Realtime, so this is only the banner.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        // A push we can't read still opens the app; the inbox is the fallback.
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            if let payload { PushCoordinator.shared.didTap(payload) }
            completionHandler()
        }
    }
}
