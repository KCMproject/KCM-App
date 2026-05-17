import Foundation
import Combine

@MainActor
final class NoticeBoardViewModel: ObservableObject {
    static let shared = NoticeBoardViewModel(portalClient: PortalClientFactory.makeLoginService())
    
    @Published var announcements: [NoticeCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let portalClient: PortalClientProtocol
    private let cacheStore = PortalCacheStore.shared
    private let attachmentFetchBatchSize = 1

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func loadCachedData() {
        let cachedNotices = cacheStore.applyCachedAttachments(to: cacheStore.loadNotices())
        guard !cachedNotices.isEmpty else { return }
        announcements = cachedNotices
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
                let fallbackNotices = announcements.isEmpty ? cacheStore.applyCachedAttachments(to: cacheStore.loadNotices()) : announcements
                if !fallbackNotices.isEmpty {
                    announcements = fallbackNotices
                    errorMessage = "掲示板を読み込めませんでした。前回の一覧を表示しています。"
                    isLoading = false
                    return false
                }
                announcements = []
                errorMessage = "掲示板を読み込めませんでした。"
                isLoading = false
                return false
            }

            let notices = cacheStore.mergeAndSaveNotices(serverNotices)
            let didUpdate = notices != announcements
            announcements = notices
            isLoading = false
            Task {
                await fetchMissingAttachments(for: notices)
            }
            return didUpdate
        } catch {
            let fallbackNotices = announcements.isEmpty ? cacheStore.applyCachedAttachments(to: cacheStore.loadNotices()) : announcements
            if !fallbackNotices.isEmpty {
                announcements = fallbackNotices
                errorMessage = "掲示板を読み込めませんでした。前回の一覧を表示しています。"
            } else {
                announcements = []
                errorMessage = "掲示板を読み込めませんでした。"
            }
            self.isLoading = false
            return false
        }
    }
    
    /// 掲示板詳細の最新URLを解決する（セッション切れ後に古いURLを更新）
    func resolveNoticeURL(for notice: NoticeCard) async -> URL? {
        do {
            return try await portalClient.resolveNoticeDetailURL(for: notice)
        } catch {
            print("❌ [NoticeBoardViewModel] URL解決失敗: \(error.localizedDescription)")
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

            let updatedNotices = cacheStore.applyCachedAttachments(to: announcements)
            if updatedNotices != announcements {
                announcements = updatedNotices
                cacheStore.saveNotices(updatedNotices)
            }
        }
    }
}
