import Foundation

/// Runtime configuration for services that are safe to call from the app.
///
/// Values come from the launch environment first (useful for tests and local
/// development), then from generated Info.plist entries. Credentials that can
/// authorize server-side work do not belong in either location; those remain on
/// the backend.
nonisolated enum AppConfig {
    struct BackendConfig: Equatable, Sendable {
        let baseURL: URL?
        let checkoutCallbackScheme: String?

        init(baseURL: URL?, checkoutCallbackScheme: String? = nil) {
            self.baseURL = AppConfig.normalizedBaseURL(baseURL)
            self.checkoutCallbackScheme = AppConfig.normalizedScheme(checkoutCallbackScheme)
        }

        static var current: BackendConfig {
            BackendConfig(
                baseURL: configuredURL(for: "REFILL_BACKEND_BASE_URL"),
                checkoutCallbackScheme: configuredString(for: "REFILL_CHECKOUT_CALLBACK_SCHEME")
            )
        }

        static let unconfigured = BackendConfig(baseURL: nil)

        var isConfigured: Bool { baseURL != nil }
        var isCheckoutConfigured: Bool { baseURL != nil && checkoutCallbackScheme != nil }

        func endpoint(_ path: String) -> URL? {
            guard let baseURL else { return nil }
            let component = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !component.isEmpty else { return baseURL }
            return baseURL.appendingPathComponent(component)
        }
    }

    struct SchoolsAPIConfig: Equatable, Sendable {
        let baseURL: URL
        let academicYear: Int
        let requestLimit: Int

        init(
            baseURL: URL = URL(string: "https://educationdata.urban.org/api/v1/schools/ccd/directory/")!,
            academicYear: Int = 2024,
            requestLimit: Int = 500
        ) {
            self.baseURL = baseURL
            self.academicYear = academicYear
            self.requestLimit = min(max(requestLimit, 1), 1_000)
        }

        static let `default` = SchoolsAPIConfig()
    }

    private static func configuredString(for key: String) -> String? {
        let environmentValue = ProcessInfo.processInfo.environment[key]
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: key) as? String

        for candidate in [environmentValue, bundleValue] {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !value.hasPrefix("$(") else { continue }
            return value
        }
        return nil
    }

    private static func configuredURL(for key: String) -> URL? {
        guard let value = configuredString(for: key), let url = URL(string: value) else { return nil }
        return normalizedBaseURL(url)
    }

    private static func normalizedBaseURL(_ url: URL?) -> URL? {
        guard var components = url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              let host = components.host,
              !host.isEmpty else { return nil }

        let isLocalDevelopment = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard components.scheme?.lowercased() == "https"
                || (isLocalDevelopment && components.scheme?.lowercased() == "http") else { return nil }

        if !components.path.hasSuffix("/") { components.path += "/" }
        return components.url
    }

    private static func normalizedScheme(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty,
              value.range(of: #"^[a-z][a-z0-9+.-]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }
}
