import Foundation

/// CampusSquareのHTMLパースに特化したユーティリティ
enum CampusSquareParser {
    
    /// お知らせ一覧のパース
    static func parseAnnouncements(from html: String) -> [NoticeCard] {
        var results: [NoticeCard] = []
        let rowPattern = "<tr[^>]*>(.*?)</tr>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        
        let matches = rowRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        
        for match in matches {
            guard let rowRange = Range(match.range(at: 1), in: html) else { continue }
            let rowHtml = String(html[rowRange])
            
            let cellPattern = "<td[^>]*>(.*?)</td>"
            guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { continue }
            let cellMatches = cellRegex.matches(in: rowHtml, options: [], range: NSRange(location: 0, length: rowHtml.utf16.count))
            
            if cellMatches.count >= 4 {
                let dateFull = stripHtmlTags(from: extractCellContent(from: rowHtml, match: cellMatches[0]))
                let date = String(dateFull.prefix(10))
                
                let titleWithLink = extractCellContent(from: rowHtml, match: cellMatches[1])
                let title = stripHtmlTags(from: titleWithLink)
                
                let category = stripHtmlTags(from: extractCellContent(from: rowHtml, match: cellMatches[3]))
                
                let id = "\(title)_\(date)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
                
                if !title.isEmpty && !date.isEmpty && !title.contains("掲載日時") {
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
    
    /// 時間割のパース
    static func parseTimetable(from html: String) -> [Course] {
        var results: [Course] = []
        let cellPattern = "<td[^>]*class=\"[^\"]*timetable-(?:course|cell)[^\"]*\"[^>]*>(.*?)</td>"
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        
        let matches = cellRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        
        for match in matches {
            guard let cellRange = Range(match.range(at: 1), in: html) else { continue }
            let cellHtml = String(html[cellRange])
            
            let title = stripHtmlTags(from: extractTagContent(from: cellHtml, tag: "a") ?? "")
            let room = stripHtmlTags(from: extractTagContent(from: cellHtml, tag: "span", className: "room") ?? "")
            
            if !title.isEmpty {
                results.append(Course(
                    id: UUID(),
                    weekday: "", 
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
    
    /// スケジュール管理（カレンダー形式）のパース
    static func parseSchedule(from html: String) -> [Course] {
        var results: [Course] = []
        
        // カレンダーの各セル（<td>）を抽出
        // <td class="day ..."> または <td class="today ...">
        let cellPattern = "<td[^>]*class=\"(?:today|day|sat|sun)[^\"]*\"[^>]*>(.*?)</td>"
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        
        let matches = cellRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        
        // 曜日判定用（カレンダーは通常日〜土の順）
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        
        for (index, match) in matches.enumerated() {
            guard let cellRange = Range(match.range(at: 1), in: html) else { continue }
            let cellHtml = String(html[cellRange])
            
            // 曜日の特定（簡易的にインデックスから算出。実際はヘッダーと合わせる必要あり）
            let weekday = weekdays[index % 7]
            
            // セル内の個別スケジュール（.kaiko, .kyuko, .hoko 等のクラスを持つ要素）を抽出
            // <div class="kaiko">...</div> のような構造を想定
            let itemPattern = "<div[^>]*class=\"(kaiko|kyuko|hoko)[^\"]*\"[^>]*>(.*?)</div>"
            guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators]) else { continue }
            let itemMatches = itemRegex.matches(in: cellHtml, options: [], range: NSRange(location: 0, length: cellHtml.utf16.count))
            
            for itemMatch in itemMatches {
                guard let itemContentRange = Range(itemMatch.range(at: 2), in: cellHtml) else { continue }
                let itemHtml = String(cellHtml[itemContentRange])
                let statusType = String(cellHtml[Range(itemMatch.range(at: 1), in: cellHtml)!])
                
                // 講義名、教室、教員名をパース
                // 通常は <a>タイトル</a><br>教室 などの構造
                let title = stripHtmlTags(from: extractTagContent(from: itemHtml, tag: "a") ?? "")
                
                // 教室名はタイトルの後のテキストとして存在することが多い
                let room = extractRoomName(from: itemHtml)
                
                let status = (statusType == "kyuko") ? "休講" : (statusType == "hoko" ? "補講" : "")
                
                if !title.isEmpty {
                    results.append(Course(
                        id: UUID(),
                        weekday: weekday,
                        period: "", // カレンダー形式からは時限の特定が難しいため後で調整
                        title: title,
                        room: room,
                        status: status,
                        instructor: "",
                        nextClassInfo: "",
                        materials: [],
                        assignments: []
                    ))
                }
            }
        }
        return results
    }

    private static func extractRoomName(from html: String) -> String {
        // <a>...</a><br>教室名 のような構造から教室名を抽出
        let pattern = "</a><br[^>]*>(.*?)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
           let range = Range(match.range(at: 1), in: html) {
            return stripHtmlTags(from: String(html[range]))
        }
        return ""
    }
    
    private static func extractCellContent(from html: String, match: NSTextCheckingResult) -> String {
        guard let range = Range(match.range(at: 1), in: html) else { return "" }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractTagContent(from html: String, tag: String, className: String? = nil) -> String? {
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
    
    static func stripHtmlTags(from html: String) -> String {
        let pattern = "<[^>]+>"
        return html.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func extractHref(from html: String, withId id: String) -> String? {
        let pattern = "id=\"\(id)\".*?href=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) else {
            return nil
        }
        let hrefRange = match.range(at: 1)
        if let swiftRange = Range(hrefRange, in: html) {
            return String(html[swiftRange]).replacingOccurrences(of: "&amp;", with: "&")
        }
        return nil
    }
}
