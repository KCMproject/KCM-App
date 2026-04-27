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
    static let notices = "portalCache.notices"
    static let favoriteNoticeIDs = "portalCache.favoriteNoticeIDs"
    static let classroomURLs = "portalCache.classroomURLs"
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
        guard let data = try? encoder.encode(courses) else { return }
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
      course.instructor
    ].joined(separator: "|")
  }
}
