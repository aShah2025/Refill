import Combine
import Foundation

enum DonorsChooseError: LocalizedError {
    case fileNotFound
    case invalidData(Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "The bundled classroom-project fixture is missing."
        case .invalidData:
            return "The bundled classroom-project fixture is invalid."
        }
    }
}

/// Compatibility wrapper for callers that need the bundled offline fixture.
/// Returned projects are mapped through the same stable-ID pipeline as the main
/// repository and are always marked with `NeedOrigin.sample`.
@MainActor
final class DonorsChooseLoader: ObservableObject {
    static let shared = DonorsChooseLoader()

    private let fileURL: URL?

    init(fileURL: URL? = Bundle.main.url(forResource: "donorschoose", withExtension: "json")) {
        self.fileURL = fileURL
    }

    func fetchNeeds() async throws -> [ClassroomNeed] {
        guard let fileURL else { throw DonorsChooseError.fileNotFound }
        do {
            return try await ClassroomNeedsService.loadBundledSamples(from: fileURL)
        } catch {
            throw DonorsChooseError.invalidData(error)
        }
    }

    func fetchNeed(id: String) async throws -> ClassroomNeed? {
        let needs = try await fetchNeeds()
        if let uuid = UUID(uuidString: id) {
            return needs.first { $0.id == uuid }
        }
        return needs.first { $0.sourceID == id }
    }
}
