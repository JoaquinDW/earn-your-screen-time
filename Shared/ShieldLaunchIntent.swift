import Foundation

/// A short-lived handoff from the system shield action extension to the main app.
enum ShieldLaunchIntent {
    private static let key = "shield.pendingAppLaunch.v1"
    private static let maximumAge: TimeInterval = 30

    static func mark(now: Date = Date()) {
        AppGroup.defaults.set(now, forKey: key)
    }

    static func consume(now: Date = Date()) -> Bool {
        guard let markedAt = AppGroup.defaults.object(forKey: key) as? Date else { return false }
        AppGroup.defaults.removeObject(forKey: key)
        return now.timeIntervalSince(markedAt) >= 0 && now.timeIntervalSince(markedAt) <= maximumAge
    }
}
