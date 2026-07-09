import SwiftUI

struct PortalCloneView: View {
    @State private var selectedTab: Int = 0
    @State private var lastSelectedTabID: String = "today"
    @State private var todayViewKey = UUID()
    @State private var isGameTabLocked = false
    @AppStorage(AppSettings.tabBarConfiguration) private var tabBarData: Data = Data()
    @AppStorage(AppSettings.gameTabEnabled) private var gameTabEnabled = true
    let onLogout: () -> Void

    private struct TabDef: Codable, Hashable {
        let id: String
        let title: String
        let icon: String
    }

    /// 並び替え可能なタブ（順序設定の対象）
    private let defaultTabs: [TabDef] = [
        .init(id: "today", title: "今日", icon: "calendar"),
        .init(id: "timetable", title: "時間割", icon: "calendar.badge.clock"),
        .init(id: "board", title: "掲示板", icon: "tray.full")
    ]

    private let gameTab = TabDef(id: "game", title: "ゲーム", icon: "gamecontroller")
    private let accountTab = TabDef(id: "account", title: "アカウント", icon: "person.crop.circle")

    private var tabConfig: [TabDef] {
        assembleTabs(reorderable: decodeReorderableTabs())
    }

    private func decodeReorderableTabs() -> [TabDef] {
        if let decoded = try? JSONDecoder().decode([TabDef].self, from: tabBarData), !decoded.isEmpty {
            return normalizedTabConfig(decoded)
        }
        return normalizedTabConfig(defaultTabs)
    }

    private func assembleTabs(reorderable: [TabDef]) -> [TabDef] {
        var tabs = reorderable
        if gameTabEnabled {
            tabs.append(gameTab)
        }
        tabs.append(accountTab)
        return tabs
    }

    @State private var hasRefreshedOneYear = false

    var body: some View {
        VStack(spacing: 0) {
            SwipeableView(
                selectedTab: selectedTab,
                tabCount: tabConfig.count,
                contentProvider: { index in
                    AnyView(contentView(for: tabConfig[index]))
                },
                onSwipeToTab: { index in switchTab(to: index) },
                isSwipeEnabled: !isGameTabLocked || tabConfig[selectedTab].id != "game"
            )

            customTabBar
        }
        .onAppear {
            // まずキャッシュを即座に読み込んで表示する
            PortalDataCoordinator.shared.loadCachedData()

            if !hasRefreshedOneYear {
                hasRefreshedOneYear = true
                Task {
                    await PortalDataCoordinator.shared.refreshScheduleForOneYear(showUpdateBanner: true)
                }
            }
            if selectedTab < tabConfig.count {
                lastSelectedTabID = tabConfig[selectedTab].id
            }
        }
        .onChange(of: gameTabEnabled) { _, _ in
            adjustSelectedTabAfterTabConfigChange()
        }
        .onChange(of: tabBarData) { _, _ in
            adjustSelectedTabAfterTabConfigChange()
        }
    }

    private func adjustSelectedTabAfterTabConfigChange() {
        if let index = tabConfig.firstIndex(where: { $0.id == lastSelectedTabID }) {
            selectedTab = index
        } else {
            selectedTab = min(selectedTab, max(0, tabConfig.count - 1))
        }
    }

    private func switchTab(to index: Int) {
        guard index >= 0, index < tabConfig.count, index != selectedTab else { return }
        selectedTab = index
        lastSelectedTabID = tabConfig[index].id
    }

    @ViewBuilder
    private func contentView(for tab: TabDef) -> some View {
        switch tab.id {
        case "today":
            TodayTimelineView(
                onToggle: {
                    if let timetableIndex = tabConfig.firstIndex(where: { $0.id == "timetable" }) {
                        switchTab(to: timetableIndex)
                    }
                }
            )
            .id(todayViewKey)
        case "timetable":
            WeeklyTimetableCloneView {
                if let todayIndex = tabConfig.firstIndex(where: { $0.id == "today" }) {
                    switchTab(to: todayIndex)
                }
            }
        case "board":
            NoticeBoardCloneView()
        case "game":
            EggGameCloneView(isLocked: $isGameTabLocked)
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
                switchTab(to: index)
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
        // 並び替え対象外のタブ（game / account）は常に除外し、
        // 不足している並び替え対象タブを補完する
        let validIDs = Set(defaultTabs.map(\.id))
        var result = items.filter { validIDs.contains($0.id) }

        // デフォルトタブが抜けていれば追加
        for tab in defaultTabs where !result.contains(where: { $0.id == tab.id }) {
            result.append(tab)
        }

        return result
    }
}

#Preview {
    PortalCloneView(onLogout: {})
}
