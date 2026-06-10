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
        let progressMessage = "データを開いています..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        let didUpdateSchedule = await TimetableViewModel.shared.refreshScheduleForOneYearFromServer()
        let didUpdateWeekly = await TimetableViewModel.shared.refreshWeeklyFromServer()
        let didUpdateNotices = await NoticeBoardViewModel.shared.refreshFromServer()

        let didUpdate = didUpdateSchedule || didUpdateWeekly || didUpdateNotices
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("データを開きました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshSchedule(showUpdateBanner: Bool) async {
        let progressMessage = "予定を開いています..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        let didUpdate = await TimetableViewModel.shared.refreshScheduleForOneYearFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("予定を開きました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshScheduleForOneYear(showUpdateBanner: Bool) async {
        let progressMessage = "予定を開いています..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        let didUpdate = await TimetableViewModel.shared.refreshScheduleForOneYearFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("予定を開きました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshSchedule(through targetDate: Date, showUpdateBanner: Bool) async {
        let progressMessage = "指定期間の予定を開いています..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        _ = await TimetableViewModel.shared.refreshScheduleFromServer(through: targetDate)
        if showUpdateBanner, TimetableViewModel.shared.errorMessage == nil {
            AppBannerCenter.shared.show("指定期間の予定を開きました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshWeeklyTimetable(showUpdateBanner: Bool) async {
        let progressMessage = "時間割を開いています..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        let didUpdate = await TimetableViewModel.shared.refreshWeeklyFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("時間割を開きました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }

    func refreshNotices(showUpdateBanner: Bool) async {
        let progressMessage = "開いています..."
        if showUpdateBanner {
            AppBannerCenter.shared.showPersistent(progressMessage)
        }

        let didUpdate = await NoticeBoardViewModel.shared.refreshFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("開きました")
        } else if showUpdateBanner {
            AppBannerCenter.shared.hide(ifShowing: progressMessage)
        }
    }
}
