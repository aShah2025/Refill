import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var showResetConfirmation = false
    @State private var showSchoolDirectory = false

    var body: some View {
        NavigationStack {
            Form {
                profileHeader
                accountSection

                if state.profile.role == .teacher {
                    teacherSection
                } else {
                    parentSection
                }

                locationSection
                notificationSection
                dataStatusSection
                resetSection
            }
            .scrollContentBackground(.hidden)
            .background(LinedPaperBackground())
            .navigationTitle("Profile & Settings")
            .alert("Reset this account?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset account", role: .destructive) {
                    state.resetAccount()
                }
            } message: {
                Text("This removes the local profile, preferences, favorites, requests, and activity, then returns to onboarding. This cannot be undone.")
            }
            .sheet(isPresented: $showSchoolDirectory) {
                SchoolDirectoryPicker { school in
                    state.profile.schoolName = school.name
                    state.profile.district = school.district
                    state.profile.city = school.city
                    state.profile.zip = school.zip
                }
            }
        }
    }

    private var profileHeader: some View {
        Section {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill((state.profile.role?.accent ?? SchoolTheme.denim).opacity(0.16))
                    Text(initials)
                        .font(SchoolTheme.displayFont(size: 22))
                        .foregroundStyle(state.profile.role?.accent ?? SchoolTheme.denim)
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your profile" : state.profile.fullName)
                        .font(SchoolTheme.headlineFont(size: 19))
                        .foregroundStyle(SchoolTheme.ink)
                    Text(state.profile.role?.displayName ?? "Refill member")
                        .font(SchoolTheme.bodyFont(size: 14))
                        .foregroundStyle(SchoolTheme.mutedText)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var accountSection: some View {
        Section("Account") {
            TextField("Full name", text: $state.profile.fullName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)

            TextField("Email address", text: $state.profile.email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let role = state.profile.role {
                LabeledContent("Account type", value: role.displayName)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var teacherSection: some View {
        Section("Classroom") {
            Button {
                showSchoolDirectory = true
            } label: {
                Label("Find school in public directory", systemImage: "building.2.crop.circle")
                    .frame(minHeight: 44)
            }
            TextField("School name", text: $state.profile.schoolName)
                .textContentType(.organizationName)
            TextField("District (optional)", text: $state.profile.district)

            Picker("Grade band", selection: $state.profile.gradeBand) {
                Text("Not set").tag(nil as GradeBand?)
                ForEach(GradeBand.allCases) { grade in
                    Text(grade.rawValue).tag(Optional(grade))
                }
            }

            Picker("Primary focus", selection: $state.profile.subjectFocus) {
                Text("Not set").tag(nil as SubjectFocus?)
                ForEach(SubjectFocus.allCases) { focus in
                    Text(focus.rawValue).tag(Optional(focus))
                }
            }

            Stepper(value: $state.profile.studentCount, in: 0...200) {
                LabeledContent("Students", value: "\(state.profile.studentCount)")
            }
            .accessibilityValue("\(state.profile.studentCount) students")
        }
    }

    private var parentSection: some View {
        Section("Giving preferences") {
            Picker("Child's grade", selection: $state.profile.childGrade) {
                Text("No preference").tag(nil as GradeBand?)
                ForEach(GradeBand.allCases) { grade in
                    Text(grade.rawValue).tag(Optional(grade))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Interests")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                    ForEach(SubjectFocus.allCases) { focus in
                        interestButton(focus)
                    }
                }
            }
            .padding(.vertical, 4)

            Stepper(value: $state.profile.monthlyBudget, in: 0...1_000, step: 5) {
                LabeledContent(
                    "Monthly budget",
                    value: state.profile.monthlyBudget == 0 ? "Just browsing" : "$\(Int(state.profile.monthlyBudget))"
                )
            }
            .accessibilityValue(state.profile.monthlyBudget == 0 ? "Just browsing" : "$\(Int(state.profile.monthlyBudget)) per month")
        }
    }

    private var locationSection: some View {
        Section {
            TextField("City", text: $state.profile.city)
                .textContentType(.addressCity)
                .textInputAutocapitalization(.words)
            TextField("ZIP code", text: $state.profile.zip)
                .textContentType(.postalCode)
                .keyboardType(.numberPad)
        } header: {
            Text("Location")
        } footer: {
            Text("Used to prioritize nearby classroom needs and local funding opportunities.")
        }
    }

    private var notificationSection: some View {
        Section {
            Toggle("Show Refill in-app alerts", isOn: $state.profile.acceptedNotifications)
                .tint(state.profile.role?.accent ?? SchoolTheme.denim)

            ForEach(FundingSource.allCases) { source in
                Toggle(isOn: notificationBinding(for: source)) {
                    HStack(spacing: 10) {
                        Image(systemName: source.symbol)
                            .foregroundStyle(source.tint)
                            .accessibilityHidden(true)
                        Text(source.rawValue)
                            .foregroundStyle(SchoolTheme.ink)
                    }
                }
                .disabled(!state.profile.acceptedNotifications)
                .accessibilityHint("Controls alerts from \(source.rawValue)")
            }
            .opacity(state.profile.acceptedNotifications ? 1 : 0.45)
        } header: {
            Text("Notifications")
        } footer: {
            Text(state.profile.acceptedNotifications
                 ? "Choose the funding sources that can appear inside Refill. This build does not register for remote push notifications."
                 : "Turn in-app alerts on to choose alert categories.")
        }
    }

    private var dataStatusSection: some View {
        Section {
            LabeledContent("Feed source", value: state.feedSourceLabel)

            LabeledContent("Content") {
                HStack(spacing: 6) {
                    Image(systemName: state.feedContainsSampleData ? "shippingbox.fill" : "network")
                        .foregroundStyle(state.feedContainsSampleData ? SchoolTheme.crayonOrange : SchoolTheme.crayonTeal)
                        .accessibilityHidden(true)
                    Text(state.feedIsUsingSampleData ? "Sample data" : state.feedContainsSampleData ? "Live + sample" : "Live data")
                        .foregroundStyle(SchoolTheme.ink)
                }
            }

            LabeledContent("Classroom needs", value: "\(state.allNeeds.count)")

            if let updated = state.needsLastUpdated {
                LabeledContent("Last updated", value: updated.formatted(date: .abbreviated, time: .shortened))
            } else {
                LabeledContent("Last updated", value: "Not yet")
            }

            if let error = state.needsError {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(SchoolTheme.apple)
                    .accessibilityLabel("Feed error: \(error.localizedDescription)")
            }

            Button {
                state.refreshNeeds()
            } label: {
                HStack {
                    Label("Refresh classroom data", systemImage: "arrow.clockwise")
                    Spacer()
                    if state.needsLoading {
                        ProgressView()
                            .accessibilityLabel("Refreshing")
                    }
                }
                .frame(minHeight: 44)
            }
            .disabled(state.needsLoading)
        } header: {
            Text("Data & API")
        } footer: {
            if state.feedContainsSampleData {
                Text("Clearly labeled sample classroom requests may appear when a live source is unavailable.")
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirmation = true
            } label: {
                Label("Reset account", systemImage: "arrow.counterclockwise.circle")
                    .frame(minHeight: 44)
            }
            .accessibilityHint("Requires confirmation and returns to onboarding")
        } footer: {
            Text("Reset only when you want to remove this account's local data and start over.")
        }
    }

    private func interestButton(_ focus: SubjectFocus) -> some View {
        let selected = state.profile.interests.contains(focus)

        return Button {
            if selected {
                state.profile.interests.remove(focus)
            } else {
                state.profile.interests.insert(focus)
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: focus.symbol)
                Text(focus.rawValue)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(selected ? .white : SchoolTheme.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selected ? SchoolTheme.apple : SchoolTheme.apple.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SchoolTheme.apple.opacity(selected ? 0.8 : 0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(focus.rawValue)
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func notificationBinding(for source: FundingSource) -> Binding<Bool> {
        Binding(
            get: { state.profile.notificationCategories.contains(source) },
            set: { enabled in
                if enabled {
                    state.profile.notificationCategories.insert(source)
                } else {
                    state.profile.notificationCategories.remove(source)
                }
            }
        )
    }

    private var initials: String {
        let parts = state.profile.fullName.split(separator: " ")
        let first = parts.first?.first.map(String.init) ?? (state.profile.role == .teacher ? "T" : "P")
        let last = parts.dropFirst().first?.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }
}
