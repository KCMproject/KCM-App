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
        async let timetableUpdated = TimetableViewModel.shared.refreshFromServer()
        async let noticesUpdated = NoticeBoardViewModel.shared.refreshFromServer()

        let didUpdateTimetable = await timetableUpdated
        let didUpdateNotices = await noticesUpdated
        let didUpdate = didUpdateTimetable || didUpdateNotices
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("最新データに更新しました")
        }
    }

    func refreshSchedule(showUpdateBanner: Bool) async {
        let didUpdate = await TimetableViewModel.shared.refreshScheduleFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("予定を更新しました")
        }
    }

    func refreshWeeklyTimetable(showUpdateBanner: Bool) async {
        let didUpdate = await TimetableViewModel.shared.refreshWeeklyFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("時間割を更新しました")
        }
    }

    func refreshNotices(showUpdateBanner: Bool) async {
        let didUpdate = await NoticeBoardViewModel.shared.refreshFromServer()
        if showUpdateBanner, didUpdate {
            AppBannerCenter.shared.show("掲示板を更新しました")
        }
    }
}
