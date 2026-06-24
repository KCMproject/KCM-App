import Foundation

/// 各種キャッシュ保存のファサード
@MainActor
final class PortalCacheStore {
    static let shared = PortalCacheStore()

    private let courseCache = CourseCacheStore()
    private let noticeCache = NoticeCacheStore()
    private let classroomURLCache = ClassroomURLCacheStore()
    private let userProfileCache = UserProfileCacheStore()

    private init() {}

    // MARK: - 月次予定

    func loadCourses() -> [Course] {
        courseCache.loadCourses()
    }

    func saveCourses(_ courses: [Course]) {
        courseCache.saveCourses(courses)
    }

    func mergeAndSaveCourses(_ serverCourses: [Course]) -> [Course] {
        courseCache.mergeAndSaveCourses(serverCourses)
    }

    func mergeAndSaveCourses(_ serverCourses: [Course], replacingMonthKeys monthKeys: Set<String>) -> [Course] {
        courseCache.mergeAndSaveCourses(serverCourses, replacingMonthKeys: monthKeys)
    }

    // MARK: - 予定の月キー

    func loadScheduleMonthKeys() -> Set<String> {
        courseCache.loadScheduleMonthKeys()
    }

    func saveScheduleMonthKeys(_ keys: Set<String>) {
        courseCache.saveScheduleMonthKeys(keys)
    }

    // MARK: - 週間時間割・集中講義

    func loadWeeklyCourses(for semester: TimetableSemester) -> [Course] {
        courseCache.loadWeeklyCourses(for: semester)
    }

    func saveWeeklyCourses(_ courses: [Course], for semester: TimetableSemester) {
        courseCache.saveWeeklyCourses(courses, for: semester)
    }

    func loadIntensiveCourses(for semester: TimetableSemester) -> [IntensiveCourseCard] {
        courseCache.loadIntensiveCourses(for: semester)
    }

    func saveIntensiveCourses(_ courses: [IntensiveCourseCard], for semester: TimetableSemester) {
        courseCache.saveIntensiveCourses(courses, for: semester)
    }

    // MARK: - ユーザー名・読み

    func loadUserName() -> String? {
        userProfileCache.loadUserName()
    }

    func saveUserName(_ name: String) {
        userProfileCache.saveUserName(name)
    }

    func loadUserReading() -> String? {
        userProfileCache.loadUserReading()
    }

    func saveUserReading(_ reading: String) {
        userProfileCache.saveUserReading(reading)
    }

    // MARK: - 掲示板

    func loadNotices() -> [NoticeCard] {
        noticeCache.loadNotices()
    }

    func saveNotices(_ notices: [NoticeCard]) {
        noticeCache.saveNotices(notices)
    }

    func mergeAndSaveNotices(_ serverNotices: [NoticeCard]) -> [NoticeCard] {
        noticeCache.mergeAndSaveNotices(serverNotices)
    }

    func saveNoticeAttachments(_ attachments: [NoticeAttachment], for notice: NoticeCard) {
        noticeCache.saveNoticeAttachments(attachments, for: notice)
    }

    func applyCachedAttachments(to notices: [NoticeCard]) -> [NoticeCard] {
        noticeCache.applyCachedAttachments(to: notices)
    }

    func loadFavoriteNoticeIDs() -> Set<String> {
        noticeCache.loadFavoriteNoticeIDs()
    }

    func saveFavoriteNoticeIDs(_ ids: Set<String>) {
        noticeCache.saveFavoriteNoticeIDs(ids)
    }

    // MARK: - 教室URL

    func loadClassroomURLs() -> [String: String] {
        classroomURLCache.loadClassroomURLs()
    }

    func saveClassroomURLs(_ urls: [String: String]) {
        classroomURLCache.saveClassroomURLs(urls)
    }
}
