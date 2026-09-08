import AuthenticationServices
import Combine
import Foundation
import UIKit

struct Receipt: Identifiable, Codable, Equatable {
    let id: UUID
    let needId: UUID
    let needTitle: String
    let teacherName: String
    let amount: Double
    let donorName: String
    let message: String
    let method: String
    let last4: String?
    let transactionId: String
    let createdAt: Date

    var formattedAmount: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var isTest: Bool { method.contains("Test") }
    var isProcessorVerified: Bool { method != "Refill Test Card" }
}

nonisolated enum SampleCardValidator {
    static let testCardNumber = "4242424242424242"
    static let formattedTestCardNumber = "4242 4242 4242 4242"

    static func formattedCardNumber(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(16))
        return stride(from: 0, to: digits.count, by: 4).map { start in
            let startIndex = digits.index(digits.startIndex, offsetBy: start)
            let endIndex = digits.index(startIndex, offsetBy: min(4, digits.count - start))
            return String(digits[startIndex..<endIndex])
        }.joined(separator: " ")
    }

    static func formattedExpiry(_ value: String) -> String {
        let digits = String(value.filter(\.isNumber).prefix(4))
        guard digits.count > 2 else { return digits }
        let split = digits.index(digits.startIndex, offsetBy: 2)
        return "\(digits[..<split])/\(digits[split...])"
    }

    static func isValidCardNumber(_ value: String) -> Bool {
        value.filter(\.isNumber) == testCardNumber
    }

    static func isValidCVC(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return digits.count == 3 && digits.count == value.count
    }

    static func isValidExpiry(_ value: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let digits = value.filter(\.isNumber)
        guard digits.count == 4,
              let month = Int(digits.prefix(2)),
              let year = Int(digits.suffix(2)),
              (1...12).contains(month) else { return false }
        let current = calendar.dateComponents([.month, .year], from: now)
        guard let currentMonth = current.month, let currentYear = current.year else { return false }
        let fullYear = 2_000 + year
        return fullYear > currentYear || (fullYear == currentYear && month >= currentMonth)
    }
}

enum DonationCheckoutError: LocalizedError {
    case backendUnconfigured
    case callbackSchemeMissing
    case invalidAmount
    case invalidEmail
    case messageTooLong
    case projectUnavailable
    case alreadyProcessing
    case invalidCheckoutURL
    case checkoutExpired
    case browserCouldNotStart
    case cancelled
    case invalidCallback
    case verificationFailed
    case amountMismatch
    case projectMismatch

    var errorDescription: String? {
        switch self {
        case .backendUnconfigured:
            return "Donation checkout is not configured."
        case .callbackSchemeMissing:
            return "The secure checkout callback scheme is not configured."
        case .invalidAmount:
            return "Donations must be between $1 and $1,000."
        case .invalidEmail:
            return "Enter a valid email address."
        case .messageTooLong:
            return "Donation notes must be 500 characters or fewer."
        case .projectUnavailable:
            return "This project is not currently accepting donations."
        case .alreadyProcessing:
            return "A checkout is already in progress."
        case .invalidCheckoutURL:
            return "The server returned an invalid checkout link."
        case .checkoutExpired:
            return "This checkout session expired. Please try again."
        case .browserCouldNotStart:
            return "Secure checkout could not be opened."
        case .cancelled:
            return "Checkout was cancelled."
        case .invalidCallback:
            return "Secure checkout returned an invalid callback."
        case .verificationFailed:
            return "The payment has not been verified."
        case .amountMismatch:
            return "The verified payment amount did not match the donation."
        case .projectMismatch:
            return "The verified payment did not match this classroom project."
        }
    }
}

@MainActor
protocol CheckoutAuthenticating: AnyObject {
    func authenticate(at url: URL, callbackScheme: String) async throws -> URL
}

@MainActor
final class DonationCheckoutService: ObservableObject {
    static let shared = DonationCheckoutService()

    @Published private(set) var isProcessing = false
    @Published private(set) var lastTransaction: Receipt?
    @Published private(set) var lastError: String?

    private let networkClient: NetworkClient
    private let backendConfig: AppConfig.BackendConfig
    private let requestHeaders: [String: String]
    private let authenticator: any CheckoutAuthenticating
    private let now: () -> Date

    init(
        networkClient: NetworkClient = .shared,
        backendConfig: AppConfig.BackendConfig = .current,
        requestHeaders: [String: String] = [:],
        authenticator: (any CheckoutAuthenticating)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.networkClient = networkClient
        self.backendConfig = backendConfig
        self.requestHeaders = requestHeaders
        self.authenticator = authenticator ?? ASWebCheckoutAuthenticator()
        self.now = now
    }

    func checkout(
        amount: Double,
        to need: ClassroomNeed,
        from donorName: String,
        donorEmail: String? = nil,
        message: String
    ) async throws -> Receipt {
        guard !isProcessing else { throw DonationCheckoutError.alreadyProcessing }
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let receipt = try await performCheckout(
                amount: amount,
                need: need,
                donorName: donorName,
                donorEmail: donorEmail,
                message: message
            )
            lastTransaction = receipt
            return receipt
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    private func performCheckout(
        amount: Double,
        need: ClassroomNeed,
        donorName: String,
        donorEmail: String?,
        message: String
    ) async throws -> Receipt {
        guard need.isAcceptingSupport else { throw DonationCheckoutError.projectUnavailable }
        guard amount.isFinite else { throw DonationCheckoutError.invalidAmount }

        let amountCents = Int((amount * 100).rounded())
        guard (100...100_000).contains(amountCents) else { throw DonationCheckoutError.invalidAmount }

        let normalizedEmail = donorEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedEmail, !normalizedEmail.isEmpty {
            guard normalizedEmail.count <= 254,
                  normalizedEmail.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) != nil else {
                throw DonationCheckoutError.invalidEmail
            }
        }

        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedMessage.count <= 500 else { throw DonationCheckoutError.messageTooLong }
        guard let checkoutEndpoint = backendConfig.endpoint("v1/donations/checkout"),
              let verifyEndpoint = backendConfig.endpoint("v1/donations/verify") else {
            throw DonationCheckoutError.backendUnconfigured
        }
        guard let callbackScheme = backendConfig.checkoutCallbackScheme else {
            throw DonationCheckoutError.callbackSchemeMissing
        }

        let normalizedName = donorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceURL = need.sourceURL.flatMap { $0.scheme?.lowercased() == "https" ? $0.absoluteString : nil }
        let payload = CreateCheckoutRequest(
            amountCents: amountCents,
            currency: "usd",
            need: .init(
                id: need.id.uuidString,
                title: String(need.title.prefix(120)),
                teacherName: String(need.teacherName.prefix(100)),
                schoolName: need.schoolName.isEmpty ? nil : String(need.schoolName.prefix(120)),
                origin: need.resolvedOrigin.rawValue,
                sourceName: String(need.resolvedOrigin.displayName.prefix(50)),
                sourceURL: sourceURL
            ),
            donor: normalizedName.isEmpty && (normalizedEmail?.isEmpty != false)
                ? nil
                : .init(
                    name: normalizedName.isEmpty ? nil : String(normalizedName.prefix(100)),
                    email: normalizedEmail?.isEmpty == false ? normalizedEmail : nil
                ),
            message: normalizedMessage.isEmpty ? nil : normalizedMessage
        )

        var headers = requestHeaders
        headers["Idempotency-Key"] = UUID().uuidString.lowercased()
        let created: CreateCheckoutResponse = try await networkClient.post(
            checkoutEndpoint,
            body: payload,
            headers: headers,
            maximumResponseBytes: 64 * 1_024
        )

        guard let checkoutURL = ServiceValueMapper.safeHTTPSURL(created.checkoutURL),
              let checkoutHost = checkoutURL.host?.lowercased(),
              checkoutHost == "stripe.com" || checkoutHost.hasSuffix(".stripe.com") else {
            throw DonationCheckoutError.invalidCheckoutURL
        }
        if let expiresAt = ServiceValueMapper.date(created.expiresAt), expiresAt <= now() {
            throw DonationCheckoutError.checkoutExpired
        }

        let callbackURL = try await authenticator.authenticate(at: checkoutURL, callbackScheme: callbackScheme)
        try validateCallback(
            callbackURL,
            expectedScheme: callbackScheme,
            expectedSessionID: created.checkoutSessionId
        )

        let verified: VerifyCheckoutResponse = try await networkClient.get(
            verifyEndpoint,
            query: [URLQueryItem(name: "sessionId", value: created.checkoutSessionId)],
            headers: requestHeaders,
            maximumResponseBytes: 64 * 1_024
        )

        guard verified.checkoutSessionId == created.checkoutSessionId,
              verified.paid,
              verified.paymentStatus.lowercased() == "paid" else {
            throw DonationCheckoutError.verificationFailed
        }
        guard verified.amountTotal == amountCents,
              verified.currency?.lowercased() == "usd" else {
            throw DonationCheckoutError.amountMismatch
        }
        guard verified.needId == need.id.uuidString else {
            throw DonationCheckoutError.projectMismatch
        }

        let paidAmount = Double(verified.amountTotal ?? amountCents) / 100
        return Receipt(
            id: StableIdentifier.uuid(namespace: "refill.receipt.stripe-checkout", value: verified.checkoutSessionId),
            needId: need.id,
            needTitle: need.title,
            teacherName: need.teacherName,
            amount: paidAmount,
            donorName: normalizedName.isEmpty ? "Anonymous donor" : normalizedName,
            message: normalizedMessage,
            method: need.resolvedOrigin == .sample ? "Stripe Test Checkout" : "Stripe Checkout",
            last4: nil,
            transactionId: verified.checkoutSessionId,
            createdAt: now()
        )
    }

    private func validateCallback(
        _ callbackURL: URL,
        expectedScheme: String,
        expectedSessionID: String
    ) throws {
        guard callbackURL.scheme?.lowercased() == expectedScheme.lowercased(),
              callbackURL.host?.lowercased() == "checkout" else {
            throw DonationCheckoutError.invalidCallback
        }

        switch callbackURL.path {
        case "/cancel":
            throw DonationCheckoutError.cancelled
        case "/success":
            guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  components.queryItems?.first(where: { $0.name == "session_id" })?.value == expectedSessionID else {
                throw DonationCheckoutError.invalidCallback
            }
        default:
            throw DonationCheckoutError.invalidCallback
        }
    }
}

private struct CreateCheckoutRequest: Encodable {
    struct Need: Encodable {
        let id: String
        let title: String
        let teacherName: String
        let schoolName: String?
        let origin: String
        let sourceName: String?
        let sourceURL: String?
    }

    struct Donor: Encodable {
        let name: String?
        let email: String?
    }

    let amountCents: Int
    let currency: String?
    let need: Need
    let donor: Donor?
    let message: String?
}

private struct CreateCheckoutResponse: Decodable {
    let checkoutSessionId: String
    let checkoutURL: String
    let expiresAt: String?
}

private struct VerifyCheckoutResponse: Decodable {
    let checkoutSessionId: String
    let paid: Bool
    let paymentStatus: String
    let status: String?
    let amountTotal: Int?
    let currency: String?
    let needId: String?
}

@MainActor
private final class ASWebCheckoutAuthenticator: NSObject, CheckoutAuthenticating, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func authenticate(at url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
                guard !didResume else { return }
                didResume = true
                self?.activeSession = nil

                if let sessionError = error as? ASWebAuthenticationSessionError,
                   sessionError.code == .canceledLogin {
                    continuation.resume(throwing: DonationCheckoutError.cancelled)
                } else if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL, callbackURL.scheme?.lowercased() == callbackScheme.lowercased() {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: DonationCheckoutError.invalidCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session

            guard session.start() else {
                guard !didResume else { return }
                didResume = true
                activeSession = nil
                continuation.resume(throwing: DonationCheckoutError.browserCouldNotStart)
                return
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let keyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let window = scenes.flatMap(\.windows).first {
            return window
        }
        return UIWindow(frame: UIScreen.main.bounds)
    }
}
