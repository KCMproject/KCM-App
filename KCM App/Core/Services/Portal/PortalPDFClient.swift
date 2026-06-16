import Foundation

/// 成績通知書PDFダウンロード・ユーザー名取得を担当するクライアント
final class PortalPDFClient {

    private let networkClient: PortalNetworkClient
    private let authClient: PortalAuthClient
    private let formClient: PortalFormClient
    private let timetableClient: PortalTimetableClient
    private let baseURL: String
    private let portalURL = "/portal.do"
    private let mainURL: String

    init(
        networkClient: PortalNetworkClient,
        authClient: PortalAuthClient,
        formClient: PortalFormClient,
        timetableClient: PortalTimetableClient
    ) {
        self.networkClient = networkClient
        self.authClient = authClient
        self.formClient = formClient
        self.timetableClient = timetableClient
        self.baseURL = networkClient.baseURL
        self.mainURL = "\(baseURL)\(portalURL)?page=main"
    }

    // MARK: - 公開API

    func fetchGradeReportPDF() async throws -> Data {
        try await authClient.executeWithAutoRelogin {
            try await self._fetchGradeReportPDF()
        }
    }

    func fetchUserName() async throws -> (fullName: String, reading: String) {
        try await authClient.executeWithAutoRelogin {
            let html = try await self.timetableClient.fetchWeeklyTimetableHTML(semester: .current)
            guard let result = CampusSquareParser.parseUserName(from: html) else {
                throw CampusSquareLoginError.portalError("ユーザー名が見つかりませんでした")
            }
            return result
        }
    }

    // MARK: - 内部実装

    private func _fetchGradeReportPDF() async throws -> Data {
        // Step 1: 学生ポートフォリオページを開き、_flowExecutionKeyをURLから取得
        let portfolioURL = "\(baseURL)/campussquare.do?_flowId=CHW0001000-flow"
        let (portfolioData, portfolioResponse) = try await networkClient.fetchHTMLWithResponse(from: portfolioURL, referer: mainURL)
        let key1 = try extractFlowExecutionKey(from: portfolioData, responseURL: portfolioResponse.url)

        // Step 2: 成績修得状況ページへ遷移
        let seisekiURL = "\(baseURL)/campussquare.do?_flowExecutionKey=\(key1.urlEncoded)&_eventId=check&nextEvent=seiseki"
        let (seisekiData, seisekiResponse) = try await networkClient.fetchHTMLWithResponse(from: seisekiURL, referer: portfolioURL)
        let key2 = try extractFlowExecutionKey(from: seisekiData, responseURL: seisekiResponse.url)

        // Step 3: PDFをPOSTでダウンロード
        let pdfData = try await formClient.postFormRaw(
            fields: [
                ("_flowExecutionKey", key2),
                ("_eventId", "outputPdf")
            ],
            referer: seisekiURL
        )

        guard !pdfData.isEmpty else {
            throw CampusSquareLoginError.portalError("PDFデータが空です")
        }

        return pdfData
    }

    private func extractFlowExecutionKey(from data: Data, responseURL: URL?) throws -> String {
        if let url = responseURL,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let keyFromURL = queryItems.first(where: { $0.name == "_flowExecutionKey" })?.value,
           !keyFromURL.isEmpty {
            return keyFromURL
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw CampusSquareLoginError.portalError("HTMLのデコードに失敗しました")
        }

        let inputPattern = "name=\"_flowExecutionKey\"\\s+value=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: inputPattern),
           let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        let hrefPattern = "_flowExecutionKey=([a-zA-Z0-9_\\-]+)"
        guard let regex = try? NSRegularExpression(pattern: hrefPattern),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range(at: 1), in: html) else {
            throw CampusSquareLoginError.portalError("_flowExecutionKeyが見つかりません")
        }
        return String(html[range])
    }
}
