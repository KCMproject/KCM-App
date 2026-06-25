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
    @Published private(set) var isReady = false
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

    /// アプリ起動時に呼ばれる。既存セッションを破棄し、自動ログイン設定に応じて分岐する。
    func checkSession() {
        Task {
            // 1. 既存セッションを明示的に破棄（Cookieクリア）
            await portalClient.logout()
            isLoggedIn = false

            // 2. キャッシュデータを読み込み
            PortalDataCoordinator.shared.loadCachedData()

            // 3. 自動ログイン設定がONで資格情報が保存されている場合、裏でログイン
            if isPasswordAutofillEnabled, let credentials = credentialsStore.load() {
                // 自動ログインON：キャッシュを表示しつつ裏でログイン
                shouldShowCachedPortal = PortalDataCoordinator.shared.hasCachedContent
                isLoading = true
                studentID = credentials.studentID
                password = credentials.password
                login(studentID: credentials.studentID, password: credentials.password, automatic: true)
            } else {
                // 自動ログインOFF：ログイン画面を表示
                shouldShowCachedPortal = false
            }
        }
    }

    func logout() async {
        await portalClient.logout()
        password = ""
        isLoggedIn = false
        shouldShowCachedPortal = false
        isReady = false
        PortalCacheStore.shared.clearAllUserData()
        TimetableViewModel.shared.courses = []
        TimetableViewModel.shared.intensiveCourses = []
        TimetableViewModel.shared.weeklySchedule = Array(repeating: Array(repeating: .empty, count: 6), count: 6)
        NoticeBoardViewModel.shared.announcements = []
    }

    /// セッションをクリアする（デバッグ用）
    func clearSession() async {
        await portalClient.logout()
        isLoggedIn = false
        AppBannerCenter.shared.show("セッションをクリアしました")
    }

    var isPasswordAutofillEnabled: Bool {
        UserDefaults.standard.bool(forKey: AppSettings.passwordAutofillEnabled)
    }

    func loadSavedCredentials() -> SavedCredentials? {
        credentialsStore.load()
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
                case .success:
                    self.studentID = studentID
                    self.password = password
                    self.isLoggedIn = true
                    self.shouldShowCachedPortal = self.shouldShowCachedPortal || PortalDataCoordinator.shared.hasCachedContent
                    self.persistCredentialsIfNeeded()
                    self.isReady = false

                    Task {
                        await PortalDataCoordinator.shared.refreshAll(showUpdateBanner: true)
                        self.isReady = true
                    }
                case .failure(let error):
                    if automatic {
                        // 自動ログイン失敗時はキャッシュ表示を維持し、静かに失敗
                        self.shouldShowCachedPortal = true
                    } else {
                        self.errorMessage = error.errorDescription
                    }
                }
            }
        }
    }

    func fetchGradeReportPDF() async throws -> Data {
        try await portalClient.fetchGradeReportPDF()
    }

    private func persistCredentialsIfNeeded() {
        guard isPasswordAutofillEnabled else { return }
        guard !studentID.isEmpty, !password.isEmpty else { return }
        credentialsStore.save(studentID: studentID, password: password)
    }
}
