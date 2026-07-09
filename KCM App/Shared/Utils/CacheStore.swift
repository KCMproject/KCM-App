import Foundation

/// UserDefaults ベースのキャッシュ保存の共通基盤
class CacheStore {
    let defaults: UserDefaults
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func encode<T: Encodable>(_ value: T) -> Data? {
        try? encoder.encode(value)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    func set(_ data: Data, forKey key: String) {
        defaults.set(data, forKey: key)
    }

    func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }
}
