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
                // 1. バリデーション
                switch credentials.validate() {
                case .success: break
                case .failure(let msg):
                    completion(.failure(.authenticationFailed(msg))); return
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

                let (data, _) = try await networkClient.send(request)
                guard let responseString = String(data: data, encoding: .utf8) else {
                    completion(.failure(.authenticationFailed("レスポンス解析失敗"))); return
                }

                // 4. エラー判定
                if responseString.contains("class=\"error\"") || responseString.contains("入力に誤りがあります") {
                    completion(.failure(.authenticationFailed("ユーザー名またはパスワードが間違っています")))
                } else {
                    let sessionId = UUID().uuidString
                    print("📡 ログイン成功: SessionID=\(sessionId)")
                    
                    self.currentSession = CampusSquareSession(
                        sessionId: sessionId,
                        cookies: [], // CookieはPortalNetworkClientのURLSessionが内部で保持
                        loggedInAt: Date()
                    )
                    completion(.success(session: self.currentSession!))
                }
            } catch {
                completion(.failure(.networkError(error)))
            }
        }
    }

    func logout(completion: @escaping (Bool) -> Void) {
        currentSession = nil
        rwfHash = ""
        // CookieのクリアはPortalNetworkClientに任せるか、必要に応じて拡張
        completion(true)
    }

    func validateSession(completion: @escaping (Bool) -> Void) {
        Task {
            guard let session = currentSession, session.isValid else {
                completion(false); return
            }
            do {
                let html = try await networkClient.fetchHTML(from: "\(networkClient.baseURL)\(portalURL)?page=main")
                let hasPasswordField = html.contains("id=\"passwordInput\"") || html.contains("name=\"password\"")
                completion(!hasPasswordField)
            } catch {
                completion(false)
            }
        }
    }

    // MARK: - お知らせ

    func fetchAnnouncements() async throws -> [NoticeCard] {
        let urlString = "\(networkClient.baseURL)\(portalURL)?page=main"
        let mainHtml = try await networkClient.fetchHTML(from: urlString)

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
        var results: [Course] = []
        for offset in uniqueOffsets {
            let html = try await fetchScheduleHTML(monthOffset: offset, referer: mainURL)
            if !html.contains("schedule-calender") {
                print("⚠️ [Portal] 警告: スケジュールグリッドが見つかりません。offset=\(offset)")
            }
            results.append(contentsOf: CampusSquareParser.parseSchedule(from: html))
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
        print("🌐 [Portal] fetchWeeklyTimetable(\(semester.displayName)) 開始")
        let mainURL = "\(networkClient.baseURL)\(portalURL)?page=main"
        let mainHtml = try await networkClient.fetchHTML(from: mainURL)

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

        return CampusSquareParser.parseWeeklyTimetableFromRSW(from: html)
    }

    // MARK: - レガシーサポート

    func fetchOshirase(completion: @escaping (Bool) -> Void) {
        Task {
            do {
                _ = try await fetchAnnouncements()
                completion(true)
            } catch {
                completion(false)
            }
        }
    }
}

private extension PortalClientImpl {
    func validatePortalPage(_ html: String) throws {
        if html.contains("ログイン") && (html.contains("password") || html.contains("userName")) {
            throw CampusSquareLoginError.sessionExpired
        }
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
                let notices = CampusSquareParser.parseAnnouncements(from: html)
                for notice in notices {
                    noticesByID[notice.id] = notice
                }
                currentHtml = html
                currentReferer = url
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
            let notices = CampusSquareParser.parseAnnouncements(from: html)
            for notice in notices {
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
