import Foundation

/// 掲示板・添付ファイル・お気に入りIDのキャッシュを管理
nonisolated final class NoticeCacheStore: CacheStore {
    override init(defaults: UserDefaults = .standard) {
        super.init(defaults: defaults)
    }

    private enum Key {
        static let notices = "portalCache.notices"
        static let noticeAttachments = "portalCache.noticeAttachments"
        static let favoriteNoticeIDs = "portalCache.favoriteNoticeIDs"
        static let readNoticeIDs = "portalCache.readNoticeIDs"
    }

    // MARK: - 掲示板

    func loadNotices() -> [NoticeCard] {
        guard let data = data(forKey: Key.notices),
              let notices = decode([NoticeCard].self, from: data) else {
            return []
        }
        return notices
    }

    func saveNotices(_ notices: [NoticeCard]) {
        guard let data = encode(notices) else { return }
        set(data, forKey: Key.notices)
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

    // MARK: - 添付ファイル

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

    // MARK: - お気に入り

    func loadFavoriteNoticeIDs() -> Set<String> {
        guard let data = data(forKey: Key.favoriteNoticeIDs),
              let ids = decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    func saveFavoriteNoticeIDs(_ ids: Set<String>) {
        let sortedIDs = Array(ids).sorted()
        guard let data = encode(sortedIDs) else { return }
        set(data, forKey: Key.favoriteNoticeIDs)
    }

    // MARK: - 既読

    func loadReadNoticeIDs() -> Set<String> {
        guard let data = data(forKey: Key.readNoticeIDs),
              let ids = decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    func saveReadNoticeIDs(_ ids: Set<String>) {
        let sortedIDs = Array(ids).sorted()
        guard let data = encode(sortedIDs) else { return }
        set(data, forKey: Key.readNoticeIDs)
    }

    func markAsRead(_ id: String) {
        var ids = loadReadNoticeIDs()
        ids.insert(id)
        saveReadNoticeIDs(ids)
    }

    func clearAll() {
        defaults.removeObject(forKey: Key.notices)
        defaults.removeObject(forKey: Key.noticeAttachments)
        defaults.removeObject(forKey: Key.favoriteNoticeIDs)
        defaults.removeObject(forKey: Key.readNoticeIDs)
    }

    // MARK: - Private

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
        guard let data = data(forKey: Key.noticeAttachments),
              let cache = decode([String: [NoticeAttachment]].self, from: data) else {
            return [:]
        }
        return cache
    }

    private func saveNoticeAttachmentsCache(_ cache: [String: [NoticeAttachment]]) {
        guard let data = encode(cache) else { return }
        set(data, forKey: Key.noticeAttachments)
    }
}
