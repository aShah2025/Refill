import SwiftUI

@main
struct RefillApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .onAppear { state.bootstrap() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { state.refreshNeedsIfStale() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ZStack {
            if state.hasCompletedOnboarding, let role = state.profile.role {
                Group {
                    switch role {
                    case .teacher: TeacherRootView()
                    case .parent: ParentRootView()
                    }
                }
                .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: state.hasCompletedOnboarding)
    }
}
