import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case invalidRequest(String)
    case badStatus(Int, String?)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case requestFailed(Error)
    case invalidResponse
    case responseTooLarge(limit: Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The service URL is invalid."
        case .invalidRequest(let message):
            return "The request is invalid: \(message)"
        case .badStatus(let status, let message):
            let suffix = message.map { " \($0)" } ?? ""
            return "The server returned HTTP \(status).\(suffix)"
        case .encodingFailed:
            return "The request could not be encoded."
        case .decodingFailed:
            return "The server returned data in an unexpected format."
        case .requestFailed(let error):
            return "The service could not be reached: \(error.localizedDescription)"
        case .invalidResponse:
            return "The server returned an invalid response."
        case .responseTooLarge(let limit):
            return "The server response exceeded the \(limit)-byte safety limit."
        case .noData:
            return "The server returned no data."
        }
    }
}

protocol NetworkSession: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkSession {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

actor NetworkClient {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
    }

    struct Configuration: Sendable {
        var requestTimeout: TimeInterval = 20
        var maximumResponseBytes: Int = 16 * 1_024 * 1_024
        var maximumErrorBytes: Int = 512

        static let `default` = Configuration()
    }

    static let shared = NetworkClient()

    private let session: any NetworkSession
    private let configuration: Configuration
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        session: (any NetworkSession)? = nil,
        configuration: Configuration = .default
    ) {
        if let session {
            self.session = session
        } else {
            let urlConfiguration = URLSessionConfiguration.ephemeral
            urlConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
            urlConfiguration.timeoutIntervalForResource = max(configuration.requestTimeout * 2, configuration.requestTimeout)
            urlConfiguration.waitsForConnectivity = true
            urlConfiguration.requestCachePolicy = .reloadRevalidatingCacheData
            self.session = URLSession(configuration: urlConfiguration)
        }

        self.configuration = configuration

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let encoder = JSONEncoder()
        // Backend contracts use explicit camelCase field names. Do not silently
        // rewrite them at the transport layer.
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
    }

    func get<Response: Decodable>(
        _ url: URL,
        query: [URLQueryItem] = [],
        headers: [String: String] = [:],
        as responseType: Response.Type = Response.self,
        maximumResponseBytes: Int? = nil
    ) async throws -> Response {
        let request = try makeRequest(url: url, method: .get, query: query, headers: headers, body: nil)
        return try await send(request, as: responseType, maximumResponseBytes: maximumResponseBytes)
    }

    func post<Request: Encodable, Response: Decodable>(
        _ url: URL,
        body: Request,
        headers: [String: String] = [:],
        as responseType: Response.Type = Response.self,
        maximumResponseBytes: Int? = nil
    ) async throws -> Response {
        let encoded: Data
        do {
            encoded = try encoder.encode(body)
        } catch {
            throw NetworkError.encodingFailed(error)
        }

        let request = try makeRequest(url: url, method: .post, headers: headers, body: encoded)
        return try await send(request, as: responseType, maximumResponseBytes: maximumResponseBytes)
    }

    func send<Response: Decodable>(
        _ request: URLRequest,
        as responseType: Response.Type = Response.self,
        maximumResponseBytes: Int? = nil
    ) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NetworkError.requestFailed(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw NetworkError.badStatus(httpResponse.statusCode, boundedErrorMessage(from: data))
        }

        let limit = max(1, maximumResponseBytes ?? configuration.maximumResponseBytes)
        guard data.count <= limit else { throw NetworkError.responseTooLarge(limit: limit) }
        guard !data.isEmpty else { throw NetworkError.noData }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw NetworkError.decodingFailed(error)
        }
    }

    private func makeRequest(
        url: URL,
        method: Method,
        query: [URLQueryItem] = [],
        headers: [String: String],
        body: Data?
    ) throws -> URLRequest {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil,
              components.password == nil,
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && isLocalHost(components.host)) else {
            throw NetworkError.invalidURL
        }

        if !query.isEmpty {
            components.queryItems = (components.queryItems ?? []) + query
        }
        guard let finalURL = components.url else { throw NetworkError.invalidURL }
        guard method != .get || body == nil else {
            throw NetworkError.invalidRequest("GET requests cannot include a body.")
        }

        var request = URLRequest(url: finalURL)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.timeoutInterval = configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") }

        for (name, value) in headers where isSafeHeader(name: name, value: value) {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func boundedErrorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let prefix = data.prefix(max(1, configuration.maximumErrorBytes))
        let raw = String(decoding: prefix, as: UTF8.self)
        let cleaned = raw
            .components(separatedBy: .controlCharacters)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func isSafeHeader(name: String, value: String) -> Bool {
        guard !name.isEmpty,
              name.rangeOfCharacter(from: .newlines) == nil,
              value.rangeOfCharacter(from: .newlines) == nil else { return false }
        let blocked = ["host", "content-length", "connection"]
        return !blocked.contains(name.lowercased())
    }

    private func isLocalHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
