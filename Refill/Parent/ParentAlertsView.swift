import SwiftUI

struct ParentAlertsView: View {
    @EnvironmentObject private var state: AppState

    private var visibleNotifications: [NotificationItem] {
        NotificationPreferenceFilter.visible(state.notifications, for: state.profile)
    }

    private var unreadVisibleNotifications: [NotificationItem] {
        visibleNotifications.filter { !$0.isRead }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if visibleNotifications.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleNotifications) { item in
                            NotificationRow(item: item) {
                                state.markNotificationRead(item.id)
                            }
                        }

                        preferenceSummary
                    }
                }
                .padding(16)
            }
            .background(LinedPaperBackground())
            .navigationTitle("Alerts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !unreadVisibleNotifications.isEmpty {
                        Button("Mark all read") {
                            unreadVisibleNotifications.forEach { state.markNotificationRead($0.id) }
                        }
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(SchoolTheme.apple)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Mark all visible alerts as read")
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(SchoolTheme.apple.opacity(0.12))
                    .frame(width: 116, height: 116)
                Image(systemName: state.profile.acceptedNotifications ? "bell.slash.fill" : "bell.badge.slash.fill")
                    .font(.system(size: 48, weight: .heavy))
                    .foregroundStyle(SchoolTheme.apple)
            }
            .accessibilityHidden(true)

            Text(emptyStateTitle)
                .font(SchoolTheme.displayFont(size: 22))
                .foregroundStyle(SchoolTheme.ink)

            Text(emptyStateDetail)
                .font(SchoolTheme.bodyFont(size: 14))
                .foregroundStyle(SchoolTheme.mutedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)

            if !state.notifications.isEmpty {
                Label(
                    "\(state.notifications.count) \(state.notifications.count == 1 ? "alert is" : "alerts are") currently hidden.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
                .font(SchoolTheme.bodyFont(size: 12))
                .foregroundStyle(SchoolTheme.mutedText)
            }
        }
        .padding(.vertical, 42)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(SchoolTheme.subtleBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var preferenceSummary: some View {
        let hiddenCount = state.notifications.count - visibleNotifications.count
        if hiddenCount > 0 {
            Label(
                "\(hiddenCount) \(hiddenCount == 1 ? "alert is" : "alerts are") hidden by your notification preferences.",
                systemImage: "line.3.horizontal.decrease.circle"
            )
            .font(SchoolTheme.bodyFont(size: 12))
            .foregroundStyle(SchoolTheme.mutedText)
            .padding(.top, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var emptyStateTitle: String {
        if !state.profile.acceptedNotifications { return "Alerts are turned off" }
        if state.profile.notificationCategories.isEmpty { return "No alert categories selected" }
        if !state.notifications.isEmpty { return "No alerts match your preferences" }
        return "No alerts yet"
    }

    private var emptyStateDetail: String {
        if !state.profile.acceptedNotifications {
            return "Turn alerts back on in Settings when you want classroom and donation updates."
        }
        if state.profile.notificationCategories.isEmpty {
            return "Choose funding sources in Settings to decide which alerts appear here."
        }
        if !state.notifications.isEmpty {
            return "Alerts outside your selected funding categories are hidden. You can change those categories in Settings."
        }
        return "Updates recorded on this device will appear here when they match your selected categories."
    }
}
