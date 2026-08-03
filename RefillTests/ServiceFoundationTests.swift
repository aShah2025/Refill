import Foundation
import XCTest
@testable import Refill

@MainActor
final class ServiceFoundationTests: XCTestCase {
    func testStableIdentifierIsDeterministicNamespacedAndRFC4122Compatible() {
        let first = StableIdentifier.uuid(namespace: "refill.test", value: "alpha")
        let repeated = StableIdentifier.uuid(namespace: "refill.test", value: "alpha")
        let otherValue = StableIdentifier.uuid(namespace: "refill.test", value: "beta")
        let otherNamespace = StableIdentifier.uuid(namespace: "refill.other", value: "alpha")

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, otherValue)
        XCTAssertNotEqual(first, otherNamespace)
        XCTAssertEqual(first.uuidString, "2888B26F-4007-5A0E-9EAF-6B2C0EA511F9")

        let groups = first.uuidString.split(separator: "-")
        XCTAssertEqual(groups.count, 5)
        XCTAssertEqual(groups[2].first, "5", "Stable IDs use the SHA-256-backed UUID v5 layout.")
        let variantNibble = Int(String(groups[3].first!), radix: 16)
        XCTAssertEqual(variantNibble.map { $0 & 0b1100 }, 0b1000, "The RFC 4122 variant bits must be 10.")
    }

    func testAISuppliesParserReturnsDeterministicSemantics() {
        let text = "20 books for literacy this week"
        let first = AISuppliesParser.parse(text)
        let repeated = AISuppliesParser.parse(text)

        XCTAssertEqual(first.title, repeated.title)
        XCTAssertEqual(first.category, repeated.category)
        XCTAssertEqual(first.urgency, repeated.urgency)
        XCTAssertEqual(first.subjectFocus, repeated.subjectFocus)
        XCTAssertEqual(first.summary, repeated.summary)
        XCTAssertEqual(first.items.count, 1)
        XCTAssertEqual(repeated.items.count, 1)

        let item = first.items[0]
        let repeatedItem = repeated.items[0]
        XCTAssertEqual(item.name, repeatedItem.name)
        XCTAssertEqual(item.quantity, repeatedItem.quantity)
        XCTAssertEqual(item.unitPrice, repeatedItem.unitPrice)
        XCTAssertEqual(item.category, repeatedItem.category)

        XCTAssertEqual(first.title, text)
        XCTAssertEqual(first.category, .books)
        XCTAssertEqual(first.urgency, .thisWeek)
        XCTAssertEqual(first.subjectFocus, .literacy)
        XCTAssertEqual(item.name, "Classroom chapter books")
        XCTAssertEqual(item.quantity, 20)
        XCTAssertEqual(item.unitPrice, 6)
        XCTAssertEqual(item.category, .books)
    }

    func testBackendConfigNormalizesSafeURLsSchemesAndEndpoints() throws {
        let config = AppConfig.BackendConfig(
            baseURL: URL(string: "https://api.example.com/root"),
            checkoutCallbackScheme: " ReFill+Checkout "
        )

        XCTAssertEqual(config.baseURL?.absoluteString, "https://api.example.com/root/")
        XCTAssertEqual(config.checkoutCallbackScheme, "refill+checkout")
        XCTAssertEqual(config.endpoint("/v1/needs/")?.absoluteString, "https://api.example.com/root/v1/needs")
        XCTAssertTrue(config.isConfigured)
        XCTAssertTrue(config.isCheckoutConfigured)

        let localhost = AppConfig.BackendConfig(baseURL: URL(string: "http://127.0.0.1:8080/api"))
        XCTAssertEqual(localhost.baseURL?.absoluteString, "http://127.0.0.1:8080/api/")

        let unsafeURLs = [
            "http://api.example.com",
            "https://user:password@api.example.com",
            "https://api.example.com?token=secret",
            "https://api.example.com/root#fragment"
        ]
        for value in unsafeURLs {
            XCTAssertNil(AppConfig.BackendConfig(baseURL: URL(string: value)).baseURL, value)
        }

        let invalidScheme = AppConfig.BackendConfig(
            baseURL: URL(string: "https://api.example.com"),
            checkoutCallbackScheme: "1-not-a-scheme"
        )
        XCTAssertNil(invalidScheme.checkoutCallbackScheme)
        XCTAssertFalse(invalidScheme.isCheckoutConfigured)
    }

    func testBundledFixtureMapsProvenanceRichFieldsAndStableIDs() async throws {
        let fixtureURL = try XCTUnwrap(
            Bundle.main.url(forResource: "donorschoose", withExtension: "json"),
            "The hosted app should bundle donorschoose.json."
        )

        let firstLoad = try await ClassroomNeedsService.loadBundledSamples(from: fixtureURL)
        let repeatedLoad = try await ClassroomNeedsService.loadBundledSamples(from: fixtureURL)

        XCTAssertEqual(firstLoad.count, 6)
        XCTAssertEqual(firstLoad.map(\.id), repeatedLoad.map(\.id))
        XCTAssertEqual(firstLoad.map(\.sourceID), repeatedLoad.map(\.sourceID))
        XCTAssertEqual(Set(firstLoad.map(\.id)).count, firstLoad.count)

        for need in firstLoad {
            let sourceID = try XCTUnwrap(need.sourceID)
            XCTAssertEqual(need.origin, .sample)
            XCTAssertEqual(need.resolvedOrigin, .sample)
            XCTAssertEqual(
                need.id,
                StableIdentifier.uuid(namespace: "refill.need.sample", value: sourceID)
            )
        }

        let sample = try XCTUnwrap(firstLoad.first { $0.sourceID == "dch_001" })
        XCTAssertEqual(sample.id.uuidString, "A8CB6735-19B0-5980-A56B-C68AEF9DDFE4")
        XCTAssertEqual(sample.teacherName, "Sample Teacher A")
        XCTAssertEqual(sample.yearsTeaching, 8)
        XCTAssertNotNil(sample.teacherBio)
        XCTAssertNotNil(sample.deadline)
        XCTAssertEqual(sample.category, .books)
        XCTAssertEqual(sample.urgency, .twoWeeks)
        XCTAssertEqual(sample.fundingGoal, 380)
        XCTAssertEqual(sample.raised, 120)
        XCTAssertEqual(sample.items.count, 2)
        XCTAssertEqual(sample.items[0].id, repeatedLoad.first { $0.sourceID == "dch_001" }?.items[0].id)
    }

    func testNetworkClientRejectsRemoteHTTPBeforeCallingSession() async throws {
        let session = StubbedNetworkSession(stubs: [])
        let client = NetworkClient(session: session)

        do {
            let _: PingResponse = try await client.get(URL(string: "http://api.example.com/ping")!)
            XCTFail("Remote cleartext HTTP should be rejected.")
        } catch let error as NetworkError {
            guard case .invalidURL = error else {
                return XCTFail("Expected invalidURL, got \(error)")
            }
        }

        let requestCount = await session.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testNetworkClientAllowsLocalhostAndDecodesSnakeCase() async throws {
        let session = StubbedNetworkSession(stubs: [
            .init(statusCode: 200, data: Data(#"{"message_text":"pong"}"#.utf8))
        ])
        let client = NetworkClient(session: session)

        let response: PingResponse = try await client.get(
            URL(string: "http://127.0.0.1:8080/v1/ping?existing=one")!,
            query: [URLQueryItem(name: "page", value: "2")]
        )

        XCTAssertEqual(response.messageText, "pong")
        let requests = await session.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        let components = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems, [
            URLQueryItem(name: "existing", value: "one"),
            URLQueryItem(name: "page", value: "2")
        ])
    }

    func testNetworkClientBoundsSuccessfulAndErrorResponses() async throws {
        let oversizedSession = StubbedNetworkSession(stubs: [
            .init(statusCode: 200, data: Data(#"{"message_text":"too large"}"#.utf8))
        ])
        let oversizedClient = NetworkClient(session: oversizedSession)

        do {
            let _: PingResponse = try await oversizedClient.get(
                URL(string: "https://api.example.com/ping")!,
                maximumResponseBytes: 4
            )
            XCTFail("The response should exceed the explicit safety limit.")
        } catch let error as NetworkError {
            guard case .responseTooLarge(let limit) = error else {
                return XCTFail("Expected responseTooLarge, got \(error)")
            }
            XCTAssertEqual(limit, 4)
        }

        let errorSession = StubbedNetworkSession(stubs: [
            .init(statusCode: 503, data: Data("abcdefghijklmnopqrstuvwxyz".utf8))
        ])
        let configuration = NetworkClient.Configuration(
            requestTimeout: 1,
            maximumResponseBytes: 1_024,
            maximumErrorBytes: 8
        )
        let errorClient = NetworkClient(session: errorSession, configuration: configuration)

        do {
            let _: PingResponse = try await errorClient.get(URL(string: "https://api.example.com/ping")!)
            XCTFail("A non-2xx status should fail.")
        } catch let error as NetworkError {
            guard case .badStatus(let status, let message) = error else {
                return XCTFail("Expected badStatus, got \(error)")
            }
            XCTAssertEqual(status, 503)
            XCTAssertEqual(message, "abcdefgh")
        }
    }

    func testCheckoutSuccessCallbackVerifiesAndReturnsReceipt() async throws {
        let sessionID = "cs_test_1234567890abcdef"
        let need = makeLiveNeed()
        let session = StubbedNetworkSession(stubs: [
            .init(statusCode: 200, data: checkoutResponse(sessionID: sessionID)),
            .init(statusCode: 200, data: verificationResponse(sessionID: sessionID, needID: need.id))
        ])
        let authenticator = StubCheckoutAuthenticator(
            callbackURL: URL(string: "refill://checkout/success?session_id=\(sessionID)")!
        )
        let fixedDate = Date(timeIntervalSince1970: 1_721_649_600)
        let service = DonationCheckoutService(
            networkClient: NetworkClient(session: session),
            backendConfig: .init(
                baseURL: URL(string: "https://api.example.com"),
                checkoutCallbackScheme: "refill"
            ),
            requestHeaders: ["X-Test-Client": "RefillTests"],
            authenticator: authenticator,
            now: { fixedDate }
        )

        let receipt = try await service.checkout(
            amount: 12.50,
            to: need,
            from: " Ada Donor ",
            donorEmail: "ada@example.com",
            message: "  For your readers!  "
        )

        XCTAssertEqual(receipt.id, StableIdentifier.uuid(namespace: "refill.receipt.stripe-checkout", value: sessionID))
        XCTAssertEqual(receipt.needId, need.id)
        XCTAssertEqual(receipt.amount, 12.50)
        XCTAssertEqual(receipt.donorName, "Ada Donor")
        XCTAssertEqual(receipt.message, "For your readers!")
        XCTAssertEqual(receipt.transactionId, sessionID)
        XCTAssertEqual(receipt.createdAt, fixedDate)
        XCTAssertEqual(service.lastTransaction, receipt)
        XCTAssertFalse(service.isProcessing)
        XCTAssertNil(service.lastError)

        XCTAssertEqual(authenticator.receivedCallbackSchemes, ["refill"])
        XCTAssertEqual(authenticator.receivedURLs.map(\.host), ["checkout.stripe.com"])

        let requests = await session.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].url?.path, "/v1/donations/checkout")
        XCTAssertNotNil(requests[0].value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "X-Test-Client"), "RefillTests")
        let requestBody = try XCTUnwrap(requests[0].httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual((payload["amountCents"] as? NSNumber)?.intValue, 1_250)
        XCTAssertEqual((payload["need"] as? [String: Any])?["id"] as? String, need.id.uuidString)

        XCTAssertEqual(requests[1].httpMethod, "GET")
        XCTAssertEqual(requests[1].url?.path, "/v1/donations/verify")
        let verifyComponents = try XCTUnwrap(requests[1].url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        XCTAssertEqual(verifyComponents.queryItems, [URLQueryItem(name: "sessionId", value: sessionID)])
    }

    func testCheckoutCancelCallbackStopsBeforeVerification() async throws {
        let sessionID = "cs_test_cancel_1234567890"
        let session = StubbedNetworkSession(stubs: [
            .init(statusCode: 200, data: checkoutResponse(sessionID: sessionID))
        ])
        let authenticator = StubCheckoutAuthenticator(callbackURL: URL(string: "refill://checkout/cancel")!)
        let service = DonationCheckoutService(
            networkClient: NetworkClient(session: session),
            backendConfig: .init(
                baseURL: URL(string: "https://api.example.com"),
                checkoutCallbackScheme: "refill"
            ),
            authenticator: authenticator
        )

        do {
            _ = try await service.checkout(
                amount: 10,
                to: makeLiveNeed(),
                from: "Donor",
                message: ""
            )
            XCTFail("The cancel callback should stop checkout.")
        } catch let error as DonationCheckoutError {
            guard case .cancelled = error else {
                return XCTFail("Expected cancelled, got \(error)")
            }
        }

        let requestCount = await session.requestCount()
        XCTAssertEqual(requestCount, 1, "Cancel must not call the verification endpoint.")
        XCTAssertNil(service.lastTransaction)
        XCTAssertFalse(service.isProcessing)
    }

    func testSampleNeedCanCompleteVerifiedTestCheckout() async throws {
        let sessionID = "cs_test_sample1234567890"
        var need = makeLiveNeed()
        need.origin = .sample
        need.sourceID = "sample-unit-test-need"
        let session = StubbedNetworkSession(stubs: [
            .init(statusCode: 200, data: checkoutResponse(sessionID: sessionID)),
            .init(statusCode: 200, data: verificationResponse(sessionID: sessionID, needID: need.id))
        ])
        let authenticator = StubCheckoutAuthenticator(
            callbackURL: URL(string: "refill://checkout/success?session_id=\(sessionID)")!
        )
        let service = DonationCheckoutService(
            networkClient: NetworkClient(session: session),
            backendConfig: .init(
                baseURL: URL(string: "https://api.example.com"),
                checkoutCallbackScheme: "refill"
            ),
            authenticator: authenticator
        )

        let receipt = try await service.checkout(
            amount: 12.50,
            to: need,
            from: "Sample Tester",
            message: "Testing card checkout"
        )

        XCTAssertEqual(receipt.needId, need.id)
        XCTAssertEqual(receipt.amount, 12.50)
        let requests = await session.recordedRequests()
        let requestBody = try XCTUnwrap(requests.first?.httpBody)
        let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        XCTAssertEqual((payload["need"] as? [String: Any])?["origin"] as? String, "sample")
    }

    private func makeLiveNeed() -> ClassroomNeed {
        ClassroomNeed(
            id: StableIdentifier.uuid(namespace: "refill.need.local", value: "unit-test-need"),
            teacherId: StableIdentifier.uuid(namespace: "refill.teacher.local", value: "unit-test-teacher"),
            teacherName: "Ms. Rivera",
            schoolName: "Refill Elementary",
            title: "Books for emerging readers",
            rawRequest: "We need more classroom books.",
            items: [
                ParsedItem(
                    id: StableIdentifier.uuid(namespace: "refill.need-item.local", value: "books"),
                    name: "Chapter books",
                    quantity: 25,
                    unitPrice: 6,
                    category: .books
                )
            ],
            category: .books,
            urgency: .thisMonth,
            studentCount: 25,
            gradeBand: .elementary,
            subjectFocus: .literacy,
            city: "Oakland, CA",
            fundingProgress: 0.2,
            fundingGoal: 500,
            raised: 100,
            status: .open,
            aiSummary: "A live local test need.",
            origin: .local,
            sourceID: "unit-test-need"
        )
    }

    private func checkoutResponse(sessionID: String) -> Data {
        Data(
            """
            {
              "checkoutSessionId": "\(sessionID)",
              "checkoutURL": "https://checkout.stripe.com/c/pay/\(sessionID)",
              "expiresAt": "2099-01-01T00:00:00Z"
            }
            """.utf8
        )
    }

    private func verificationResponse(sessionID: String, needID: UUID) -> Data {
        Data(
            """
            {
              "checkoutSessionId": "\(sessionID)",
              "paid": true,
              "paymentStatus": "paid",
              "status": "complete",
              "amountTotal": 1250,
              "currency": "usd",
              "needId": "\(needID.uuidString)"
            }
            """.utf8
        )
    }
}

private struct PingResponse: Decodable, Equatable {
    let messageText: String
}

private actor StubbedNetworkSession: NetworkSession {
    struct Stub: Sendable {
        let statusCode: Int
        let data: Data
        let headers: [String: String]

        init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.data = data
            self.headers = headers
        }
    }

    enum StubError: Error {
        case unexpectedRequest
        case invalidResponseURL
    }

    private var stubs: [Stub]
    private var requests: [URLRequest] = []

    init(stubs: [Stub]) {
        self.stubs = stubs
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard !stubs.isEmpty else { throw StubError.unexpectedRequest }
        let stub = stubs.removeFirst()
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: stub.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: stub.headers
              ) else {
            throw StubError.invalidResponseURL
        }
        return (stub.data, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func requestCount() -> Int {
        requests.count
    }
}

@MainActor
private final class StubCheckoutAuthenticator: CheckoutAuthenticating {
    let callbackURL: URL
    private(set) var receivedURLs: [URL] = []
    private(set) var receivedCallbackSchemes: [String] = []

    init(callbackURL: URL) {
        self.callbackURL = callbackURL
    }

    func authenticate(at url: URL, callbackScheme: String) async throws -> URL {
        receivedURLs.append(url)
        receivedCallbackSchemes.append(callbackScheme)
        return callbackURL
    }
}
