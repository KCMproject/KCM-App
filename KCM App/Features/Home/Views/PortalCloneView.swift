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
    @State private var tabBarSize: CGSize = .zero
    @State private var isDraggingTab = false
    @State private var dragMoved = false
    @State private var dragStartX: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        SwipeableView(
            selectedTab: selectedTab,
            tabCount: tabConfig.count,
            contentProvider: { index in
                AnyView(contentView(for: tabConfig[index]).ignoresSafeArea(edges: .bottom))
            },
            onSwipeToTab: { index in switchTab(to: index) },
            isSwipeEnabled: !isGameTabLocked || tabConfig[selectedTab].id != "game"
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
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
                tabLabel(title: tab.title, icon: tab.icon, index: index)
            }
        }
        .padding(5)
        .background {
            GeometryReader { geo in
                ZStack {
                    if #available(iOS 26.0, *) {
                        Capsule()
                            .fill(.clear)
                            .glassEffect()
                            .shadow(color: .black.opacity(0.08), radius: 16, y: 8)
                    } else {
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
                    }
                    tabIndicator(in: geo.size)
                }
                .onAppear { tabBarSize = geo.size }
                .onChange(of: geo.size) { _, newSize in
                    tabBarSize = newSize
                }
            }
        }
        .simultaneousGesture(tabBarDragGesture())
        .contentShape(Rectangle().inset(by: -12))
        .scaleEffect(isDraggingTab ? 1.04 : 1.0, anchor: .bottom)
        .animation(.spring(duration: 0.35), value: selectedTab)
        .padding(.horizontal, 28)
        .padding(.bottom, 0)
    }

    private var tabWidth: CGFloat {
        guard tabBarSize.width > 0, tabConfig.count > 1 else { return 0 }
        return tabBarSize.width / CGFloat(tabConfig.count)
    }

    /// 端のタブでバーとの余白（上下の余白と同じ）
    private var endMargin: CGFloat {
        let barHeight = tabBarSize.height
        guard barHeight > 0 else { return 0 }
        return (barHeight - max(barHeight - 10, 32)) / 2
    }

    /// タブの中心位置（アイコン中心と同じ。両端ではピルの外側の余白が上下と同じになる）
    private func tabCenterX(for index: Int) -> CGFloat {
        let tabWidth = tabWidth
        guard tabWidth > 0 else { return 0 }
        if index <= 0 {
            return endMargin + pillWidth() / 2
        }
        if index >= tabConfig.count - 1 {
            return tabBarSize.width - endMargin - pillWidth() / 2
        }
        return CGFloat(index) * tabWidth + tabWidth / 2
    }

    /// 小さい長円（選択インジケーター）の中心位置。ドラッグ中は指に追従する
    private func indicatorCenterX() -> CGFloat {
        let tabWidth = tabWidth
        guard tabWidth > 0 else { return 0 }
        let pillWidth = pillWidth()
        let center: CGFloat
        if isDraggingTab {
            center = dragStartX + dragTranslation
        } else {
            center = tabCenterX(for: selectedTab)
        }
        let minCenter = endMargin + pillWidth / 2
        let maxCenter = tabBarSize.width - endMargin - pillWidth / 2
        return min(max(center, minCenter), maxCenter)
    }

    /// 横長の長円（選択インジケーター）の幅
    private func pillWidth() -> CGFloat {
        max(tabWidth - 4, 40)
    }

    private func tabIndicator(in size: CGSize) -> some View {
        let pillHeight = max(size.height - 10, 32)
        return Capsule()
            .fill(indicatorFill)
            .modifier(IndicatorGlassEffect())
            .frame(width: pillWidth(), height: pillHeight)
            .scaleEffect(isDraggingTab ? 1.1 : 1.0)
            .offset(x: indicatorCenterX() - size.width / 2)
    }

    private struct IndicatorGlassEffect: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect()
            } else {
                content
            }
        }
    }

    private var indicatorFill: some ShapeStyle {
        if #available(iOS 26.0, *) {
            AnyShapeStyle(AppTheme.accent.opacity(0.14))
        } else {
            AnyShapeStyle(AppTheme.accent.opacity(0.12))
        }
    }

    private func tabBarDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard tabWidth > 0 else { return }
                if !isDraggingTab {
                    // 指が置かれた瞬間にその位置のタブへピルを移動してから追従する
                    isDraggingTab = true
                    dragMoved = false
                    let startIndex = min(max(Int(value.location.x / tabWidth), 0), tabConfig.count - 1)
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.50)) {
                        dragStartX = tabCenterX(for: startIndex)
                        if startIndex != selectedTab {
                            switchTab(to: startIndex)
                        }
                    }
                    return
                }
                dragTranslation = value.translation.width
                if abs(dragTranslation) > 6 {
                    dragMoved = true
                }
                let center = dragStartX + dragTranslation
                let index = min(max(Int(center / tabWidth), 0), tabConfig.count - 1)
                if index != selectedTab {
                    switchTab(to: index)
                }
            }
            .onEnded { value in
                guard tabWidth > 0 else { return }
                let center = dragStartX + value.translation.width
                // ドラッグ中のライブ切り替えと同じく、指が乗っているタブに切り替える
                let index = min(max(Int(center / tabWidth), 0), tabConfig.count - 1)
                let wasTap = !dragMoved
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    isDraggingTab = false
                    dragTranslation = 0
                    switchTab(to: index)
                }
                // タップの場合は「選択中タブの再タップ = 今日タブを更新」
                if wasTap, index == 0, selectedTab == 0 {
                    todayViewKey = UUID()
                }
                dragMoved = false
            }
    }

    private func tabLabel(title: String, icon: String, index: Int) -> some View {
        VStack(spacing: 1) {
            Image(systemName: icon)
                .font(.system(size: 20))
            Text(title)
                .font(.system(size: 9))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .foregroundStyle(selectedTab == index ? AppTheme.accent : AppTheme.textMuted)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .scaleEffect(isDraggingTab && selectedTab == index ? 1.08 : 1.0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selectedTab == index ? [.isButton, .isSelected] : [.isButton])
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
