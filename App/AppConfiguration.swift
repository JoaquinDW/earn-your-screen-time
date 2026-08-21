import Foundation

enum AppConfiguration {
    static let termsOfUseURL = configuredURL(for: "TermsOfUseURL")
    static let privacyPolicyURL = configuredURL(for: "PrivacyPolicyURL")

    private static func configuredURL(for key: String, bundle: Bundle = .main) -> URL? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}
