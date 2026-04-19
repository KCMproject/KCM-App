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

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func loadCachedData() {
        let cachedNotices = cacheStore.loadNotices()
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
            let notices = try await portalClient.fetchAnnouncements()
            let didUpdate = notices != announcements
            announcements = notices
            cacheStore.saveNotices(notices)
            isLoading = false
            return didUpdate
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
            return false
        }
    }
    
    // (Existing completion based method can stay for legacy or be removed)
    func fetchAnnouncements() {
        Task { await initialFetch() }
    }
}
