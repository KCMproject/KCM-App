import Combine
import Foundation

/// GitHub の announcements.json を配信元としてお知らせを取得・管理する
/// ポータルとは完全に独立した通信のため、ポータル障害時でも動作する
@MainActor
final class AnnouncementService: ObservableObject {
    static let shared = AnnouncementService()

    /// ミュートされていないお知らせ（モーダル表示対象・新しい順）
    @Published private(set) var pendingAnnouncements: [AppAnnouncement] = []

    private static let feedURL = URL(string: "https://raw.githubusercontent.com/KCMproject/KCM-App/main/announcements.json")!
    private static let feedCacheKey = "appAnnouncements.feedCache"
    private static let seenIDsKey = "appAnnouncements.seenIDs"

    private var isFetching = false
    private var lastFetchDate: Date?

    private init() {
        loadCachedFeed()
    }

    /// 前回落としてから指定時間が経っていれば取得する（フォアグラウンド復帰用の乱打防止）
    func refreshIfStale(minimumInterval: TimeInterval = 120) async {
        if let lastFetchDate, Date().timeIntervalSince(lastFetchDate) < minimumInterval {
            return
        }
        await refresh()
    }

    /// お知らせフィードを取得する。失敗時はキャッシュ/表示を維持したままサイレントに終了
    func refresh() async {
        guard !isFetching else { return }
        isFetching = true
        defer { isFetching = false }

        var request = URLRequest(url: Self.feedURL)
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let feed = try? JSONDecoder().decode(AnnouncementFeed.self, from: data) else {
            return
        }

        lastFetchDate = Date()
        UserDefaults.standard.set(data, forKey: Self.feedCacheKey)
        apply(feed: feed)
    }

    /// 「2度と表示しない」が選択されたお知らせをミュートし、以後の表示対象から外す
    func mute(_ announcement: AppAnnouncement) {
        var ids = seenIDs
        ids.insert(announcement.id)
        saveSeenIDs(ids)
        pendingAnnouncements.removeAll { $0.id == announcement.id }
    }

    // MARK: - Private

    private func loadCachedFeed() {
        guard let data = UserDefaults.standard.data(forKey: Self.feedCacheKey),
              let feed = try? JSONDecoder().decode(AnnouncementFeed.self, from: data) else {
            return
        }
        apply(feed: feed)
    }

    private func apply(feed: AnnouncementFeed) {
        let ids = seenIDs
        pendingAnnouncements = feed.activeAnnouncements.filter { !ids.contains($0.id) }
    }

    private var seenIDs: Set<String> {
        guard let data = UserDefaults.standard.data(forKey: Self.seenIDsKey),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
    }

    private func saveSeenIDs(_ ids: Set<String>) {
        guard let data = try? JSONEncoder().encode(ids.sorted()) else { return }
        UserDefaults.standard.set(data, forKey: Self.seenIDsKey)
    }
}
