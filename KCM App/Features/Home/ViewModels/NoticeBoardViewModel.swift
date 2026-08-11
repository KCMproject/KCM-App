import Foundation
import Combine

@MainActor
final class NoticeBoardViewModel: ObservableObject {
    static let shared = NoticeBoardViewModel(portalClient: PortalClientFactory.makePortalClient())
    
    @Published var announcements: [NoticeCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var readIDs: Set<String> = []

    private let portalClient: PortalClientProtocol
    private let cacheStore = PortalCacheStore.shared
    private let attachmentFetchBatchSize = 3

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func loadCachedData() {
        let cachedNotices = cacheStore.applyCachedAttachments(to: cacheStore.loadNotices())
        guard !cachedNotices.isEmpty else { return }
        announcements = cachedNotices
        readIDs = cacheStore.loadReadNoticeIDs()
    }

    /// 指定されたジャンルの掲示板件数を返す
    func count(forGenre genre: String) -> Int {
        announcements.filter { $0.category == genre }.count
    }

    /// 全掲示板件数
    var totalCount: Int {
        announcements.count
    }

    func markAsRead(_ id: String) {
        readIDs.insert(id)
        cacheStore.markAsRead(id)
    }

    func initialFetch() async {
        _ = await refreshFromServer()
    }

    func refreshFromServer() async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let serverNotices = try await portalClient.fetchAnnouncements()
            if serverNotices.isEmpty {
                isLoading = false
                return applyFallbackNotices()
            }

            // キャッシュ全体のデコード・マージ・保存はメインスレッドを塞がないようバックグラウンドで行う
            let notices = await Task.detached(priority: .utility) { [serverNotices] in
                PortalCacheStore.shared.mergeAndSaveNotices(serverNotices)
            }.value
            let didUpdate = notices != announcements
            if didUpdate {
                announcements = notices
            }
            readIDs = cacheStore.loadReadNoticeIDs()
            isLoading = false
            await fetchMissingAttachments(for: notices)
            return didUpdate
        } catch {
            readIDs = cacheStore.loadReadNoticeIDs()
            self.isLoading = false
            return applyFallbackNotices()
        }
    }

    private func applyFallbackNotices() -> Bool {
        let fallbackNotices = announcements.isEmpty ? cacheStore.applyCachedAttachments(to: cacheStore.loadNotices()) : announcements
        if !fallbackNotices.isEmpty {
            announcements = fallbackNotices
            errorMessage = "掲示板を読み込めませんでした。前回の一覧を表示しています。"
            return true
        }
        announcements = []
        errorMessage = "掲示板を読み込めませんでした。"
        return false
    }
    
    /// お知らせを開く前にセッションの有効性を確認し、切れていれば再ログインする
    func ensureValidSession() async -> Bool {
        let result = await portalClient.ensureValidSession()
        return result
    }

    /// 掲示板詳細の最新URLを解決する（セッション切れ後に古いURLを更新）
    func resolveNoticeURL(for notice: NoticeCard) async -> URL? {
        do {
            let url = try await portalClient.resolveNoticeDetailURL(for: notice)
            return url
        } catch {
            return nil
        }
    }
    
    // (Existing completion based method can stay for legacy or be removed)
    func fetchAnnouncements() {
        Task { await initialFetch() }
    }

    private func fetchMissingAttachments(for notices: [NoticeCard]) async {
        let uncheckedNotices = notices.filter { $0.attachments == nil }
        guard !uncheckedNotices.isEmpty else { return }

        for batchStart in stride(from: 0, to: uncheckedNotices.count, by: attachmentFetchBatchSize) {
            let batchEnd = min(batchStart + attachmentFetchBatchSize, uncheckedNotices.count)
            let batch = Array(uncheckedNotices[batchStart..<batchEnd])
            guard !batch.isEmpty else { continue }

            await withTaskGroup(of: (NoticeCard, [NoticeAttachment]?).self) { group in
                for notice in batch {
                    group.addTask { [portalClient] in
                        do {
                            let attachments = try await portalClient.fetchNoticeAttachments(for: notice)
                            return (notice, attachments)
                        } catch {
                            return (notice, nil)
                        }
                    }
                }

                for await (notice, attachments) in group {
                    guard let attachments else { continue }
                    cacheStore.saveNoticeAttachments(attachments, for: notice)
                }
            }

            // 添付ファイルのマージ・保存はバックグラウンドで行う
            let currentAnnouncements = announcements
            let updatedNotices = await Task.detached(priority: .utility) { [currentAnnouncements] in
                let store = PortalCacheStore.shared
                let updated = store.applyCachedAttachments(to: currentAnnouncements)
                store.saveNotices(updated)
                return updated
            }.value
            if updatedNotices != announcements {
                announcements = updatedNotices
            }
        }
    }
}
