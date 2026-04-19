import Foundation

// MARK: - ログイン結果

/// ログイン処理の結果
enum CampusSquareLoginResult {
    case success(session: CampusSquareSession)
    case failure(CampusSquareLoginError)
}

// MARK: - 内部実装

/// CAMPUSSQUARE 自動ログインクラス
final class PortalClientImpl: PortalClientProtocol {

    private let baseURL = "https://cs.kunitachi.ac.jp/campusweb"
    private let portalURL = "/portal.do"
    private let session: URLSession
    private var currentSession: CampusSquareSession?
    
    // 🌟 サーバーから取得したセキュリティトークンを保持する変数
    private var rwfHash: String = ""

    // リトライ制限
    private var loginAttemptCount = 0
    private let maxLoginAttempts = 5

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: configuration)
    }

    /// テスト用にURLSessionConfigurationを注入するためのイニシャライザ
    init(configuration: URLSessionConfiguration) {
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        if configuration.timeoutIntervalForRequest == 0 {
            configuration.timeoutIntervalForRequest = 30
        }
        self.session = URLSession(configuration: configuration)
    }

    // MARK: - CampusSquareLoginProtocol

    func login(credentials: CampusSquareCredentials, completion: @escaping (CampusSquareLoginResult) -> Void) {
        // バリデーション
        switch credentials.validate() {
        case .success:
            break
        case .failure(let message):
            completion(.failure(.authenticationFailed(message)))
            return
        }

        guard loginAttemptCount < maxLoginAttempts else {
            completion(.failure(.accountLocked))
            return
        }

        loginAttemptCount += 1

        // 1. ログインページにGETアクセスしてセッションと rwfHash を取得
        getLoginPage { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                // 2. POSTでログイン情報を送信
                self.postLogin(credentials: credentials, completion: completion)
            case .failure(let error):
                completion(.failure(.networkError(error)))
            }
        }
    }

    func validateSession(completion: @escaping (Bool) -> Void) {
        guard let session = currentSession, session.isValid else {
            print("⚠️ ローカルでのセッション有効期限が切れています")
            completion(false)
            return
        }

        // ログイン後のメイン画面を指定
        let url = URL(string: "\(baseURL)\(portalURL)?page=main")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // ブラウザに近いヘッダー構成にする
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("\(baseURL)\(portalURL)", forHTTPHeaderField: "Referer")
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let task = self.session.dataTask(with: request) { data, response, error in
            // 1. ネットワークエラーの確認
            if let error = error {
                print("❌ 通信エラーが発生しました: \(error.localizedDescription)")
                completion(false)
                return
            }

            // 2. レスポンスの確認
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ 有効なレスポンスが得られませんでした")
                completion(false)
                return
            }

            print("📡 セッション確認レスポンスコード: \(httpResponse.statusCode)")

            guard httpResponse.statusCode == 200, let data = data else {
                print("⚠️ サーバーが期待通りに応答しませんでした (Status: \(httpResponse.statusCode))")
                completion(false)
                return
            }

            if let html = String(data: data, encoding: .utf8) {
                // 3. ログイン画面の要素（パスワード入力欄）が含まれていないかチェック
                let hasPasswordField = html.contains("id=\"passwordInput\"") || html.contains("name=\"password\"")
                let isLoggedIn = !hasPasswordField
                
                if isLoggedIn {
                    print("✨ セッション検証成功: ログイン状態が維持されています")
                } else {
                    print("⚠️ セッション検証失敗: ログイン画面にリダイレクトされました")
                }
                
                completion(isLoggedIn)
            } else {
                print("❌ レスポンスのパースに失敗しました")
                completion(false)
            }
        }
        task.resume()
    }

    func logout(completion: @escaping (Bool) -> Void) {
        currentSession = nil
        loginAttemptCount = 0
        rwfHash = ""

        if let url = URL(string: baseURL) {
            HTTPCookieStorage.shared.cookies(for: url)?.forEach { cookie in
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        completion(true)
    }

    // MARK: - Private Methods

    /// ログインページにGETアクセスし、rwfHashを取得
    private func getLoginPage(completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "\(baseURL)\(portalURL)?locale=ja_JP")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let data = data, let html = String(data: data, encoding: .utf8) {
                // 🌟 正規表現でHTMLから 'rwfHash' : 'xxxxx' の値を抽出する
                let pattern = "'rwfHash'\\s*:\\s*'([^']+)'"
                if let regex = try? NSRegularExpression(pattern: pattern, options: []),
                   let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
                    let rwfHashRange = match.range(at: 1)
                    if let swiftRange = Range(rwfHashRange, in: html) {
                        self.rwfHash = String(html[swiftRange])
                        print("🔑 rwfHash を取得しました: \(self.rwfHash)")
                    }
                }
            }

            completion(.success(()))
        }
        task.resume()
    }

    /// ログイン情報をPOST送信
    private func postLogin(credentials: CampusSquareCredentials, completion: @escaping (CampusSquareLoginResult) -> Void) {
        let url = URL(string: "\(baseURL)\(portalURL)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue("\(baseURL)\(portalURL)?locale=ja_JP", forHTTPHeaderField: "Referer")
        request.setValue("https://cs.kunitachi.ac.jp", forHTTPHeaderField: "Origin")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        // 🌟 実際のブラウザの通信と完全に一致するPOSTボディを作成
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

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                completion(.failure(.networkError(error)))
                return
            }

            guard let data = data,
                  let responseString = String(data: data, encoding: .utf8) else {
                completion(.failure(.authenticationFailed("レスポンスの解析に失敗")))
                return
            }

            // 🌟 実際の通信から判明したエラー判定ロジック
            if responseString.contains("class=\"error\"") || responseString.contains("入力に誤りがあります") {
                completion(.failure(.authenticationFailed("ユーザー名またはパスワードが間違っています")))
            } else {
                // エラーメッセージがなければログイン成功
                self.loginAttemptCount = 0

                let sessionId = UUID().uuidString
                self.currentSession = CampusSquareSession(
                    sessionId: sessionId,
                    cookies: HTTPCookieStorage.shared.cookies(for: url) ?? [],
                    loggedInAt: Date()
                )

                completion(.success(session: self.currentSession!))
            }
        }
        task.resume()
    }
// MARK: - 新規追加: リンクを辿ってお知らせを取得する処理

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

    /// お知らせ一覧を取得する (async)
    func fetchAnnouncements() async throws -> [NoticeCard] {
        // 1. メインページから掲示板リンクを抽出
        let mainHtml = try await fetchMainPageHtml()
        
        guard let bulletinPath = self.extractHref(from: mainHtml, withId: "menu-link-mf-164854") else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "掲示板リンクが見つかりません"])
        }
        
        // 2. 掲示板ページへアクセス (直接フローを開始)
        let url = URL(string: "\(baseURL)/\(bulletinPath)")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        request.setValue("\(baseURL)\(portalURL)?page=main", forHTTPHeaderField: "Referer")
        
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "掲示板ページの取得に失敗"])
        }
        
        return parseAnnouncements(from: html)
    }

    /// お知らせ一覧を取得する (completion handler)
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

    /// 時間割を取得する (async)
    func fetchTimetable() async throws -> [Course] {
        let html = try await fetchMainPageHtml()
        return parseTimetable(from: html)
    }

    /// 時間割を取得する (completion handler)
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

    /// メインページのHTMLから時間割をパースする
    private func parseTimetable(from html: String) -> [Course] {
        var results: [Course] = []
        
        // CampusSquareのメインページ時間割テーブルのセルを抽出
        // <td class="timetable-course">...</td> のような構造を想定
        let cellPattern = "<td[^>]*class=\"[^\"]*timetable-(?:course|cell)[^\"]*\"[^>]*>(.*?)</td>"
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        
        let matches = cellRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        
        for match in matches {
            guard let cellRange = Range(match.range(at: 1), in: html) else { continue }
            let cellHtml = String(html[cellRange])
            
            // 講義名、教室、教員名を抽出
            let title = stripHtmlTags(from: extractTagContent(from: cellHtml, tag: "a") ?? "")
            let room = stripHtmlTags(from: extractTagContent(from: cellHtml, tag: "span", className: "room") ?? "")
            
            if !title.isEmpty {
                results.append(Course(
                    id: UUID(),
                    weekday: "", // HTML構造から曜日・時限を特定する必要があるが、ここでは簡易化
                    period: "",
                    title: title,
                    room: room,
                    status: "",
                    instructor: "",
                    nextClassInfo: "",
                    materials: [],
                    assignments: []
                ))
            }
        }
        
        return results
    }

    /// メインページのHTMLを取得する
    private func fetchMainPageHtml() async throws -> String {
        let url = URL(string: "\(baseURL)\(portalURL)?page=main")!
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "メインページの取得に失敗"])
        }
        return html
    }

    /// お知らせ掲示板のHTMLからお知らせ一覧をパースする
    private func parseAnnouncements(from html: String) -> [NoticeCard] {
        var results: [NoticeCard] = []
        
        // CampusSquareのお知らせ一覧テーブルの行を抽出する正規表現
        // <td>日付</td><td>カテゴリ</td><td><a...>タイトル</a></td> のような構造を想定
        let rowPattern = "<tr[^>]*>(.*?)</tr>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        
        let matches = rowRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        
        for match in matches {
            guard let rowRange = Range(match.range(at: 1), in: html) else { continue }
            let rowHtml = String(html[rowRange])
            
            // 各セルの内容を抽出
            let cellPattern = "<td[^>]*>(.*?)</td>"
            guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { continue }
            let cellMatches = cellRegex.matches(in: rowHtml, options: [], range: NSRange(location: 0, length: rowHtml.utf16.count))
            
            // [掲載日時, 表題, 返信未読, ジャンル, 所属, 氏名, 掲示期間]
            if cellMatches.count >= 4 {
                let dateFull = stripHtmlTags(from: extractCellContent(from: rowHtml, match: cellMatches[0]))
                // 日付のみ抽出 (例: 2026/04/14 17:06:53 -> 2026/04/14)
                let date = String(dateFull.prefix(10))
                
                let titleWithLink = extractCellContent(from: rowHtml, match: cellMatches[1])
                let title = stripHtmlTags(from: titleWithLink)
                
                let category = stripHtmlTags(from: extractCellContent(from: rowHtml, match: cellMatches[3]))
                
                // IDはリンク等から抽出（ここでは簡易的にタイトル+日付）
                let id = "\(title)_\(date)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
                
                if !title.isEmpty && !date.isEmpty && !title.contains("掲載日時") { // ヘッダー行を除外
                    results.append(NoticeCard(
                        id: id,
                        title: title,
                        date: date,
                        category: category,
                        isPinned: rowHtml.contains("icon_pin") || rowHtml.contains("重要"),
                        content: ""
                    ))
                }
            }
        }
        
        return results
    }

    private func extractCellContent(from html: String, match: NSTextCheckingResult) -> String {
        guard let range = Range(match.range(at: 1), in: html) else { return "" }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripHtmlTags(from html: String) -> String {
        let pattern = "<[^>]+>"
        return html.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractTagContent(from html: String, tag: String, className: String? = nil) -> String? {
        let pattern: String
        if let className = className {
            pattern = "<\(tag)[^>]*class=\"[^\"]*\(className)[^\"]*\"[^>]*>(.*?)</\(tag)>"
        } else {
            pattern = "<\(tag)[^>]*>(.*?)</\(tag)>"
        }
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) else {
            return nil
        }
        
        let range = match.range(at: 1)
        if let swiftRange = Range(range, in: html) {
            return String(html[swiftRange])
        }
        return nil
    }

    /// HTMLから指定したIDを持つタグのhrefを抽出するヘルパー
    private func extractHref(from html: String, withId id: String) -> String? {
        let pattern = "id=\"\(id)\".*?href=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) else {
            return nil
        }
        let hrefRange = match.range(at: 1)
        if let swiftRange = Range(hrefRange, in: html) {
            // &amp; を & に戻してURLとして正しく機能させる
            return String(html[swiftRange]).replacingOccurrences(of: "&amp;", with: "&")
        }
        return nil
    }

    /// HTMLから指定したテキスト（リンク文字）を持つタグのhrefを抽出するヘルパー
    private func extractHrefByText(from html: String, text: String) -> String? {
        // 例: href="抽出したいURL" >お知らせ掲示板</a> というパターンを探す
        let pattern = "href=\"([^\"]+)\"[^>]*>\(text)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) else { return nil }
        
        let hrefRange = match.range(at: 1)
        if let swiftRange = Range(hrefRange, in: html) {
            return String(html[swiftRange]).replacingOccurrences(of: "&amp;", with: "&")
        }
        return nil
    }

    /// HTMLをファイルに書き出す
    private func saveHtmlToFile(html: String, fileName: String) {
        let fileURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(fileName)
        do {
            try html.write(to: fileURL, atomically: true, encoding: .utf8)
            print("\n✨ 成功！ファイルを保存しました。")
            print("📂 保存先: \(fileURL.path)")
            print("💡 このファイルをブラウザで開いて確認してください。\n")
        } catch {
            print("⚠️ ファイルの保存に失敗しました: \(error)")
        }
    }
}

// MARK: - String拡張: URLエンコード

extension String {
    var urlEncoded: String {
        self.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
