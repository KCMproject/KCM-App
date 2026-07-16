import Foundation

/// ポータル認証・セッション管理を担当するクライアント
final class PortalAuthClient {

    private let networkClient: PortalNetworkClient
    private let portalURL = "/portal.do"

    private(set) var currentSession: CampusSquareSession?
    private var rwfHash: String = ""

    init(networkClient: PortalNetworkClient) {
        self.networkClient = networkClient
    }

    // MARK: - 公開API

    func login(credentials: CampusSquareCredentials) async throws -> CampusSquareSession {
        let session = try await performLogin(credentials: credentials)
        self.currentSession = session
        return session
    }

    func logout() async {
        currentSession = nil
        rwfHash = ""
        networkClient.deleteCookies()
    }

    func validateSession() async throws -> Bool {
        guard let session = currentSession, session.isValid else {
            return false
        }
        do {
            let html = try await networkClient.fetchHTML(from: mainPageURL)
            let hasPasswordField = html.contains("id=\"passwordInput\"") || html.contains("name=\"password\"")
            return !hasPasswordField
        } catch {
            return false
        }
    }

    /// セッション切れ時に自動再ログインし、元の操作を再試行する
    func executeWithAutoRelogin<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch CampusSquareLoginError.sessionExpired {
            let reloginSuccess = try await attemptRelogin()
            guard reloginSuccess else {
                throw CampusSquareLoginError.sessionExpired
            }
            return try await operation()
        }
    }

    // MARK: - 内部実装

    private func performLogin(credentials: CampusSquareCredentials) async throws -> CampusSquareSession {
        switch credentials.validate() {
        case .success: break
        case .failure(let msg):
            throw CampusSquareLoginError.authenticationFailed(msg)
        }

        let loginPageHtml = try await networkClient.fetchHTML(from: loginPageURL)

        let pattern = "'rwfHash'\\s*:\\s*'([^']+)'"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(
            in: loginPageHtml,
            options: [],
            range: NSRange(location: 0, length: loginPageHtml.utf16.count)
           ),
           let range = Range(match.range(at: 1), in: loginPageHtml) {
            self.rwfHash = String(loginPageHtml[range])
        }

        guard let postURL = URL(string: "\(networkClient.baseURL)\(portalURL)") else { throw CampusSquareLoginError.authenticationFailed("無効なポータルURLです") }
        var request = networkClient.makeRequest(
            url: postURL,
            method: "POST",
            referer: loginPageURL
        )

        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("https://cs.kunitachi.ac.jp", forHTTPHeaderField: "Origin")

        let bodyString = [
            "wfId=nwf_PTW0060002_login",
            "locale=ja_JP",
            "userName=\(credentials.userName.urlEncoded)",
            "password=\(credentials.password.urlEncoded)",
            "action=rwf",
            "tabId=home",
            "page=",
            "rwfHash=\(self.rwfHash)"
        ].joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await networkClient.send(request)

        if let httpResponse = response as? HTTPURLResponse,
           let url = response.url {
            let fields = httpResponse.allHeaderFields as? [String: String] ?? [:]
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw CampusSquareLoginError.authenticationFailed("レスポンス解析失敗")
        }

        if responseString.contains("class=\"error\"") || responseString.contains("入力に誤りがあります") {
            throw CampusSquareLoginError.authenticationFailed("ユーザー名またはパスワードが間違っています")
        }

        let sessionId = self.networkClient.sessionIdentifier() ?? UUID().uuidString
        let expiresIn = self.networkClient.earliestExpirationInMinutes() ?? 20

        return CampusSquareSession(
            sessionId: sessionId,
            loggedInAt: Date(),
            expiresInMinutes: expiresIn
        )
    }

    private func attemptRelogin() async throws -> Bool {
        guard let credentials = SavedCredentialsStore.shared.load() else {
            return false
        }
        do {
            _ = try await performLogin(credentials: CampusSquareCredentials(
                userName: credentials.studentID,
                password: credentials.password
            ))
            return true
        } catch {
            return false
        }
    }

    // MARK: - URL 生成

    private var mainPageURL: String {
        "\(networkClient.baseURL)\(portalURL)?page=main"
    }

    private var loginPageURL: String {
        "\(networkClient.baseURL)\(portalURL)?locale=ja_JP"
    }
}
