import Foundation
import os

enum AIInsightsClientError: LocalizedError {
    case backendNotConfigured
    case invalidResponse
    case httpStatus(Int)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .backendNotConfigured:
            return "AI Insights backend is not configured."
        case .invalidResponse:
            return "AI Insights backend returned an invalid response."
        case .httpStatus(let statusCode):
            return "AI Insights backend request failed with status \(statusCode)."
        case .unauthorized:
            return "AI Insights backend request is unauthorized."
        }
    }
}

final class BackendAIInsightsService: AIInsightsServicing {
    private let configuration: AIInsightsBackendConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let authService: AuthServicing
    private let logger = Logger(subsystem: "LoveSaving", category: "AIInsightsBackendService")

    init(
        configuration: AIInsightsBackendConfiguration = .current(),
        session: URLSession = .shared,
        authService: AuthServicing
    ) {
        self.configuration = configuration
        self.session = session
        self.authService = authService

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let rawValue = try container.decode(String.self)

            if let date = AIInsightsDateParser.parse(rawValue) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported ISO8601 date: \(rawValue)"
            )
        }
        self.decoder = decoder

        let encoder = JSONEncoder()
        self.encoder = encoder
    }

    func fetchThreads() async throws -> [AIInsightThread] {
        let request = try await authorizedRequest(path: "api/v1/ai/chats")
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        do {
            return try decoder.decode([AIInsightThread].self, from: data)
        } catch {
            logger.error("fetchThreads decode failed: \(String(describing: error), privacy: .public)")
            logger.error("fetchThreads payload: \(String(decoding: data, as: UTF8.self), privacy: .public)")
            throw error
        }
    }

    func fetchMessages(chatId: String) async throws -> [AIInsightMessage] {
        let request = try await authorizedRequest(path: "api/v1/ai/chats/\(chatId)/messages")
        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        do {
            return try decoder.decode([AIInsightMessage].self, from: data)
        } catch {
            logger.error("fetchMessages decode failed for \(chatId, privacy: .public): \(String(describing: error), privacy: .public)")
            logger.error("fetchMessages payload for \(chatId, privacy: .public): \(String(decoding: data, as: UTF8.self), privacy: .public)")
            throw error
        }
    }

    func streamReply(chatId: String, contextGroupId: String, message: String) -> AsyncThrowingStream<AIInsightStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = try await authorizedRequest(
                        path: "api/v1/ai/chats/\(chatId)/stream",
                        method: "POST"
                    )
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.timeoutInterval = 60

                    request.httpBody = try encoder.encode(StreamChatTurnRequest(message: message, contextGroupId: contextGroupId))

                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response: response)

                    var currentEventName: String?
                    var currentDataLines: [String] = []

                    for try await line in bytes.lines {
                        if line.isEmpty {
                            try emitEvent(name: currentEventName, dataLines: currentDataLines, continuation: continuation)
                            currentEventName = nil
                            currentDataLines = []
                            continue
                        }

                        if line.hasPrefix("event:") {
                            currentEventName = line.dropFirst("event:".count).trimmingCharacters(in: .whitespaces)
                        } else if line.hasPrefix("data:") {
                            var dataLine = String(line.dropFirst("data:".count))
                            if dataLine.first == " " {
                                dataLine.removeFirst()
                            }
                            currentDataLines.append(dataLine)
                        }
                    }

                    if currentEventName != nil || !currentDataLines.isEmpty {
                        try emitEvent(name: currentEventName, dataLines: currentDataLines, continuation: continuation)
                    }
                    continuation.finish()
                } catch {
                    self.logger.error("streamReply failed: \(String(describing: error), privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func renameThread(chatId: String, title: String) async throws -> AIInsightRenameResult {
        var request = try await authorizedRequest(path: "api/v1/ai/chats/\(chatId)", method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RenameThreadRequest(title: title))

        let (data, response) = try await session.data(for: request)
        try validate(response: response)
        let thread = try decoder.decode(AIInsightThread.self, from: data)
        return AIInsightRenameResult(chatId: thread.chatId, title: thread.title)
    }

    func softDeleteThread(chatId: String) async throws {
        let request = try await authorizedRequest(path: "api/v1/ai/chats/\(chatId)", method: "DELETE")
        let (_, response) = try await session.data(for: request)
        try validate(response: response)
    }

    private func authorizedRequest(path: String, method: String = "GET") async throws -> URLRequest {
        guard let baseURL = configuration.baseURL else {
            throw AIInsightsClientError.backendNotConfigured
        }

        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        if let idToken = try await authService.currentIDToken(), !idToken.isEmpty {
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func validate(response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIInsightsClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw AIInsightsClientError.unauthorized
        default:
            throw AIInsightsClientError.httpStatus(httpResponse.statusCode)
        }
    }

    private func emitEvent(
        name: String?,
        dataLines: [String],
        continuation: AsyncThrowingStream<AIInsightStreamEvent, Error>.Continuation
    ) throws {
        guard let name else { return }
        let payload = dataLines.joined(separator: "\n")

        switch name {
        case "metadata":
            do {
                let metadata = try decoder.decode(StreamMetadata.self, from: Data(payload.utf8))
                continuation.yield(.metadata(chatId: metadata.chatId, uid: metadata.uid, groupId: metadata.groupId))
            } catch {
                logger.error("Ignoring malformed metadata event: \(payload, privacy: .public)")
            }
        case "delta":
            continuation.yield(.delta(payload))
        case "done":
            do {
                let done = try decoder.decode(StreamDone.self, from: Data(payload.utf8))
                continuation.yield(.done(title: done.title ?? ""))
            } catch {
                logger.error("Ignoring malformed done event: \(payload, privacy: .public)")
            }
        default:
            return
        }
    }
}

enum AIInsightsDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ rawValue: String) -> Date? {
        if let direct = fractionalFormatter.date(from: rawValue) ?? plainFormatter.date(from: rawValue) {
            return direct
        }

        guard let normalized = normalizeFractionalSeconds(rawValue) else {
            return nil
        }

        return fractionalFormatter.date(from: normalized) ?? plainFormatter.date(from: normalized)
    }

    private static func normalizeFractionalSeconds(_ rawValue: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(.*?)(?:\.(\d+))?(Z|[+\-]\d{2}:\d{2})$"#,
            options: []
        ) else {
            return nil
        }

        let fullRange = NSRange(rawValue.startIndex..., in: rawValue)
        guard let match = regex.firstMatch(in: rawValue, options: [], range: fullRange) else {
            return nil
        }

        guard
            let prefixRange = Range(match.range(at: 1), in: rawValue),
            let suffixRange = Range(match.range(at: 3), in: rawValue)
        else {
            return nil
        }

        let prefix = String(rawValue[prefixRange])
        let suffix = String(rawValue[suffixRange])

        if let fractionalRange = Range(match.range(at: 2), in: rawValue) {
            let fractional = String(rawValue[fractionalRange])
            let normalizedFraction = String(fractional.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            return "\(prefix).\(normalizedFraction)\(suffix)"
        }

        return "\(prefix)\(suffix)"
    }
}

private struct StreamChatTurnRequest: Encodable {
    let message: String
    let contextGroupId: String
}

private struct RenameThreadRequest: Encodable {
    let title: String
}

private struct StreamMetadata: Decodable {
    let chatId: String
    let uid: String
    let groupId: String
}

private struct StreamDone: Decodable {
    let status: String
    let title: String?
}
