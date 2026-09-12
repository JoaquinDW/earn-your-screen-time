import Foundation
import OSLog

protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
}

struct CompositeAnalytics: AnalyticsTracking {
    private let trackers: [any AnalyticsTracking]

    init(_ trackers: [any AnalyticsTracking]) {
        self.trackers = trackers
    }

    func track(_ event: AnalyticsEvent) {
        for tracker in trackers {
            tracker.track(event)
        }
    }
}

struct OSLogAnalytics: AnalyticsTracking {
    private let logger: Logger

    init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "EarnYourScreenTime",
        category: String = "Analytics"
    ) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func track(_ event: AnalyticsEvent) {
        if event.properties.isEmpty {
            logger.notice("event=\(event.name, privacy: .public)")
        } else {
            logger.notice(
                "event=\(event.name, privacy: .public) properties=\(event.logProperties, privacy: .public)"
            )
        }
    }
}

@MainActor
enum AppAnalytics {
    static func make() -> any AnalyticsTracking {
        let local = OSLogAnalytics()
        guard MetaAttribution.configureIfAvailable() else { return local }
        return CompositeAnalytics([local, MetaAnalytics()])
    }
}
