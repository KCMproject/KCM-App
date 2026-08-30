import Foundation

/// ユーザーが追加したカスタムリンク
nonisolated struct CustomLink: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var urlString: String

    init(id: UUID = UUID(), title: String, urlString: String) {
        self.id = id
        self.title = title
        self.urlString = urlString
    }
}

/// カスタムリンクのキャッシュを管理
final class CustomLinkCacheStore: CacheStore {
    override init(defaults: UserDefaults = .standard) {
        super.init(defaults: defaults)
    }

    private enum Key {
        static let customLinks = "portalCache.customLinks"
    }

    func loadCustomLinks() -> [CustomLink] {
        guard let data = data(forKey: Key.customLinks),
              let links = decode([CustomLink].self, from: data) else {
            return []
        }
        return links
    }

    func saveCustomLinks(_ links: [CustomLink]) {
        guard let data = encode(links) else { return }
        set(data, forKey: Key.customLinks)
    }
}
