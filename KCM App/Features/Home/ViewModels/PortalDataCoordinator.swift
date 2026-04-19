import Foundation

@MainActor
final class PortalDataCoordinator {
    static let shared = PortalDataCoordinator()

    private init() {}

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
}
