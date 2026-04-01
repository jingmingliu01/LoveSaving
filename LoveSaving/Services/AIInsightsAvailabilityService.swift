import Foundation

struct AIInsightsBackendConfiguration {
    static let baseURLInfoKey = "AI_INSIGHTS_BASE_URL"
    static let baseURLEnvironmentKey = "LOVESAVING_AI_INSIGHTS_BASE_URL"

    let baseURL: URL?

    static func current(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AIInsightsBackendConfiguration {
        let environmentValue = environment[baseURLEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentValue, !environmentValue.isEmpty,
           let url = URL(string: environmentValue) {
            return AIInsightsBackendConfiguration(baseURL: url)
        }

        let infoValue = bundle.object(forInfoDictionaryKey: baseURLInfoKey) as? String
        let trimmedInfoValue = infoValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedInfoValue, !trimmedInfoValue.isEmpty,
           let url = URL(string: trimmedInfoValue) {
            return AIInsightsBackendConfiguration(baseURL: url)
        }

        return AIInsightsBackendConfiguration(baseURL: nil)
    }
}

final class BackendAIInsightsAvailabilityService: AIInsightsAvailabilityServicing {
    private let configuration: AIInsightsBackendConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        configuration: AIInsightsBackendConfiguration = .current(),
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.configuration = configuration
        self.session = session
        self.decoder = decoder
    }

    func fetchAvailability() async -> AIInsightsAvailability {
        guard let baseURL = configuration.baseURL else {
            return .unavailable(reason: "AI Insights backend is not configured for this build.")
        }

        let endpoint = baseURL.appending(path: "api/v1/ai/capabilities")
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unavailable(reason: "AI Insights backend returned an invalid response.")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                return .unavailable(reason: "AI Insights backend is configured but not ready yet.")
            }

            let capabilities = try decoder.decode(AIInsightsCapabilities.self, from: data)
            if capabilities.enabled {
                return .available(capabilities)
            }

            return .unavailable(reason: humanReadableReason(for: capabilities.reason))
        } catch {
            return .unavailable(reason: "AI Insights backend is configured but currently unreachable.")
        }
    }

    private func humanReadableReason(for backendReason: String?) -> String {
        switch backendReason {
        case "missing_backend_configuration":
            return "AI Insights backend is deployed but missing required server configuration."
        case .some(let value) where !value.isEmpty:
            return "AI Insights is currently unavailable: \(value)."
        default:
            return "AI Insights is currently unavailable."
        }
    }
}
