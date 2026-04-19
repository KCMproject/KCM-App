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
        print("🔍 掲示板への遷移を開始します...")
        
        // 1. メインページ (page=main) を取得
        let mainURL = URL(string: "\(baseURL)\(portalURL)?page=main")!
        var request = URLRequest(url: mainURL)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, let html = String(data: data, encoding: .utf8) else {
                completion(false); return
            }

            // 2. 「掲示板」リンク (id="menu-link-mf-164854") を抽出
            guard let bulletinPath = self.extractHref(from: html, withId: "menu-link-mf-164854") else {
                print("❌ 「掲示板」リンクが見つかりません。")
                completion(false); return
            }
            print("🔗 掲示板へのリンクを抽出しました")

            // 3. 掲示板メニューページを取得
            let bulletinURL = URL(string: "\(self.baseURL)/\(bulletinPath)")!
            var bulletinReq = URLRequest(url: bulletinURL)
            bulletinReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            bulletinReq.setValue("\(self.baseURL)\(self.portalURL)?page=main", forHTTPHeaderField: "Referer")

            self.session.dataTask(with: bulletinReq) { data, response, error in
                guard let data = data, let bulletinHtml = String(data: data, encoding: .utf8) else {
                    completion(false); return
                }

                // 4. 「お知らせ掲示板」リンク (id="auto-a-29") を抽出 (flowExecutionKeyを含む)
                guard let oshirasePath = self.extractHrefByText(from: bulletinHtml, text: "お知らせ掲示板") else {
                    print("❌ お知らせ掲示板リンクが見つかりません。")
                    self.saveHtmlToFile(html: bulletinHtml, fileName: "debug_bulletin.html")
                    completion(false); return
                }
                print("🔗 お知らせ掲示板への動的リンクを抽出しました")
                // 5. 最終的なお知らせ掲示板を取得
                let oshiraseURL = URL(string: "\(self.baseURL)/\(oshirasePath)")!
                var oshiraseReq = URLRequest(url: oshiraseURL)
                oshiraseReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                oshiraseReq.setValue(bulletinURL.absoluteString, forHTTPHeaderField: "Referer")

                self.session.dataTask(with: oshiraseReq) { data, response, error in
                    guard let data = data, let finalHtml = String(data: data, encoding: .utf8) else {
                        completion(false); return
                    }

                    // 🌟 6. 結果をファイルに保存
                    self.saveHtmlToFile(html: finalHtml, fileName: "oshirase_board.html")
                    completion(true)
                }.resume()
            }.resume()
        }
        task.resume()
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
