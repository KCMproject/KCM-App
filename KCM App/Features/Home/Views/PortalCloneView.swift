import SwiftUI

struct PortalCloneView: View {
    @State private var selectedTab: Int = 0
    @State private var todayViewKey = UUID()
    @AppStorage(AppSettings.tabBarConfiguration) private var tabBarData: Data = Data()
    let onLogout: () -> Void

    private struct TabDef: Codable, Hashable {
        let id: String
        let title: String
        let icon: String
    }

    private let defaultTabs: [TabDef] = [
        .init(id: "today", title: "今日", icon: "calendar"),
        .init(id: "timetable", title: "時間割", icon: "calendar.badge.clock"),
        .init(id: "board", title: "掲示板", icon: "tray.full"),
        .init(id: "account", title: "アカウント", icon: "person.crop.circle")
    ]

    private var tabConfig: [TabDef] {
        if let decoded = try? JSONDecoder().decode([TabDef].self, from: tabBarData), !decoded.isEmpty {
            return normalizedTabConfig(decoded)
        }
        return normalizedTabConfig(defaultTabs)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                ForEach(Array(tabConfig.enumerated()), id: \.element.id) { index, tab in
                    contentView(for: tab)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            customTabBar
        }
    }

    @ViewBuilder
    private func contentView(for tab: TabDef) -> some View {
        switch tab.id {
        case "today":
            TodayTimelineView(
                onToggle: {
                    if let timetableIndex = tabConfig.firstIndex(where: { $0.id == "timetable" }) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            selectedTab = timetableIndex
                        }
                    }
                }
            )
            .id(todayViewKey)
        case "timetable":
            WeeklyTimetableCloneView {
                if let todayIndex = tabConfig.firstIndex(where: { $0.id == "today" }) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selectedTab = todayIndex
                    }
                }
            }
        case "board":
            NoticeBoardCloneView()
        case "account":
            AccountProfileCloneView(onLogout: onLogout) { newOrder in
                let encoded = try? JSONEncoder().encode(newOrder)
                tabBarData = encoded ?? Data()
            }
        default:
            Color.clear
        }
    }

    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabConfig.enumerated()), id: \.offset) { index, tab in
                tabButton(title: tab.title, icon: tab.icon, index: index)
            }
        }
        .background(Color.white)
        .overlay(alignment: .top) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            if selectedTab == index {
                if index == 0 {
                    todayViewKey = UUID()
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedTab = index
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(selectedTab == index ? AppTheme.accent : AppTheme.textMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func normalizedTabConfig(_ items: [TabDef]) -> [TabDef] {
        let accountTab = defaultTabs.first { $0.id == "account" }
        let filtered = items.filter { $0.id != "account" }

        if let accountTab {
            return filtered + [accountTab]
        }

        return filtered
    }
}

#Preview {
    PortalCloneView(onLogout: {})
}
