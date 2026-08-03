import SwiftUI

struct TeacherMatchesView: View {
    @EnvironmentObject private var state: AppState
    @State private var filter: FundingSource? = nil
    @State private var pulsingMatchId: UUID? = nil

    var filtered: [FundingMatch] {
        guard let f = filter else { return state.matches }
        return state.matches.filter { $0.source == f }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard
                    filterChips
                    if filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(filtered) { match in
                            MatchCard(match: match, isPulsing: pulsingMatchId == match.id)
                                .onAppear { pulse(match.id) }
                        }
                    }
                }
                .padding(16)
            }
            .background(LinedPaperBackground())
            .navigationTitle("Funding Routes")
        }
    }

    private var summaryCard: some View {
        PaperCard {
            HStack(spacing: 12) {
                SymbolBadge(system: "sparkles", color: SchoolTheme.crayonPurple, size: 52, symbolSize: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Practical ways to fund each request")
                        .font(SchoolTheme.headlineFont(size: 16))
                        .foregroundStyle(SchoolTheme.ink)
                    Text("Review each route, verify eligibility with the provider, then open or share the next step.")
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(SchoolTheme.mutedText)
                }
            }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", system: "rectangle.3.group.fill", color: SchoolTheme.denim, isOn: filter == nil) {
                    filter = nil
                }
                ForEach(FundingSource.allCases) { src in
                    filterChip(label: src.rawValue, system: src.symbol, color: src.tint, isOn: filter == src) {
                        filter = (filter == src) ? nil : src
                    }
                }
            }
        }
    }

    private func filterChip(label: String, system: String, color: Color, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system).font(.system(size: 12, weight: .heavy))
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(isOn ? .white : color)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(isOn ? color : color.opacity(0.12)))
            .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(SchoolTheme.crayonPurple)
            Text("No funding routes yet")
                .font(SchoolTheme.headlineFont(size: 16))
                .foregroundStyle(SchoolTheme.ink)
            Text("Create a request on Home and Refill will prepare relevant funding routes.")
                .font(SchoolTheme.bodyFont(size: 13))
                .foregroundStyle(SchoolTheme.mutedText)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
    }

    private func pulse(_ id: UUID) {
        guard pulsingMatchId == nil else { return }
        withAnimation(.easeInOut(duration: 0.4)) { pulsingMatchId = id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeInOut(duration: 0.4)) { pulsingMatchId = nil }
        }
    }
}

struct MatchCard: View {
    let match: FundingMatch
    var isPulsing: Bool = false
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SymbolBadge(system: match.source.symbol, color: match.source.tint, size: 44, symbolSize: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.source.rawValue)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(match.source.tint)
                    Text(match.headline)
                        .font(SchoolTheme.headlineFont(size: 15))
                        .foregroundStyle(SchoolTheme.ink)
                }
                Spacer()
                confidenceBadge
            }
            Text(match.detail)
                .font(SchoolTheme.bodyFont(size: 13))
                .foregroundStyle(SchoolTheme.mutedText)
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .foregroundStyle(SchoolTheme.apple)
                Text("Target $\(Int(match.estimatedAmount))")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(SchoolTheme.ink)
                Spacer()
                if let url = match.actionURL {
                    Link(destination: url) {
                        actionLabel(text: match.nextStep, system: "arrow.up.right.square.fill")
                    }
                    .buttonStyle(.plain)
                } else {
                    ShareLink(item: outreachDraft) {
                        actionLabel(text: match.nextStep, system: "square.and.arrow.up.fill")
                    }
                    .buttonStyle(.plain)
                }
            }
            if let deadline = match.deadline {
                Label("Deadline \(deadline.formatted(date: .abbreviated, time: .omitted))", systemImage: "calendar.badge.clock")
                    .font(SchoolTheme.bodyFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white)
                .shadow(color: match.source.tint.opacity(isPulsing ? 0.35 : 0.0), radius: isPulsing ? 14 : 0, x: 0, y: 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(match.source.tint.opacity(0.35), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.3), value: isPulsing)
    }

    private func actionLabel(text: String, system: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
            Text(text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .font(.system(size: 13, weight: .heavy, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(match.source.tint)
        .clipShape(Capsule())
    }

    private var outreachDraft: String {
        let need = state.needs.first { $0.id == match.needId }
        let title = need?.title ?? "our classroom request"
        return "Help fund \(title). Suggested route: \(match.source.rawValue). \(match.detail)"
    }

    private var confidenceBadge: some View {
        let pct = Int(match.confidence * 100)
        return VStack(spacing: 0) {
            Text("\(pct)%")
                .font(SchoolTheme.headlineFont(size: 14))
                .foregroundStyle(match.source.tint)
            Text(match.providerVerified == true ? "OFFICIAL" : "FIT")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.4)
                .foregroundStyle(SchoolTheme.mutedText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(match.providerVerified == true ? "Official provider link, \(pct) percent category fit" : "\(pct) percent category fit")
        .frame(width: 56, height: 44)
        .background(RoundedRectangle(cornerRadius: 10).fill(match.source.tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(match.source.tint.opacity(0.5), lineWidth: 1))
    }
}
