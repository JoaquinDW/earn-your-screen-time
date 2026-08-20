import Foundation

/// Identifiers shared by the app and its Screen Time extensions.
///
/// If you change the bundle identifier prefix, change it here and in `project.yml` too.
enum AppGroup {
    static let identifier = "group.com.balthasardeweert.earnyourscreentime"

    /// Shared defaults. Falls back to standard defaults so the app still runs (with the
    /// extensions inert) when the App Group capability has not been configured yet.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    static var isConfigured: Bool {
        UserDefaults(suiteName: identifier) != nil
    }
}
