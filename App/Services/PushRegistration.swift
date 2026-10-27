import UIKit

extension Notification.Name {
    static let pushTokenDidChange = Notification.Name("earnit.pushTokenDidChange")
}

/// Remote notifications exist only for Friends: a friend nudged you, cheered you, added you,
/// or missed their goal. Every other notification Earnit sends is local.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushToken.current = deviceToken.map { String(format: "%02x", $0) }.joined()
        NotificationCenter.default.post(name: .pushTokenDidChange, object: nil)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Without a token friends still see everything in the app's inbox.
    }
}

/// The APNs device token, and the last one the server accepted, so it is uploaded once.
enum PushToken {
    private static let currentKey = "push.deviceToken.v1"
    private static let uploadedKey = "push.deviceToken.uploaded.v1"

    static var current: String? {
        get { UserDefaults.standard.string(forKey: currentKey) }
        set { UserDefaults.standard.set(newValue, forKey: currentKey) }
    }

    static var uploaded: String? {
        get { UserDefaults.standard.string(forKey: uploadedKey) }
        set { UserDefaults.standard.set(newValue, forKey: uploadedKey) }
    }

    /// Debug builds run against the APNs sandbox; TestFlight and the App Store use production.
    static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

/// Whether this person has set up Friends. Nothing about their day leaves the phone before that.
enum SocialStore {
    private static let hasProfileKey = "social.hasProfile.v1"
    private static let unreadKey = "social.unread.v1"

    static var hasProfile: Bool {
        get { UserDefaults.standard.bool(forKey: hasProfileKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasProfileKey) }
    }

    static var unreadCount: Int {
        get { UserDefaults.standard.integer(forKey: unreadKey) }
        set { UserDefaults.standard.set(newValue, forKey: unreadKey) }
    }
}
