import Combine
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    static let shared = LoginViewModel(portalClient: PortalClientFactory.makeLoginService())
    
    @Published var studentID = ""
    @Published var password = ""
    @Published private(set) var isLoggedIn = false
    @Published private(set) var isLoading = false
    @Published private(set) var shouldShowCachedPortal = false
    @Published var errorMessage: String?

    private let portalClient: PortalClientProtocol
    private let credentialsStore = SavedCredentialsStore.shared
    private let defaults = UserDefaults.standard

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func login() {
        login(studentID: studentID, password: password, automatic: false)
    }

    func checkSession() {
        portalClient.validateSession { [weak self] isValid in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isLoggedIn = isValid
                if isValid {
                    self.shouldShowCachedPortal = true
                    Task {
                        PortalDataCoordinator.shared.loadCachedData()
                        await PortalDataCoordinator.shared.refreshAll(showUpdateBanner: true)
                    }
                } else {
                    self.tryAutomaticLoginIfNeeded()
                }
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
                    self.shouldShowCachedPortal = false
                }
            }
        }
    }

    var isPasswordAutofillEnabled: Bool {
        defaults.bool(forKey: AppSettings.passwordAutofillEnabled)
    }

    func loadSavedCredentials() -> SavedCredentials? {
        credentialsStore.load()
    }

    func setPasswordAutofillEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: AppSettings.passwordAutofillEnabled)
    }

    func saveCredentials(studentID: String, password: String) {
        credentialsStore.save(studentID: studentID, password: password)
        self.studentID = studentID
        self.password = password
        AppBannerCenter.shared.show("パスワードを保存しました")
    }

    private func login(studentID: String, password: String, automatic: Bool) {
        guard !studentID.isEmpty, !password.isEmpty else {
            if !automatic {
                errorMessage = "学籍番号とパスワードを入力してください"
            }
            return
        }

        isLoading = true
        if !automatic {
            errorMessage = nil
        }

        let credentials = CampusSquareCredentials(userName: studentID, password: password)

        portalClient.login(credentials: credentials) { [weak self] result in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isLoading = false
                switch result {
                case .success(let session):
                    print("Login success: \(session)")
                    self.studentID = studentID
                    self.password = password
                    self.isLoggedIn = true
                    self.shouldShowCachedPortal = true
                    self.persistCredentialsIfNeeded()

                    Task {
                        PortalDataCoordinator.shared.loadCachedData()
                        await PortalDataCoordinator.shared.refreshAll(showUpdateBanner: true)
                    }
                case .failure(let error):
                    if automatic {
                        self.shouldShowCachedPortal = false
                    }
                    if !automatic {
                        self.errorMessage = error.errorDescription
                    }
                }
            }
        }
    }

    private func tryAutomaticLoginIfNeeded() {
        guard isPasswordAutofillEnabled,
              let credentials = credentialsStore.load() else {
            return
        }

        shouldShowCachedPortal = PortalDataCoordinator.shared.hasCachedContent
        studentID = credentials.studentID
        password = credentials.password
        login(studentID: credentials.studentID, password: credentials.password, automatic: true)
    }

    private func persistCredentialsIfNeeded() {
        guard isPasswordAutofillEnabled else { return }
        guard !studentID.isEmpty, !password.isEmpty else { return }
        credentialsStore.save(studentID: studentID, password: password)
    }
}
