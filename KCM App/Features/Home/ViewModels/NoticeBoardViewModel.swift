import Foundation
import Combine

@MainActor
final class NoticeBoardViewModel: ObservableObject {
    @Published var announcements: [NoticeCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let portalClient: PortalClientProtocol

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func fetchAnnouncements() {
        isLoading = true
        errorMessage = nil

        portalClient.fetchAnnouncements { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let announcements):
                    self.announcements = announcements
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
