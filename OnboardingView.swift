import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentStep = 0
    @State private var password = ""
    @AppStorage("name") private var name = ""
    @AppStorage("email") private var email = ""
    @AppStorage("userRole") private var userRole = ""

    enum UserRole: String, CaseIterable, Identifiable {
        case teacher = "Teacher"
        case parent = "Parent"
        case business = "Business Sponsor"
        var id: String { rawValue }
    }

    var body: some View {
        GeometryReader { _ in
            TabView(selection: $currentStep) {
                problemStep.tag(0)
                setupStep.tag(1)
                completionStep.tag(2)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: currentStep)
        }
    }

    private var problemStep: some View {
        VStack(alignment: .center, spacing: 20) {
            Text("How Teachers Spend")
                .font(.largeTitle.bold())
                .padding()

            Text("Teachers often have to spend their own money on classroom supplies.")
                .multilineTextAlignment(.center)
                .padding()
        }
    }

    private var setupStep: some View {
        VStack(spacing: 20) {
            Text("Select Your Role")
                .font(.largeTitle.bold())

            Button(action: { userRole = UserRole.teacher.rawValue }) {
                RoleSelectionCard(title: "I am a Teacher")
            }

            Button(action: { userRole = UserRole.parent.rawValue }) {
                RoleSelectionCard(title: "I am a Parent/Sponsor")
            }

            TextField("Full Name", text: $name)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            TextField("Email Address", text: $email)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)

            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())

            Button(action: {
                if !name.isEmpty && !email.isEmpty && !password.isEmpty {
                    saveUserDetails()
                    withAnimation { currentStep = 2 }
                }
            }) {
                Text("Next")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .disabled(name.isEmpty || email.isEmpty || password.isEmpty)
        }
        .padding()
    }

    private var completionStep: some View {
        VStack(spacing: 20) {
            Text("AI Parsing Speech")
                .font(.largeTitle.bold())

            Text("You're all set! Start describing your classroom needs.")
                .multilineTextAlignment(.center)
                .padding()

            Button(action: {
                hasCompletedOnboarding = true
            }) {
                Text("Get Started")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
    }

    private func saveUserDetails() {
        UserDefaults.standard.set(userRole, forKey: "userRole")
        UserDefaults.standard.set(name, forKey: "name")
        UserDefaults.standard.set(email, forKey: "email")
    }
}

struct RoleSelectionCard: View {
    let title: String

    var body: some View {
        Text(title)
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}
