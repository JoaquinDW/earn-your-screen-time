import Foundation

/// The languages Earnit ships strings for. A case may only be added once the matching
/// `.lproj` directory exists under `App/Resources`, because that directory is what makes
/// XcodeGen register the region and what the Screen Time extensions load their bundle from.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case spanish
    case german
    case french
    case italian
    case portugueseBrazil
    case japanese

    static let defaultsKey = "app.language.preference.v1"

    var id: Self { self }

    /// The `.lproj` resource name, or `nil` when the system's own choice wins.
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .spanish: "es"
        case .german: "de"
        case .french: "fr"
        case .italian: "it"
        case .portugueseBrazil: "pt-BR"
        case .japanese: "ja"
        }
    }

    var locale: Locale {
        guard let localeIdentifier else { return .autoupdatingCurrent }
        return Locale(identifier: localeIdentifier)
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
