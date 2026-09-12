import AppTrackingTransparency
import FacebookCore
import Foundation
import OSLog
import UIKit

/// Owns Meta SDK startup and ATT. This file belongs only to the app target; extensions must
/// never initialize an analytics SDK or send data from their constrained processes.
@MainActor
enum MetaAttribution {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EarnYourScreenTime",
        category: "MetaAttribution"
    )
    private static var isRequestInFlight = false
    private static var didInitializeSDK = false

    static var isConfigured: Bool {
        MetaConfiguration().isAvailable
    }

    @discardableResult
    static func configureIfAvailable() -> Bool {
        guard isConfigured else {
            logger.info("Meta SDK disabled: FACEBOOK_APP_ID or FACEBOOK_CLIENT_TOKEN is missing")
            return false
        }
        guard !didInitializeSDK else { return true }

        Settings.shared.isAutoLogAppEventsEnabled = true
        Settings.shared.isSKAdNetworkReportEnabled = true
        Settings.shared.isAdvertiserIDCollectionEnabled =
            ATTrackingManager.trackingAuthorizationStatus == .authorized
        ApplicationDelegate.shared.initializeSDK()
        didInitializeSDK = true
        logger.info("Meta SDK initialized with App Events and SKAdNetwork reporting enabled")
        return true
    }

    static func requestTrackingAuthorizationIfNeeded() async {
        guard isConfigured, !isRequestInFlight else { return }
        guard UIApplication.shared.applicationState == .active else { return }

        let currentStatus = ATTrackingManager.trackingAuthorizationStatus
        guard currentStatus == .notDetermined else {
            apply(currentStatus)
            return
        }

        isRequestInFlight = true
        defer { isRequestInFlight = false }
        let status = await ATTrackingManager.requestTrackingAuthorization()
        apply(status)
    }

    private static func apply(_ status: ATTrackingManager.AuthorizationStatus) {
        Settings.shared.isAdvertiserIDCollectionEnabled = status == .authorized
        logger.info("ATT status updated: \(status.logDescription, privacy: .public)")
    }
}

private struct MetaConfiguration {
    private static let appIDKey = "FacebookAppID"
    private static let clientTokenKey = "FacebookClientToken"

    let appID: String?
    let clientToken: String?

    init(bundle: Bundle = .main) {
        appID = Self.configuredValue(for: Self.appIDKey, bundle: bundle)
        clientToken = Self.configuredValue(for: Self.clientTokenKey, bundle: bundle)
    }

    var isAvailable: Bool { appID != nil && clientToken != nil }

    private static func configuredValue(for key: String, bundle: Bundle) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let placeholders = ["YOUR_", "TU_", "REPLACE_WITH"]
        guard !value.isEmpty,
              !value.contains("$("),
              !placeholders.contains(where: { value.uppercased().contains($0) }) else { return nil }
        return value
    }
}

struct MetaAnalytics: AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {
        let parameters = Dictionary(uniqueKeysWithValues: event.properties.map { key, value in
            (AppEvents.ParameterName(key), value.metaValue)
        })
        AppEvents.shared.logEvent(AppEvents.Name(event.name), parameters: parameters)

        // Earnit has no account creation. Completing onboarding is its closest meaningful
        // registration conversion, so expose it as Meta's standard registration event too.
        if event.name == AnalyticsEvent.onboardingCompleted.name {
            AppEvents.shared.logEvent(
                .completedRegistration,
                parameters: [.registrationMethod: "onboarding"]
            )
        }
    }
}

private extension AnalyticsPropertyValue {
    var metaValue: Any {
        switch self {
        case let .string(value): value
        case let .int(value): NSNumber(value: value)
        case let .bool(value): NSNumber(value: value)
        }
    }
}

private extension ATTrackingManager.AuthorizationStatus {
    var logDescription: String {
        switch self {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }
}
