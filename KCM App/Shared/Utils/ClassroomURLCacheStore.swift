import Foundation

/// 教室URLのキャッシュを管理
final class ClassroomURLCacheStore: CacheStore {
    override init(defaults: UserDefaults = .standard) {
        super.init(defaults: defaults)
    }

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

    func clearAll() {
        defaults.removeObject(forKey: Key.classroomURLs)
    }
}
