import Foundation

@MainActor
final class PortalDataCoordinator {
    static let shared = PortalDataCoordinator()

    private init() {}

    /// 更新の実行中フラグ（多重更新・並行実行を防ぐ）
    private var isRefreshing = false

    /// 起動時に refreshAll（全データ更新）が実行されたかどうか
    private(set) var hasCompletedStartupRefresh = false

    var hasCachedContent: Bool {
        !TimetableViewModel.shared.courses.isEmpty || !NoticeBoardViewModel.shared.announcements.isEmpty
    }

    func loadCachedData() {
        TimetableViewModel.shared.loadCachedData()
        NoticeBoardViewModel.shared.loadCachedData()
    }

    @discardableResult
    private func runRefresh(progressMessage: String, showUpdateBanner: Bool, operation: () async -> Bool) async -> Bool {
        // 更新が実行中の場合は多重実行せずスキップする
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }
        let didUpdate = await operation()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
            try? await Task.sleep(nanoseconds: 300_000_000)
            AppBannerCenter.shared.show("完了しました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
        return didUpdate
    }

    func refreshAll(showUpdateBanner: Bool) async {
        hasCompletedStartupRefresh = true
        await runRefresh(progressMessage: "全体を更新中...", showUpdateBanner: showUpdateBanner) {
            var results: [Bool] = []
            await withTaskGroup(of: Bool.self) { group in
                group.addTask { await TimetableViewModel.shared.refreshScheduleForOneYearFromServer() }
                group.addTask { await TimetableViewModel.shared.refreshWeeklyFromServer() }
                group.addTask { await NoticeBoardViewModel.shared.refreshFromServer() }

                for await result in group {
                    results.append(result)
                }
            }
            return results.contains(true)
        }
    }

    func refreshSchedule(showUpdateBanner: Bool) async {
        await runRefresh(progressMessage: "予定を更新中...", showUpdateBanner: showUpdateBanner) {
            await TimetableViewModel.shared.refreshScheduleForOneYearFromServer()
        }
    }

    /// `refreshSchedule` と同等（互換性のため残存）
    func refreshScheduleForOneYear(showUpdateBanner: Bool) async {
        await refreshSchedule(showUpdateBanner: showUpdateBanner)
    }

    func refreshSchedule(through targetDate: Date, showUpdateBanner: Bool) async {
        await runRefresh(progressMessage: "指定期間の予定を更新中...", showUpdateBanner: showUpdateBanner) {
            _ = await TimetableViewModel.shared.refreshScheduleFromServer(through: targetDate)
            return TimetableViewModel.shared.errorMessage == nil
        }
    }

    func refreshWeeklyTimetable(showUpdateBanner: Bool) async {
        await runRefresh(progressMessage: "時間割タブを更新中...", showUpdateBanner: showUpdateBanner) {
            await TimetableViewModel.shared.refreshWeeklyFromServer()
        }
    }

    func refreshNotices(showUpdateBanner: Bool) async {
        await runRefresh(progressMessage: "掲示板タブを更新中...", showUpdateBanner: showUpdateBanner) {
            await NoticeBoardViewModel.shared.refreshFromServer()
        }
    }
}
