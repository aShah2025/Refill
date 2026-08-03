import Foundation

nonisolated enum SchoolsAPIError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "School directory data is temporarily unavailable."
    }
}

/// Read-only school reference data from the Urban Institute Education Data
/// Portal. This service never creates or infers classroom requests.
nonisolated enum SchoolsAPI {
    struct School: Identifiable, Codable, Hashable, Sendable {
        let id: String
        let name: String
        let district: String
        let city: String
        let state: String
        let zip: String
        let street: String?
        let phone: String?
        let gradeLow: String?
        let gradeHigh: String?
        let level: Int
        let enrollment: Int
        let teachersFTE: Double?
        let freeLunch: Int?
        let reducedLunch: Int?
        let charter: Bool
        let magnet: Bool?
        let titleI: Bool?
        let latitude: Double?
        let longitude: Double?
        let website: String?

        var gradeRange: String {
            switch (gradeLow, gradeHigh) {
            case let (low?, high?) where low == high: return low
            case let (low?, high?): return "\(low)–\(high)"
            case (let low?, _): return low
            case (_, let high?): return high
            default: return "K–12"
            }
        }

        var levelName: String {
            switch level {
            case 1: return "Primary"
            case 2: return "Middle"
            case 3: return "High"
            case 4: return "Other"
            default: return "School"
            }
        }
    }

    /// Full state+county Census FIPS values used by the CCD dataset.
    static let ca19CountyFIPS = ["6053", "6087", "6069", "6085"]

    private struct APIRecord: Decodable, Sendable {
        let ncessch: String
        let schoolName: String
        let leaName: String
        let cityLocation: String
        let stateLocation: String
        let zipLocation: String?
        let streetLocation: String?
        let phone: String?
        let lowestGradeOffered: Int?
        let highestGradeOffered: Int?
        let schoolLevel: Int
        let enrollment: Int?
        let teachersFte: Double?
        let freeLunch: Int?
        let reducedPriceLunch: Int?
        let charter: Int?
        let magnet: Int?
        let titleIEligible: Int?
        let latitude: Double?
        let longitude: Double?
        let schoolUrl: String?
        let countyCode: String?
    }

    private struct APIResponse: Decodable, Sendable {
        let count: Int
        let next: URL?
        let results: [APIRecord]
    }

    static func loadCA19Schools(
        client: NetworkClient = .shared,
        config: AppConfig.SchoolsAPIConfig = .default
    ) async throws -> [School] {
        let yearURL = config.baseURL.appendingPathComponent("\(config.academicYear)")

        let statewideRecords: [APIRecord]
        do {
            statewideRecords = try await fetchCaliforniaPages(
                yearURL: yearURL,
                client: client,
                requestLimit: config.requestLimit
            )
        } catch {
            throw SchoolsAPIError.unavailable
        }
        let allowedCounties = Set(ca19CountyFIPS)
        let records = statewideRecords.filter { record in
            guard let county = record.countyCode else { return false }
            return allowedCounties.contains(county)
        }

        guard !records.isEmpty else { throw SchoolsAPIError.unavailable }

        var seen = Set<String>()
        return records
            .filter { seen.insert($0.ncessch).inserted }
            .map(map)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func fetchCaliforniaPages(
        yearURL: URL,
        client: NetworkClient,
        requestLimit: Int
    ) async throws -> [APIRecord] {
        var nextURL: URL? = yearURL
        var firstPage = true
        var records: [APIRecord] = []

        // The provider currently ignores its county and limit filters and can
        // return almost the whole state per request. Fetch each state page once
        // and enforce the county set locally instead of downloading the same
        // multi-megabyte payload four times.
        for _ in 0..<4 {
            guard let pageURL = nextURL else { break }
            let query = firstPage ? [
                URLQueryItem(name: "fips", value: "6"),
                URLQueryItem(name: "limit", value: String(requestLimit))
            ] : []
            let response: APIResponse = try await client.get(
                pageURL,
                query: query,
                maximumResponseBytes: 16 * 1_024 * 1_024
            )
            records.append(contentsOf: response.results)
            nextURL = response.next
            firstPage = false
        }
        return records
    }

    static func search(
        query: String,
        client: NetworkClient = .shared,
        config: AppConfig.SchoolsAPIConfig = .default
    ) async throws -> [School] {
        let schools = try await loadCA19Schools(client: client, config: config)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return schools }
        return schools.filter {
            $0.name.lowercased().contains(term)
                || $0.city.lowercased().contains(term)
                || $0.zip.lowercased().contains(term)
                || $0.district.lowercased().contains(term)
        }
    }

    private static func map(_ record: APIRecord) -> School {
        School(
            id: record.ncessch,
            name: record.schoolName,
            district: record.leaName,
            city: record.cityLocation,
            state: record.stateLocation,
            zip: record.zipLocation ?? "",
            street: record.streetLocation,
            phone: record.phone,
            gradeLow: record.lowestGradeOffered.map(gradeLabel),
            gradeHigh: record.highestGradeOffered.map(gradeLabel),
            level: record.schoolLevel,
            enrollment: max(record.enrollment ?? 0, 0),
            teachersFTE: record.teachersFte,
            freeLunch: record.freeLunch,
            reducedLunch: record.reducedPriceLunch,
            charter: record.charter == 1,
            magnet: record.magnet.map { $0 == 1 },
            titleI: record.titleIEligible.map { $0 == 1 },
            latitude: record.latitude,
            longitude: record.longitude,
            website: record.schoolUrl
        )
    }

    private static func gradeLabel(_ value: Int) -> String {
        switch value {
        case -1: return "PK"
        case 0: return "K"
        case 1...12: return String(value)
        default: return String(value)
        }
    }
}
