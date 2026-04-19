import Foundation

/// Portalサイトとの通信を担当する基盤クラス
final class PortalNetworkClient {
    private let session: URLSession
    let baseURL: String
    
    init(baseURL: String) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        // クッキーを明示的に共有ストレージで管理するように設定
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
    
    /// async/awaitでデータを取得
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        return try await session.data(for: request)
    }
    
    /// 文字列としてHTMLを取得
    func fetchHTML(from urlString: String, referer: String? = nil) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "PortalNetworkClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(urlString)"])
        }
        let request = makeRequest(url: url, referer: referer)
        let (data, _) = try await send(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PortalNetworkClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode HTML"])
        }
        return html
    }
}
