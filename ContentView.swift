import SwiftUI

struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        TabView {
            if !hasCompletedOnboarding {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .tabItem {
                        Label("Onboarding", systemImage: "person.badge.plus")
                    }
            } else {
                NavigationView {
                    TeacherHomeView()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button(action: {
                                    // Navigate to ProfileDropdown view
                                }) {
                                    ProfileAvatarButton()
                                }
                            }
                        }
                }
                .tabItem {
                    Label("Teacher Home", systemImage: "house")
                }
            }
            
            Text("Match Results")
                .tabItem {
                    Label("Match Results", systemImage: "sparkles")
                }
            
            Text("Parent Feed")
                .tabItem {
                    Label("Parent Feed", systemImage: "heart.text.square")
                }
            
            Text("Impact Dashboard")
                .tabItem {
                    Label("Impact Dashboard", systemImage: "chart.bar.doc.horizontal")
                }
        }
    }
}

struct ProfileAvatarButton: View {
    var body: some View {
        Button(action: {
            // Trigger popover for profile details
        }) {
            Image(systemName: "person.circle")
                .resizable()
                .frame(width: 40, height: 40)
                .foregroundColor(.blue)
        }
    }
}
