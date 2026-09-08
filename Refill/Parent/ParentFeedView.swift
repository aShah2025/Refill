import SwiftUI

struct ParentFeedView: View {
    @EnvironmentObject private var state: AppState
    @State private var scope: FeedScope = .all

    private enum FeedScope: Hashable {
        case forYou
        case all
        case focus(SubjectFocus)
    }

    private var visibleNeeds: [ClassroomNeed] {
        switch scope {
        case .forYou:
            let filtered = state.allNeeds.filter { need in
                let matchesInterest = state.profile.interests.isEmpty
                    || state.profile.interests.contains(need.subjectFocus)
                let matchesGrade = state.profile.childGrade == nil
                    || state.profile.childGrade == need.gradeBand
                return matchesInterest && matchesGrade
            }
            return filtered.sorted {
                let lhs = personalizationScore(for: $0)
                let rhs = personalizationScore(for: $1)
                return lhs == rhs ? $0.createdAt > $1.createdAt : lhs > rhs
            }
        case .all:
            return state.allNeeds
        case .focus(let focus):
            return state.allNeeds.filter { $0.subjectFocus == focus }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    greeting
                    heroCard
                    sourceStatus
                    quickFilters
                    resultsHeader
                    needsList
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(LinedPaperBackground())
            .navigationTitle("Feed")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        state.refreshNeeds()
                    } label: {
                        if state.needsLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(SchoolTheme.denim)
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(state.needsLoading)
                    .accessibilityLabel(state.needsLoading ? "Refreshing classroom needs" : "Refresh classroom needs")
                }
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Hi, \(firstName)")
                .font(SchoolTheme.displayFont(size: 26))
                .foregroundStyle(SchoolTheme.ink)
            Text(greetingDetail)
                .font(SchoolTheme.bodyFont(size: 15))
                .foregroundStyle(SchoolTheme.mutedText)
        }
        .accessibilityElement(children: .combine)
    }

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [SchoolTheme.apple, SchoolTheme.crayonOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: 14) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 38, weight: .heavy))
                    .foregroundStyle(.white)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Every chip fills a classroom.")
                        .font(SchoolTheme.displayFont(size: 18))
                        .foregroundStyle(.white)
                    Text("Even $5 from 50 supporters can cover a teacher's needs list.")
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private var sourceStatus: some View {
        HStack(spacing: 8) {
            Image(systemName: state.feedContainsSampleData ? "shippingbox.fill" : "network")
                .foregroundStyle(state.feedContainsSampleData ? SchoolTheme.crayonOrange : SchoolTheme.crayonTeal)
                .accessibilityHidden(true)
            Text(state.feedSourceLabel)
                .lineLimit(1)
                .foregroundStyle(SchoolTheme.ink)
            Spacer()
            if let updated = state.needsLastUpdated {
                Text(updated.formatted(.relative(presentation: .named)))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
        }
        .font(.system(.caption, design: .rounded, weight: .semibold))
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(
            Capsule()
                .fill((state.feedContainsSampleData ? SchoolTheme.crayonOrange : SchoolTheme.crayonTeal).opacity(0.1))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Feed source: \(state.feedSourceLabel)")
    }

    private var quickFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Show me")
                .font(SchoolTheme.headlineFont(size: 15))
                .foregroundStyle(SchoolTheme.ink)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    scopeButton(
                        title: "For You",
                        system: "sparkles",
                        selected: scope == .forYou
                    ) {
                        scope = .forYou
                    }

                    scopeButton(
                        title: "All",
                        system: "rectangle.3.group.fill",
                        selected: scope == .all
                    ) {
                        scope = .all
                    }

                    ForEach(SubjectFocus.allCases) { focus in
                        scopeButton(
                            title: focus.rawValue,
                            system: focus.symbol,
                            selected: scope == .focus(focus)
                        ) {
                            scope = scope == .focus(focus) ? .forYou : .focus(focus)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func scopeButton(
        title: String,
        system: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: system)
                    .font(.system(size: 12, weight: .heavy))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .foregroundStyle(selected ? .white : SchoolTheme.apple)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(Capsule().fill(selected ? SchoolTheme.apple : SchoolTheme.apple.opacity(0.1)))
            .overlay(Capsule().stroke(SchoolTheme.apple.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var resultsHeader: some View {
        HStack {
            Text(scopeTitle)
                .font(SchoolTheme.displayFont(size: 20))
                .foregroundStyle(SchoolTheme.ink)
            Spacer()
            if !state.allNeeds.isEmpty {
                Text("\(visibleNeeds.count) \(visibleNeeds.count == 1 ? "need" : "needs")")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(SchoolTheme.mutedText)
                    .accessibilityLabel("\(visibleNeeds.count) classroom \(visibleNeeds.count == 1 ? "need" : "needs")")
            }
        }
    }

    @ViewBuilder
    private var needsList: some View {
        VStack(spacing: 12) {
            if !state.allNeeds.isEmpty, let error = state.needsError {
                inlineError(error)
            }

            if state.allNeeds.isEmpty && state.needsLoading {
                loadingState
            } else if state.allNeeds.isEmpty, let error = state.needsError {
                errorState(error)
            } else if state.allNeeds.isEmpty {
                emptyFeedState
            } else if visibleNeeds.isEmpty {
                noInterestMatchesState
            } else {
                ForEach(visibleNeeds) { need in
                    DonorFeedGridCard(need: need)
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Loading classroom needs…")
                .font(SchoolTheme.bodyFont(size: 15))
                .foregroundStyle(SchoolTheme.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading classroom needs")
    }

    private func inlineError(_ error: Error) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(SchoolTheme.crayonOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't refresh")
                    .font(SchoolTheme.headlineFont(size: 13))
                Text("Showing saved results. \(error.localizedDescription)")
                    .font(SchoolTheme.bodyFont(size: 12))
                    .foregroundStyle(SchoolTheme.mutedText)
            }
            Spacer()
            Button("Retry") { state.refreshNeeds() }
                .font(.system(.caption, design: .rounded, weight: .bold))
                .frame(minHeight: 44)
                .disabled(state.needsLoading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(SchoolTheme.crayonOrange.opacity(0.1)))
        .accessibilityElement(children: .contain)
    }

    private func errorState(_ error: Error) -> some View {
        stateCard(
            system: "wifi.exclamationmark",
            title: "Couldn't load classroom needs",
            detail: error.localizedDescription,
            actionTitle: "Try again"
        ) {
            state.refreshNeeds()
        }
    }

    private var emptyFeedState: some View {
        stateCard(
            system: "tray",
            title: "No needs yet",
            detail: "Check again soon for classroom requests in your community.",
            actionTitle: "Refresh"
        ) {
            state.refreshNeeds()
        }
    }

    private var noInterestMatchesState: some View {
        stateCard(
            system: "slider.horizontal.3",
            title: "No needs match this view",
            detail: scope == .forYou
                ? "Try All, choose a different subject, or update your interests in Settings."
                : "Choose another subject or show all classroom needs.",
            actionTitle: "Show all"
        ) {
            scope = .all
        }
    }

    private func stateCard(
        system: String,
        title: String,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: system)
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(SchoolTheme.mutedText)
                .accessibilityHidden(true)
            Text(title)
                .font(SchoolTheme.headlineFont(size: 16))
                .foregroundStyle(SchoolTheme.ink)
            Text(detail)
                .font(SchoolTheme.bodyFont(size: 13))
                .foregroundStyle(SchoolTheme.mutedText)
                .multilineTextAlignment(.center)
            Button(actionTitle, action: action)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .background(SchoolTheme.denim)
                .clipShape(Capsule())
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 180)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
    }

    private var firstName: String {
        guard !state.profile.fullName.isEmpty else { return "Friend" }
        return state.profile.fullName.split(separator: " ").first.map(String.init) ?? "Friend"
    }

    private var greetingDetail: String {
        if state.feedIsUsingSampleData {
            return "Explore the preview, then connect a live project feed when you're ready."
        }
        let city = state.profile.city.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty
            ? "Live classroom projects, ranked for your interests."
            : "Live classroom projects, with \(city) matches ranked first."
    }

    private func personalizationScore(for need: ClassroomNeed) -> Int {
        var score = 0
        if state.profile.interests.contains(need.subjectFocus) { score += 4 }
        if state.profile.childGrade == need.gradeBand { score += 3 }

        let profileZIP = state.profile.zip.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profileZIP.isEmpty, need.zip?.hasPrefix(profileZIP) == true { score += 4 }

        let profileCity = state.profile.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if !profileCity.isEmpty, need.city.localizedCaseInsensitiveContains(profileCity) { score += 2 }

        let budget = state.profile.monthlyBudget
        if budget > 0, need.amountRemaining <= max(budget * 4, budget) { score += 1 }
        return score
    }

    private var scopeTitle: String {
        switch scope {
        case .forYou: return "Picked for you"
        case .all: return "All classrooms"
        case .focus(let focus): return focus.rawValue
        }
    }
}
