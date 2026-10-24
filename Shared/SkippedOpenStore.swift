import EarnDomain
import Foundation

/// The App Group copy of `SkippedOpenLog`, written by the shield action extension and the
/// blocked-app screen, read by the app.
enum SkippedOpenStore {
    private static let key = "shield.skippedOpens.v1"

    static func load() -> SkippedOpenLog {
        guard let data = AppGroup.defaults.data(forKey: key),
              let log = try? JSONDecoder().decode(SkippedOpenLog.self, from: data) else {
            return SkippedOpenLog()
        }
        return log
    }

    /// Someone reached for a protected app and chose to stay out.
    @discardableResult
    static func recordSkip(now: Date = Date()) -> SkippedOpenLog {
        var log = load()
        log.record(on: DayKey(date: now))
        if let data = try? JSONEncoder().encode(log) {
            AppGroup.defaults.set(data, forKey: key)
        }
        return log
    }
}
