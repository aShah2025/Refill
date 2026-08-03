import Combine
import Foundation

nonisolated struct NeedFilters: Equatable {
    var categories: Set<SupplyCategory> = []
    var urgencies: Set<Urgency> = []
    var maxAmount: Double?
    var locations: Set<String> = []
    var gradeBands: Set<GradeBand> = []
    var subjectFocuses: Set<SubjectFocus> = []
}

enum ClassroomNeedsError: LocalizedError {
    case backendUnconfigured
    case emptyBackendResponse
    case fixtureMissing
    case fixtureInvalid(Error)
    case noAvailableNeeds(underlying: Error?)

    var errorDescription: String? {
        switch self {
        case .backendUnconfigured:
            return "The live classroom-needs service is not configured."
        case .emptyBackendResponse:
            return "The live classroom-needs service returned no projects."
        case .fixtureMissing:
            return "The bundled sample projects are unavailable."
        case .fixtureInvalid:
            return "The bundled sample projects could not be read."
        case .noAvailableNeeds(let error):
            return error?.localizedDescription ?? "No classroom projects are available."
        }
    }
}

/// Cache-first classroom project repository.
///
/// The live feed comes only from the configured backend. NCES is school
/// reference data and is intentionally never converted into classroom requests.
/// A bundled fixture is the final, explicitly marked sample fallback.
@MainActor
final class ClassroomNeedsService: ObservableObject {
    static let shared = ClassroomNeedsService()

    @Published private(set) var needs: [ClassroomNeed] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: Error?
    @Published private(set) var lastUpdated: Date?

    private let networkClient: NetworkClient
    private let backendConfig: AppConfig.BackendConfig
    private let requestHeaders: [String: String]
    private let cacheFileURL: URL?
    private let fixtureURL: URL?
    private let cacheLifetime: TimeInterval
    private let now: () -> Date
    private let cacheEncoder: JSONEncoder
    private let cacheDecoder: JSONDecoder

    init(
        networkClient: NetworkClient = .shared,
        backendConfig: AppConfig.BackendConfig = .current,
        requestHeaders: [String: String] = [:],
        cacheFileURL: URL? = nil,
        fixtureURL: URL? = nil,
        cacheLifetime: TimeInterval = 24 * 60 * 60,
        now: @escaping () -> Date = Date.init
    ) {
        self.networkClient = networkClient
        self.backendConfig = backendConfig
        self.requestHeaders = requestHeaders
        self.cacheLifetime = max(0, cacheLifetime)
        self.now = now
        self.fixtureURL = fixtureURL ?? Bundle.main.url(forResource: "donorschoose", withExtension: "json")

        if let suppliedCacheURL = cacheFileURL {
            self.cacheFileURL = suppliedCacheURL
        } else if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let directory = appSupport.appendingPathComponent("Refill/Cache", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.cacheFileURL = directory.appendingPathComponent("classroom-needs-v2.json")
        } else {
            self.cacheFileURL = nil
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        self.cacheEncoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.cacheDecoder = decoder
    }

    func bootstrap() async {
        _ = try? await fetchNeeds()
    }

    /// Loads a valid cache before attempting live data. A live success replaces
    /// the cache; a live failure returns the valid cache. The bundled sample is
    /// used only when neither live nor cache can provide projects.
    func fetchNeeds() async throws -> [ClassroomNeed] {
        guard !isLoading else {
            if !needs.isEmpty { return needs }
            throw ClassroomNeedsError.noAvailableNeeds(underlying: lastError)
        }

        isLoading = true
        defer { isLoading = false }
        lastError = nil

        let cached = await loadValidCache()
        if let cached {
            needs = cached.needs
            lastUpdated = cached.timestamp
        }

        var liveFailure: Error?
        if let endpoint = backendConfig.endpoint("v1/needs") {
            do {
                let live = try await fetchLiveNeeds(from: endpoint)
                guard !live.needs.isEmpty else { throw ClassroomNeedsError.emptyBackendResponse }

                needs = live.needs
                lastUpdated = live.fetchedAt
                await saveCache(live.needs, timestamp: live.fetchedAt)
                return live.needs
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                liveFailure = error
                lastError = error
            }
        } else {
            liveFailure = ClassroomNeedsError.backendUnconfigured
        }

        if let cached, !cached.needs.isEmpty {
            return cached.needs
        }

        do {
            let samples = try await loadBundledSamples()
            guard !samples.isEmpty else { throw ClassroomNeedsError.fixtureInvalid(NetworkError.noData) }
            needs = samples
            lastUpdated = nil
            // Keep the backend failure available for diagnostics while the UI
            // clearly labels every returned record as sample data.
            lastError = liveFailure
            return samples
        } catch {
            let underlying = liveFailure ?? error
            lastError = underlying
            throw ClassroomNeedsError.noAvailableNeeds(underlying: underlying)
        }
    }

    func refresh() async throws {
        _ = try await fetchNeeds()
    }

    func fetchNeed(id: String) async throws -> ClassroomNeed? {
        let available = needs.isEmpty ? try await fetchNeeds() : needs
        if let uuid = UUID(uuidString: id) {
            return available.first { $0.id == uuid }
        }
        return available.first { $0.sourceID == id }
    }

    func search(query: String, filters: NeedFilters = NeedFilters()) async -> [ClassroomNeed] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return needs.filter { need in
            let matchesText = term.isEmpty
                || need.title.lowercased().contains(term)
                || need.teacherName.lowercased().contains(term)
                || need.schoolName.lowercased().contains(term)
                || need.rawRequest.lowercased().contains(term)
            let matchesCategory = filters.categories.isEmpty || filters.categories.contains(need.category)
            let matchesUrgency = filters.urgencies.isEmpty || filters.urgencies.contains(need.urgency)
            let matchesAmount = filters.maxAmount.map { need.fundingGoal <= $0 } ?? true
            let matchesLocation = filters.locations.isEmpty || filters.locations.contains(need.city)
            let matchesGrade = filters.gradeBands.isEmpty || filters.gradeBands.contains(need.gradeBand)
            let matchesSubject = filters.subjectFocuses.isEmpty || filters.subjectFocuses.contains(need.subjectFocus)
            return matchesText && matchesCategory && matchesUrgency && matchesAmount
                && matchesLocation && matchesGrade && matchesSubject
        }
    }

    private func fetchLiveNeeds(from endpoint: URL) async throws -> (needs: [ClassroomNeed], fetchedAt: Date) {
        let payload: BackendNeedsResponse = try await networkClient.get(
            endpoint,
            headers: requestHeaders,
            maximumResponseBytes: 8 * 1_024 * 1_024
        )
        let fetchedAt = ServiceValueMapper.date(payload.fetchedAt) ?? now()
        let mapped = payload.needs.compactMap { ClassroomNeedDTOMapper.mapBackend($0, now: fetchedAt) }
        return (deduplicated(mapped), fetchedAt)
    }

    private func loadBundledSamples() async throws -> [ClassroomNeed] {
        guard let fixtureURL else { throw ClassroomNeedsError.fixtureMissing }

        return try await Self.loadBundledSamples(from: fixtureURL)
    }

    static func loadBundledSamples(from fixtureURL: URL) async throws -> [ClassroomNeed] {

        let data: Data
        do {
            data = try await Task.detached(priority: .utility) { try Data(contentsOf: fixtureURL) }.value
        } catch {
            throw ClassroomNeedsError.fixtureInvalid(error)
        }

        do {
            let decoded = try JSONDecoder().decode([FixtureNeedDTO].self, from: data)
            var seen = Set<UUID>()
            return decoded
                .compactMap { ClassroomNeedDTOMapper.mapFixture($0) }
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            throw ClassroomNeedsError.fixtureInvalid(error)
        }
    }

    private func loadValidCache() async -> CachedNeeds? {
        guard let cacheFileURL else { return nil }
        do {
            let data = try await Task.detached(priority: .utility) { try Data(contentsOf: cacheFileURL) }.value
            let cached = try cacheDecoder.decode(CachedNeeds.self, from: data)
            guard cached.version == CachedNeeds.currentVersion,
                  now().timeIntervalSince(cached.timestamp) >= 0,
                  now().timeIntervalSince(cached.timestamp) <= cacheLifetime,
                  !cached.needs.isEmpty else { return nil }
            return cached
        } catch {
            return nil
        }
    }

    private func saveCache(_ needs: [ClassroomNeed], timestamp: Date) async {
        guard let cacheFileURL else { return }
        do {
            let snapshot = CachedNeeds(version: CachedNeeds.currentVersion, timestamp: timestamp, needs: needs)
            let data = try cacheEncoder.encode(snapshot)
            try await Task.detached(priority: .utility) {
                try FileManager.default.createDirectory(
                    at: cacheFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: cacheFileURL, options: [.atomic])
            }.value
        } catch {
            // Cache failure must never turn a successful live response into an
            // application failure. Keep it available for diagnostics.
            lastError = error
        }
    }

    private func deduplicated(_ values: [ClassroomNeed]) -> [ClassroomNeed] {
        var seen = Set<UUID>()
        return values
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

nonisolated private struct CachedNeeds: Codable {
    static let currentVersion = 2
    let version: Int
    let timestamp: Date
    let needs: [ClassroomNeed]
}

// MARK: - Backend transport DTOs

nonisolated private struct BackendNeedsResponse: Decodable {
    let needs: [BackendNeedDTO]
    let source: String?
    let fetchedAt: String?
}

nonisolated private struct BackendNeedDTO: Decodable {
    let sourceId: String
    let sourceName: String
    let sourceURL: String?
    let teacherName: String?
    let teacherPhotoURL: String?
    let teacherBio: String?
    let yearsTeaching: Int?
    let schoolName: String?
    let city: String?
    let state: String?
    let zip: String?
    let schoolType: String?
    let title: String
    let description: String?
    let category: String?
    let gradeLevel: String?
    let studentCount: Int?
    let items: [BackendNeedItemDTO]
    let targetAmount: Double?
    let currentAmount: Double?
    let donorCount: Int?
    let createdAt: String?
    let deadline: String?
    let photoURLs: [String]
    let status: String?
}

nonisolated private struct BackendNeedItemDTO: Decodable {
    let name: String
    let quantity: Int?
    let unitPrice: Double?
    let category: String?
}

// MARK: - Bundled fixture DTOs

nonisolated private struct FixtureNeedDTO: Decodable {
    let id: String
    let teacherName: String
    let teacherPhoto: String?
    let yearsTeaching: Int?
    let schoolName: String
    let city: String
    let state: String
    let zip: String?
    let gradeLevel: String?
    let studentCount: Int?
    let requestTitle: String
    let requestDescription: String?
    let items: [FixtureNeedItemDTO]
    let category: String?
    let urgency: String?
    let primaryFunding: String?
    let communityFunding: [String]?
    let targetAmount: Double?
    let currentAmount: Double?
    let donorCount: Int?
    let aiSummary: String?
    let status: String?
    let createdAt: String?
    let deadline: String?
    let schoolType: String?
    let photoUrls: [String]?
    let teacherBio: String?
}

nonisolated private struct FixtureNeedItemDTO: Decodable {
    let name: String
    let quantity: Int?
    let unitPrice: Double?
    let category: String?
}

// MARK: - Mapping

private enum ClassroomNeedDTOMapper {
    static func mapBackend(_ dto: BackendNeedDTO, now: Date) -> ClassroomNeed? {
        let sourceID = dto.sourceId.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = dto.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceID.isEmpty, !title.isEmpty else { return nil }

        let origin: NeedOrigin = ServiceValueMapper.token(dto.sourceName).contains("donorschoose")
            ? .donorsChoose : .local
        let normalized = NormalizedNeed(
            sourceID: sourceID,
            origin: origin,
            sourceURL: dto.sourceURL,
            teacherName: dto.teacherName,
            teacherPhotoURL: dto.teacherPhotoURL,
            teacherBio: dto.teacherBio,
            yearsTeaching: dto.yearsTeaching,
            schoolName: dto.schoolName,
            city: dto.city,
            state: dto.state,
            zip: dto.zip,
            schoolType: dto.schoolType,
            title: title,
            description: dto.description,
            items: dto.items.map { NormalizedItem(name: $0.name, quantity: $0.quantity, unitPrice: $0.unitPrice, category: $0.category) },
            category: dto.category,
            urgency: nil,
            gradeLevel: dto.gradeLevel,
            subjectFocus: nil,
            studentCount: dto.studentCount,
            fundingSources: origin == .donorsChoose ? ["donorschoose"] : [],
            targetAmount: dto.targetAmount,
            currentAmount: dto.currentAmount,
            donorCount: dto.donorCount,
            createdAt: dto.createdAt,
            deadline: dto.deadline,
            photoURLs: dto.photoURLs,
            status: dto.status,
            aiSummary: nil,
            latitude: nil,
            longitude: nil
        )
        return map(normalized, fallbackDate: now)
    }

    static func mapFixture(_ dto: FixtureNeedDTO) -> ClassroomNeed? {
        let normalized = NormalizedNeed(
            sourceID: dto.id,
            origin: .sample,
            sourceURL: nil,
            teacherName: dto.teacherName,
            teacherPhotoURL: dto.teacherPhoto,
            teacherBio: dto.teacherBio,
            yearsTeaching: dto.yearsTeaching,
            schoolName: dto.schoolName,
            city: dto.city,
            state: dto.state,
            zip: dto.zip,
            schoolType: dto.schoolType,
            title: dto.requestTitle,
            description: dto.requestDescription,
            items: dto.items.map { NormalizedItem(name: $0.name, quantity: $0.quantity, unitPrice: $0.unitPrice, category: $0.category) },
            category: dto.category,
            urgency: dto.urgency,
            gradeLevel: dto.gradeLevel,
            subjectFocus: nil,
            studentCount: dto.studentCount,
            fundingSources: [dto.primaryFunding].compactMap { $0 } + (dto.communityFunding ?? []),
            targetAmount: dto.targetAmount,
            currentAmount: dto.currentAmount,
            donorCount: dto.donorCount,
            createdAt: dto.createdAt,
            deadline: dto.deadline,
            photoURLs: dto.photoUrls ?? [],
            status: dto.status,
            aiSummary: dto.aiSummary,
            latitude: nil,
            longitude: nil
        )
        return map(normalized, fallbackDate: Date(timeIntervalSince1970: 0))
    }

    private static func map(_ dto: NormalizedNeed, fallbackDate: Date) -> ClassroomNeed? {
        let sourceID = dto.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = dto.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceID.isEmpty, !title.isEmpty else { return nil }

        let category = ServiceValueMapper.category(dto.category)
        let deadline = ServiceValueMapper.date(dto.deadline)
        let urgency = ServiceValueMapper.urgency(dto.urgency, deadline: deadline, relativeTo: fallbackDate)
        let gradeBand = ServiceValueMapper.gradeBand(dto.gradeLevel)
        let subject = ServiceValueMapper.subject(dto.subjectFocus, category: category)
        let originNamespace = dto.origin.rawValue

        let items = dto.items.enumerated().compactMap { index, item -> ParsedItem? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            let quantity = min(max(item.quantity ?? 1, 1), 10_000)
            let unitPrice = ServiceValueMapper.nonnegativeAmount(item.unitPrice)
            let itemCategory = ServiceValueMapper.category(item.category, fallback: category)
            return ParsedItem(
                id: StableIdentifier.uuid(
                    namespace: "refill.need-item.\(originNamespace).\(sourceID)",
                    value: "\(index):\(name.lowercased())"
                ),
                name: name,
                quantity: quantity,
                unitPrice: unitPrice,
                category: itemCategory
            )
        }

        let itemTotal = items.reduce(0) { $0 + $1.total }
        let providerGoal = ServiceValueMapper.nonnegativeAmount(dto.targetAmount)
        let goal = providerGoal > 0 ? providerGoal : itemTotal
        let raised = ServiceValueMapper.nonnegativeAmount(dto.currentAmount)
        let progress = goal > 0 ? min(max(raised / goal, 0), 1) : 0
        var status = ServiceValueMapper.status(dto.status)
        if goal > 0, raised >= goal { status = .funded }

        let teacherName = ServiceValueMapper.nonempty(dto.teacherName) ?? "Classroom teacher"
        let schoolName = ServiceValueMapper.nonempty(dto.schoolName) ?? "School not listed"
        let teacherIdentity = "\(schoolName.lowercased()):\(teacherName.lowercased())"
        let city = ServiceValueMapper.location(city: dto.city, state: dto.state)
        let matchedSources = ServiceValueMapper.fundingSources(dto.fundingSources)

        return ClassroomNeed(
            id: StableIdentifier.uuid(namespace: "refill.need.\(originNamespace)", value: sourceID),
            teacherId: StableIdentifier.uuid(namespace: "refill.teacher.\(originNamespace)", value: teacherIdentity),
            teacherName: teacherName,
            schoolName: schoolName,
            title: title,
            rawRequest: ServiceValueMapper.nonempty(dto.description) ?? title,
            items: items,
            category: category,
            urgency: urgency,
            studentCount: min(max(dto.studentCount ?? 0, 0), 100_000),
            gradeBand: gradeBand,
            subjectFocus: subject,
            city: city,
            createdAt: ServiceValueMapper.date(dto.createdAt) ?? fallbackDate,
            fundingProgress: progress,
            fundingGoal: goal,
            raised: raised,
            donorCount: max(dto.donorCount ?? 0, 0),
            matchedSources: matchedSources,
            status: status,
            aiSummary: ServiceValueMapper.nonempty(dto.aiSummary) ?? "",
            origin: dto.origin,
            sourceID: sourceID,
            sourceURL: ServiceValueMapper.safeHTTPSURL(dto.sourceURL),
            teacherPhotoURL: ServiceValueMapper.safeHTTPSURL(dto.teacherPhotoURL),
            teacherBio: ServiceValueMapper.nonempty(dto.teacherBio),
            yearsTeaching: dto.yearsTeaching.map { max($0, 0) },
            deadline: deadline,
            zip: ServiceValueMapper.nonempty(dto.zip),
            schoolType: ServiceValueMapper.nonempty(dto.schoolType),
            photoURLs: {
                let urls = dto.photoURLs.compactMap(ServiceValueMapper.safeHTTPSURL)
                return urls.isEmpty ? nil : urls
            }(),
            latitude: dto.latitude,
            longitude: dto.longitude
        )
    }
}

nonisolated private struct NormalizedNeed {
    let sourceID: String
    let origin: NeedOrigin
    let sourceURL: String?
    let teacherName: String?
    let teacherPhotoURL: String?
    let teacherBio: String?
    let yearsTeaching: Int?
    let schoolName: String?
    let city: String?
    let state: String?
    let zip: String?
    let schoolType: String?
    let title: String
    let description: String?
    let items: [NormalizedItem]
    let category: String?
    let urgency: String?
    let gradeLevel: String?
    let subjectFocus: String?
    let studentCount: Int?
    let fundingSources: [String]
    let targetAmount: Double?
    let currentAmount: Double?
    let donorCount: Int?
    let createdAt: String?
    let deadline: String?
    let photoURLs: [String]
    let status: String?
    let aiSummary: String?
    let latitude: Double?
    let longitude: Double?
}

nonisolated private struct NormalizedItem {
    let name: String
    let quantity: Int?
    let unitPrice: Double?
    let category: String?
}

nonisolated enum ServiceValueMapper {
    static func token(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static func nonnegativeAmount(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return max(value, 0)
    }

    static func safeHTTPSURL(_ value: String?) -> URL? {
        guard let value = nonempty(value),
              let url = URL(string: value),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else { return nil }
        return url
    }

    static func category(_ value: String?, fallback: SupplyCategory = .other) -> SupplyCategory {
        switch token(value) {
        case "books", "books_reading", "literacy": return .books
        case "tech", "technology", "educational_technology": return .tech
        case "supplies", "classroom_supplies", "general_supplies": return .supplies
        case "furniture", "classroom_furniture": return .furniture
        case "hygiene", "wellness", "hygiene_wellness": return .hygiene
        case "art", "music", "art_music", "arts": return .art
        case "math", "math_manipulatives", "mathematics": return .math
        case "other": return .other
        default: return fallback
        }
    }

    static func urgency(_ value: String?, deadline: Date?, relativeTo now: Date) -> Urgency {
        switch token(value) {
        case "this_week", "urgent": return .thisWeek
        case "two_weeks", "within_two_weeks", "within_2_weeks": return .twoWeeks
        case "this_month", "within_a_month": return .thisMonth
        case "flexible": return .flexible
        default:
            guard let deadline else { return .flexible }
            let days = deadline.timeIntervalSince(now) / 86_400
            if days <= 7 { return .thisWeek }
            if days <= 14 { return .twoWeeks }
            if days <= 31 { return .thisMonth }
            return .flexible
        }
    }

    static func gradeBand(_ value: String?) -> GradeBand {
        let raw = token(value)
        if raw.contains("pre_k") || raw.contains("prek") || raw.contains("preschool") || raw == "pk" { return .preK }
        if raw.contains("k_12") || raw.contains("kindergarten_12") { return .multi }
        if raw.contains("elementary") || raw.contains("kindergarten") || raw == "k" { return .elementary }
        if raw.contains("middle") || raw.contains("junior_high") { return .middle }
        if raw.contains("high_school") || raw.contains("high") || raw.contains("ap_") || raw.hasPrefix("ap") { return .high }

        let numbers = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let bands = Set(numbers.compactMap { grade -> GradeBand? in
            if (0...5).contains(grade) { return .elementary }
            if (6...8).contains(grade) { return .middle }
            if (9...12).contains(grade) { return .high }
            return nil
        })
        if bands.count > 1 { return .multi }
        if let band = bands.first { return band }
        return .multi
    }

    static func subject(_ value: String?, category: SupplyCategory) -> SubjectFocus {
        switch token(value) {
        case "stem": return .stem
        case "literacy": return .literacy
        case "arts", "art_music": return .arts
        case "sel", "sel_wellness", "wellness": return .sel
        case "general", "general_supplies": return .general
        case "other": return .other
        default:
            switch category {
            case .books: return .literacy
            case .tech, .math: return .stem
            case .art: return .arts
            case .hygiene: return .sel
            case .supplies, .furniture: return .general
            case .other: return .other
            }
        }
    }

    static func fundingSources(_ values: [String]) -> [FundingSource] {
        var seen = Set<FundingSource>()
        return values.compactMap { value in
            let source: FundingSource?
            switch token(value) {
            case "donorschoose", "donors_choose": source = .donorsChoose
            case "education_foundation", "foundation": source = .foundation
            case "parent_donations", "parents": source = .parents
            case "business_sponsor", "business": source = .business
            case "district_funds", "district": source = .district
            default: source = nil
            }
            guard let source, seen.insert(source).inserted else { return nil }
            return source
        }
    }

    static func status(_ value: String?) -> ClassroomNeed.Status {
        switch token(value) {
        case "funded": return .funded
        case "in_progress", "inprogress": return .inProgress
        case "closed", "expired", "completed": return .closed
        default: return .open
        }
    }

    static func location(city: String?, state: String?) -> String {
        let components = [nonempty(city), nonempty(state)].compactMap { $0 }
        return components.isEmpty ? "Location not listed" : components.joined(separator: ", ")
    }

    static func date(_ value: String?) -> Date? {
        guard let value = nonempty(value) else { return nil }
        if let date = fractionalISO8601.date(from: value) ?? basicISO8601.date(from: value) { return date }
        return dateOnly.date(from: value)
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let basicISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
