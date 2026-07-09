import Foundation

/// ユーザー名・読みのキャッシュを管理
final class UserProfileCacheStore: CacheStore {
    override init(defaults: UserDefaults = .standard) {
        super.init(defaults: defaults)
    }

    private enum Key {
        static let userName = "portalCache.userName"
        static let userReading = "portalCache.userReading"
    }

    func loadUserName() -> String? {
        string(forKey: Key.userName)
    }

    func saveUserName(_ name: String) {
        set(name, forKey: Key.userName)
    }

    func loadUserReading() -> String? {
        string(forKey: Key.userReading)
    }

    func saveUserReading(_ reading: String) {
        set(reading, forKey: Key.userReading)
    }

    func clearAll() {
        defaults.removeObject(forKey: Key.userName)
        defaults.removeObject(forKey: Key.userReading)
    }
}
