import SwiftUI

struct TeacherRootView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab: Tab = .home

    enum Tab: Hashable { case home, matches, notifications, impact, settings }

    private var visibleUnreadCount: Int {
        NotificationPreferenceFilter.visible(state.notifications, for: state.profile)
            .filter { !$0.isRead }
            .count
    }

    var body: some View {
        TabView(selection: $tab) {
            TeacherHomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(Tab.home)
            TeacherMatchesView()
                .tabItem { Label("Matches", systemImage: "sparkles") }
                .tag(Tab.matches)
            TeacherNotificationsView()
                .tabItem {
                    Label("Outreach", systemImage: "megaphone.fill")
                }
                .badge(visibleUnreadCount)
                .tag(Tab.notifications)
            TeacherImpactView()
                .tabItem { Label("Impact", systemImage: "chart.bar.fill") }
                .tag(Tab.impact)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "person.crop.circle.fill") }
                .tag(Tab.settings)
        }
        .tint(SchoolTheme.denim)
    }
}
