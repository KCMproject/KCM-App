import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var studentID = ""
    @Published var password = ""
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let portalClient: PortalClientProtocol

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func login() {
        guard !studentID.isEmpty, !password.isEmpty else {
            errorMessage = "学籍番号とパスワードを入力してください"
            return
        }

        isLoading = true
        errorMessage = nil

        let credentials = CampusSquareCredentials(userName: studentID, password: password)

        portalClient.login(credentials: credentials) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let session):
                    print("Login success: \(session)")
                    self.isLoggedIn = true
                case .failure(let error):
                    self.errorMessage = error.errorDescription
                }
            }
        }
    }

    func checkSession() {
        portalClient.validateSession { [weak self] isValid in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoggedIn = isValid
            }
        }
    }

    func logout() {
        portalClient.logout { [weak self] success in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if success {
                    self.password = ""
                    self.isLoggedIn = false
                }
            }
        }
    }
}
