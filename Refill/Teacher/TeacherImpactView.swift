import SwiftUI

struct TeacherImpactView: View {
    @EnvironmentObject private var state: AppState

    private var ownedNeedIDs: Set<UUID> { Set(state.needs.map(\.id)) }
    private var ownedDonations: [Donation] { state.donations.filter { ownedNeedIDs.contains($0.needId) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headline
                    bigStats
                    fundingBreakdown
                    recentDonations
                }
                .padding(16)
            }
            .background(LinedPaperBackground())
            .navigationTitle("Impact")
        }
    }

    private var headline: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SymbolBadge(system: "chart.line.uptrend.xyaxis", color: SchoolTheme.crayonTeal, size: 36, symbolSize: 18)
                    Text("What your classroom unlocked")
                        .font(SchoolTheme.headlineFont(size: 16))
                        .foregroundStyle(SchoolTheme.ink)
                }
                Text("Verified contributions completed through this installation appear here.")
                    .font(SchoolTheme.bodyFont(size: 13))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
        }
    }

    private var bigStats: some View {
        HStack(spacing: 10) {
            bigStat(value: "$\(Int(state.needs.reduce(0) { $0 + $1.raised }))", label: "Raised", color: SchoolTheme.apple, symbol: "dollarsign.circle.fill")
            bigStat(value: "\(state.needs.reduce(0) { $0 + $1.donorCount })", label: "Donations", color: SchoolTheme.denim, symbol: "heart.fill")
            bigStat(value: "\(uniqueDonorCount)", label: "Supporters", color: SchoolTheme.crayonPurple, symbol: "person.3.fill")
        }
    }

    
    
    private func bigStat(value: String, label: String, color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(color)
                Spacer()
            }
            Text(value)
                .font(SchoolTheme.displayFont(size: 24))
                .foregroundStyle(SchoolTheme.ink)
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(SchoolTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.3), lineWidth: 1))
    }


    private var uniqueDonorCount: Int {
        Set(ownedDonations.map { $0.donorName }).count
    }

    private var fundingBreakdown: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Where the money comes from")
                    .font(SchoolTheme.headlineFont(size: 16))
                    .foregroundStyle(SchoolTheme.ink)
                let grouped = Dictionary(grouping: ownedDonations, by: { $0.source })
                ForEach(FundingSource.allCases) { src in
                    let amount = grouped[src]?.reduce(0) { $0 + $1.amount } ?? 0
                    let total = max(ownedDonations.reduce(0) { $0 + $1.amount }, 1)
                    let pct = amount / total
                    HStack(spacing: 8) {
                        SymbolBadge(system: src.symbol, color: src.tint, size: 32, symbolSize: 14)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(src.rawValue)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(SchoolTheme.ink)
                                Spacer()
                                Text("$\(Int(amount))")
                                    .font(SchoolTheme.monoFont(size: 12))
                                    .foregroundStyle(SchoolTheme.mutedText)
                            }
                            ChalkProgress(progress: pct, height: 10)
                        }
                    }
                }
            }
        }
    }

    private var recentDonations: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent activity")
                .font(SchoolTheme.displayFont(size: 20))
                .foregroundStyle(SchoolTheme.ink)
            if ownedDonations.isEmpty {
                Text("No verified contributions have been recorded on this device yet.")
                    .font(SchoolTheme.bodyFont(size: 13))
                    .foregroundStyle(SchoolTheme.mutedText)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
            } else {
                ForEach(ownedDonations.prefix(8)) { d in
                    HStack(spacing: 10) {
                        SymbolBadge(system: d.source.symbol, color: d.source.tint, size: 36, symbolSize: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(d.donorName) · $\(Int(d.amount))")
                                .font(SchoolTheme.headlineFont(size: 14))
                                .foregroundStyle(SchoolTheme.ink)
                            Text(d.needTitle)
                                .font(SchoolTheme.bodyFont(size: 12))
                                .foregroundStyle(SchoolTheme.mutedText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(d.createdAt.formatted(.relative(presentation: .numeric)))
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(SchoolTheme.mutedText)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
                }
            }
        }
    }
}
