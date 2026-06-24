import Foundation

/// 教室URLのキャッシュを管理
@MainActor
final class ClassroomURLCacheStore: CacheStore {
    private enum Key {
        static let classroomURLs = "portalCache.classroomURLs"
    }

    func loadClassroomURLs() -> [String: String] {
        guard let data = data(forKey: Key.classroomURLs),
              let urls = decode([String: String].self, from: data) else {
            return [:]
        }
        return urls
    }

    func saveClassroomURLs(_ urls: [String: String]) {
        guard let data = encode(urls) else { return }
        set(data, forKey: Key.classroomURLs)
    }
}
