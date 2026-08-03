import SwiftUI
import UIKit

struct TeacherHomeView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var speech = SpeechRecognizer()
    @AppStorage("refill.use-live-ai") private var useLiveAI = false
    @State private var draft: String = ""
    @State private var showCompose = false
    @State private var newNeedTitle = ""
    @State private var newNeedUrgency: Urgency = .thisMonth
    @State private var activityPayload: ActivityPayload?
    @State private var actionError: String?
    @State private var preparedRequest: PreparedRequest?
    @State private var isAnalyzing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    greetingHeader

                    composeCard

                    teacherStats

                    myRequestsSection

                    quickActions
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(LinedPaperBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    profileButton
                }
            }
            .overlay {
                if isAnalyzing {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.large)
                            Text("Structuring your request…")
                                .font(SchoolTheme.headlineFont(size: 15))
                            Text("You’ll review every item and price before it is published.")
                                .font(SchoolTheme.bodyFont(size: 12))
                                .foregroundStyle(SchoolTheme.mutedText)
                                .multilineTextAlignment(.center)
                        }
                        .padding(22)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .padding(30)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Analyzing classroom request")
                }
            }
            .sheet(isPresented: $showCompose) {
                ComposeRequestSheet(
                    title: $newNeedTitle,
                    urgency: $newNeedUrgency,
                    useLiveAI: $useLiveAI,
                    onSubmit: { title, urgency in
                        submit(text: title, urgency: urgency)
                    }
                )
            }
            .sheet(item: $activityPayload) { payload in
                ActivityView(items: payload.items)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $preparedRequest) { prepared in
                ReviewRequestSheet(prepared: prepared) { reviewed in
                    publish(reviewed)
                }
            }
            .alert("Couldn’t complete that action", isPresented: Binding(
                get: { actionError != nil || speech.errorMessage != nil },
                set: {
                    if !$0 {
                        actionError = nil
                        speech.clearError()
                    }
                }
            )) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? speech.errorMessage ?? "Please try again.")
            }
            .onChange(of: speech.transcript) { _, transcript in
                if !transcript.isEmpty { draft = transcript }
            }
            .onDisappear { speech.stop() }
        }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Hi, \(state.profile.fullName.isEmpty ? "Teacher" : state.profile.fullName.split(separator: " ").first.map(String.init) ?? "Teacher") 👋")
                .font(SchoolTheme.displayFont(size: 26))
                .foregroundStyle(SchoolTheme.ink)
            Text("What does your classroom need today?")
                .font(SchoolTheme.bodyFont(size: 15))
                .foregroundStyle(SchoolTheme.mutedText)
        }
    }

    private var composeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SymbolBadge(system: "sparkles", color: SchoolTheme.crayonPurple, size: 32, symbolSize: 16)
                Text("Ask Refill in plain English")
                    .font(SchoolTheme.headlineFont(size: 16))
                    .foregroundStyle(SchoolTheme.ink)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(SchoolTheme.denim.opacity(0.18), lineWidth: 1)
                    )

                if draft.isEmpty {
                    Text("e.g. \"I need 30 books for 3rd graders reading below grade level by next week.\"")
                        .font(SchoolTheme.bodyFont(size: 14))
                        .foregroundStyle(SchoolTheme.mutedText)
                        .padding(14)
                }
                TextEditor(text: $draft)
                    .frame(minHeight: 110)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(.clear)
            }

            Toggle(isOn: $useLiveAI) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use secure AI analysis")
                        .font(SchoolTheme.headlineFont(size: 13))
                    Text(useLiveAI
                         ? "Sends this request and classroom context to the configured Refill server and OpenAI."
                         : "Keeps analysis on this device with the offline parser.")
                        .font(SchoolTheme.bodyFont(size: 11))
                        .foregroundStyle(SchoolTheme.mutedText)
                }
            }
            .tint(SchoolTheme.crayonPurple)
            .disabled(!AppConfig.BackendConfig.current.isConfigured)
            .onAppear {
                if !AppConfig.BackendConfig.current.isConfigured { useLiveAI = false }
            }

            HStack(spacing: 10) {
                Button {
                    Task {
                        await speech.toggle(startingWith: draft)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic")
                            .font(.system(size: 16, weight: .heavy))
                            .symbolEffect(.bounce, value: speech.isRecording)
                        Text(speech.isRecording ? "Stop" : "Speak")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(SchoolTheme.apple)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(SchoolTheme.apple.opacity(0.12)))
                    .overlay(Capsule().stroke(SchoolTheme.apple.opacity(0.5), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.isRecording ? "Stop dictation" : "Dictate classroom request")

                Spacer()

                Button {
                    submit(text: draft, urgency: .flexible)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .heavy))
                        Text("Review Request")
                            .font(SchoolTheme.headlineFont(size: 15))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        ZStack {
                            Capsule().fill(SchoolTheme.denim.opacity(0.35)).offset(y: 4)
                            Capsule().fill(SchoolTheme.denim)
                        }
                    )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing)
                .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnalyzing ? 0.55 : 1)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(SchoolTheme.pencilYellow.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(SchoolTheme.pencilYellow.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
    }

    private var teacherStats: some View {
        let ownedIDs = Set(state.needs.map(\.id))
        let raised = state.donations.filter { ownedIDs.contains($0.needId) }.reduce(0) { $0 + $1.amount }
        let communityCount = state.allNeeds.filter { !ownedIDs.contains($0.id) }.count
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statChip(symbol: "sparkles", value: "\(state.matches.count)", label: "matches", color: SchoolTheme.crayonPurple)
            statChip(symbol: "heart.fill", value: "$\(Int(raised))", label: "raised", color: SchoolTheme.apple)
            statChip(symbol: "person.3.fill", value: "\(state.needs.count)", label: "my needs", color: SchoolTheme.denim)
            statChip(symbol: "icloud.and.arrow.down", value: "\(communityCount)", label: "nearby", color: SchoolTheme.crayonPurple)
        }
    }

    private func statChip(symbol: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(color)
            Text(value)
                .font(SchoolTheme.headlineFont(size: 18))
                .foregroundStyle(SchoolTheme.ink)
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(SchoolTheme.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var myRequestsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your Requests")
                    .font(SchoolTheme.displayFont(size: 20))
                    .foregroundStyle(SchoolTheme.ink)
                Spacer()
                Button {
                    showCompose = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("New")
                    }
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(SchoolTheme.denim)
                }
            }

            if state.needs.isEmpty { emptyRequests } else {
                ForEach(state.needs) { need in
                    HStack(spacing: 8) {
                        NavigationLink {
                            NeedDetailView(need: need)
                        } label: {
                            NeedRowCard(need: need)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button {
                                activityPayload = ActivityPayload(items: [RequestSharing.text(for: [need], teacherName: need.teacherName)])
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            if need.status != .closed && need.status != .funded {
                                Button {
                                    state.closeNeed(need.id)
                                } label: {
                                    Label("Close request", systemImage: "archivebox")
                                }
                            }
                            Button(role: .destructive) {
                                state.deleteNeed(need.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20, weight: .semibold))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Actions for \(need.title)")
                    }
                }
            }

            let ownedIDs = Set(state.needs.map(\.id))
            let communityNeeds = state.allNeeds.filter { !ownedIDs.contains($0.id) }
            if !communityNeeds.isEmpty {
                Text("Other Classrooms Near You")
                    .font(SchoolTheme.displayFont(size: 18))
                    .foregroundStyle(SchoolTheme.ink)
                    .padding(.top, 8)

                ForEach(communityNeeds.prefix(5)) { need in
                    NavigationLink {
                        NeedDetailView(need: need)
                    } label: {
                        NeedRowCard(need: need)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyRequests: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(SchoolTheme.mutedText)
            Text("No requests yet")
                .font(SchoolTheme.headlineFont(size: 16))
                .foregroundStyle(SchoolTheme.ink)
            Text("Describe the need, review every field, then choose how to share it.")
                .font(SchoolTheme.bodyFont(size: 13))
                .foregroundStyle(SchoolTheme.mutedText)
                .multilineTextAlignment(.center)
            Button {
                showCompose = true
            } label: {
                Text("Create your first request")
                    .font(SchoolTheme.headlineFont(size: 14))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(SchoolTheme.denim)
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick actions")
                .font(SchoolTheme.displayFont(size: 20))
                .foregroundStyle(SchoolTheme.ink)

            HStack(spacing: 10) {
                quickButton(symbol: "square.and.arrow.up.fill", text: "Share requests", color: SchoolTheme.apple) {
                    guard !state.needs.isEmpty else {
                        actionError = "Create a classroom request before sharing."
                        return
                    }
                    activityPayload = ActivityPayload(items: [RequestSharing.text(for: state.needs, teacherName: state.profile.fullName.isEmpty ? "this teacher" : state.profile.fullName)])
                }
                quickButton(symbol: "doc.on.doc.fill", text: "Export PDF", color: SchoolTheme.denim) {
                    do {
                        let url = try RequestPDFExporter.export(needs: state.needs, profile: state.profile)
                        activityPayload = ActivityPayload(items: [url])
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
            }
            HStack(spacing: 10) {
                quickButton(symbol: "doc.on.clipboard.fill", text: "Copy summary", color: SchoolTheme.crayonPurple) {
                    guard !state.needs.isEmpty else {
                        actionError = "Create a classroom request before copying a summary."
                        return
                    }
                    UIPasteboard.general.string = RequestSharing.text(
                        for: state.needs,
                        teacherName: state.profile.fullName.isEmpty ? "this teacher" : state.profile.fullName
                    )
                }
                quickButton(symbol: "questionmark.bubble.fill", text: "Report an issue", color: SchoolTheme.crayonTeal) {
                    guard let url = URL(string: "https://github.com/aShah2025/Refill/issues/new") else { return }
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private func quickButton(symbol: String, text: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SymbolBadge(system: symbol, color: color, size: 36, symbolSize: 16)
                Text(text)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(SchoolTheme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var profileButton: some View {
        ZStack {
            Circle().fill(SchoolTheme.denim.opacity(0.18))
            Text(initials(for: state.profile.fullName.isEmpty ? "T" : state.profile.fullName))
                .font(SchoolTheme.headlineFont(size: 14))
                .foregroundStyle(SchoolTheme.denim)
        }
        .frame(width: 36, height: 36)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? "T"
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    private func submit(text: String, urgency: Urgency) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnalyzing else { return }
        showCompose = false
        isAnalyzing = true

        Task {
            do {
                let parsed: AISuppliesParser.ParseResult
                let sourceLabel: String
                if useLiveAI {
                    let context = AIParsingContext(
                        gradeLevel: state.profile.gradeBand?.rawValue,
                        subject: state.profile.subjectFocus?.rawValue,
                        studentCount: state.profile.studentCount > 0 ? state.profile.studentCount : nil,
                        urgency: urgency == .flexible ? nil : urgency.rawValue
                    )
                    let outcome = try await AIParsingService.shared.parse(trimmed, context: context)
                    parsed = outcome.result
                    sourceLabel = analysisSourceLabel(outcome.source)
                } else {
                    parsed = AISuppliesParser.parse(trimmed)
                    sourceLabel = "the private on-device parser"
                }
                preparedRequest = PreparedRequest(
                    rawRequest: trimmed,
                    title: parsed.title,
                    items: parsed.items,
                    category: parsed.category,
                    urgency: urgency == .flexible ? parsed.urgency : urgency,
                    subjectFocus: parsed.subjectFocus,
                    summary: parsed.summary,
                    analysisSource: sourceLabel
                )
            } catch {
                actionError = error.localizedDescription
            }
            isAnalyzing = false
        }
    }

    private func analysisSourceLabel(_ source: AIParsingSource) -> String {
        switch source {
        case .backend(let model): return "OpenAI \(model) via the Refill server"
        case .deterministicFallback: return "the private on-device fallback"
        }
    }

    private func publish(_ reviewed: ReviewedRequest) {
        let teacherId = state.profile.id ?? StableIdentifier.uuid(
            namespace: "refill-user",
            value: state.profile.email.lowercased()
        )
        let needID = UUID()
        let need = ClassroomNeed(
            id: needID,
            teacherId: teacherId,
            teacherName: state.profile.fullName.isEmpty ? "You" : state.profile.fullName,
            schoolName: state.profile.schoolName.isEmpty ? "Your school" : state.profile.schoolName,
            title: reviewed.title,
            rawRequest: reviewed.rawRequest,
            items: reviewed.items,
            category: reviewed.category,
            urgency: reviewed.urgency,
            studentCount: max(state.profile.studentCount, 1),
            gradeBand: state.profile.gradeBand ?? .elementary,
            subjectFocus: state.profile.subjectFocus ?? reviewed.subjectFocus,
            city: state.profile.city.isEmpty ? "CA-19" : state.profile.city,
            fundingProgress: 0,
            fundingGoal: reviewed.items.reduce(0) { $0 + $1.total },
            raised: 0,
            donorCount: 0,
            matchedSources: suggestedSources(for: reviewed.category),
            status: .open,
            aiSummary: reviewed.summary,
            origin: .local,
            sourceID: needID.uuidString,
            zip: state.profile.zip.isEmpty ? nil : state.profile.zip
        )
        let newMatches = makeMatches(for: need)
        state.addNeed(need, matches: newMatches)
        state.sendNotification(
            title: "\(newMatches.count) funding routes prepared",
            body: "Review each route and verify provider eligibility for \(reviewed.title).",
            symbol: "sparkles",
            tint: SchoolTheme.crayonPurple
        )
        draft = ""
        newNeedTitle = ""
        preparedRequest = nil
    }

    private func suggestedSources(for category: SupplyCategory) -> [FundingSource] {
        switch category {
        case .books: return [.donorsChoose, .parents, .foundation]
        case .tech: return [.donorsChoose, .business, .district]
        case .furniture: return [.foundation, .parents, .business]
        case .supplies: return [.parents, .foundation, .donorsChoose]
        case .hygiene: return [.district, .parents, .business]
        case .art: return [.foundation, .parents, .donorsChoose]
        case .math: return [.donorsChoose, .district, .business]
        case .other: return [.donorsChoose, .parents, .foundation]
        }
    }

    private func makeMatches(for need: ClassroomNeed) -> [FundingMatch] {
        need.matchedSources.map { source in
            let confidence = categoryFit(source: source, category: need.category)
            let suggestedShare = suggestedCoverage(source: source)
            return FundingMatch(
                needId: need.id,
                source: source,
                headline: headline(for: source, need: need),
                detail: detail(for: source, need: need),
                estimatedAmount: min(need.fundingGoal, max(5, need.fundingGoal * suggestedShare)),
                confidence: confidence,
                nextStep: nextStep(for: source),
                actionURL: actionURL(for: source),
                providerVerified: source == .donorsChoose
            )
        }
    }

    private func headline(for src: FundingSource, need: ClassroomNeed) -> String {
        switch src {
        case .donorsChoose: return "Publish a DonorsChoose project"
        case .foundation: return "Prepare a local foundation grant brief"
        case .parents: return "Share a supporter micro-campaign"
        case .business: return "Request a local business sponsorship"
        case .district: return "Ask your district grants administrator"
        }
    }

    private func detail(for src: FundingSource, need: ClassroomNeed) -> String {
        switch src {
        case .donorsChoose: return "Open the official teacher workflow and use this request's editable title, story, and item list. DonorsChoose approval rules apply."
        case .foundation: return "Share a concise request brief with a foundation you already trust. Availability and eligibility must be confirmed with the funder."
        case .parents: return "Use the system share sheet to invite voluntary $5–$20 contributions without exposing family contact data."
        case .business: return "Share a sponsorship brief with a local business. Refill has not pre-approved or contacted a sponsor."
        case .district: return "Ask your district which current discretionary, Title, or site funds apply. Refill does not determine eligibility."
        }
    }

    private func nextStep(for src: FundingSource) -> String {
        switch src {
        case .donorsChoose: return "Review & post"
        case .foundation: return "Share brief"
        case .parents: return "Share campaign"
        case .business: return "Share request"
        case .district: return "Share with district"
        }
    }

    private func actionURL(for source: FundingSource) -> URL? {
        guard source == .donorsChoose else { return nil }
        return URL(string: "https://www.donorschoose.org/teachers")
    }

    private func categoryFit(source: FundingSource, category: SupplyCategory) -> Double {
        switch (source, category) {
        case (.donorsChoose, _): return 0.90
        case (.district, .tech), (.district, .math), (.district, .hygiene): return 0.82
        case (.foundation, .books), (.foundation, .art), (.foundation, .supplies): return 0.80
        case (.business, .tech), (.business, .furniture): return 0.78
        case (.parents, _): return 0.74
        default: return 0.65
        }
    }

    private func suggestedCoverage(source: FundingSource) -> Double {
        switch source {
        case .donorsChoose: return 1
        case .foundation: return 0.5
        case .parents: return 0.35
        case .business: return 0.5
        case .district: return 0.6
        }
    }
}

private struct ActivityPayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct PreparedRequest: Identifiable {
    let id = UUID()
    let rawRequest: String
    let title: String
    let items: [ParsedItem]
    let category: SupplyCategory
    let urgency: Urgency
    let subjectFocus: SubjectFocus
    let summary: String
    let analysisSource: String
}

private struct ReviewedRequest {
    let rawRequest: String
    let title: String
    let items: [ParsedItem]
    let category: SupplyCategory
    let urgency: Urgency
    let subjectFocus: SubjectFocus
    let summary: String
}

private struct ReviewRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    let prepared: PreparedRequest
    let onPublish: (ReviewedRequest) -> Void

    @State private var title: String
    @State private var items: [ParsedItem]
    @State private var category: SupplyCategory
    @State private var urgency: Urgency
    @State private var summary: String

    init(prepared: PreparedRequest, onPublish: @escaping (ReviewedRequest) -> Void) {
        self.prepared = prepared
        self.onPublish = onPublish
        _title = State(initialValue: prepared.title)
        _items = State(initialValue: prepared.items)
        _category = State(initialValue: prepared.category)
        _urgency = State(initialValue: prepared.urgency)
        _summary = State(initialValue: prepared.summary)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Generated by \(prepared.analysisSource). Review every field before publishing.", systemImage: "checkmark.shield.fill")
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(SchoolTheme.mutedText)
                }

                Section("Request") {
                    TextField("Public title", text: $title, axis: .vertical)
                        .textInputAutocapitalization(.sentences)
                    Picker("Category", selection: $category) {
                        ForEach(SupplyCategory.allCases) { value in
                            Label(value.rawValue, systemImage: value.symbol).tag(value)
                        }
                    }
                    Picker("Urgency", selection: $urgency) {
                        ForEach(Urgency.allCases) { value in
                            Text(value.rawValue).tag(value)
                        }
                    }
                    LabeledContent("Line items", value: "\(items.count)")
                }

                Section {
                    ForEach(Array(items.indices), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Item name", text: $items[index].name)
                            Stepper("Quantity: \(items[index].quantity)", value: $items[index].quantity, in: 1...500)
                            HStack {
                                Text("Unit price")
                                Spacer()
                                TextField("0.00", value: $items[index].unitPrice, format: .number.precision(.fractionLength(2)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 100)
                            }
                            Button(role: .destructive) {
                                items.remove(at: index)
                            } label: {
                                Label("Remove item", systemImage: "trash")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Button {
                        items.append(ParsedItem(name: "New classroom item", quantity: 1, unitPrice: 0, category: category))
                    } label: {
                        Label("Add item", systemImage: "plus.circle.fill")
                    }
                } header: {
                    HStack {
                        Text("Supplies")
                        Spacer()
                        Text(total.formatted(.currency(code: "USD")))
                    }
                } footer: {
                    Text("Prices are estimates. Confirm actual vendor pricing before sharing the request.")
                }

                Section("Public summary") {
                    TextEditor(text: $summary)
                        .frame(minHeight: 100)
                        .accessibilityLabel("Public request summary")
                }

                Section("Original description") {
                    Text(prepared.rawRequest)
                        .font(SchoolTheme.bodyFont(size: 14))
                        .foregroundStyle(SchoolTheme.mutedText)
                }
            }
            .navigationTitle("Review request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Publish") {
                        onPublish(ReviewedRequest(
                            rawRequest: prepared.rawRequest,
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            items: items,
                            category: category,
                            urgency: urgency,
                            subjectFocus: prepared.subjectFocus,
                            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                        dismiss()
                    }
                    .fontWeight(.bold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private var total: Double { items.reduce(0) { $0 + $1.total } }
    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !items.isEmpty
            && items.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.quantity > 0 && $0.unitPrice > 0 }
            && total > 0
    }
}

// MARK: - Need row card

struct NeedRowCard: View {
    let need: ClassroomNeed
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SchoolTag(text: need.category.rawValue, color: need.category.tint, system: need.category.symbol)
                SchoolTag(text: need.urgency.rawValue, color: need.urgency.tint, system: "clock.fill")
                Spacer()
                Text("$\(Int(need.raised)) / $\(Int(need.fundingGoal))")
                    .font(SchoolTheme.monoFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
            Text(need.title)
                .font(SchoolTheme.headlineFont(size: 16))
                .foregroundStyle(SchoolTheme.ink)
                .lineLimit(2)
            Label(need.resolvedOrigin.displayName, systemImage: sourceSymbol)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(sourceColor)
            HStack(spacing: 8) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 12, weight: .heavy))
                Text("\(need.schoolName) · \(need.gradeBand.rawValue)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(need.donorCount) supporters")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(SchoolTheme.apple)
            }
            .foregroundStyle(SchoolTheme.mutedText)

            ChalkProgress(progress: need.fundingProgress)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }

    private var sourceSymbol: String {
        switch need.resolvedOrigin {
        case .local: return "doc.text.fill"
        case .donorsChoose: return "checkmark.shield.fill"
        case .sample: return "shippingbox.fill"
        }
    }

    private var sourceColor: Color {
        switch need.resolvedOrigin {
        case .local: return SchoolTheme.denim
        case .donorsChoose: return SchoolTheme.crayonTeal
        case .sample: return SchoolTheme.crayonOrange
        }
    }
}

// MARK: - Compose sheet

struct ComposeRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var title: String
    @Binding var urgency: Urgency
    @Binding var useLiveAI: Bool
    var onSubmit: (String, Urgency) -> Void
    @State private var local: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New request")
                            .font(SchoolTheme.displayFont(size: 24))
                            .foregroundStyle(SchoolTheme.ink)
                        Text("Refill turns this into an editable draft and suggests funding routes to verify.")
                            .font(SchoolTheme.bodyFont(size: 14))
                            .foregroundStyle(SchoolTheme.mutedText)
                    }
                    PaperCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Describe the need")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(SchoolTheme.mutedText)
                            TextEditor(text: $local)
                                .frame(minHeight: 140)
                                .scrollContentBackground(.hidden)
                                .background(.clear)
                        }
                    }
                    Toggle(isOn: $useLiveAI) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Use secure AI analysis")
                                .font(SchoolTheme.headlineFont(size: 14))
                            Text(useLiveAI
                                 ? "Request text and classroom context are sent through your Refill server to OpenAI."
                                 : "Use the private on-device parser instead.")
                                .font(SchoolTheme.bodyFont(size: 12))
                                .foregroundStyle(SchoolTheme.mutedText)
                        }
                    }
                    .tint(SchoolTheme.crayonPurple)
                    .disabled(!AppConfig.BackendConfig.current.isConfigured)
                    PaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("How urgent?")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(SchoolTheme.mutedText)
                            HStack(spacing: 8) {
                                ForEach(Urgency.allCases) { u in
                                    Button {
                                        urgency = u
                                    } label: {
                                        Text(u.rawValue)
                                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                                            .foregroundStyle(urgency == u ? .white : u.tint)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(Capsule().fill(urgency == u ? u.tint : u.tint.opacity(0.12)))
                                            .overlay(Capsule().stroke(u.tint.opacity(0.6), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(LinedPaperBackground())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSubmit(local, urgency)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill")
                            Text("Review")
                        }
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                    }
                    .disabled(local.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
