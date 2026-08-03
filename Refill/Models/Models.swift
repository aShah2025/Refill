import Foundation
import SwiftUI
import CryptoKit

enum StableIdentifier {
    /// Creates the same UUID for the same provider identifier on every launch.
    /// This keeps favorites, cached projects, and donation history attached to
    /// their source records without persisting an arbitrary generated UUID.
    static func uuid(namespace: String, value: String) -> UUID {
        let digest = SHA256.hash(data: Data("\(namespace):\(value)".utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

enum UserRole: String, Codable, CaseIterable, Identifiable {
    case teacher
    case parent
    var id: String { rawValue }
    var displayName: String { self == .teacher ? "Teacher" : "Parent / Supporter" }
    var subtitle: String {
        self == .teacher
            ? "Draft supply requests and compare funding routes to verify."
            : "Discover clearly sourced classroom projects and ways to help."
    }
    var accent: Color {
        self == .teacher ? SchoolTheme.denim : SchoolTheme.apple
    }
    var symbol: String {
        self == .teacher ? "graduationcap.fill" : "heart.text.square.fill"
    }
}

enum GradeBand: String, Codable, CaseIterable, Identifiable {
    case preK = "Pre-K"
    case elementary = "Elementary"
    case middle = "Middle School"
    case high = "High School"
    case multi = "Mixed / Multi-grade"
    var id: String { rawValue }
}

enum SubjectFocus: String, Codable, CaseIterable, Identifiable {
    case stem = "STEM"
    case literacy = "Literacy"
    case arts = "Arts"
    case sel = "SEL & Wellness"
    case general = "General Supplies"
    case other = "Other"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .stem: return "atom"
        case .literacy: return "book.fill"
        case .arts: return "paintpalette.fill"
        case .sel: return "heart.fill"
        case .general: return "pencil.and.outline"
        case .other: return "questionmark.circle"
        }
    }
}

enum Urgency: String, Codable, CaseIterable, Identifiable {
    case thisWeek = "This week"
    case twoWeeks = "Within 2 weeks"
    case thisMonth = "This month"
    case flexible = "Flexible"
    var id: String { rawValue }
    var tint: Color {
        switch self {
        case .thisWeek: return SchoolTheme.apple
        case .twoWeeks: return SchoolTheme.crayonOrange
        case .thisMonth: return SchoolTheme.denimLight
        case .flexible: return SchoolTheme.crayonTeal
        }
    }
}

enum FundingSource: String, Codable, CaseIterable, Identifiable {
    case donorsChoose = "DonorsChoose"
    case foundation = "Education Foundation"
    case parents = "Parent Donations"
    case business = "Business Sponsor"
    case district = "District Funds"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .donorsChoose: return "sparkles"
        case .foundation: return "building.columns.fill"
        case .parents: return "person.3.fill"
        case .business: return "briefcase.fill"
        case .district: return "shield.lefthalf.filled"
        }
    }
    var tint: Color {
        switch self {
        case .donorsChoose: return SchoolTheme.crayonPurple
        case .foundation: return SchoolTheme.denim
        case .parents: return SchoolTheme.apple
        case .business: return SchoolTheme.crayonOrange
        case .district: return SchoolTheme.crayonTeal
        }
    }
}

enum SupplyCategory: String, Codable, CaseIterable, Identifiable {
    case books = "Books & Reading"
    case tech = "Technology"
    case supplies = "Classroom Supplies"
    case furniture = "Furniture"
    case hygiene = "Hygiene & Wellness"
    case art = "Art & Music"
    case math = "Math Manipulatives"
    case other = "Other"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .books: return "books.vertical.fill"
        case .tech: return "laptopcomputer"
        case .supplies: return "pencil.and.outline"
        case .furniture: return "sofa.fill"
        case .hygiene: return "hand.raised.fill"
        case .art: return "paintpalette.fill"
        case .math: return "function"
        case .other: return "questionmark.app"
        }
    }
    var tint: Color {
        switch self {
        case .books: return SchoolTheme.crayonPurple
        case .tech: return SchoolTheme.denim
        case .supplies: return SchoolTheme.pencilYellow
        case .furniture: return SchoolTheme.crayonOrange
        case .hygiene: return SchoolTheme.crayonTeal
        case .art: return SchoolTheme.eraser
        case .math: return SchoolTheme.apple
        case .other: return SchoolTheme.mutedText
        }
    }
}

struct Profile: Codable, Equatable {
    var id: UUID?
    var role: UserRole?
    var fullName: String = ""
    var email: String = ""
    var schoolName: String = ""
    var district: String = ""
    var gradeBand: GradeBand?
    var subjectFocus: SubjectFocus?
    var studentCount: Int = 0
    var city: String = ""
    var zip: String = ""
    var acceptedNotifications: Bool = true
    var notificationCategories: Set<FundingSource> = Set(FundingSource.allCases)

    // Parent/sponsor specific
    var childGrade: GradeBand?
    var interests: Set<SubjectFocus> = []
    var monthlyBudget: Double = 0
}

enum NeedOrigin: String, Codable, CaseIterable, Identifiable {
    case local
    case donorsChoose
    case sample

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .local: return "Refill community"
        case .donorsChoose: return "DonorsChoose"
        case .sample: return "Sample data"
        }
    }

    var isLive: Bool { self != .sample }
}

struct ClassroomNeed: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var teacherId: UUID
    var teacherName: String
    var schoolName: String
    var title: String
    var rawRequest: String
    var items: [ParsedItem]
    var category: SupplyCategory
    var urgency: Urgency
    var studentCount: Int
    var gradeBand: GradeBand
    var subjectFocus: SubjectFocus
    var city: String
    var createdAt: Date = Date()
    var fundingProgress: Double = 0  // 0...1
    var fundingGoal: Double = 0
    var raised: Double = 0
    var donorCount: Int = 0
    var matchedSources: [FundingSource] = []
    var status: Status = .open
    var aiSummary: String = ""

    // Provenance and richer project metadata. Optional fields keep older saved
    // snapshots and bundled fixtures backward compatible.
    var origin: NeedOrigin?
    var sourceID: String?
    var sourceURL: URL?
    var teacherPhotoURL: URL?
    var teacherBio: String?
    var yearsTeaching: Int?
    var deadline: Date?
    var zip: String?
    var schoolType: String?
    var photoURLs: [URL]?
    var latitude: Double?
    var longitude: Double?

    enum Status: String, Codable { case open, funded, inProgress, closed }

    var amountRemaining: Double { max(fundingGoal - raised, 0) }
    var isAcceptingSupport: Bool { status == .open && amountRemaining > 0 }
    var resolvedOrigin: NeedOrigin { origin ?? .sample }
}

struct ParsedItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var quantity: Int
    var unitPrice: Double
    var category: SupplyCategory
    var total: Double { Double(quantity) * unitPrice }
}

struct FundingMatch: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var needId: UUID
    var source: FundingSource
    var headline: String
    var detail: String
    var estimatedAmount: Double
    var confidence: Double   // 0...1
    var nextStep: String
    var urlLabel: String = "Open"
    var actionURL: URL?
    var deadline: Date?
    var providerVerified: Bool?
}

struct Donation: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var needId: UUID
    var needTitle: String
    var donorName: String
    var amount: Double
    var source: FundingSource
    var message: String = ""
    var createdAt: Date = Date()
    var transactionId: String?
    var isVerified: Bool?
    var isTest: Bool?
}

struct NotificationItem: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var createdAt: Date = Date()
    var symbol: String = "bell.fill"
    var tintName: String = "denim"
    var isRead: Bool = false

    var tint: Color {
        switch tintName {
        case "apple": return SchoolTheme.apple
        case "pencilYellow": return SchoolTheme.pencilYellow
        case "crayonPurple": return SchoolTheme.crayonPurple
        case "crayonOrange": return SchoolTheme.crayonOrange
        case "crayonTeal": return SchoolTheme.crayonTeal
        case "denimLight": return SchoolTheme.denimLight
        default: return SchoolTheme.denim
        }
    }

    init(id: UUID = UUID(), title: String, body: String, createdAt: Date = Date(), symbol: String = "bell.fill", tint: Color = SchoolTheme.denim, isRead: Bool = false) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.symbol = symbol
        self.isRead = isRead
        switch tint {
        case SchoolTheme.apple: self.tintName = "apple"
        case SchoolTheme.pencilYellow: self.tintName = "pencilYellow"
        case SchoolTheme.crayonPurple: self.tintName = "crayonPurple"
        case SchoolTheme.crayonOrange: self.tintName = "crayonOrange"
        case SchoolTheme.crayonTeal: self.tintName = "crayonTeal"
        case SchoolTheme.denimLight: self.tintName = "denimLight"
        default: self.tintName = "denim"
        }
    }
}
