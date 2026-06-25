import Foundation

@MainActor
final class PortalCacheStore {
    static let shared = PortalCacheStore()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

 private enum Key {
    static let courses = "portalCache.courses"
    static let scheduleMonthKeys = "portalCache.scheduleMonthKeys"
    static let weeklyCoursesPrefix = "portalCache.weeklyCourses."
    static let intensiveCoursesPrefix = "portalCache.intensiveCourses."
    static let notices = "portalCache.notices"
    static let noticeAttachments = "portalCache.noticeAttachments"
    static let favoriteNoticeIDs = "portalCache.favoriteNoticeIDs"
    static let classroomURLs = "portalCache.classroomURLs"
    static let userName = "portalCache.userName"
    static let userReading = "portalCache.userReading"
  }

    private init() {}

    func loadCourses() -> [Course] {
        guard let data = defaults.data(forKey: Key.courses),
              let courses = try? decoder.decode([Course].self, from: data) else {
            return []
        }
        return courses
    }

    func saveCourses(_ courses: [Course]) {
        guard let data = try? encoder.encode(courses) else {
            return
        }
        defaults.set(data, forKey: Key.courses)
    }

    func mergeAndSaveCourses(_ serverCourses: [Course]) -> [Course] {
        let merged = mergeCourses(cached: loadCourses(), server: serverCourses)
        saveCourses(merged)
        return merged
    }

    func mergeAndSaveCourses(_ serverCourses: [Course], replacingMonthKeys monthKeys: Set<String>) -> [Course] {
        let merged = mergeCourses(cached: loadCourses(), server: serverCourses, replacingMonthKeys: monthKeys)
        saveCourses(merged)
        return merged
    }

    func loadScheduleMonthKeys() -> Set<String> {
        guard let data = defaults.data(forKey: Key.scheduleMonthKeys),
              let keys = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return Set(keys)
    }

    func saveScheduleMonthKeys(_ keys: Set<String>) {
        guard let data = try? encoder.encode(Array(keys).sorted()) else { return }
        defaults.set(data, forKey: Key.scheduleMonthKeys)
    }

    func loadWeeklyCourses(for semester: TimetableSemester) -> [Course] {
        guard let data = defaults.data(forKey: weeklyCoursesKey(for: semester)),
              let courses = try? decoder.decode([Course].self, from: data) else {
            return []
        }
        return courses
    }

    func saveWeeklyCourses(_ courses: [Course], for semester: TimetableSemester) {
        guard let data = try? encoder.encode(courses) else { return }
        defaults.set(data, forKey: weeklyCoursesKey(for: semester))
    }

    func loadIntensiveCourses(for semester: TimetableSemester) -> [IntensiveCourseCard] {
        guard let data = defaults.data(forKey: intensiveCoursesKey(for: semester)),
              let courses = try? decoder.decode([IntensiveCourseCard].self, from: data) else {
            return []
        }
        return courses
    }

    func saveIntensiveCourses(_ courses: [IntensiveCourseCard], for semester: TimetableSemester) {
        guard let data = try? encoder.encode(courses) else { return }
        defaults.set(data, forKey: intensiveCoursesKey(for: semester))
    }

    private func intensiveCoursesKey(for semester: TimetableSemester) -> String {
        "\(Key.intensiveCoursesPrefix)\(semester.rawValue)"
    }

    func loadUserName() -> String? {
        defaults.string(forKey: Key.userName)
    }

    func saveUserName(_ name: String) {
        defaults.set(name, forKey: Key.userName)
    }

    func loadUserReading() -> String? {
        defaults.string(forKey: Key.userReading)
    }

    func saveUserReading(_ reading: String) {
        defaults.set(reading, forKey: Key.userReading)
    }

    func loadNotices() -> [NoticeCard] {
        guard let data = defaults.data(forKey: Key.notices),
              let notices = try? decoder.decode([NoticeCard].self, from: data) else {
            return []
        }
        return notices
    }

    func saveNotices(_ notices: [NoticeCard]) {
        guard let data = try? encoder.encode(notices) else { return }
        defaults.set(data, forKey: Key.notices)
    }

    func mergeAndSaveNotices(_ serverNotices: [NoticeCard]) -> [NoticeCard] {
        var merged: [String: NoticeCard] = [:]
        for notice in applyCachedAttachments(to: loadNotices()) {
            merged[noticeCacheKey(for: notice)] = notice
        }

        for notice in applyCachedAttachments(to: serverNotices) {
            let key = noticeCacheKey(for: notice)
            merged[key] = notice
        }

        let notices = merged.values.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.title < rhs.title
        }
        saveNotices(notices)
        return notices
    }

    private func noticeCacheKey(for notice: NoticeCard) -> String {
        stableNoticeKey(from: notice.url) ?? notice.id
    }

    private func noticeAttachmentCacheKey(for notice: NoticeCard) -> String {
        "noticeAttachment.v5.\(stableNoticeKey(from: notice.url) ?? notice.id)"
    }

    private func stableNoticeKey(from rawURL: String?) -> String? {
        guard let rawURL, !rawURL.isEmpty else {
            return nil
        }

        let decodedURL = rawURL.replacingOccurrences(of: "&amp;", with: "&")
        let absoluteURL: String
        if decodedURL.hasPrefix("http://") || decodedURL.hasPrefix("https://") {
            absoluteURL = decodedURL
        } else if decodedURL.hasPrefix("/") {
            absoluteURL = "https://cs.kunitachi.ac.jp\(decodedURL)"
        } else {
            absoluteURL = "https://cs.kunitachi.ac.jp/campusweb/\(decodedURL)"
        }

        if let components = URLComponents(string: absoluteURL),
           let queryItems = components.queryItems {
            var values: [String: String] = [:]
            for item in queryItems {
                values[item.name] = item.value ?? ""
            }
            if let keijitype = values["keijitype"],
               let genrecd = values["genrecd"],
               let seqNo = values["seqNo"] {
                return "\(keijitype).\(genrecd).\(seqNo)"
            }
        }

        return nil
    }

    private func loadNoticeAttachmentsCache() -> [String: [NoticeAttachment]] {
        guard let data = defaults.data(forKey: Key.noticeAttachments),
              let cache = try? decoder.decode([String: [NoticeAttachment]].self, from: data) else {
            return [:]
        }
        return cache
    }

    private func saveNoticeAttachmentsCache(_ cache: [String: [NoticeAttachment]]) {
        guard let data = try? encoder.encode(cache) else { return }
        defaults.set(data, forKey: Key.noticeAttachments)
    }

    func saveNoticeAttachments(_ attachments: [NoticeAttachment], for notice: NoticeCard) {
        var cache = loadNoticeAttachmentsCache()
        cache[noticeAttachmentCacheKey(for: notice)] = attachments
        saveNoticeAttachmentsCache(cache)
    }

    func applyCachedAttachments(to notices: [NoticeCard]) -> [NoticeCard] {
        let cache = loadNoticeAttachmentsCache()
        return notices.map { notice in
            let strippedNotice = notice.withAttachments(nil)
            guard let cached = cache[noticeAttachmentCacheKey(for: notice)] else {
                return strippedNotice
            }
            return strippedNotice.withAttachments(cached)
        }
    }

    func loadFavoriteNoticeIDs() -> Set<String> {
        guard let data = defaults.data(forKey: Key.favoriteNoticeIDs),
              let ids = try? decoder.decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

func saveFavoriteNoticeIDs(_ ids: Set<String>) {
    let sortedIDs = Array(ids).sorted()
    guard let data = try? encoder.encode(sortedIDs) else { return }
    defaults.set(data, forKey: Key.favoriteNoticeIDs)
  }

  func loadClassroomURLs() -> [String: String] {
    guard let data = defaults.data(forKey: Key.classroomURLs),
      let urls = try? decoder.decode([String: String].self, from: data) else {
      return [:]
    }
    return urls
  }

  func saveClassroomURLs(_ urls: [String: String]) {
    guard let data = try? encoder.encode(urls) else { return }
    defaults.set(data, forKey: Key.classroomURLs)
  }

  private func weeklyCoursesKey(for semester: TimetableSemester) -> String {
    Key.weeklyCoursesPrefix + semester.rawValue
  }

  private func mergeCourses(cached: [Course], server: [Course]) -> [Course] {
    mergeCourses(cached: cached, server: server, replacingMonthKeys: [])
  }

  private func mergeCourses(cached: [Course], server: [Course], replacingMonthKeys monthKeys: Set<String>) -> [Course] {
    // サーバーが空の場合はキャッシュを消さない（セッション切れ等で空配列が返る可能性があるため）
    if server.isEmpty {
      return cached
    }
    var merged: [String: Course] = [:]
    let serverDates = Set(server.compactMap(\.dateString))
    for course in cached {
      if let dateString = course.dateString,
        monthKeys.contains(String(dateString.prefix(7))) {
        continue
      }
      if let dateString = course.dateString, serverDates.contains(dateString) {
        continue
      }
      merged[courseCacheKey(course)] = course
    }
    for course in server {
      merged[courseCacheKey(course)] = course
    }
    return merged.values.sorted { lhs, rhs in
      let leftDate = lhs.dateString ?? ""
      let rightDate = rhs.dateString ?? ""
      if leftDate != rightDate { return leftDate < rightDate }
      if lhs.weekday != rhs.weekday { return lhs.weekday < rhs.weekday }
      if lhs.period != rhs.period { return lhs.period < rhs.period }
      return lhs.title < rhs.title
    }
  }

  private func courseCacheKey(_ course: Course) -> String {
    [
      course.dateString ?? "",
      course.weekday,
      course.period,
      course.title,
      course.instructor,
      course.scheduleNoteCategory ?? ""
    ].joined(separator: "|")
  }

  func clearAllUserData() {
    let keys = [
      Key.courses,
      Key.scheduleMonthKeys,
      Key.notices,
      Key.noticeAttachments,
      Key.favoriteNoticeIDs,
      Key.classroomURLs,
      Key.userName,
      Key.userReading,
    ]
    for key in keys {
      defaults.removeObject(forKey: key)
    }
    // 学期別のデータをクリア
    for semester in TimetableSemester.allCases {
      defaults.removeObject(forKey: weeklyCoursesKey(for: semester))
      defaults.removeObject(forKey: intensiveCoursesKey(for: semester))
    }
  }
}
