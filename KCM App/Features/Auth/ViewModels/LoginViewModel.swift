import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var studentID = ""
    @Published var password = ""
    @Published private(set) var isLoggedIn = false

    func login() {
        guard !studentID.isEmpty, !password.isEmpty else { return }
        isLoggedIn = true
    }

    func logout() {
        password = ""
        isLoggedIn = false
    }
}
