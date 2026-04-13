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
            return decoded
        }
        return defaultTabs
    }

    var body: some View {
        VStack(spacing: 0) {
            // メインコンテンツ
            ZStack {
                TodayTimelineView(
                    onToggle: {
                        selectedTab = 1
                    }
                )
                .id(todayViewKey)
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)

                if selectedTab == 1 {
                    WeeklyTimetableCloneView {
                        selectedTab = 0
                    }
                    .transition(.opacity)
                }

                if selectedTab == 2 {
                    NoticeBoardCloneView()
                        .transition(.opacity)
                }

                if selectedTab == 3 {
                    AccountProfileCloneView(onLogout: onLogout) { newOrder in
                        let encoded = try? JSONEncoder().encode(newOrder)
                        tabBarData = encoded ?? Data()
                    }
                    .transition(.opacity)
                }
            }

            // カスタムタブバー
            customTabBar
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
}

#Preview {
    PortalCloneView(onLogout: {})
}
