import Foundation

nonisolated struct AIParsingContext: Encodable, Equatable, Sendable {
    var gradeLevel: String?
    var subject: String?
    var studentCount: Int?
    var urgency: String?

    init(
        gradeLevel: String? = nil,
        subject: String? = nil,
        studentCount: Int? = nil,
        urgency: String? = nil
    ) {
        self.gradeLevel = gradeLevel
        self.subject = subject
        self.studentCount = studentCount
        self.urgency = urgency
    }
}

nonisolated enum AIParsingSource: Equatable, Sendable {
    case backend(model: String)
    case deterministicFallback
}

struct AIParsingOutcome {
    let result: AISuppliesParser.ParseResult
    let source: AIParsingSource
    let fallbackReason: String?
}

enum AIParsingServiceError: LocalizedError {
    case emptyRequest
    case requestTooLong(maximumCharacters: Int)
    case invalidBackendResult

    var errorDescription: String? {
        switch self {
        case .emptyRequest:
            return "Describe the classroom supplies you need."
        case .requestTooLong(let maximumCharacters):
            return "The request must be \(maximumCharacters) characters or fewer."
        case .invalidBackendResult:
            return "The AI service returned an incomplete result."
        }
    }
}

@MainActor
final class AIParsingService {
    static let shared = AIParsingService()

    private let networkClient: NetworkClient
    private let backendConfig: AppConfig.BackendConfig
    private let requestHeaders: [String: String]
    private let maximumCharacters: Int

    init(
        networkClient: NetworkClient = .shared,
        backendConfig: AppConfig.BackendConfig = .current,
        requestHeaders: [String: String] = [:],
        maximumCharacters: Int = 2_000
    ) {
        self.networkClient = networkClient
        self.backendConfig = backendConfig
        self.requestHeaders = requestHeaders
        self.maximumCharacters = max(1, maximumCharacters)
    }

    func parse(
        _ request: String,
        context: AIParsingContext? = nil
    ) async throws -> AIParsingOutcome {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIParsingServiceError.emptyRequest }
        guard trimmed.count <= maximumCharacters else {
            throw AIParsingServiceError.requestTooLong(maximumCharacters: maximumCharacters)
        }

        guard let endpoint = backendConfig.endpoint("v1/ai/parse") else {
            return fallback(for: trimmed, reason: "The live AI service is not configured.")
        }

        do {
            let response: BackendAIParseResponse = try await networkClient.post(
                endpoint,
                body: BackendAIParseRequest(request: trimmed, context: context),
                headers: requestHeaders,
                maximumResponseBytes: 256 * 1_024
            )
            return try map(response, request: trimmed)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard shouldUseFallback(for: error) else { throw error }
            return fallback(for: trimmed, reason: error.localizedDescription)
        }
    }

    private func map(_ response: BackendAIParseResponse, request: String) throws -> AIParsingOutcome {
        let title = response.result.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = response.result.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !summary.isEmpty, !response.result.items.isEmpty else {
            throw AIParsingServiceError.invalidBackendResult
        }

        let category = ServiceValueMapper.category(response.result.category)
        let items = response.result.items.enumerated().compactMap { index, item -> ParsedItem? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.quantity > 0, item.unitPrice.isFinite, item.unitPrice >= 0 else { return nil }
            return ParsedItem(
                id: StableIdentifier.uuid(
                    namespace: "refill.ai-item.\(request.lowercased())",
                    value: "\(index):\(name.lowercased())"
                ),
                name: name,
                quantity: min(item.quantity, 10_000),
                unitPrice: item.unitPrice,
                category: ServiceValueMapper.category(item.category, fallback: category)
            )
        }
        guard !items.isEmpty else { throw AIParsingServiceError.invalidBackendResult }

        let parsed = AISuppliesParser.ParseResult(
            title: title,
            items: items,
            category: category,
            urgency: ServiceValueMapper.urgency(response.result.urgency, deadline: nil, relativeTo: Date()),
            subjectFocus: ServiceValueMapper.subject(response.result.subjectFocus, category: category),
            summary: summary
        )
        return AIParsingOutcome(
            result: parsed,
            source: .backend(model: response.model),
            fallbackReason: nil
        )
    }

    private func fallback(for request: String, reason: String) -> AIParsingOutcome {
        AIParsingOutcome(
            result: AISuppliesParser.parse(request),
            source: .deterministicFallback,
            fallbackReason: reason
        )
    }

    private func shouldUseFallback(for error: Error) -> Bool {
        guard let networkError = error as? NetworkError else { return false }
        switch networkError {
        case .requestFailed, .invalidResponse, .noData, .responseTooLarge:
            return true
        case .badStatus(let status, _):
            return status == 404 || status == 408 || status == 425 || status == 429 || status >= 500
        case .invalidURL, .invalidRequest, .encodingFailed, .decodingFailed:
            return false
        }
    }
}

nonisolated private struct BackendAIParseRequest: Encodable {
    let request: String
    let context: AIParsingContext?
}

nonisolated private struct BackendAIParseResponse: Decodable {
    let result: BackendAIResult
    let model: String
}

nonisolated private struct BackendAIResult: Decodable {
    let title: String
    let summary: String
    let category: String
    let urgency: String
    let subjectFocus: String
    let studentCount: Int?
    let items: [BackendAIItem]
    let suggestedSources: [String]
    let estimatedTotal: Double
}

nonisolated private struct BackendAIItem: Decodable {
    let name: String
    let quantity: Int
    let unitPrice: Double
    let category: String
}
