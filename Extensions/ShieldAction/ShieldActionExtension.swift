import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
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
        guard action == .primaryButtonPressed else { return .none }

        if #available(iOS 26.5, *) {
            return .openParentalControlsApp
        }
        // Before iOS 26.5 no public API can open the parent app from a shield. Closing the
        // restricted app is the safest useful response and leaves every restriction intact.
        return .close
    }
}
