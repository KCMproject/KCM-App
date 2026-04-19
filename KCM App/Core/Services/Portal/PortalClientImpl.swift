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

                let (data, response) = try await networkClient.send(request)
                guard let responseString = String(data: data, encoding: .utf8) else {
                    completion(.failure(.authenticationFailed("レスポンス解析失敗"))); return
                }

                // 4. エラー判定
                if responseString.contains("class=\"error\"") || responseString.contains("入力に誤りがあります") {
                    completion(.failure(.authenticationFailed("ユーザー名またはパスワードが間違っています")))
                } else {
                    let sessionId = UUID().uuidString
                    let cookies = (response as? HTTPURLResponse)?.allHeaderFields["Set-Cookie"] as? String ?? ""
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
        
        let bulletinURL = "\(networkClient.baseURL)/\(bulletinPath)"
        let html = try await networkClient.fetchHTML(from: bulletinURL, referer: urlString)
        return CampusSquareParser.parseAnnouncements(from: html)
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

    /// 時間割を取得する (async)
    func fetchTimetable() async throws -> [Course] {
        // 1. ホーム画面（メインページ）を取得
        let mainHtml = try await networkClient.fetchHTML(from: "\(networkClient.baseURL)\(portalURL)?page=main")

        // 2. スケジュール管理 (PTW0001200-flow) へのリンクを抽出
        // HOME.html 内の onclick="loadPortletMenu('main', '...') " からURLを抽出
        let pattern = "campussquare\\.do\\?_flowId=PTW0001200-flow[^'\"]*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: mainHtml, options: [], range: NSRange(location: 0, length: mainHtml.utf16.count)),
              let range = Range(match.range, in: mainHtml) else {
            throw NSError(domain: "PortalClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "スケジュール管理へのリンクが見つかりません"])
        }

        let scheduleURL = String(mainHtml[range]).replacingOccurrences(of: "&amp;", with: "&")

        // 3. スケジュール管理ページへアクセス
        let html = try await networkClient.fetchHTML(from: "\(networkClient.baseURL)/\(scheduleURL)", referer: "\(networkClient.baseURL)\(portalURL)?page=main")

        // 4. パース
        return CampusSquareParser.parseSchedule(from: html)
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

// MARK: - String拡張: URLエンコード

extension String {
    var urlEncoded: String {
        self.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
