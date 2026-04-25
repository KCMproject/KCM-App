import Foundation

@MainActor
final class PortalCacheStore {
    static let shared = PortalCacheStore()

    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

private enum Key {
    static let courses = "portalCache.courses"
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
}
