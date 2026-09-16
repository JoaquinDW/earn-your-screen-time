import Foundation

enum AppConfiguration {
    static let termsOfUseURL = configuredURL(for: "TermsOfUseURL")
    static let privacyPolicyURL = configuredURL(for: "PrivacyPolicyURL")
    static let supabaseURL = configuredURL(for: "SupabaseURL")
    static let supabasePublishableKey = configuredString(for: "SupabasePublishableKey")

    private static func configuredURL(for key: String, bundle: Bundle = .main) -> URL? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: value),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }

    private static func configuredString(for key: String, bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("$(") else { return nil }
        return trimmed
    }
}
