import Foundation
import OSLog

protocol AnalyticsTracking: Sendable {
    func track(_ event: AnalyticsEvent)
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
