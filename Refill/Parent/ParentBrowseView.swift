import SwiftUI

struct ParentBrowseView: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var selectedCategory: SupplyCategory?
    @State private var selectedUrgency: Urgency?
    @State private var selectedGrade: GradeBand?
    @State private var sortOption: SortOption = .urgent
    @State private var favoritesOnly = false

    private enum SortOption: String, CaseIterable, Identifiable {
        case urgent = "Most urgent"
        case closestToGoal = "Closest to goal"
        case newest = "Newest"
        case amount = "Funding goal"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .urgent: return "exclamationmark.circle.fill"
            case .closestToGoal: return "chart.line.uptrend.xyaxis"
            case .newest: return "clock.fill"
            case .amount: return "dollarsign.circle.fill"
            }
        }
    }

    private var filteredNeeds: [ClassroomNeed] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = state.allNeeds.filter { need in
            let matchesCategory = selectedCategory == nil || need.category == selectedCategory
            let matchesUrgency = selectedUrgency == nil || need.urgency == selectedUrgency
            let matchesGrade = selectedGrade == nil || need.gradeBand == selectedGrade
            let matchesFavorite = !favoritesOnly || state.isFavorite(need)
            let matchesQuery = normalizedQuery.isEmpty || searchableText(for: need).localizedCaseInsensitiveContains(normalizedQuery)
            return matchesCategory && matchesUrgency && matchesGrade && matchesFavorite && matchesQuery
        }

        return matches.sorted(by: sortPredicate)
    }

    private var hasActiveFilters: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedCategory != nil
            || selectedUrgency != nil
            || selectedGrade != nil
            || favoritesOnly
            || sortOption != .urgent
    }

    private var activeFilterCount: Int {
        [selectedCategory != nil, selectedUrgency != nil, selectedGrade != nil, favoritesOnly]
            .filter { $0 }
            .count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                categoryStrip
                filterControls
                resultsSummary

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if !state.allNeeds.isEmpty, let error = state.needsError {
                            inlineError(error)
                        }

                        content
                    }
                    .padding(16)
                }
            }
            .background(LinedPaperBackground())
            .navigationTitle("Browse")
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
                        }
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(state.needsLoading)
                    .accessibilityLabel(state.needsLoading ? "Refreshing classroom needs" : "Refresh classroom needs")
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SchoolTheme.mutedText)
                .accessibilityHidden(true)
            TextField("Search title, teacher, school, item, or city", text: $query)
                .font(SchoolTheme.bodyFont(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search classroom needs")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SchoolTheme.mutedText)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, query.isEmpty ? 12 : 0)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryButton(title: "All", system: "rectangle.3.group.fill", color: SchoolTheme.denim, selected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(SupplyCategory.allCases) { category in
                categoryButton(
                        title: category.rawValue,
                        system: category.symbol,
                        color: category.tint,
                        selectedForeground: selectedForeground(for: category),
                        selected: selectedCategory == category
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func categoryButton(
        title: String,
        system: String,
        color: Color,
        selectedForeground: Color = .white,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: system)
                    .font(.system(size: 11, weight: .heavy))
                Text(title)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? selectedForeground : color)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Capsule().fill(selected ? color : color.opacity(0.1)))
            .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var filterControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                urgencyMenu
                gradeMenu
                sortMenu

                Button {
                    favoritesOnly.toggle()
                } label: {
                    filterLabel(
                        title: "Favorites",
                        system: favoritesOnly ? "heart.fill" : "heart",
                        active: favoritesOnly,
                        color: SchoolTheme.apple
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Favorites only")
                .accessibilityValue(favoritesOnly ? "On" : "Off")
                .accessibilityAddTraits(favoritesOnly ? .isSelected : [])

                if hasActiveFilters {
                    Button("Clear") {
                        clearFilters()
                    }
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(SchoolTheme.apple)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Clear all browse filters")
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var urgencyMenu: some View {
        Menu {
            Button {
                selectedUrgency = nil
            } label: {
                menuChoiceLabel("Any urgency", selected: selectedUrgency == nil)
            }
            Divider()
            ForEach(Urgency.allCases) { urgency in
                Button {
                    selectedUrgency = urgency
                } label: {
                    menuChoiceLabel(urgency.rawValue, selected: selectedUrgency == urgency)
                }
            }
        } label: {
            filterLabel(
                title: selectedUrgency?.rawValue ?? "Urgency",
                system: "clock.fill",
                active: selectedUrgency != nil,
                color: selectedUrgency?.tint ?? SchoolTheme.denim
            )
        }
        .accessibilityLabel("Urgency filter")
        .accessibilityValue(selectedUrgency?.rawValue ?? "Any urgency")
    }

    private var gradeMenu: some View {
        Menu {
            Button {
                selectedGrade = nil
            } label: {
                menuChoiceLabel("Any grade", selected: selectedGrade == nil)
            }
            Divider()
            ForEach(GradeBand.allCases) { grade in
                Button {
                    selectedGrade = grade
                } label: {
                    menuChoiceLabel(grade.rawValue, selected: selectedGrade == grade)
                }
            }
        } label: {
            filterLabel(
                title: selectedGrade?.rawValue ?? "Grade",
                system: "studentdesk",
                active: selectedGrade != nil,
                color: SchoolTheme.crayonPurple
            )
        }
        .accessibilityLabel("Grade filter")
        .accessibilityValue(selectedGrade?.rawValue ?? "Any grade")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SortOption.allCases) { option in
                Button {
                    sortOption = option
                } label: {
                    menuChoiceLabel(option.rawValue, selected: sortOption == option, system: option.systemImage)
                }
            }
        } label: {
            filterLabel(
                title: sortOption.rawValue,
                system: "arrow.up.arrow.down",
                active: sortOption != .urgent,
                color: SchoolTheme.crayonTeal
            )
        }
        .accessibilityLabel("Sort classroom needs")
        .accessibilityValue(sortOption.rawValue)
    }

    private func filterLabel(title: String, system: String, active: Bool, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .bold))
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .opacity(system == "heart" || system == "heart.fill" ? 0 : 1)
        }
        .foregroundStyle(active ? activeForeground(for: color) : color)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Capsule().fill(active ? color : color.opacity(0.1)))
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1))
    }

    private func menuChoiceLabel(_ title: String, selected: Bool, system: String? = nil) -> some View {
        HStack {
            if let system {
                Image(systemName: system)
            }
            Text(title)
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var resultsSummary: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(filteredNeeds.count) \(filteredNeeds.count == 1 ? "classroom need" : "classroom needs")")
                    .font(SchoolTheme.headlineFont(size: 14))
                    .foregroundStyle(SchoolTheme.ink)
                Text(state.feedSourceLabel)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(state.feedContainsSampleData ? SchoolTheme.crayonOrange : SchoolTheme.mutedText)
            }
            Spacer()
            if activeFilterCount > 0 {
                Text("\(activeFilterCount) active")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(SchoolTheme.denim)
            }
            if state.needsLoading, !state.allNeeds.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Refreshing results")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if state.allNeeds.isEmpty && state.needsLoading {
            loadingState
        } else if state.allNeeds.isEmpty, let error = state.needsError {
            errorState(error)
        } else if state.allNeeds.isEmpty {
            emptyDataState
        } else if filteredNeeds.isEmpty {
            filteredEmptyState
        } else {
            ForEach(filteredNeeds) { need in
                needRow(need)
            }
        }
    }

    private func needRow(_ need: ClassroomNeed) -> some View {
        HStack(alignment: .top, spacing: 8) {
            NavigationLink {
                NeedDetailView(need: need)
            } label: {
                NeedRowCard(need: need)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens request details")

            Button {
                state.toggleFavorite(need)
            } label: {
                Image(systemName: state.isFavorite(need) ? "heart.fill" : "heart")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(SchoolTheme.apple)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white))
                    .overlay(Circle().stroke(SchoolTheme.apple.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(state.isFavorite(need) ? "Remove \(need.title) from favorites" : "Add \(need.title) to favorites")
            .accessibilityValue(state.isFavorite(need) ? "Favorite" : "Not favorite")
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
        .frame(maxWidth: .infinity, minHeight: 220)
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

    private var emptyDataState: some View {
        stateCard(
            system: "tray",
            title: "No classroom needs yet",
            detail: "New requests will appear here as teachers publish them.",
            actionTitle: "Refresh"
        ) {
            state.refreshNeeds()
        }
    }

    private var filteredEmptyState: some View {
        stateCard(
            system: favoritesOnly ? "heart.slash" : "magnifyingglass",
            title: favoritesOnly && state.favoriteNeedIDs.isEmpty ? "No favorites yet" : "No matching needs",
            detail: favoritesOnly && state.favoriteNeedIDs.isEmpty
                ? "Tap the heart beside a classroom request to save it here."
                : "Try a broader search or remove one of your filters.",
            actionTitle: "Clear filters"
        ) {
            clearFilters()
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
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
    }

    private func searchableText(for need: ClassroomNeed) -> String {
        ([need.title, need.teacherName, need.schoolName, need.city] + need.items.map(\.name))
            .joined(separator: " \n")
    }

    private func selectedForeground(for category: SupplyCategory) -> Color {
        switch category {
        case .supplies, .furniture, .hygiene, .art:
            return SchoolTheme.chalkboardDeep
        case .books, .tech, .math, .other:
            return .white
        }
    }

    private func activeForeground(for color: Color) -> Color {
        switch color {
        case SchoolTheme.crayonOrange, SchoolTheme.crayonTeal, SchoolTheme.denimLight,
             SchoolTheme.pencilYellow, SchoolTheme.eraser:
            return SchoolTheme.chalkboardDeep
        default:
            return .white
        }
    }

    private func sortPredicate(_ lhs: ClassroomNeed, _ rhs: ClassroomNeed) -> Bool {
        switch sortOption {
        case .urgent:
            let leftRank = urgencyRank(lhs.urgency)
            let rightRank = urgencyRank(rhs.urgency)
            return leftRank == rightRank ? lhs.createdAt > rhs.createdAt : leftRank < rightRank
        case .closestToGoal:
            if lhs.fundingProgress == rhs.fundingProgress {
                return remainingAmount(for: lhs) < remainingAmount(for: rhs)
            }
            return lhs.fundingProgress > rhs.fundingProgress
        case .newest:
            return lhs.createdAt > rhs.createdAt
        case .amount:
            if lhs.fundingGoal == rhs.fundingGoal {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.fundingGoal < rhs.fundingGoal
        }
    }

    private func urgencyRank(_ urgency: Urgency) -> Int {
        switch urgency {
        case .thisWeek: return 0
        case .twoWeeks: return 1
        case .thisMonth: return 2
        case .flexible: return 3
        }
    }

    private func remainingAmount(for need: ClassroomNeed) -> Double {
        max(need.fundingGoal - need.raised, 0)
    }

    private func clearFilters() {
        query = ""
        selectedCategory = nil
        selectedUrgency = nil
        selectedGrade = nil
        sortOption = .urgent
        favoritesOnly = false
    }
}
