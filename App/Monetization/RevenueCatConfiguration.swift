import Foundation

struct RevenueCatConfiguration {
    static let apiKeyInfoPlistKey = "RevenueCatAPIKey"
    static let entitlementIdentifier = Entitlements.pro
    static let currentOfferingIdentifier: String? = nil

    let apiKey: String?

    init(bundle: Bundle = .main) {
        let value = bundle.object(forInfoDictionaryKey: Self.apiKeyInfoPlistKey) as? String
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = trimmed.flatMap { $0.isEmpty || $0.contains("YOUR_") ? nil : $0 }
    }

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    var isAvailable: Bool { apiKey != nil }
}
