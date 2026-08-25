import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case spanish

    static let defaultsKey = "app.language.preference.v1"

    var id: Self { self }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .spanish: Locale(identifier: "es")
        }
    }

    static var saved: AppLanguage {
        guard let rawValue = AppGroup.defaults.string(forKey: defaultsKey) else { return .system }
        return AppLanguage(rawValue: rawValue) ?? .system
    }

    func save() {
        AppGroup.defaults.set(rawValue, forKey: Self.defaultsKey)
    }
}

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
