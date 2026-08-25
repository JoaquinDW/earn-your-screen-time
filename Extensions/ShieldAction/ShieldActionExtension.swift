import ManagedSettings
import OSLog

final class ShieldActionExtension: ShieldActionDelegate {
    private let logger = Logger(subsystem: "EarnYourScreenTime", category: "Shield")
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(response(for: action))
    }

    private func response(for action: ShieldAction) -> ShieldActionResponse {
        if action == .secondaryButtonPressed {
            logger.notice("event=shield_secondary_action")
            return .close
        }
        guard action == .primaryButtonPressed else { return .none }
        logger.notice("event=shield_primary_action")

        if #available(iOS 26.5, *) {
            ShieldLaunchIntent.mark()
            return .openParentalControlsApp
        }
        // Before iOS 26.5 no public API can open the parent app from a shield. Closing the
        // restricted app is the safest useful response and leaves every restriction intact.
        return .close
    }
}
