import Foundation

/// Portalサイトとの通信を担当する基盤クラス
final class PortalNetworkClient {
    private let session: URLSession
    let baseURL: String
    
    init(baseURL: String = "https://cs.kunitachi.ac.jp/campusweb") {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        // 共有Cookieストレージを使用（URLSessionの標準動作）
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config)
    }
    
    /// 共通ヘッダーを付与したURLRequestを作成
    func makeRequest(url: URL, method: String = "GET", referer: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        if let referer = referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        return request
    }
    
    /// async/awaitでデータを取得（Cookieを明示的に保存）
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await session.data(for: request)
        // 明示的にCookieを.sharedストレージに保存（URLSessionの自動保存との二重保存になっても安全）
        if let httpResponse = response as? HTTPURLResponse,
           let url = response.url {
            let fields = httpResponse.allHeaderFields as? [String: String] ?? [:]
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
        return (data, response)
    }
    
    /// HTMLとレスポンスURLを一緒に取得（リダイレクト後のURLを捕捉するため）
    func fetchHTMLWithResponse(from urlString: String, referer: String? = nil) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: urlString) else {
            throw CampusSquareLoginError.portalError("Invalid URL: \(urlString)")
        }
        let request = makeRequest(url: url, referer: referer)
        let (data, response) = try await send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CampusSquareLoginError.portalError("非HTTPレスポンスを受信しました")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CampusSquareLoginError.serverError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
        }
        return (data, httpResponse)
    }

    /// 文字列としてHTMLを取得
    func fetchHTML(from urlString: String, referer: String? = nil) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw CampusSquareLoginError.portalError("Invalid URL: \(urlString)")
        }
        let request = makeRequest(url: url, referer: referer)
        let (data, response) = try await send(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CampusSquareLoginError.portalError("非HTTPレスポンスを受信しました")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw CampusSquareLoginError.serverError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode)")
        }
        guard let html = String(data: data, encoding: .utf8) else {
            throw CampusSquareLoginError.portalError("Failed to decode HTML")
        }
        return html
    }
    
    // MARK: - Cookie 管理
    
    private var cookieStorage: HTTPCookieStorage { .shared }
    
    /// 指定ドメインのCookieをすべて削除する
    func deleteCookies(for domain: String = "cs.kunitachi.ac.jp") {
        guard let cookies = cookieStorage.cookies else { return }
        for cookie in cookies {
            let cookieDomain = cookie.domain
            // cookieDomain が domain を含む、または domain が cookieDomain を含む（両方向）
            if cookieDomain.contains(domain) || domain.contains(cookieDomain) {
                cookieStorage.deleteCookie(cookie)
            }
        }
    }
    
    /// 指定ドメインのすべてのCookieを取得する
    func cookies(for domain: String = "cs.kunitachi.ac.jp") -> [HTTPCookie] {
        guard let allCookies = cookieStorage.cookies else { return [] }
        return allCookies.filter { cookie in
            let cookieDomain = cookie.domain
            return cookieDomain.contains(domain) || domain.contains(cookieDomain)
        }
    }
    
    /// セッション識別子（JSESSIONID等）を取得する
    func sessionIdentifier() -> String? {
        let sessionCookies = cookies()
        return sessionCookies.first { $0.name == "JSESSIONID" }?.value
            ?? sessionCookies.first(where: { $0.name.lowercased().contains("session") })?.value
    }
    
    /// 指定ドメインのCookieから最も近い有効期限を取得する（分単位）
    func earliestExpirationInMinutes(for domain: String = "cs.kunitachi.ac.jp") -> Int? {
        let domainCookies = cookies(for: domain)
        guard let earliest = domainCookies.compactMap(\.expiresDate).min() else { return nil }
        let seconds = earliest.timeIntervalSince(Date())
        return max(0, Int(seconds / 60))
    }
}
