import Foundation

/// ポータルへのフォームPOST送信を担当するクライアント
final class PortalFormClient {

    private let networkClient: PortalNetworkClient

    init(networkClient: PortalNetworkClient) {
        self.networkClient = networkClient
    }

    /// フォームをPOST送信し、HTMLレスポンスを取得する
    func submitPortalForm(fields: [(String, String)], referer: String) async throws -> String {
        let (data, _) = try await sendForm(fields: fields, referer: referer)
        guard let html = String(data: data, encoding: .utf8) else {
            throw CampusSquareLoginError.portalError("掲示板検索結果の解析に失敗しました")
        }
        return html
    }

    /// フォームをPOST送信し、生のDataを取得する（PDFダウンロード等）
    func postFormRaw(fields: [(String, String)], referer: String) async throws -> Data {
        let (data, response) = try await sendForm(fields: fields, referer: referer)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw CampusSquareLoginError.portalError("PDFダウンロードに失敗しました")
        }

        return data
    }

    // MARK: - 内部実装

    private func sendForm(fields: [(String, String)], referer: String) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(networkClient.baseURL)/campussquare.do") else {
            throw CampusSquareLoginError.portalError("掲示板検索URLを生成できません")
        }

        var request = networkClient.makeRequest(url: url, method: "POST", referer: referer)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cs.kunitachi.ac.jp", forHTTPHeaderField: "Origin")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.httpBody = PortalClientHelper.formURLEncoded(fields).data(using: .utf8)

        return try await networkClient.send(request)
    }
}
