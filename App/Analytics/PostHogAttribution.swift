import Foundation
import OSLog
import PostHog

/// Owns PostHog SDK startup. This file belongs only to the app target; extensions must never
/// initialize an analytics SDK or send data from their constrained processes.
@MainActor
enum PostHogAttribution {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "EarnYourScreenTime",
        category: "PostHogAttribution"
    )
    private static var didInitializeSDK = false

    static var isConfigured: Bool {
        PostHogConfiguration().isAvailable
    }

    @discardableResult
    static func configureIfAvailable() -> Bool {
        let configuration = PostHogConfiguration()
        guard configuration.isAvailable else {
            logger.info("PostHog SDK disabled: POSTHOG_API_KEY is missing")
            return false
        }
        guard !didInitializeSDK else { return true }
        guard let apiKey = configuration.apiKey else { return false }

        let config = PostHogConfig(projectToken: apiKey, host: configuration.host)
        // Only the app's ~90 manually-instrumented events are ever sent; no autocapture and no
        // session replay, so a screen never leaks data PRIVACY.md forbids in analytics.
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.sessionReplay = false

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["environment": buildEnvironment])
        didInitializeSDK = true
        logger.info("PostHog SDK initialized (environment=\(buildEnvironment, privacy: .public))")
        return true
    }

    /// "debug" for local builds, "testflight" for a sandbox-receipt install, "release" otherwise.
    private static var buildEnvironment: String {
        #if DEBUG
        "debug"
        #else
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" ? "testflight" : "release"
        #endif
    }
}

private struct PostHogConfiguration {
    private static let apiKeyKey = "PostHogAPIKey"
    private static let hostKey = "PostHogHost"

    let apiKey: String?
    let host: String

    init(bundle: Bundle = .main) {
        apiKey = Self.configuredValue(for: Self.apiKeyKey, bundle: bundle)
        host = Self.configuredValue(for: Self.hostKey, bundle: bundle) ?? PostHogConfig.defaultHost
    }

    var isAvailable: Bool { apiKey != nil }

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

struct PostHogAnalytics: AnalyticsTracking {
    func track(_ event: AnalyticsEvent) {
        let properties = event.properties.mapValues(\.postHogValue)
        PostHogSDK.shared.capture(event.name, properties: properties.isEmpty ? nil : properties)
    }
}

private extension AnalyticsPropertyValue {
    var postHogValue: Any {
        switch self {
        case let .string(value): value
        case let .int(value): value
        case let .bool(value): value
        }
    }
}
