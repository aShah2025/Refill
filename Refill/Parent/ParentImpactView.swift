import SwiftUI

struct ParentImpactView: View {
    @EnvironmentObject private var state: AppState

    var myDonations: [Donation] {
        // The local store contains only donations completed by this account.
        // Never infer identity from a first-name substring or show other donors'
        // activity as the current supporter's history.
        state.donations
    }

    private var realDonations: [Donation] {
        myDonations.filter { $0.isTest != true }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headline
                    myStats
                    timeline
                }
                .padding(16)
            }
            .background(LinedPaperBackground())
            .navigationTitle("Your Impact")
        }
    }

    private var headline: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    SymbolBadge(system: "heart.circle.fill", color: SchoolTheme.apple, size: 36, symbolSize: 18)
                    Text("Every chip, every classroom")
                        .font(SchoolTheme.headlineFont(size: 16))
                        .foregroundStyle(SchoolTheme.ink)
                }
                Text("Verified contributions completed through this installation. Sample checkout tests are labeled and excluded from totals.")
                    .font(SchoolTheme.bodyFont(size: 13))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
        }
    }

    private var myStats: some View {
        let mine = realDonations
        let total = mine.reduce(0) { $0 + $1.amount }
        return HStack(spacing: 10) {
            stat(value: "$\(Int(total))", label: "Given", color: SchoolTheme.apple)
            stat(value: "\(mine.count)", label: "Donations", color: SchoolTheme.denim)
            stat(value: "\(Set(mine.map { $0.needId }).count)", label: "Classrooms", color: SchoolTheme.crayonPurple)
        }
    }

    private func stat(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(SchoolTheme.displayFont(size: 22))
                .foregroundStyle(SchoolTheme.ink)
            Text(label)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.3), lineWidth: 1))
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Timeline")
                .font(SchoolTheme.displayFont(size: 20))
                .foregroundStyle(SchoolTheme.ink)
            let mine = myDonations
            if mine.isEmpty {
                Text("No activity yet.")
                    .font(SchoolTheme.bodyFont(size: 14))
                    .foregroundStyle(SchoolTheme.mutedText)
                    .padding(14)
            } else {
                ForEach(mine) { d in
                    HStack(spacing: 10) {
                        SymbolBadge(system: d.source.symbol, color: d.source.tint, size: 36, symbolSize: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("$\(Int(d.amount)) · \(d.needTitle)")
                                .font(SchoolTheme.headlineFont(size: 14))
                                .foregroundStyle(SchoolTheme.ink)
                                .lineLimit(2)
                            if d.isTest == true {
                                Label("Stripe test · no real charge", systemImage: "testtube.2")
                                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                                    .foregroundStyle(SchoolTheme.crayonOrange)
                            }
                            if !d.message.isEmpty {
                                Text("\"\(d.message)\"")
                                    .font(SchoolTheme.bodyFont(size: 12))
                                    .foregroundStyle(SchoolTheme.mutedText)
                            }
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
