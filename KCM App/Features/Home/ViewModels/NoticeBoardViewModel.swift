import Foundation
import Combine

@MainActor
final class NoticeBoardViewModel: ObservableObject {
    static let shared = NoticeBoardViewModel(portalClient: PortalClientFactory.makeLoginService())
    
    @Published var announcements: [NoticeCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let portalClient: PortalClientProtocol

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func initialFetch() async {
        isLoading = true
        errorMessage = nil

        do {
            let notices = try await portalClient.fetchAnnouncements()
            await MainActor.run {
                self.announcements = notices
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    // (Existing completion based method can stay for legacy or be removed)
    func fetchAnnouncements() {
        Task { await initialFetch() }
    }
}
