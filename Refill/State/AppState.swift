import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var profile: Profile = Profile()
    /// Requests created by the signed-in teacher on this device.
    @Published var needs: [ClassroomNeed] = []
    @Published var matches: [FundingMatch] = []
    @Published var donations: [Donation] = []
    @Published var notifications: [NotificationItem] = []
    @Published var unreadNotificationCount: Int = 0
    @Published var hasCompletedOnboarding: Bool = false

    /// Published community projects shown in supporter discovery. This is kept
    /// separate from `needs` so teachers never gain controls over another class.
    @Published var allNeeds: [ClassroomNeed] = []
    @Published var needsLoading: Bool = false
    @Published var needsError: Error?
    @Published var needsLastUpdated: Date?
    @Published var favoriteNeedIDs: Set<UUID> = []
    @Published var feedIsUsingSampleData: Bool = true
    @Published var feedContainsSampleData: Bool = true
    @Published var feedSourceLabel: String = "Sample classrooms"

    private let needsService: ClassroomNeedsService
    private var cancellables: Set<AnyCancellable> = []
    private var didBootstrap = false
    private var isRestoring = false
    private var lastNeedsLoadAttempt: Date?

    private static let snapshotKey = "refill.app-state.v2"

    private struct Snapshot: Codable {
        var profile: Profile
        var needs: [ClassroomNeed]
        var matches: [FundingMatch]
        var donations: [Donation]
        var notifications: [NotificationItem]
        var favoriteNeedIDs: Set<UUID>
        var hasCompletedOnboarding: Bool
    }

    init() {
        self.needsService = ClassroomNeedsService()
        restoreSnapshot()
        observePersistentState()
        recomputeUnread()
    }

    init(needsService: ClassroomNeedsService) {
        self.needsService = needsService
        restoreSnapshot()
        observePersistentState()
        recomputeUnread()
    }

    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        recomputeUnread()
        loadNeedsFromAPI()
    }

    func loadNeedsFromAPI() {
        guard !needsLoading else { return }
        lastNeedsLoadAttempt = Date()
        needsLoading = true
        needsError = nil
        Task {
            do {
                let fetched = try await needsService.fetchNeeds()
                guard !fetched.isEmpty else {
                    throw NetworkError.noData
                }

                let previousByID = Dictionary(uniqueKeysWithValues: allNeeds.map { ($0.id, $0) })
                let refreshed = fetched.map { incoming -> ClassroomNeed in
                    guard let previous = previousByID[incoming.id] else { return incoming }
                    var merged = incoming
                    // Preserve a locally verified update until the upstream feed
                    // catches up, while never reducing provider-reported totals.
                    merged.raised = max(incoming.raised, previous.raised)
                    merged.donorCount = max(incoming.donorCount, previous.donorCount)
                    merged.fundingProgress = min(max(merged.raised / max(merged.fundingGoal, 1), 0), 1)
                    if merged.fundingProgress >= 1 { merged.status = .funded }
                    return merged
                }

                publishCommunityFeed(remoteNeeds: refreshed)
                needsLastUpdated = needsService.lastUpdated ?? Date()

                let origins = Set(refreshed.map(\.resolvedOrigin))
                let hasSample = origins.contains(.sample)
                let hasDonorsChoose = origins.contains(.donorsChoose)
                let hasCommunity = origins.contains(.local)
                let hasLive = hasDonorsChoose || hasCommunity
                feedIsUsingSampleData = !hasLive
                feedContainsSampleData = hasSample
                switch (hasSample, hasDonorsChoose, hasCommunity) {
                case (true, false, false):
                    feedSourceLabel = "Sample classrooms · configure the live API"
                case (true, true, _):
                    feedSourceLabel = "Live DonorsChoose + sample previews"
                case (true, false, true):
                    feedSourceLabel = "Refill community + sample previews"
                case (false, true, true):
                    feedSourceLabel = "DonorsChoose + Refill community"
                case (false, true, false):
                    feedSourceLabel = "Live DonorsChoose projects"
                case (false, false, true):
                    feedSourceLabel = "Refill community"
                default:
                    feedSourceLabel = "No classroom source"
                }
            } catch {
                needsError = error
            }

            needsLoading = false
        }
    }

    private func publishCommunityFeed(remoteNeeds: [ClassroomNeed]) {
        var seen = Set<UUID>()
        allNeeds = (needs.filter { $0.status != .closed } + remoteNeeds)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func refreshNeeds() {
        loadNeedsFromAPI()
    }

    func refreshNeedsIfStale(maximumAge: TimeInterval = 15 * 60) {
        guard !needsLoading else { return }
        guard let referenceDate = needsLastUpdated ?? lastNeedsLoadAttempt else {
            loadNeedsFromAPI()
            return
        }
        if Date().timeIntervalSince(referenceDate) > maximumAge {
            loadNeedsFromAPI()
        }
    }

    func recomputeUnread() {
        unreadNotificationCount = notifications.filter { !$0.isRead }.count
    }

    func markAllNotificationsRead() {
        for i in notifications.indices { notifications[i].isRead = true }
        recomputeUnread()
    }

    func markNotificationRead(_ id: UUID) {
        guard let index = notifications.firstIndex(where: { $0.id == id }) else { return }
        notifications[index].isRead = true
        recomputeUnread()
    }

    func addNeed(_ need: ClassroomNeed, matches: [FundingMatch]) {
        var ownedNeed = need
        ownedNeed.origin = .local
        ownedNeed.sourceID = ownedNeed.sourceID ?? ownedNeed.id.uuidString
        needs.insert(ownedNeed, at: 0)
        self.matches.insert(contentsOf: matches, at: 0)
        upsertPublishedNeed(ownedNeed)
    }

    func updateNeed(_ need: ClassroomNeed) {
        guard let index = needs.firstIndex(where: { $0.id == need.id }) else { return }
        var updated = need
        updated.origin = .local
        needs[index] = updated
        upsertPublishedNeed(updated)
    }

    func closeNeed(_ id: UUID) {
        guard let index = needs.firstIndex(where: { $0.id == id }) else { return }
        needs[index].status = .closed
        matches.removeAll { $0.needId == id }
        allNeeds.removeAll { $0.id == id }
    }

    func deleteNeed(_ id: UUID) {
        needs.removeAll { $0.id == id }
        matches.removeAll { $0.needId == id }
        allNeeds.removeAll { $0.id == id }
        favoriteNeedIDs.remove(id)
    }

    private func upsertPublishedNeed(_ need: ClassroomNeed) {
        if need.status == .closed {
            allNeeds.removeAll { $0.id == need.id }
        } else if let index = allNeeds.firstIndex(where: { $0.id == need.id }) {
            allNeeds[index] = need
        } else {
            allNeeds.insert(need, at: 0)
        }
    }

    func addDonation(_ donation: Donation, to needId: UUID) {
        guard donation.amount > 0 else { return }
        donations.insert(donation, at: 0)
        if let idx = needs.firstIndex(where: { $0.id == needId }) {
            apply(donation: donation, to: &needs[idx])
        }

        if let idx = allNeeds.firstIndex(where: { $0.id == needId }) {
            apply(donation: donation, to: &allNeeds[idx])
        }
    }

    private func apply(donation: Donation, to need: inout ClassroomNeed) {
        need.raised = min(need.raised + donation.amount, max(need.fundingGoal, need.raised + donation.amount))
        need.donorCount += 1
        need.fundingProgress = min(max(need.raised / max(need.fundingGoal, 1), 0), 1)
        if need.fundingProgress >= 1 { need.status = .funded }
    }

    func sendNotification(title: String, body: String, symbol: String = "megaphone.fill", tint: Color? = nil) {
        let note = NotificationItem(title: title, body: body, symbol: symbol, tint: tint ?? SchoolTheme.apple, isRead: false)
        notifications.insert(note, at: 0)
        recomputeUnread()
    }

    func isFavorite(_ need: ClassroomNeed) -> Bool {
        favoriteNeedIDs.contains(need.id)
    }

    func toggleFavorite(_ need: ClassroomNeed) {
        if favoriteNeedIDs.contains(need.id) {
            favoriteNeedIDs.remove(need.id)
        } else {
            favoriteNeedIDs.insert(need.id)
        }
    }

    @discardableResult
    func completeOnboarding() -> Bool {
        guard profile.role != nil else { return false }
        if profile.id == nil {
            let identity = profile.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            profile.id = StableIdentifier.uuid(namespace: "refill-user", value: identity.isEmpty ? UUID().uuidString : identity)
        }
        hasCompletedOnboarding = true
        persistSnapshot()
        return true
    }

    func resetAccount() {
        isRestoring = true
        profile = Profile()
        needs = []
        matches = []
        donations = []
        notifications = []
        favoriteNeedIDs = []
        hasCompletedOnboarding = false
        unreadNotificationCount = 0
        isRestoring = false
        UserDefaults.standard.removeObject(forKey: Self.snapshotKey)
        UserDefaults.standard.removeObject(forKey: "refill.use-live-ai")
    }

    private func restoreSnapshot() {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        isRestoring = true
        profile = snapshot.profile
        needs = snapshot.needs
        matches = snapshot.matches
        donations = snapshot.donations
        notifications = snapshot.notifications
        favoriteNeedIDs = snapshot.favoriteNeedIDs
        hasCompletedOnboarding = snapshot.hasCompletedOnboarding && snapshot.profile.role != nil
        isRestoring = false
    }

    private func observePersistentState() {
        $profile.dropFirst().sink { [weak self] _ in self?.persistSnapshot() }.store(in: &cancellables)
        $needs.dropFirst().sink { [weak self] _ in self?.persistSnapshot() }.store(in: &cancellables)
        $matches.dropFirst().sink { [weak self] _ in self?.persistSnapshot() }.store(in: &cancellables)
        $donations.dropFirst().sink { [weak self] _ in self?.persistSnapshot() }.store(in: &cancellables)
        $notifications.dropFirst().sink { [weak self] _ in
            self?.recomputeUnread()
            self?.persistSnapshot()
        }.store(in: &cancellables)
        $favoriteNeedIDs.dropFirst().sink { [weak self] _ in self?.persistSnapshot() }.store(in: &cancellables)
        $hasCompletedOnboarding.dropFirst().sink { [weak self] _ in self?.persistSnapshot() }.store(in: &cancellables)
    }

    private func persistSnapshot() {
        guard !isRestoring else { return }
        let snapshot = Snapshot(
            profile: profile,
            needs: needs,
            matches: matches,
            donations: donations,
            notifications: notifications,
            favoriteNeedIDs: favoriteNeedIDs,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.snapshotKey)
    }
}

// Private, deterministic fallback that turns plain English into a structured
// draft without sending classroom text off device. Teachers still review and
// edit every field before publishing.
@MainActor
enum AISuppliesParser {
    struct ParseResult {
        var title: String
        var items: [ParsedItem]
        var category: SupplyCategory
        var urgency: Urgency
        var subjectFocus: SubjectFocus
        var summary: String
    }
    
    static func parse(_ text: String) -> ParseResult {
        let lower = text.lowercased()
        let category = detectCategory(lower)
        let urgency = detectUrgency(lower)
        let subject = detectSubject(lower)
        let (qty, unit) = detectQuantityAndUnit(lower)
        let title = makeTitle(text: text, category: category, qty: qty)
        let item = ParsedItem(
            name: displayName(category: category, unit: unit, text: text),
            quantity: qty,
            unitPrice: estimateUnitPrice(category: category, unit: unit),
            category: category
        )
        let items = [item]
        let summary = "Refill found \(qty) \(displayName(category: category, unit: unit, text: text)) for \(subject.rawValue.lowercased()). Suggested funding routes: \(topSourcesText(for: category))"
        return ParseResult(title: title, items: items, category: category, urgency: urgency, subjectFocus: subject, summary: summary)
    }
    
    private static func detectCategory(_ s: String) -> SupplyCategory {
        if s.contains("calculator") || s.contains("laptop") || s.contains("chromebook") || s.contains("tablet") || s.contains("computer") { return .tech }
        if s.contains("book") || s.contains("novel") || s.contains("reader") || s.contains("library") { return .books }
        if s.contains("chair") || s.contains("desk") || s.contains("rug") || s.contains("shelf") || s.contains("table") { return .furniture }
        if s.contains("fidget") || s.contains("calm") || s.contains("wellness") || s.contains("hygiene") || s.contains("tissue") { return .supplies }
        if s.contains("paint") || s.contains("crayon") || s.contains("marker") || s.contains("music") || s.contains("instrument") { return .art }
        if s.contains("math") || s.contains("algebra") || s.contains("fraction") || s.contains("manipulativ") { return .math }
        if s.contains("pencil") || s.contains("paper") || s.contains("supply") || s.contains("supplies") { return .supplies }
        return .other
    }
    
    private static func detectUrgency(_ s: String) -> Urgency {
        if s.contains("today") || s.contains("asap") || s.contains("this week") || s.contains("urgent") || s.contains("tomorrow") { return .thisWeek }
        if s.contains("two weeks") || s.contains("2 weeks") || s.contains("next week") { return .twoWeeks }
        if s.contains("this month") || s.contains("month") { return .thisMonth }
        return .flexible
    }
    
    private static func detectSubject(_ s: String) -> SubjectFocus {
        if s.contains("math") || s.contains("science") || s.contains("stem") || s.contains("robot") { return .stem }
        if s.contains("read") || s.contains("book") || s.contains("literacy") || s.contains("english") { return .literacy }
        if s.contains("art") || s.contains("paint") || s.contains("music") { return .arts }
        if s.contains("calm") || s.contains("wellness") || s.contains("sel") || s.contains("social") { return .sel }
        return .general
    }
    
    private static func detectQuantityAndUnit(_ s: String) -> (Int, String) {
        // Find first number in the text
        let scanner = Scanner(string: s)
        var n: Int = 1
        _ = scanner.scanInt(&n)
        if n <= 0 { n = 1 }
        if n > 500 { n = 500 }
        var unit = "each"
        if s.contains("pack") { unit = "pack" }
        if s.contains("set") { unit = "set" }
        if s.contains("box") { unit = "box" }
        return (n, unit)
    }
    
    private static func displayName(category: SupplyCategory, unit: String, text: String) -> String {
        switch category {
        case .books: return "Classroom chapter books"
        case .tech: return "Educational technology device"
        case .furniture: return "Classroom furniture item"
        case .hygiene: return "Wellness supplies"
        case .art: return "Art supplies"
        case .math: return "Math manipulatives"
        case .supplies: return "General classroom supplies"
        case .other: return "Classroom supplies"
        }
    }
    
    private static func makeTitle(text: String, category: SupplyCategory, qty: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 6 && trimmed.count < 70 { return trimmed.prefix(1).uppercased() + trimmed.dropFirst() }
        return "Need \(qty) \(displayName(category: category, unit: "each", text: text))"
    }
    
    private static func estimateUnitPrice(category: SupplyCategory, unit: String) -> Double {
        switch category {
        case .books: return 6.0
        case .tech: return unit == "set" ? 220.0 : 95.0
        case .furniture: return 75.0
        case .hygiene: return 12.0
        case .art: return 18.0
        case .math: return 14.0
        case .supplies: return 8.0
        case .other: return 15.0
        }
    }
    
    private static func topSourcesText(for category: SupplyCategory) -> String {
        switch category {
        case .books: return "DonorsChoose literacy catalog + local libraries"
        case .tech: return "DonorsChoose STEM + business sponsorships"
        case .furniture: return "Education foundations + parent donations"
        case .hygiene: return "District health funds + business sponsors"
        case .art: return "Arts foundations + PTA grants"
        case .math: return "DonorsChoose + district math initiatives"
        case .supplies: return "Parent donations + community foundations"
        case .other: return "DonorsChoose + business sponsorships"
        }
    }
}
