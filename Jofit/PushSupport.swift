import UIKit
import UserNotifications

/// Registering for a device token and showing banners while the app is in the foreground both
/// require UIKit's AppDelegate callbacks — there's no pure-SwiftUI equivalent for either.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Set by `JofitApp` once the environment objects exist, so the token can reach
    /// `ReservationStore` as soon as APNs hands it over.
    var onDeviceToken: ((String) -> Void)? {
        // The token can arrive before `JofitApp.onAppear` installs the handler; replay it.
        didSet { if let latestToken { onDeviceToken?(latestToken) } }
    }
    private var latestToken: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        latestToken = tokenString
        onDeviceToken?(tokenString)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[push] failed to register for remote notifications: \(error)")
    }
}

/// Without this, a push that arrives while the app is already open wouldn't show a banner.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
