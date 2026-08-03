import SwiftUI

struct ParentRootView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab: Tab = .feed

    enum Tab: Hashable { case feed, browse, alerts, impact, settings }

    private var visibleUnreadCount: Int {
        NotificationPreferenceFilter.visible(state.notifications, for: state.profile)
            .filter { !$0.isRead }
            .count
    }

    var body: some View {
        TabView(selection: $tab) {
            ParentFeedView()
                .tabItem { Label("Feed", systemImage: "heart.text.square.fill") }
                .tag(Tab.feed)
            ParentBrowseView()
                .tabItem { Label("Browse", systemImage: "rectangle.3.group.fill") }
                .tag(Tab.browse)
            ParentAlertsView()
                .tabItem { Label("Alerts", systemImage: "bell.fill") }
                .badge(visibleUnreadCount)
                .tag(Tab.alerts)
            ParentImpactView()
                .tabItem { Label("Impact", systemImage: "chart.bar.fill") }
                .tag(Tab.impact)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "person.crop.circle.fill") }
                .tag(Tab.settings)
        }
        .tint(SchoolTheme.apple)
    }
}
