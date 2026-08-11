import Foundation

/// PortalClient 系クラスで共通して使う純粋関数・軽量ユーティリティ
enum PortalClientHelper {

    /// ポータル相対パスを絶対URLに解決する
    static func absolutePortalURLString(from path: String, baseURL: String) -> String {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }
        if path.hasPrefix("/") {
            guard let base = URL(string: baseURL),
                  let url = URL(string: path, relativeTo: base) else {
                return path
            }
            return url.absoluteString
        }
        return "\(baseURL)/\(path)"
    }

    /// ログイン画面に戻されていないか判定する
    static func validatePortalPage(_ html: String) throws {
        if html.contains("ログイン") && (html.contains("password") || html.contains("userName")) {
            throw CampusSquareLoginError.sessionExpired
        }
        // セッション無効時に返される「認証エラー」ページもセッション切れとして扱う
        if html.contains("認証エラー") || html.contains("authorization-error-flow") {
            throw CampusSquareLoginError.sessionExpired
        }
    }

    /// ページング: 次ページリンクを抽出する
    static func extractNextPageHref(from html: String) -> String? {
        if let href = firstHref(in: html, pattern: #"<a[^>]*rel=\"next\"[^>]*href=\"([^\"]+)\""#) {
            return href
        }
        if let href = firstHref(in: html, pattern: #"href=\"([^\"]*_eventId_paging[^\"]*)\""#) {
            return href
        }
        if let range = html.range(
            of: #"(?is)<a[^>]*href=\"([^\"]+)\"[^>]*>\s*次へ\s*&?[^<]*</a>"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let match = String(html[range])
            if let hrefRange = match.range(of: #"href=\"([^\"]+)\""#, options: .regularExpression) {
                let href = String(match[hrefRange])
                    .replacingOccurrences(of: "href=\"", with: "")
                    .replacingOccurrences(of: "\"", with: "")
                return href.replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        if let href = firstHref(in: html, pattern: #"href=\"([^\"]*_eventId_(next|nextPage)[^\"]*)\""#) {
            return href
        }
        return nil
    }

    /// ページング: 前ページリンクを抽出する
    static func extractPrevPageHref(from html: String) -> String? {
        if let href = firstHref(in: html, pattern: #"<a[^>]*rel=\"prev\"[^>]*href=\"([^\"]+)\""#) {
            return href
        }
        if let href = firstHref(in: html, pattern: #"<a[^>]*href=\"([^\"]+)\"[^>]*>\s*前へ\s*[<>\w\W]*?</a>"#) {
            return href
        }
        if let href = firstHref(in: html, pattern: #"href=\"([^\"]*_eventId_(prev|prevPage)[^\"]*)\""#) {
            return href
        }
        return nil
    }

    /// 正規表現で最初にマッチした href の値を返す
    static func firstHref(in html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsrange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: nsrange),
              match.numberOfRanges >= 2,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
    }

    /// フォームフィールドを application/x-www-form-urlencoded 形式に変換する
    static func formURLEncoded(_ fields: [(String, String)]) -> String {
        fields
            .map { "\($0.urlEncoded)=\($1.urlEncoded)" }
            .joined(separator: "&")
    }

    /// お知らせを日付降順、同一日付はタイトル昇順でソートする
    static func sortAnnouncements(_ notices: [NoticeCard]) -> [NoticeCard] {
        notices.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.title < rhs.title
        }
    }
}

// MARK: - String拡張: URLエンコード

extension String {
    var urlEncoded: String {
        self.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}
