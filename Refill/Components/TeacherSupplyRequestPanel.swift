import SwiftUI

/// A read-only project summary suitable for dashboards. Actions intentionally
/// live in `NeedDetailView`, where role and project provenance can be checked.
struct TeacherSupplyRequestPanel: View {
    let need: ClassroomNeed
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SchoolTag(text: need.category.rawValue, color: need.category.tint, system: need.category.symbol)
                SchoolTag(text: need.urgency.rawValue, color: need.urgency.tint, system: "clock.fill")
                Spacer()
                Text(need.resolvedOrigin.displayName)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(need.resolvedOrigin.isLive ? SchoolTheme.crayonTeal : SchoolTheme.crayonOrange)
            }

            Text(need.title)
                .font(SchoolTheme.headlineFont(size: 17))
                .foregroundStyle(SchoolTheme.ink)
                .multilineTextAlignment(.leading)

            Label("\(need.teacherName) · \(need.schoolName)", systemImage: "graduationcap.fill")
                .font(SchoolTheme.bodyFont(size: 12))
                .foregroundStyle(SchoolTheme.mutedText)

            ChalkProgress(progress: need.fundingProgress, height: 12)
                .accessibilityLabel("Funding progress")
                .accessibilityValue("\(Int(need.fundingProgress * 100)) percent")

            HStack {
                Text("\(need.raised.formatted(.currency(code: "USD").precision(.fractionLength(0)))) raised")
                    .font(SchoolTheme.headlineFont(size: 13))
                Spacer()
                Text("\(need.amountRemaining.formatted(.currency(code: "USD").precision(.fractionLength(0)))) left")
                    .font(SchoolTheme.monoFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
            }

            if expanded {
                Divider()
                Text(need.rawRequest)
                    .font(SchoolTheme.bodyFont(size: 13))
                    .foregroundStyle(SchoolTheme.mutedText)
                ForEach(need.items.prefix(5)) { item in
                    HStack {
                        Text("\(item.quantity) × \(item.name)")
                        Spacer()
                        Text(item.total.formatted(.currency(code: "USD")))
                    }
                    .font(SchoolTheme.bodyFont(size: 12))
                }
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                Label(expanded ? "Show less" : "Show details", systemImage: expanded ? "chevron.up" : "chevron.down")
                    .font(SchoolTheme.headlineFont(size: 13))
                    .foregroundStyle(SchoolTheme.denim)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
    }
}
