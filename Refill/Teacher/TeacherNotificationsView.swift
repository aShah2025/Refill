import SwiftUI

struct TeacherNotificationsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showCompose = false

    private var shareableNeeds: [ClassroomNeed] {
        guard let teacherID = state.profile.id else { return [] }
        return state.needs.filter {
            $0.teacherId == teacherID && ($0.status == .open || $0.status == .inProgress)
        }
    }

    private var visibleNotifications: [NotificationItem] {
        NotificationPreferenceFilter.visible(state.notifications, for: state.profile)
    }

    private var unreadVisibleNotifications: [NotificationItem] {
        visibleNotifications.filter { !$0.isRead }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    composeCard
                    inboxSection
                }
                .padding(16)
            }
            .background(LinedPaperBackground())
            .navigationTitle("Outreach")
            .sheet(isPresented: $showCompose) {
                ComposeOutreachSheet(
                    needs: shareableNeeds,
                    teacherName: state.profile.fullName.isEmpty ? "A local teacher" : state.profile.fullName
                )
            }
        }
    }

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [SchoolTheme.denim, SchoolTheme.crayonPurple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.16))
                        .frame(width: 64, height: 64)
                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.system(size: 29, weight: .heavy))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("You choose who receives every message.")
                        .font(SchoolTheme.displayFont(size: 18))
                        .foregroundStyle(.white)
                    Text("Refill drafts the words. You review them and choose recipients in Mail, Messages, or another app.")
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(.white.opacity(0.94))
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private var composeCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    SymbolBadge(system: "text.badge.plus", color: SchoolTheme.denim, size: 36, symbolSize: 16)
                        .accessibilityHidden(true)
                    Text("Draft classroom outreach")
                        .font(SchoolTheme.headlineFont(size: 16))
                        .foregroundStyle(SchoolTheme.ink)
                }

                Text("Choose one of your open requests and an audience. Refill will prepare editable copy tailored to that audience.")
                    .font(SchoolTheme.bodyFont(size: 13))
                    .foregroundStyle(SchoolTheme.mutedText)

                privacyNotice

                Button {
                    showCompose = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                        Text("Choose request & draft")
                    }
                    .font(SchoolTheme.headlineFont(size: 15))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(shareableNeeds.isEmpty ? SchoolTheme.mutedText : SchoolTheme.denim)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(shareableNeeds.isEmpty)
                .accessibilityHint(shareableNeeds.isEmpty
                                   ? "Create an open classroom request first"
                                   : "Opens an editable outreach draft")

                if shareableNeeds.isEmpty {
                    Label("Create an open request on Home before drafting outreach.", systemImage: "info.circle")
                        .font(SchoolTheme.bodyFont(size: 12))
                        .foregroundStyle(SchoolTheme.mutedText)
                }
            }
        }
    }

    private var privacyNotice: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(SchoolTheme.crayonTeal)
                .accessibilityHidden(true)
            Text("Refill does not access or send to private parent, staff, sponsor, or funder contact lists. It cannot confirm delivery.")
                .font(SchoolTheme.bodyFont(size: 12))
                .foregroundStyle(SchoolTheme.ink)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(SchoolTheme.crayonTeal.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }

    private var inboxSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Alerts")
                    .font(SchoolTheme.displayFont(size: 20))
                    .foregroundStyle(SchoolTheme.ink)
                Spacer()
                if !unreadVisibleNotifications.isEmpty {
                    Button("Mark all read") {
                        unreadVisibleNotifications.forEach { state.markNotificationRead($0.id) }
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(SchoolTheme.denim)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Mark all visible alerts as read")
                }
            }

            if visibleNotifications.isEmpty {
                notificationEmptyState
            } else {
                ForEach(visibleNotifications) { item in
                    NotificationRow(item: item) {
                        state.markNotificationRead(item.id)
                    }
                }

                preferenceSummary
            }
        }
    }

    private var notificationEmptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: state.profile.acceptedNotifications ? "bell.slash" : "bell.badge.slash.fill")
                .font(.system(size: 32, weight: .heavy))
                .foregroundStyle(SchoolTheme.mutedText)
                .accessibilityHidden(true)
            Text(emptyStateTitle)
                .font(SchoolTheme.headlineFont(size: 15))
                .foregroundStyle(SchoolTheme.ink)
            Text(emptyStateDetail)
                .font(SchoolTheme.bodyFont(size: 12))
                .foregroundStyle(SchoolTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preferenceSummary: some View {
        let hiddenCount = state.notifications.count - visibleNotifications.count
        if hiddenCount > 0 {
            Label(
                "\(hiddenCount) \(hiddenCount == 1 ? "alert is" : "alerts are") hidden by your notification preferences.",
                systemImage: "line.3.horizontal.decrease.circle"
            )
            .font(SchoolTheme.bodyFont(size: 12))
            .foregroundStyle(SchoolTheme.mutedText)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyStateTitle: String {
        if !state.profile.acceptedNotifications { return "Alerts are turned off" }
        if state.profile.notificationCategories.isEmpty { return "No alert categories selected" }
        if !state.notifications.isEmpty { return "No alerts match your preferences" }
        return "No alerts yet"
    }

    private var emptyStateDetail: String {
        if !state.profile.acceptedNotifications {
            return "Turn alerts back on in Settings when you want funding, donation, and deadline updates."
        }
        if state.profile.notificationCategories.isEmpty {
            return "Choose funding sources in Settings to decide which alerts appear here."
        }
        if !state.notifications.isEmpty {
            return "Other alerts are safely hidden by the categories you selected in Settings."
        }
        return "Funding-route and request updates recorded on this device will appear here."
    }
}

struct NotificationRow: View {
    let item: NotificationItem
    var onMarkRead: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SymbolBadge(system: item.symbol, color: item.tint, size: 40, symbolSize: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(SchoolTheme.headlineFont(size: 14))
                    .foregroundStyle(SchoolTheme.ink)

                Text(item.body)
                    .font(SchoolTheme.bodyFont(size: 13))
                    .foregroundStyle(SchoolTheme.mutedText)

                Text(item.createdAt.formatted(.relative(presentation: .numeric)))
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(SchoolTheme.mutedText)
            }

            Spacer(minLength: 4)

            if !item.isRead, let onMarkRead {
                Button(action: onMarkRead) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(item.tint)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(item.tint.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(item.title) as read")
                .accessibilityHint("Removes its unread status")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(item.isRead ? Color.white : item.tint.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(item.isRead ? SchoolTheme.subtleBorder : item.tint.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityValue(item.isRead ? "Read" : "Unread")
    }
}

private struct ComposeOutreachSheet: View {
    @Environment(\.dismiss) private var dismiss
    let needs: [ClassroomNeed]
    let teacherName: String

    @State private var selectedNeedID: UUID?
    @State private var audience: FundingSource = .parents
    @State private var subject = ""
    @State private var messageText = ""
    @State private var activityPayload: OutreachActivityPayload?

    private var selectedNeed: ClassroomNeed? {
        guard let selectedNeedID else { return nil }
        return needs.first { $0.id == selectedNeedID }
    }

    private var canShare: Bool {
        selectedNeed != nil && !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    privacyCard
                    requestCard
                    audienceCard
                    draftCard
                    shareCard
                }
                .padding(16)
            }
            .background(LinedPaperBackground())
            .navigationTitle("Draft outreach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(item: $activityPayload) { payload in
                ActivityView(items: payload.items)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: selectedNeedID) { _, _ in
                regenerateDraft()
            }
            .onChange(of: audience) { _, _ in
                regenerateDraft()
            }
        }
    }

    private var privacyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(SchoolTheme.crayonTeal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("A draft, never an automatic send")
                    .font(SchoolTheme.headlineFont(size: 14))
                    .foregroundStyle(SchoolTheme.ink)
                Text("Refill has no access to private contact lists. The system share sheet lets you choose the app and recipients; Refill cannot confirm delivery.")
                    .font(SchoolTheme.bodyFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(SchoolTheme.crayonTeal.opacity(0.1)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(SchoolTheme.crayonTeal.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var requestCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("1. Choose one of your requests")
                    .font(SchoolTheme.headlineFont(size: 14))
                    .foregroundStyle(SchoolTheme.ink)

                Picker("Classroom request", selection: $selectedNeedID) {
                    Text("Choose a request").tag(nil as UUID?)
                    ForEach(needs) { need in
                        Text(need.title).tag(Optional(need.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityValue(selectedNeed?.title ?? "No request selected")

                if let selectedNeed {
                    Text("\(selectedNeed.schoolName) · \(selectedNeed.amountRemaining.formatted(.currency(code: "USD").precision(.fractionLength(0)))) remaining")
                        .font(SchoolTheme.bodyFont(size: 12))
                        .foregroundStyle(SchoolTheme.mutedText)
                }
            }
        }
    }

    private var audienceCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("2. Tailor it for one audience")
                    .font(SchoolTheme.headlineFont(size: 14))
                    .foregroundStyle(SchoolTheme.ink)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FundingSource.allCases) { source in
                            Button {
                                audience = source
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: source.symbol)
                                    Text(source.rawValue)
                                }
                                .font(.system(.caption, design: .rounded, weight: .bold))
                                .foregroundStyle(audience == source ? .white : source.tint)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(audience == source ? SchoolTheme.denim : source.tint.opacity(0.1)))
                                .overlay(Capsule().stroke(source.tint.opacity(0.4), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(source.rawValue)
                            .accessibilityValue(audience == source ? "Selected" : "Not selected")
                            .accessibilityAddTraits(audience == source ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var draftCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("3. Review and edit")
                        .font(SchoolTheme.headlineFont(size: 14))
                        .foregroundStyle(SchoolTheme.ink)
                    Spacer()
                    Button("Regenerate") { regenerateDraft() }
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .disabled(selectedNeed == nil)
                        .frame(minHeight: 44)
                }

                TextField("Subject", text: $subject, axis: .vertical)
                    .font(SchoolTheme.bodyFont(size: 15))
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
                    .accessibilityLabel("Outreach subject")

                TextEditor(text: $messageText)
                    .frame(minHeight: 190)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Editable outreach message")
            }
        }
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                openShareSheet()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Open system share options")
                }
                .font(SchoolTheme.headlineFont(size: 16))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(canShare ? SchoolTheme.denim : SchoolTheme.mutedText)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canShare)
            .accessibilityHint(canShare
                               ? "Choose Mail, Messages, or another installed sharing app"
                               : "Select a request and add message text first")

            Text("Nothing is marked sent when this opens. Delivery depends on the app and recipients you choose next.")
                .font(SchoolTheme.bodyFont(size: 12))
                .foregroundStyle(SchoolTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func regenerateDraft() {
        guard let need = selectedNeed else {
            subject = ""
            messageText = ""
            return
        }

        subject = OutreachDraft.subject(for: need, audience: audience)
        messageText = OutreachDraft.message(for: need, audience: audience, teacherName: teacherName)
    }

    private func openShareSheet() {
        guard canShare else { return }
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMessage = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        let shareText = trimmedSubject.isEmpty ? trimmedMessage : "\(trimmedSubject)\n\n\(trimmedMessage)"
        activityPayload = OutreachActivityPayload(items: [shareText])
    }
}

private struct OutreachActivityPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private enum OutreachDraft {
    static func subject(for need: ClassroomNeed, audience: FundingSource) -> String {
        switch audience {
        case .parents:
            return "Help our classroom with \(need.title)"
        case .foundation:
            return "Classroom funding request: \(need.title)"
        case .business:
            return "Local classroom sponsorship opportunity"
        case .district:
            return "School funding request for \(need.title)"
        case .donorsChoose:
            return "Project draft: \(need.title)"
        }
    }

    static func message(for need: ClassroomNeed, audience: FundingSource, teacherName: String) -> String {
        let remaining = need.amountRemaining.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        let goal = need.fundingGoal.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        let school = need.schoolName.isEmpty ? "our school" : need.schoolName

        switch audience {
        case .parents:
            return """
            Hi,

            I'm \(teacherName) at \(school). Our \(need.gradeBand.rawValue.lowercased()) classroom is raising support for \(need.title). The request will help \(need.studentCount) students, and \(remaining) remains toward the \(goal) goal.

            If you're able, please consider supporting or sharing this classroom request. Thank you for being part of our school community.
            """
        case .foundation:
            return """
            Hello,

            I'm \(teacherName), an educator at \(school), seeking consideration for a classroom request titled “\(need.title).” This \(need.category.rawValue.lowercased()) project supports \(need.studentCount) \(need.gradeBand.rawValue.lowercased()) students and has a total goal of \(goal), with \(remaining) remaining.

            I would be grateful for the opportunity to confirm eligibility and provide any documentation your foundation requires.
            """
        case .business:
            return """
            Hello,

            I'm \(teacherName) at \(school). We are looking for a local community partner for “\(need.title),” a \(need.category.rawValue.lowercased()) request serving \(need.studentCount) students. \(remaining) remains toward our \(goal) goal.

            Would your team be open to discussing sponsorship or sharing this request with your community-giving program?
            """
        case .district:
            return """
            Hello,

            I'm requesting guidance on district funding eligibility for “\(need.title)” at \(school). The request supports \(need.studentCount) \(need.gradeBand.rawValue.lowercased()) students, has a \(goal) goal, and is categorized as \(need.category.rawValue.lowercased()).

            Please let me know the appropriate funding route, required documentation, and review timeline.
            """
        case .donorsChoose:
            return """
            My students need \(need.title.lowercased()). This \(need.category.rawValue.lowercased()) project will support \(need.studentCount) learners at \(school) and has a \(goal) funding goal.

            \(need.rawRequest.isEmpty ? "These materials will give students more consistent access to the resources they need to learn." : need.rawRequest)

            This is draft project copy. Please review it against DonorsChoose requirements before posting.
            """
        }
    }
}

enum NotificationPreferenceFilter {
    static func visible(_ notifications: [NotificationItem], for profile: Profile) -> [NotificationItem] {
        guard profile.acceptedNotifications else { return [] }
        return notifications.filter { item in
            guard let source = source(for: item) else { return true }
            return profile.notificationCategories.contains(source)
        }
    }

    static func source(for item: NotificationItem) -> FundingSource? {
        let text = "\(item.title) \(item.body)".lowercased()

        if text.contains("donorschoose") { return .donorsChoose }
        if text.contains("district") || text.contains("title ii") || text.contains("title iv") { return .district }
        if text.contains("foundation") || text.contains("rotary") || text.contains("mini-grant") { return .foundation }
        if text.contains("business") || text.contains("sponsor") || text.contains("company") { return .business }
        if text.contains("parent") || text.contains("donation") || text.contains("donor") || text.contains("supporter") { return .parents }

        // "sparkles" is also used for general AI activity, so only use the
        // unambiguous funding-source symbols as a fallback.
        if let matchingSymbol = FundingSource.allCases.first(where: {
            $0 != .donorsChoose && $0.symbol == item.symbol
        }) {
            return matchingSymbol
        }
        return nil
    }
}
