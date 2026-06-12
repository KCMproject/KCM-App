import Foundation

// MARK: - ログイン結果

/// ログイン処理の結果
enum CampusSquareLoginResult {
    case success(session: CampusSquareSession)
    case failure(CampusSquareLoginError)
}

// MARK: - 内部実装

/// CAMPUSSQUARE 自動ログイン・データ取得クラス
final class PortalClientImpl: PortalClientProtocol {

    private let networkClient: PortalNetworkClient
    private let portalURL = "/portal.do"
    private var currentSession: CampusSquareSession?
    
    // 🌟 セキュリティトークン
    private var rwfHash: String = ""
    
    init(baseURL: String = "https://cs.kunitachi.ac.jp/campusweb") {
        self.networkClient = PortalNetworkClient(baseURL: baseURL)
    }

    // MARK: - 認証

    func login(credentials: CampusSquareCredentials, completion: @escaping (CampusSquareLoginResult) -> Void) {
        Task {
            do {
                let session = try await performLogin(credentials: credentials)
                completion(.success(session: session))
            } catch let error as CampusSquareLoginError {
                completion(.failure(error))
            } catch {
                completion(.failure(.networkError(error)))
            }
        }
    }
    
    // MARK: - 内部ログイン実装（async/await）
    
    private func performLogin(credentials: CampusSquareCredentials) async throws -> CampusSquareSession {
        // 1. バリデーション
        switch credentials.validate() {
        case .success: break
        case .failure(let msg):
            throw CampusSquareLoginError.authenticationFailed(msg)
        }

        // 2. ログインページにアクセスして rwfHash を取得
        let loginPageHtml = try await networkClient.fetchHTML(from: "\(networkClient.baseURL)\(portalURL)?locale=ja_JP")
        
        let pattern = "'rwfHash'\\s*:\\s*'([^']+)'"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: loginPageHtml, options: [], range: NSRange(location: 0, length: loginPageHtml.utf16.count)),
           let range = Range(match.range(at: 1), in: loginPageHtml) {
            self.rwfHash = String(loginPageHtml[range])
        }

        // 3. ログイン情報をPOST送信
        let postURL = URL(string: "\(networkClient.baseURL)\(portalURL)")!
        var request = networkClient.makeRequest(url: postURL, method: "POST", referer: "\(networkClient.baseURL)\(portalURL)?locale=ja_JP")
        
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
        
        // 🍪 Cookieを明示的に保存
        if let httpResponse = response as? HTTPURLResponse,
           let url = response.url {
            let fields = httpResponse.allHeaderFields as? [String: String] ?? [:]
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
                print("🍪 Cookie保存: \(cookie.name)=\(cookie.value.prefix(20))... domain=\(cookie.domain)")
            }
        }
        
        guard let responseString = String(data: data, encoding: .utf8) else {
            throw CampusSquareLoginError.authenticationFailed("レスポンス解析失敗")
        }

        // 4. エラー判定
        if responseString.contains("class=\"error\"") || responseString.contains("入力に誤りがあります") {
            throw CampusSquareLoginError.authenticationFailed("ユーザー名またはパスワードが間違っています")
        }
        
        // 実際のセッション識別子をCookieから取得
        let sessionId = self.networkClient.sessionIdentifier() ?? UUID().uuidString
        let expiresIn = self.networkClient.earliestExpirationInMinutes() ?? 20
        print("📡 ログイン成功: SessionID=\(sessionId), 有効期限: \(expiresIn)分")
        
        let session = CampusSquareSession(
            sessionId: sessionId,
            loggedInAt: Date(),
            expiresInMinutes: expiresIn
        )
        self.currentSession = session
        return session
    }
    
    // MARK: - セッション切れ時の自動再ログイン
    
    private func attemptRelogin() async throws -> Bool {
        guard let credentials = SavedCredentialsStore.shared.load() else {
            print("🔑 [Portal] 再ログイン不可: 保存された資格情報がありません")
            return false
        }
        print("🔑 [Portal] セッション切れ。保存された資格情報で再ログインを試行します...")
        do {
            let session = try await performLogin(credentials: CampusSquareCredentials(
                userName: credentials.studentID,
                password: credentials.password
            ))
            print("🔑 [Portal] 自動再ログイン成功。SessionID=\(session.sessionId)")
            return true
        } catch {
            print("❌ [Portal] 自動再ログイン失敗: \(error.localizedDescription)")
            return false
        }
    }
    
    /// セッション切れ時に自動再ログインし、元の操作を再試行する
    private func executeWithAutoRelogin<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch CampusSquareLoginError.sessionExpired {
            print("🔑 [Portal] セッション切れを検出。自動再ログインを試行します...")
            let reloginSuccess = try await attemptRelogin()
            guard reloginSuccess else {
                throw CampusSquareLoginError.sessionExpired
            }
            print("🔑 [Portal] 再ログイン成功。元のリクエストを再試行します。")
            return try await operation()
        }
    }

    func logout() async {
        currentSession = nil
        rwfHash = ""
        networkClient.deleteCookies()
        print("🔒 ログアウト完了: Cookieとセッションをクリアしました")
    }

    func validateSession() async throws -> Bool {
        guard let session = currentSession, session.isValid else {
            return false
        }
        do {
            let html = try await networkClient.fetchHTML(from: "\(networkClient.baseURL)\(portalURL)?page=main")
            let hasPasswordField = html.contains("id=\"passwordInput\"") || html.contains("name=\"password\"")
            return !hasPasswordField
        } catch {
            // HTTPエラー（401/403等）や通信エラーはセッション無効とみなす
            return false
        }
    }

    // MARK: - お知らせ

    func fetchAnnouncements() async throws -> [NoticeCard] {
        try await executeWithAutoRelogin {
            try await self._fetchAnnouncements()
        }
    }
    
    private func _fetchAnnouncements() async throws -> [NoticeCard] {
        let urlString = "\(networkClient.baseURL)\(portalURL)?page=main"
        let mainHtml = try await networkClient.fetchHTML(from: urlString)

        // セッション切れチェック
        try validatePortalPage(mainHtml)

        guard let bulletinPath = CampusSquareParser.extractHref(from: mainHtml, withId: "menu-link-mf-164854") else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "掲示板リンクが見つかりません"])
        }
        
        let bulletinURL = absolutePortalURLString(from: bulletinPath)
        let html = try await networkClient.fetchHTML(from: bulletinURL, referer: urlString)
        try validatePortalPage(html)

        let genreNotices = try await fetchAnnouncementGenreLists(from: html, referer: bulletinURL)
        if !genreNotices.isEmpty {
            return genreNotices
        }

        let directNotices = CampusSquareParser.parseAnnouncements(from: html)
        if !directNotices.isEmpty {
            return directNotices
        }

        let searchNotices = try await fetchAnnouncementSearchResults(from: html, referer: bulletinURL)
        if !searchNotices.isEmpty {
            return searchNotices
        }

        throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "掲示板を読み込めませんでした"])
    }

    func fetchAnnouncements(completion: @escaping (Result<[NoticeCard], Error>) -> Void) {
        Task {
            do {
                let notices = try await fetchAnnouncements()
                completion(.success(notices))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchNoticeAttachments(for notice: NoticeCard) async throws -> [NoticeAttachment] {
        try await executeWithAutoRelogin {
            try await self._fetchNoticeAttachments(for: notice)
        }
    }
    
    func resolveNoticeDetailURL(for notice: NoticeCard) async throws -> URL? {
        try await executeWithAutoRelogin {
            try await self._resolveNoticeDetailURL(for: notice)
        }
    }
    
    private func _fetchNoticeAttachments(for notice: NoticeCard) async throws -> [NoticeAttachment] {
        guard let path = notice.url, !path.isEmpty else {
            return []
        }

        let detailURL = absolutePortalURLString(from: path)
        let mainURL = "\(networkClient.baseURL)\(portalURL)?page=main"
        let html = try await networkClient.fetchHTML(from: detailURL, referer: mainURL)
        if isNoticeDetailPage(html, for: notice) {
            return CampusSquareParser.parseNoticeAttachments(from: html, baseURL: networkClient.baseURL)
        }

        if let freshDetail = try await resolveFreshNoticeDetailURL(for: notice, mainURL: mainURL) {
            let freshHtml = try await networkClient.fetchHTML(from: freshDetail.url, referer: freshDetail.referer)
            guard isNoticeDetailPage(freshHtml, for: notice) else {
                throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "掲示板詳細を取得できませんでした"])
            }
            return CampusSquareParser.parseNoticeAttachments(from: freshHtml, baseURL: networkClient.baseURL)
        }

        throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "掲示板詳細URLを更新できませんでした"])
    }

    /// 時間割を取得する (async)
    func fetchTimetable() async throws -> [Course] {
        try await fetchTimetable(monthOffsets: [0])
    }

    func fetchTimetable(monthOffsets: [Int]) async throws -> [Course] {
        try await executeWithAutoRelogin {
            try await self._fetchTimetable(monthOffsets: monthOffsets)
        }
    }
    
    private func _fetchTimetable(monthOffsets: [Int]) async throws -> [Course] {
        print("🌐 [Portal] fetchTimetable 開始: メインページ取得中...")
        let mainURL = "\(networkClient.baseURL)\(portalURL)?page=main"
        let mainHtml = try await networkClient.fetchHTML(from: mainURL)
        print("✅ [Portal] メインページ取得成功 (サイズ: \(mainHtml.count))")

        // セッションが切れていないか確認
        if mainHtml.contains("ログイン") && (mainHtml.contains("password") || mainHtml.contains("userName")) {
            print("❌ [Portal] セッション切れ。ログイン画面に戻っています。")
            throw CampusSquareLoginError.sessionExpired
        }

        let uniqueOffsets = Array(Set(monthOffsets)).sorted()
        let maxConcurrent = 5
        var results: [Course] = []

        await withTaskGroup(of: [Course].self) { group in
            var pending = 0
            for offset in uniqueOffsets {
                group.addTask {
                    do {
                        let html = try await self.fetchScheduleHTML(monthOffset: offset, referer: mainURL)
                        if !html.contains("schedule-calender") {
                            print("⚠️ [Portal] 警告: スケジュールグリッドが見つかりません。offset=\(offset)")
                        }
                        return await CampusSquareParser.parseSchedule(from: html)
                    } catch {
                        print("❌ [Portal] offset=\(offset) の取得に失敗: \(error.localizedDescription)")
                        return []
                    }
                }
                pending += 1
                // 最大並列数に達したら、1つ完了するまで待機
                if pending >= maxConcurrent {
                    let courses = await group.next() ?? []
                    results.append(contentsOf: courses)
                    pending -= 1
                }
            }
            // 残りを全て収集
            for await courses in group {
                results.append(contentsOf: courses)
            }
        }

        print("🏁 [Portal] パース完了: \(results.count) 件のコースを返します")
        return results
    }

    func fetchTimetable(completion: @escaping (Result<[Course], Error>) -> Void) {
        Task {
            do {
                let courses = try await fetchTimetable()
                completion(.success(courses))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// 週間時間割（グリッド形式）を取得する
    func fetchWeeklyTimetable() async throws -> [Course] {
        try await fetchWeeklyTimetable(semester: .current)
    }

    func fetchWeeklyTimetable(semester: TimetableSemester) async throws -> [Course] {
        try await executeWithAutoRelogin {
            let html = try await self._fetchWeeklyTimetableHTML(semester: semester)
            return CampusSquareParser.parseWeeklyTimetableFromRSW(from: html)
        }
    }

    func fetchWeeklyTimetableHTML(semester: TimetableSemester) async throws -> String {
        try await executeWithAutoRelogin {
            try await self._fetchWeeklyTimetableHTML(semester: semester)
        }
    }

    func fetchWeeklyTimetableWithHTML(semester: TimetableSemester) async throws -> (courses: [Course], html: String) {
        try await executeWithAutoRelogin {
            let html = try await self._fetchWeeklyTimetableHTML(semester: semester)
            let courses = CampusSquareParser.parseWeeklyTimetableFromRSW(from: html)
            return (courses, html)
        }
    }

    private func _fetchWeeklyTimetableHTML(semester: TimetableSemester) async throws -> String {
        print("🌐 [Portal] fetchWeeklyTimetableHTML(\(semester.displayName)) 開始")
        let mainURL = "\(networkClient.baseURL)\(portalURL)?page=main"
        let mainHtml = try await networkClient.fetchHTML(from: mainURL)

        // セッション切れチェック
        try validatePortalPage(mainHtml)

        guard let rswPath = CampusSquareParser.extractHref(from: mainHtml, withId: "menu-link-mf-164915") else {
            print("❌ [Portal] 履修登録リンク(menu-link-mf-164915)が見つかりません。")
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "履修登録リンクが見つかりません"])
        }

        let rswURL = absolutePortalURLString(from: rswPath)
        let initialHtml = try await networkClient.fetchHTML(from: rswURL, referer: mainURL)
        let selectedSemester = CampusSquareParser.parseSelectedTimetableSemester(from: initialHtml)

        let html: String
        if selectedSemester == semester {
            html = initialHtml
        } else if let semesterPath = CampusSquareParser.extractTimetableSemesterHref(from: initialHtml, semester: semester) {
            let semesterURL = absolutePortalURLString(from: semesterPath)
            print("🔁 [Portal] \(semester.displayName) に切替: \(semesterURL)")
            html = try await networkClient.fetchHTML(from: semesterURL, referer: rswURL)
        } else {
            print("⚠️ [Portal] \(semester.displayName) 切替リンクが見つからないため初期HTMLを利用します")
            html = initialHtml
        }

        return html
    }

    // MARK: - レガシーサポート

    func fetchOshirase() async -> Bool {
        do {
            _ = try await fetchAnnouncements()
            return true
        } catch {
            return false
        }
    }

    // MARK: - 成績通知書PDF

    func fetchGradeReportPDF() async throws -> Data {
        try await executeWithAutoRelogin {
            try await self._fetchGradeReportPDF()
        }
    }

    func fetchUserName() async throws -> (fullName: String, reading: String) {
        try await executeWithAutoRelogin {
            let html = try await self._fetchWeeklyTimetableHTML(semester: .current)
            guard let result = CampusSquareParser.parseUserName(from: html) else {
                throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "ユーザー名が見つかりませんでした"])
            }
            return result
        }
    }

    private func _fetchGradeReportPDF() async throws -> Data {
        let mainURL = "\(networkClient.baseURL)\(portalURL)?page=main"

        // Step 1: 学生ポートフォリオページを開き、_flowExecutionKeyをURLから取得
        let portfolioURL = "\(networkClient.baseURL)/campussquare.do?_flowId=CHW0001000-flow"
        print("📄 [PDF] Step1: 学生ポートフォリオを取得: \(portfolioURL)")
        let (portfolioData, portfolioResponse) = try await networkClient.fetchHTMLWithResponse(from: portfolioURL, referer: mainURL)
        let key1 = try extractFlowExecutionKey(from: portfolioData, responseURL: portfolioResponse.url)
        print("📄 [PDF] _flowExecutionKey(1) = \(key1)")

        // Step 2: 成績修得状況ページへ遷移
        let seisekiURL = "\(networkClient.baseURL)/campussquare.do?_flowExecutionKey=\(key1.urlEncoded)&_eventId=check&nextEvent=seiseki"
        print("📄 [PDF] Step2: 成績修得状況を取得: \(seisekiURL)")
        let (seisekiData, seisekiResponse) = try await networkClient.fetchHTMLWithResponse(from: seisekiURL, referer: portfolioURL)
        let key2 = try extractFlowExecutionKey(from: seisekiData, responseURL: seisekiResponse.url)
        print("📄 [PDF] _flowExecutionKey(2) = \(key2)")

        // Step 3: PDFをPOSTでダウンロード
        print("📄 [PDF] Step3: PDFをダウンロード")
        let pdfData = try await postFormRaw(
            fields: [
                ("_flowExecutionKey", key2),
                ("_eventId", "outputPdf")
            ],
            referer: seisekiURL
        )
        print("📄 [PDF] ダウンロード完了: \(pdfData.count) bytes")

        guard !pdfData.isEmpty else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDFデータが空です"])
        }

        return pdfData
    }
}

private extension PortalClientImpl {
    func validatePortalPage(_ html: String) throws {
        if html.contains("ログイン") && (html.contains("password") || html.contains("userName")) {
            throw CampusSquareLoginError.sessionExpired
        }
    }
    
    // ページング: 次ページリンクを抽出（"次へ" もしくは rel="next"、またはページング用イベントが含まれるリンク）
    func extractNextPageHref(from html: String) -> String? {
        // rel="next"
        if let href = firstHref(in: html, pattern: #"<a[^>]*rel=\"next\"[^>]*href=\"([^\"]+)\""#) {
            return href
        }
        // _eventId_paging を含むリンク（実際のポータルで使用されるページング）
        if let href = firstHref(in: html, pattern: #"href=\"([^\"]*_eventId_paging[^\"]*)\""#) {
            return href
        }
        // アンカーテキストが「次へ」
        if let range = html.range(of: "(?is)<a[^>]*href=\\\"([^\\\"]+)\\\"[^>]*>\\s*次へ\\s*&?[^<]*</a>", options: [.regularExpression, .caseInsensitive]) {
            let match = String(html[range])
            if let hrefRange = match.range(of: "href=\\\"([^\\\"]+)\\\"", options: .regularExpression) {
                let href = String(match[hrefRange]).replacingOccurrences(of: "href=\"", with: "").replacingOccurrences(of: "\"", with: "")
                return href.replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        // _eventId_next / nextPage を含むリンク
        if let href = firstHref(in: html, pattern: #"href=\"([^\"]*_eventId_(next|nextPage)[^\"]*)\""#) {
            return href
        }
        return nil
    }

    // 「前へ」リンクの抽出（必要に応じて使用）
    func extractPrevPageHref(from html: String) -> String? {
        // rel="prev"
        if let href = firstHref(in: html, pattern: #"<a[^>]*rel=\"prev\"[^>]*href=\"([^\"]+)\""#) {
            return href
        }
        // アンカーテキストに「前へ」
        if let href = firstHref(in: html, pattern: #"<a[^>]*href=\"([^\"]+)\"[^>]*>\s*前へ\s*[<>\w\W]*?</a>"#) {
            return href
        }
        // _eventId_prev / prevPage を含むリンク
        if let href = firstHref(in: html, pattern: #"href=\"([^\"]*_eventId_(prev|prevPage)[^\"]*)\""#) {
            return href
        }
        return nil
    }

    // 汎用: 最初にマッチした href の値を返す
    func firstHref(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
        if let match = regex.firstMatch(in: html, options: [], range: nsrange), match.numberOfRanges >= 2,
           let range = Range(match.range(at: 1), in: html) {
            let href = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            return href
        }
        return nil
    }

    /// 掲示板ページをページングしながらすべてのお知らせを収集する（最大 maxPages ページ）
    func collectAnnouncementsWithPagination(initialHtml: String, initialURL: String, referer: String, maxPages: Int = 10) async throws -> (notices: [NoticeCard], lastHtml: String, lastURL: String) {
        var allByID: [String: NoticeCard] = [:]
        var currentHtml = initialHtml
        var currentURL = initialURL
        var pageCount = 0

        while pageCount < maxPages {
            // 現ページのパース
            let notices = CampusSquareParser.parseAnnouncements(from: currentHtml)
            for n in notices { allByID[n.id] = n }

            // 次ページリンク探索（存在しなければ終了）
            guard let nextHref = extractNextPageHref(from: currentHtml) else {
                break
            }
            pageCount += 1
            
            let nextURL = absolutePortalURLString(from: nextHref)
            let nextHtml = try await networkClient.fetchHTML(from: nextURL, referer: currentURL)
            try validatePortalPage(nextHtml)

            currentHtml = nextHtml
            currentURL = nextURL
        }

        return (sortAnnouncements(Array(allByID.values)), currentHtml, currentURL)
    }

    func fetchAnnouncementGenreLists(from topHtml: String, referer: String) async throws -> [NoticeCard] {
        let targets = CampusSquareParser.extractNoticeGenreLinks(from: topHtml)
        guard !targets.isEmpty else {
            return []
        }

        var currentHtml = topHtml
        var currentReferer = referer
        var noticesByID: [String: NoticeCard] = [:]

        for target in targets {
            let currentTargets = CampusSquareParser.extractNoticeGenreLinks(from: currentHtml)
            let link = currentTargets.first {
                $0.keijitype == target.keijitype && $0.genrecd == target.genrecd
            } ?? target
            let url = absolutePortalURLString(from: link.href)

            do {
                let html = try await networkClient.fetchHTML(from: url, referer: currentReferer)
                try validatePortalPage(html)
                let collected = try await collectAnnouncementsWithPagination(initialHtml: html, initialURL: url, referer: currentReferer, maxPages: 10)
                for notice in collected.notices {
                    noticesByID[notice.id] = notice
                }
                currentHtml = collected.lastHtml
                currentReferer = collected.lastURL
            } catch {
                continue
            }
        }

        return sortAnnouncements(Array(noticesByID.values))
    }

    func resolveFreshNoticeDetailURL(for notice: NoticeCard, mainURL: String) async throws -> (url: String, referer: String)? {
        guard let values = noticeQueryValues(from: notice.url),
              let keijitype = values["keijitype"],
              let genrecd = values["genrecd"],
              let seqNo = values["seqNo"] else {
            return nil
        }

        let mainHtml = try await networkClient.fetchHTML(from: mainURL)
        try validatePortalPage(mainHtml)
        guard let bulletinPath = CampusSquareParser.extractHref(from: mainHtml, withId: "menu-link-mf-164854") else {
            return nil
        }

        let bulletinURL = absolutePortalURLString(from: bulletinPath)
        let topHtml = try await networkClient.fetchHTML(from: bulletinURL, referer: mainURL)
        try validatePortalPage(topHtml)

        guard let genreLink = CampusSquareParser.extractNoticeGenreLinks(from: topHtml).first(where: {
            $0.keijitype == keijitype && $0.genrecd == genrecd
        }) else {
            return nil
        }

        let genreURL = absolutePortalURLString(from: genreLink.href)
        let genreHtml = try await networkClient.fetchHTML(from: genreURL, referer: bulletinURL)
        try validatePortalPage(genreHtml)

        guard let detailHref = extractNoticeDetailHref(from: genreHtml, keijitype: keijitype, genrecd: genrecd, seqNo: seqNo) else {
            return nil
        }

        let detailURL = absolutePortalURLString(from: detailHref)
        return (detailURL, genreURL)
    }
    
    private func _resolveNoticeDetailURL(for notice: NoticeCard) async throws -> URL? {
        let mainURL = "\(networkClient.baseURL)\(portalURL)?page=main"
        guard let freshDetail = try await resolveFreshNoticeDetailURL(for: notice, mainURL: mainURL) else {
            return nil
        }
        return URL(string: freshDetail.url)
    }

    func extractNoticeDetailHref(from html: String, keijitype: String, genrecd: String, seqNo: String) -> String? {
        let linkPattern = "<a[^>]*href\\s*=\\s*['\"]([^'\"]*seqNo=\(NSRegularExpression.escapedPattern(for: seqNo))[^'\"]*)['\"][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        for match in regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let href = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            guard let values = noticeQueryValues(from: href),
                  values["keijitype"] == keijitype,
                  values["genrecd"] == genrecd,
                  values["seqNo"] == seqNo else {
                continue
            }
            return href
        }

        return nil
    }

    func noticeQueryValues(from rawURL: String?) -> [String: String]? {
        guard let rawURL, !rawURL.isEmpty else { return nil }
        let decodedURL = rawURL.replacingOccurrences(of: "&amp;", with: "&")
        let absoluteURL: String
        if decodedURL.hasPrefix("http://") || decodedURL.hasPrefix("https://") {
            absoluteURL = decodedURL
        } else if decodedURL.hasPrefix("/") {
            absoluteURL = "https://cs.kunitachi.ac.jp\(decodedURL)"
        } else {
            absoluteURL = "\(networkClient.baseURL)/\(decodedURL)"
        }

        guard let components = URLComponents(string: absoluteURL),
              let queryItems = components.queryItems else {
            return nil
        }

        var values: [String: String] = [:]
        for item in queryItems {
            values[item.name] = item.value ?? ""
        }
        return values
    }

    func isNoticeDetailPage(_ html: String, for notice: NoticeCard) -> Bool {
        html.contains("KeijiReferView")
            && (html.contains("keiji-title") || html.contains("keiji-naiyo"))
            && html.contains(notice.title)
    }

    func fetchAnnouncementSearchResults(from searchHtml: String, referer: String) async throws -> [NoticeCard] {
        guard let initialSearchHtml = try await fetchAnnouncementSearchPage(from: searchHtml, referer: referer) else {
            return []
        }

        let genreValues = CampusSquareParser.parseSelectValues(from: initialSearchHtml, formID: "keijiSearchForm", selectName: "genreCd")
        var noticesByID: [String: NoticeCard] = [:]
        let searchTargets = genreValues.isEmpty ? [""] : genreValues

        for (index, genreValue) in searchTargets.enumerated() {
            let formHtml: String
            if index == 0 {
                formHtml = initialSearchHtml
            } else {
                let freshTopHtml = try await networkClient.fetchHTML(from: referer, referer: referer)
                try validatePortalPage(freshTopHtml)
                guard let freshSearchHtml = try await fetchAnnouncementSearchPage(from: freshTopHtml, referer: referer) else {
                    continue
                }
                formHtml = freshSearchHtml
            }

            let baseFields = CampusSquareParser.parseFormFields(from: formHtml, formID: "keijiSearchForm")
            guard !baseFields.isEmpty else {
                continue
            }

            let html = try await submitAnnouncementSearch(fields: baseFields, genreValue: genreValue, referer: referer)
            try validatePortalPage(html)
            // 検索結果ページもページング対応
            let tempURL = referer // POST のため明確なURLがないので referer を基準にする
            let collected = try await collectAnnouncementsWithPagination(initialHtml: html, initialURL: tempURL, referer: referer, maxPages: 10)
            for notice in collected.notices {
                noticesByID[notice.id] = notice
            }
        }

        return sortAnnouncements(Array(noticesByID.values))
    }

    func fetchAnnouncementSearchPage(from topHtml: String, referer: String) async throws -> String? {
        if !CampusSquareParser.parseFormFields(from: topHtml, formID: "keijiSearchForm").isEmpty {
            return topHtml
        }

        let topFields = CampusSquareParser.parseFormFields(from: topHtml, formID: "keijiReferForm")
        guard !topFields.isEmpty else { return nil }

        let html = try await submitPortalForm(fields: topFields + [("_eventId_search", "掲示情報検索")], referer: referer)
        try validatePortalPage(html)
        return html
    }

    func submitAnnouncementSearch(fields: [(String, String)], genreValue: String, referer: String) async throws -> String {
        let bodyFields = fields.map { field in
            field.0 == "genreCd" && !genreValue.isEmpty ? (field.0, genreValue) : field
        }
        return try await submitPortalForm(fields: bodyFields, referer: referer)
    }

    func submitPortalForm(fields: [(String, String)], referer: String) async throws -> String {
        guard let url = URL(string: "\(networkClient.baseURL)/campussquare.do") else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "掲示板検索URLを生成できません"])
        }

        var request = networkClient.makeRequest(url: url, method: "POST", referer: referer)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cs.kunitachi.ac.jp", forHTTPHeaderField: "Origin")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.httpBody = formURLEncoded(fields).data(using: .utf8)

        let (data, _) = try await networkClient.send(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "掲示板検索結果の解析に失敗しました"])
        }
        return html
    }

    func formURLEncoded(_ fields: [(String, String)]) -> String {
        fields
            .map { "\($0.urlEncoded)=\($1.urlEncoded)" }
            .joined(separator: "&")
    }

    func sortAnnouncements(_ notices: [NoticeCard]) -> [NoticeCard] {
        notices.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.title < rhs.title
        }
    }

    func fetchScheduleHTML(monthOffset: Int, referer: String) async throws -> String {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.startOfDay(for: Date())
        guard let targetDate = calendar.date(byAdding: .month, value: monthOffset, to: baseDate) else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "スケジュール月の計算に失敗しました"])
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let initDate = formatter.string(from: targetDate)
        let path = "campussquare.do?_flowId=PTW0001200-flow&initDate=\(initDate)"
        let url = absolutePortalURLString(from: path)
        print("🔗 [Portal] スケジュール月取得 offset=\(monthOffset): \(url)")
        return try await networkClient.fetchHTML(from: url, referer: referer)
    }

    func extractFlowExecutionKey(from data: Data, responseURL: URL?) throws -> String {
        // 1. レスポンスURLから抽出（リダイレクト後にURLに含まれるケース）
        if let url = responseURL,
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems,
           let keyFromURL = queryItems.first(where: { $0.name == "_flowExecutionKey" })?.value,
           !keyFromURL.isEmpty {
            return keyFromURL
        }

        // 2. HTML内の<input hidden>から抽出
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "HTMLのデコードに失敗しました"])
        }

        let inputPattern = "name=\"_flowExecutionKey\"\\s+value=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: inputPattern),
           let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
           let range = Range(match.range(at: 1), in: html) {
            return String(html[range])
        }

        // 3. form action URL や a href から抽出（URLエンコードされた&amp;を含む可能性あり）
        let hrefPattern = "_flowExecutionKey=([a-zA-Z0-9_\\-]+)"
        guard let regex = try? NSRegularExpression(pattern: hrefPattern),
              let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range(at: 1), in: html) else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "_flowExecutionKeyが見つかりません"])
        }
        return String(html[range])
    }

    func postFormRaw(fields: [(String, String)], referer: String) async throws -> Data {
        guard let url = URL(string: "\(networkClient.baseURL)/campussquare.do") else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "URLを生成できません"])
        }

        var request = networkClient.makeRequest(url: url, method: "POST", referer: referer)
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cs.kunitachi.ac.jp", forHTTPHeaderField: "Origin")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.httpBody = formURLEncoded(fields).data(using: .utf8)

        let (data, response) = try await networkClient.send(request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDFダウンロードに失敗しました"])
        }

        return data
    }

    func absolutePortalURLString(from path: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        if path.hasPrefix("/") {
            guard let base = URL(string: networkClient.baseURL),
                  let url = URL(string: path, relativeTo: base) else {
                return path
            }
            return url.absoluteString
        }
        return "\(networkClient.baseURL)/\(path)"
    }
}

// MARK: - String拡張: URLエンコード

extension String {
    var urlEncoded: String {
        self.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
