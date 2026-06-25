import Foundation

/// ユーザー名・読みのキャッシュを管理
@MainActor
final class UserProfileCacheStore: CacheStore {
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
