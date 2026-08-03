import SwiftUI

/// Searchable, read-only school reference data from the Urban Institute
/// Education Data Portal. Selecting a result fills editable profile fields; it
/// never creates a classroom request or claims that a teacher is verified.
struct SchoolDirectoryPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (SchoolsAPI.School) -> Void

    @State private var schools: [SchoolsAPI.School] = []
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var results: [SchoolsAPI.School] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return Array(schools.prefix(100)) }
        return schools.filter { school in
            school.name.localizedCaseInsensitiveContains(term)
                || school.district.localizedCaseInsensitiveContains(term)
                || school.city.localizedCaseInsensitiveContains(term)
                || school.zip.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && schools.isEmpty {
                    ProgressView("Loading the public school directory…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if schools.isEmpty, let errorMessage {
                    ContentUnavailableView {
                        Label("Directory unavailable", systemImage: "building.2.crop.circle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                    }
                } else {
                    List(results) { school in
                        Button {
                            onSelect(school)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(school.name)
                                    .font(SchoolTheme.headlineFont(size: 15))
                                    .foregroundStyle(SchoolTheme.ink)
                                Text("\(school.district) · \(school.city), \(school.state) \(school.zip)")
                                    .font(SchoolTheme.bodyFont(size: 12))
                                    .foregroundStyle(SchoolTheme.mutedText)
                                    .lineLimit(2)
                                HStack(spacing: 10) {
                                    Label(school.gradeRange, systemImage: "graduationcap.fill")
                                    if school.enrollment > 0 {
                                        Label("\(school.enrollment) students", systemImage: "person.3.fill")
                                    }
                                }
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .foregroundStyle(SchoolTheme.denim)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Fills the school, district, city, and ZIP fields")
                    }
                    .overlay {
                        if results.isEmpty {
                            ContentUnavailableView.search(text: query)
                        }
                    }
                }
            }
            .background(LinedPaperBackground())
            .navigationTitle("Find your school")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "School, district, city, or ZIP")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !schools.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Text("Urban Institute Education Data Portal · 2024 CCD")
                            .font(.caption2)
                            .foregroundStyle(SchoolTheme.mutedText)
                    }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            schools = try await SchoolsAPI.loadCA19Schools()
        } catch is CancellationError {
            isLoading = false
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
