import Foundation

@MainActor
final class PortalDataCoordinator {
    static let shared = PortalDataCoordinator()

    private init() {}

    var hasCachedContent: Bool {
        !TimetableViewModel.shared.courses.isEmpty || !NoticeBoardViewModel.shared.announcements.isEmpty
    }

    func loadCachedData() {
        TimetableViewModel.shared.loadCachedData()
        NoticeBoardViewModel.shared.loadCachedData()
    }

    func refreshAll(showUpdateBanner: Bool) async {
        let progressMessage = "全体を更新中..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        async let timetableUpdated = TimetableViewModel.shared.refreshFromServer()
        async let noticesUpdated = NoticeBoardViewModel.shared.refreshFromServer()

        let didUpdateTimetable = await timetableUpdated
        let didUpdateNotices = await noticesUpdated
        let didUpdate = didUpdateTimetable || didUpdateNotices
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("最新データに更新しました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshSchedule(showUpdateBanner: Bool) async {
        let progressMessage = "今日タブを更新中..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        let didUpdate = await TimetableViewModel.shared.refreshScheduleFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("予定を更新しました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshSchedule(through targetDate: Date, showUpdateBanner: Bool) async {
        let progressMessage = "指定期間の予定を更新中..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        _ = await TimetableViewModel.shared.refreshScheduleFromServer(through: targetDate)
        if showUpdateBanner, TimetableViewModel.shared.errorMessage == nil {
            AppBannerCenter.shared.show("指定期間の予定を更新しました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshWeeklyTimetable(showUpdateBanner: Bool) async {
        let progressMessage = "時間割タブを更新中..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        let didUpdate = await TimetableViewModel.shared.refreshWeeklyFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("時間割を更新しました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshNotices(showUpdateBanner: Bool) async {
        let progressMessage = "掲示板タブを更新中..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        let didUpdate = await NoticeBoardViewModel.shared.refreshFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("掲示板を更新しました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }
}
