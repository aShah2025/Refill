import SwiftUI

struct NeedDetailView: View {
    let need: ClassroomNeed
    @EnvironmentObject private var state: AppState

    private var currentNeed: ClassroomNeed {
        state.needs.first(where: { $0.id == need.id })
            ?? state.allNeeds.first(where: { $0.id == need.id })
            ?? need
    }

    private var isOwnedByCurrentTeacher: Bool {
        state.profile.role == .teacher && state.needs.contains { $0.id == need.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                headerCard
                photoGallery
                storyCard
                itemsCard
                aiSummaryCard
                if isOwnedByCurrentTeacher {
                    matchesCard
                } else {
                    supportCard
                }
                provenanceCard
                Spacer(minLength: 40)
            }
            .padding(16)
        }
        .background(LinedPaperBackground())
        .navigationTitle(currentNeed.schoolName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isOwnedByCurrentTeacher {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        state.toggleFavorite(currentNeed)
                    } label: {
                        Image(systemName: state.isFavorite(currentNeed) ? "heart.fill" : "heart")
                            .foregroundStyle(SchoolTheme.apple)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(state.isFavorite(currentNeed) ? "Remove from favorites" : "Add to favorites")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: RequestSharing.text(for: [currentNeed], teacherName: currentNeed.teacherName)) {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Share classroom request")
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SchoolTag(text: currentNeed.category.rawValue, color: currentNeed.category.tint, system: currentNeed.category.symbol)
                SchoolTag(text: currentNeed.urgency.rawValue, color: currentNeed.urgency.tint, system: "clock.fill")
                Spacer()
                statusTag
            }

            Text(currentNeed.title)
                .font(SchoolTheme.displayFont(size: 24))
                .foregroundStyle(SchoolTheme.ink)

            HStack(spacing: 10) {
                teacherAvatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentNeed.teacherName)
                        .font(SchoolTheme.headlineFont(size: 14))
                        .foregroundStyle(SchoolTheme.ink)
                    Text("\(currentNeed.schoolName) · \(currentNeed.city)")
                        .font(SchoolTheme.bodyFont(size: 12))
                        .foregroundStyle(SchoolTheme.mutedText)
                        .lineLimit(2)
                }
            }

            VStack(spacing: 6) {
                ChalkProgress(progress: currentNeed.fundingProgress, height: 14)
                    .accessibilityLabel("Funding progress")
                    .accessibilityValue("\(Int(currentNeed.fundingProgress * 100)) percent")
                HStack {
                    Text("\(currentNeed.raised.formatted(.currency(code: "USD").precision(.fractionLength(0)))) raised")
                        .font(SchoolTheme.headlineFont(size: 13))
                    Spacer()
                    Text("\(currentNeed.amountRemaining.formatted(.currency(code: "USD").precision(.fractionLength(0)))) remaining")
                        .font(SchoolTheme.monoFont(size: 12))
                        .foregroundStyle(SchoolTheme.mutedText)
                }
            }

            HStack(spacing: 14) {
                Label("\(currentNeed.studentCount) students", systemImage: "person.3.fill")
                Label(currentNeed.gradeBand.rawValue, systemImage: "graduationcap.fill")
                if let deadline = currentNeed.deadline {
                    Label(deadline.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                }
            }
            .font(SchoolTheme.bodyFont(size: 12))
            .foregroundStyle(SchoolTheme.mutedText)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
    }

    @ViewBuilder
    private var statusTag: some View {
        switch currentNeed.status {
        case .funded:
            SchoolTag(text: "Funded", color: SchoolTheme.crayonTeal, system: "checkmark.seal.fill")
        case .closed:
            SchoolTag(text: "Closed", color: SchoolTheme.mutedText, system: "archivebox.fill")
        case .inProgress:
            SchoolTag(text: "In progress", color: SchoolTheme.denim, system: "hourglass")
        case .open:
            if currentNeed.fundingProgress >= 0.75 {
                SchoolTag(text: "Almost there", color: SchoolTheme.apple, system: "heart.fill")
            }
        }
    }

    private var teacherAvatar: some View {
        AsyncImage(url: currentNeed.teacherPhotoURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(SchoolTheme.denim.opacity(0.15))
                    Image(systemName: "person.fill")
                        .foregroundStyle(SchoolTheme.denim)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var photoGallery: some View {
        if let urls = currentNeed.photoURLs, !urls.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(urls, id: \.absoluteString) { url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                photoPlaceholder
                            default:
                                ZStack { photoPlaceholder; ProgressView() }
                            }
                        }
                        .frame(width: 260, height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .accessibilityLabel("Project photos")
        }
    }

    private var photoPlaceholder: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(SchoolTheme.denim.opacity(0.08))
            .overlay(Image(systemName: "photo").foregroundStyle(SchoolTheme.mutedText))
    }

    private var storyCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Classroom story")
                    .font(SchoolTheme.headlineFont(size: 16))
                    .foregroundStyle(SchoolTheme.ink)
                Text(currentNeed.rawRequest)
                    .font(SchoolTheme.bodyFont(size: 14))
                    .foregroundStyle(SchoolTheme.ink)
                if let bio = currentNeed.teacherBio, !bio.isEmpty {
                    Divider()
                    Text("About \(currentNeed.teacherName)")
                        .font(SchoolTheme.headlineFont(size: 14))
                    Text(bio)
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(SchoolTheme.mutedText)
                }
            }
        }
    }

    private var itemsCard: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("What they need")
                    .font(SchoolTheme.headlineFont(size: 16))
                    .foregroundStyle(SchoolTheme.ink)
                if currentNeed.items.isEmpty {
                    Text("See the source project for its current item list.")
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(SchoolTheme.mutedText)
                } else {
                    ForEach(currentNeed.items) { item in
                        HStack(spacing: 8) {
                            SymbolBadge(system: item.category.symbol, color: item.category.tint, size: 30, symbolSize: 14)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(SchoolTheme.bodyFont(size: 14))
                                    .foregroundStyle(SchoolTheme.ink)
                                Text("Qty \(item.quantity) · \(item.unitPrice.formatted(.currency(code: "USD"))) each")
                                    .font(SchoolTheme.monoFont(size: 12))
                                    .foregroundStyle(SchoolTheme.mutedText)
                            }
                            Spacer()
                            Text(item.total.formatted(.currency(code: "USD")))
                                .font(SchoolTheme.monoFont(size: 13))
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var aiSummaryCard: some View {
        if !currentNeed.aiSummary.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                SymbolBadge(system: "sparkles", color: SchoolTheme.crayonPurple, size: 40, symbolSize: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text("REFILL SUMMARY")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(SchoolTheme.crayonPurple)
                    Text(currentNeed.aiSummary)
                        .font(SchoolTheme.bodyFont(size: 14))
                        .foregroundStyle(SchoolTheme.ink)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(SchoolTheme.crayonPurple.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.crayonPurple.opacity(0.3), lineWidth: 1))
        }
    }

    private var matchesCard: some View {
        let matches = state.matches.filter { $0.needId == currentNeed.id }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Funding routes")
                .font(SchoolTheme.headlineFont(size: 16))
                .foregroundStyle(SchoolTheme.ink)
            if matches.isEmpty {
                Text("No routes prepared yet.")
                    .font(SchoolTheme.bodyFont(size: 13))
                    .foregroundStyle(SchoolTheme.mutedText)
            } else {
                ForEach(matches) { MatchCard(match: $0) }
            }
        }
    }

    @ViewBuilder
    private var supportCard: some View {
        switch currentNeed.resolvedOrigin {
        case .donorsChoose:
            PaperCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Donate on the official project", systemImage: "checkmark.shield.fill")
                        .font(SchoolTheme.headlineFont(size: 16))
                        .foregroundStyle(SchoolTheme.crayonTeal)
                    Text("DonorsChoose securely handles payment and keeps the authoritative funding total.")
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(SchoolTheme.mutedText)
                    if let url = currentNeed.sourceURL {
                        Link(destination: url) {
                            Label("Open DonorsChoose", systemImage: "arrow.up.right.square.fill")
                                .font(SchoolTheme.headlineFont(size: 15))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, minHeight: 50)
                                .background(SchoolTheme.apple)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    } else {
                        Label("The provider did not return a valid project link.", systemImage: "exclamationmark.triangle.fill")
                            .font(SchoolTheme.bodyFont(size: 13))
                            .foregroundStyle(SchoolTheme.apple)
                    }
                }
            }
        case .local:
            DonationCheckoutView(need: currentNeed)
        case .sample:
            DonationCheckoutView(need: currentNeed)
        }
    }

    private var provenanceCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: provenanceSymbol)
                .foregroundStyle(provenanceColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(currentNeed.resolvedOrigin.displayName)
                    .font(SchoolTheme.headlineFont(size: 13))
                Text(provenanceDetail)
                    .font(SchoolTheme.bodyFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
    }

    private var provenanceDetail: String {
        switch currentNeed.resolvedOrigin {
        case .donorsChoose:
            return "Project details came from DonorsChoose. Confirm current totals and eligibility on the official source page."
        case .local:
            return "This request was created in Refill and is stored on this device. It is not automatically published to DonorsChoose or a shared backend."
        case .sample:
            return "This bundled example demonstrates the interface and is not a live fundraising request."
        }
    }

    private var provenanceSymbol: String {
        switch currentNeed.resolvedOrigin {
        case .donorsChoose: return "checkmark.shield.fill"
        case .local: return "internaldrive.fill"
        case .sample: return "info.circle.fill"
        }
    }

    private var provenanceColor: Color {
        switch currentNeed.resolvedOrigin {
        case .donorsChoose: return SchoolTheme.crayonTeal
        case .local: return SchoolTheme.denim
        case .sample: return SchoolTheme.crayonOrange
        }
    }
}
