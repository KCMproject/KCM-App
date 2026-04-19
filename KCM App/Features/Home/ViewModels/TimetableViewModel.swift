import Foundation
import Combine

@MainActor
final class TimetableViewModel: ObservableObject {
    @Published var courses: [Course] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let portalClient: PortalClientProtocol

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func fetchTimetable() {
        isLoading = true
        errorMessage = nil

        portalClient.fetchTimetable { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let courses):
                    self.courses = courses
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
