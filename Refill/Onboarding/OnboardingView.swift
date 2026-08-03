import SwiftUI

// A polished, multi-step onboarding flow with a school theme.
// Steps:
//   0 - Welcome
//   1 - Are you a teacher or a parent/supporter?
//   2 - Name + email
//   3 - Role-tailored questions (teacher: school/grade/students; parent: child grade/interests/budget)
//   4 - In-app alert preferences
//   5 - Finish
struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @State private var step: Int = 0
    @State private var animateBackground = false
    @State private var showConfetti = false
    @State private var validationError: String? = nil
    @State private var showSchoolDirectory = false

    private let totalSteps = 6

    var body: some View {
        ZStack {
            ChalkboardBackground()
                .overlay(
                    ZStack {
                        ForEach(0..<20, id: \.self) { i in
                            Image(systemName: ["plus", "minus", "multiply", "divide", "x.squareroot", "function", "atom", "books.vertical", "graduationcap", "pencil"][i % 10])
                                .font(.system(size: CGFloat.random(in: 18...46), weight: .heavy))
                                .foregroundStyle(.white.opacity(0.05))
                                .offset(
                                    x: CGFloat.random(in: -180...180),
                                    y: CGFloat.random(in: -380...380)
                                )
                                .rotationEffect(.degrees(.random(in: -25...25)))
                        }
                    }
                )
                // This is purely decorative. Keep its full-screen Canvas and symbols
                // out of hit testing so they can never sit in front of the controls.
                .allowsHitTesting(false)
                .onAppear { animateBackground.toggle() }

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                content
                Spacer(minLength: 0)
                bottomBar
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .contentShape(Rectangle())

            if showConfetti {
                ConfettiView()
                    .ignoresSafeArea()
            }
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

    // MARK: - Top bar (back + progress)
    private var topBar: some View {
        VStack(spacing: 14) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        if step == 0 { return } else { step -= 1 }
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(step == 0 ? .white.opacity(0.25) : .white)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(.white.opacity(step == 0 ? 0.05 : 0.12)))
                }
                .disabled(step == 0)

                Spacer()

                Text("Step \(step + 1) of \(totalSteps)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                if step == 4 {
                    Button {
                        state.profile.acceptedNotifications = false
                        advance()
                    } label: {
                        Text("Not now")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .accessibilityHint("Continues without requesting notification permission")
                } else {
                    Color.clear.frame(width: 58, height: 36)
                }
            }

            StepDot(index: step, current: step, total: totalSteps)
                .padding(.bottom, 2)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Content switch
    @ViewBuilder
    private var content: some View {
        Group {
            switch step {
            case 0: welcomeStep.transition(stepTransition)
            case 1: roleStep.transition(stepTransition)
            case 2: identityStep.transition(stepTransition)
            case 3: detailStep.transition(stepTransition)
            case 4: notificationsStep.transition(stepTransition)
            default: finishStep.transition(stepTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Bottom bar
    private var bottomBar: some View {
        VStack(spacing: 6) {
            if let err = validationError {
                Text(err)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(SchoolTheme.eraser)
                    .transition(.opacity)
            }

            Button {
                advance()
            } label: {
                HStack(spacing: 8) {
                    Text(primaryButtonTitle)
                        .font(SchoolTheme.headlineFont(size: 17))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(state.profile.role?.accent ?? SchoolTheme.denim)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.white.opacity(0.95))
                            .offset(y: 5)
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.white)
                    }
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 22))
            .disabled(step == 1 && state.profile.role == nil)
            .opacity(step == 1 && state.profile.role == nil ? 0.58 : 1)
            .accessibilityHint(step == 1 && state.profile.role == nil ? "Choose a role above before continuing" : "")
            .padding(.bottom, 6)
        }
        .padding(.bottom, 12)
    }

    private var primaryButtonTitle: String {
        switch step {
        case 0: return "Get Started"
        case 4: return "Save alert preferences"
        case 5: return "Enter the classroom"
        default: return "Continue"
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            Polaroid(rotation: -4) {
                VStack(spacing: 8) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 60, weight: .heavy))
                        .foregroundStyle(SchoolTheme.apple)
                    Text("Refill")
                        .font(SchoolTheme.displayFont(size: 36))
                        .foregroundStyle(SchoolTheme.denim)
                }
                .padding(.top, 18)
            }
            .scaleEffect(animateBackground ? 1.0 : 0.9)
            .animation(.spring(response: 0.6, dampingFraction: 0.6).repeatCount(1, autoreverses: false), value: animateBackground)

            VStack(spacing: 10) {
                Text("No teacher should pay out of pocket.")
                    .font(SchoolTheme.displayFont(size: 26))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Turn a plain-English classroom need into an editable request, then explore practical funding routes and official project links.")
                    .font(SchoolTheme.bodyFont(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .padding(.top, 8)

            HStack(spacing: 14) {
                featureChip(system: "sparkles", text: "Smart drafts", color: SchoolTheme.pencilYellow)
                featureChip(system: "megaphone.fill", text: "Outreach", color: SchoolTheme.apple)
                featureChip(system: "chart.bar.fill", text: "Impact", color: SchoolTheme.crayonTeal)
            }
            .padding(.top, 4)

            Spacer()
            Spacer()
        }
    }

    private func featureChip(system: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: system)
                .font(.system(size: 12, weight: .heavy))
            Text(text)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(.white.opacity(0.1)))
        .overlay(Capsule().stroke(color.opacity(0.6), lineWidth: 1.2))
    }

    private var roleStep: some View {
        VStack(spacing: 18) {
            Spacer()
            VStack(spacing: 10) {
                Text("First — who are you?")
                    .font(SchoolTheme.displayFont(size: 28))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Refill works differently for each. Pick the one that fits you best today.")
                    .font(SchoolTheme.bodyFont(size: 15))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            VStack(spacing: 14) {
                roleCard(role: .teacher, title: "I'm a teacher", detail: "Create reviewed requests, compare funding routes, and share outreach drafts.", symbols: "graduationcap.fill")
                roleCard(role: .parent, title: "I'm a parent or supporter", detail: "Browse clearly labeled live or sample projects and use official support links.", symbols: "heart.text.square.fill")
            }
            .padding(.top, 6)
            Spacer()
            Spacer()
        }
    }

    private func roleCard(role: UserRole, title: String, detail: String, symbols: String) -> some View {
        let isSelected = state.profile.role == role
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                state.profile.role = role
            }
        } label: {
            HStack(spacing: 14) {
                SymbolBadge(system: symbols, color: role.accent, size: 56, symbolSize: 26)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(SchoolTheme.headlineFont(size: 18))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(SchoolTheme.bodyFont(size: 13))
                        .foregroundStyle(.white.opacity(0.86))
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(isSelected ? SchoolTheme.pencilYellow : .white.opacity(0.4))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(isSelected ? role.accent.opacity(0.25) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(isSelected ? role.accent : Color.white.opacity(0.18),
                            lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var identityStep: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Let's set up your account")
                    .font(SchoolTheme.displayFont(size: 26))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("This personalizes your local profile, request drafts, and in-app alerts.")
                    .font(SchoolTheme.bodyFont(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                schoolField(system: "person.fill", placeholder: "Full name", text: $state.profile.fullName)
                schoolField(system: "envelope.fill", placeholder: "Email address", text: $state.profile.email, keyboard: .emailAddress)
            }
            .padding(.top, 10)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(SchoolTheme.pencilYellow)
                .padding(.top, 6)
            Text("Your profile is saved locally on this device. You can edit or reset it any time in Settings.")
                .font(SchoolTheme.bodyFont(size: 12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Spacer()
        }
    }

    private func schoolField(system: String, placeholder: String, text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22)
            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(.white.opacity(0.4)))
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .font(SchoolTheme.bodyFont(size: 16))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var detailStep: some View {
        if state.profile.role == .teacher {
            teacherDetailStep
        } else {
            parentDetailStep
        }
    }

    private var teacherDetailStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Tell us about your classroom")
                        .font(SchoolTheme.displayFont(size: 24))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Refill uses this context to prepare relevant funding routes for you to verify.")
                        .font(SchoolTheme.bodyFont(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                Button {
                    showSchoolDirectory = true
                } label: {
                    Label("Search the public school directory", systemImage: "building.2.crop.circle")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(SchoolTheme.pencilYellow)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                schoolField(system: "building.2.fill", placeholder: "School name", text: $state.profile.schoolName)
                schoolField(system: "map.fill", placeholder: "City", text: $state.profile.city)
                HStack(spacing: 10) {
                    schoolField(system: "mappin.and.ellipse", placeholder: "ZIP", text: $state.profile.zip)
                    studentStepper
                }
                schoolField(system: "shield.lefthalf.filled", placeholder: "District (optional)", text: $state.profile.district)
                gradePicker
                subjectPicker
                Spacer(minLength: 0)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var parentDetailStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("What pulls you in?")
                        .font(SchoolTheme.displayFont(size: 24))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("Refill will prioritize relevant classroom projects from the configured California feed.")
                        .font(SchoolTheme.bodyFont(size: 14))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                gradePicker
                interestGrid
                budgetPicker
                schoolField(system: "map.fill", placeholder: "City (optional)", text: $state.profile.city)
                schoolField(system: "mappin.and.ellipse", placeholder: "ZIP (optional)", text: $state.profile.zip)
                Spacer(minLength: 0)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var studentStepper: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 22)
            Text("\(state.profile.studentCount) students")
                .font(SchoolTheme.bodyFont(size: 15))
                .foregroundStyle(.white)
            Spacer()
            Button {
                if state.profile.studentCount > 0 { state.profile.studentCount -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(.white.opacity(0.7))
            }
            Button {
                if state.profile.studentCount < 200 { state.profile.studentCount += 1 }
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.25), lineWidth: 1))
    }

    private var gradePicker: some View {
        chipPicker(title: "Grade band", options: GradeBand.allCases, selection: gradeBinding)
    }

    private var gradeBinding: Binding<GradeBand?> {
        Binding(
            get: { state.profile.role == .parent ? state.profile.childGrade : state.profile.gradeBand },
            set: { newValue in
                if state.profile.role == .parent { state.profile.childGrade = newValue }
                else { state.profile.gradeBand = newValue }
            }
        )
    }

    private var subjectPicker: some View {
        chipPicker(title: "Primary focus", options: SubjectFocus.allCases, selection: $state.profile.subjectFocus)
    }

    private var interestGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.8))
                Text("Pick what you care about")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SubjectFocus.allCases) { focus in
                    let on = state.profile.interests.contains(focus)
                    Button {
                        if on { state.profile.interests.remove(focus) }
                        else { state.profile.interests.insert(focus) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: focus.symbol)
                                .font(.system(size: 16, weight: .heavy))
                            Text(focus.rawValue)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(on ? SchoolTheme.chalkboard : .white.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(on ? Color.white : Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(on ? SchoolTheme.pencilYellow : Color.white.opacity(0.2),
                                        lineWidth: on ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var budgetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.8))
                    Text("Monthly giving budget")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text(state.profile.monthlyBudget > 0 ? "$\(Int(state.profile.monthlyBudget))/mo" : "—")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(SchoolTheme.pencilYellow)
            }
            HStack(spacing: 8) {
                ForEach([0, 10, 25, 50, 100], id: \.self) { amt in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            state.profile.monthlyBudget = Double(amt)
                        }
                    } label: {
                        Text(amt == 0 ? "Just browse" : "$\(amt)")
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(state.profile.monthlyBudget == Double(amt) ? SchoolTheme.chalkboard : .white.opacity(0.85))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(state.profile.monthlyBudget == Double(amt) ? Color.white : Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(state.profile.monthlyBudget == Double(amt) ? SchoolTheme.pencilYellow : Color.white.opacity(0.2),
                                            lineWidth: state.profile.monthlyBudget == Double(amt) ? 2 : 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chipPicker<T: Identifiable & Hashable & RawRepresentable>(title: String, options: [T], selection: Binding<T?>) -> some View where T.RawValue == String {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.8))
                Text(title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { opt in
                        let on = selection.wrappedValue == opt
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selection.wrappedValue = on ? nil : opt
                            }
                        } label: {
                            Text(opt.rawValue)
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundStyle(on ? SchoolTheme.chalkboard : .white.opacity(0.85))
                                .padding(.horizontal, 14)
                                .frame(minHeight: 38)
                                .background(
                                    Capsule()
                                        .fill(on ? Color.white : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(on ? SchoolTheme.pencilYellow : Color.white.opacity(0.2),
                                                lineWidth: on ? 2 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var notificationsStep: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundStyle(SchoolTheme.pencilYellow)
                Text("Stay in the loop")
                    .font(SchoolTheme.displayFont(size: 24))
                    .foregroundStyle(.white)
                Text(state.profile.role == .parent
                     ? "Choose which updates should appear in your in-app Alerts tab."
                     : "Choose which updates should appear in your in-app Outreach inbox.")
                    .font(SchoolTheme.bodyFont(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: $state.profile.acceptedNotifications) {
                    Text("Show in-app alerts")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .toggleStyle(SwitchToggleStyle(tint: SchoolTheme.pencilYellow))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.08)))

                Text("Notify me about")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(FundingSource.allCases) { src in
                        let on = state.profile.notificationCategories.contains(src)
                        Button {
                            if on { state.profile.notificationCategories.remove(src) }
                            else { state.profile.notificationCategories.insert(src) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: src.symbol)
                                    .font(.system(size: 15, weight: .heavy))
                                Text(src.rawValue)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .foregroundStyle(on ? SchoolTheme.chalkboard : .white.opacity(0.85))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(on ? Color.white : Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(on ? src.tint : Color.white.opacity(0.2),
                                            lineWidth: on ? 2 : 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var finishStep: some View {
        VStack(spacing: 20) {
            Spacer()
            BouncingPencil(color: SchoolTheme.pencilYellow)
                .frame(width: 60, height: 80)
            VStack(spacing: 6) {
                Text("Your classroom,\nready to refill.")
                    .font(SchoolTheme.displayFont(size: 28))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(state.profile.role == .parent
                     ? "Your feed will clearly identify live projects, saved data, and preview samples."
                     : "Refill is ready to turn your next idea into a request you control.")
                    .font(SchoolTheme.bodyFont(size: 15))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
            ThinkingDots(color: .white)
                .padding(.top, 6)
            Spacer()
            Spacer()
        }
    }

    // MARK: - Flow control
    private func advance() {
        validationError = nil
        switch step {
        case 1:
            guard state.profile.role != nil else {
                validationError = "Pick who you are to continue."
                return
            }
        case 2:
            let email = state.profile.email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !state.profile.fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  email.contains("@"), email.split(separator: "@").last?.contains(".") == true else {
                validationError = "Add your name and email."
                return
            }
        case 3:
            if state.profile.role == .teacher {
                guard !state.profile.schoolName.isEmpty, state.profile.gradeBand != nil, state.profile.subjectFocus != nil else {
                    validationError = "Add your school, grade, and focus."
                    return
                }
            } else {
                guard !state.profile.interests.isEmpty else {
                    validationError = "Pick at least one interest."
                    return
                }
            }
        default:
            break
        }

        if step == 4 {
            showConfetti = true
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            if step < totalSteps - 1 { step += 1 } else { finishOnboarding() }
        }
    }

    private func finishOnboarding() {
        withAnimation(.easeInOut(duration: 0.4)) {
            if !state.completeOnboarding() {
                validationError = "Choose a role before continuing."
                step = 1
            }
        }
    }
}
