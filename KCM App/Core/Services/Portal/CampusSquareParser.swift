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
    
    /// 時間割のパース (RSW0001000 - 履修登録画面)
    static func parseWeeklyTimetable(from html: String) -> [[ClassCell]] {
        var grid: [[ClassCell]] = Array(repeating: Array(repeating: .empty, count: 5), count: 6)
        
        let rowPattern = "<tr[^>]*>(.*?)</tr>"
        guard let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators]) else { return grid }
        let rowMatches = rowRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        
        var periodIndex = 0
        for rowMatch in rowMatches {
            guard let rowRange = Range(rowMatch.range(at: 1), in: html) else { continue }
            let rowHtml = String(html[rowRange])
            
            if !rowHtml.contains("timetable-period") && !rowHtml.range(of: ">\\s*\\d\\s*<", options: .regularExpression).map({ _ in true })! { continue }
            if periodIndex >= 6 { break }
            
            let cellPattern = "<td[^>]*>(.*?)</td>"
            guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { continue }
            let cellMatches = cellRegex.matches(in: rowHtml, options: [], range: NSRange(location: 0, length: rowHtml.utf16.count))
            
            var dayIndex = 0
            for i in 1..<cellMatches.count {
                if dayIndex >= 5 { break }
                let cellContent = extractCellContent(from: rowHtml, match: cellMatches[i])
                if let title = extractTagContent(from: cellContent, tag: "a") {
                    let room = extractRoomNameFromCell(cellContent)
                    grid[periodIndex][dayIndex] = .filled(stripHtmlTags(from: title), room)
                }
                dayIndex += 1
            }
            periodIndex += 1
        }
        return grid
    }

    /// スケジュール管理（カレンダー形式）のパース (PTW0001200)
    static func parseSchedule(from html: String) -> [Course] {
        print("🕵️ [Parser] parseSchedule 開始 (HTMLサイズ: \(html.count))")
        var results: [Course] = []
        
        // カレンダーの各セル（<td>）を抽出
        let cellPattern = "<td[^>]*class=\"(?:today|day|sat|sun|kyujitsu|tokubetsukikan)[^\"]*\"[^>]*>(.*?)</td>"
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let matches = cellRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        print("🕵️ [Parser] \(matches.count) 個の日付セルを検出")
        
        for (index, match) in matches.enumerated() {
            guard let cellRange = Range(match.range(at: 1), in: html) else { continue }
            let cellHtml = String(html[cellRange])
            let weekday = weekdays[index % 7]
            
            // スケジュール項目（span class="kaiko/kyuko/hoko"）を抽出
            let itemPattern = "<span[^>]*class=\"(kaiko|kyuko|hoko)[^\"]*\"[^>]*>(.*?)</span>"
            guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators]) else { continue }
            let itemMatches = itemRegex.matches(in: cellHtml, options: [], range: NSRange(location: 0, length: cellHtml.utf16.count))
            
            for itemMatch in itemMatches {
                guard let itemContentRange = Range(itemMatch.range(at: 2), in: cellHtml) else { continue }
                let itemContentHtml = String(cellHtml[itemContentRange])
                let statusType = String(cellHtml[Range(itemMatch.range(at: 1), in: cellHtml)!])
                
                // HTMLタグを除去した純粋なテキスト (例: "1限:道徳指導論@5-121" or "【休講】3限:...")
                let fullText = stripHtmlTags(from: itemContentHtml)
                if fullText.isEmpty || fullText.contains("休日設定") || fullText.contains("特別期間") { continue }
                
                // 解析ロジック (時限:タイトル@教室)
                // 正規表現で分離: (時限)限?:(タイトル)@?(教室)?
                let parsePattern = "(?:.*?(\\d)限:)?([^@]+)(?:@(.+))?"
                var title = fullText
                var period = ""
                var room = ""
                
                if let pRegex = try? NSRegularExpression(pattern: parsePattern, options: []),
                   let pMatch = pRegex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)) {
                    
                    if let r1 = Range(pMatch.range(at: 1), in: fullText) { period = String(fullText[r1]) }
                    if let r2 = Range(pMatch.range(at: 2), in: fullText) { title = String(fullText[r2]).trimmingCharacters(in: .whitespacesAndNewlines) }
                    if let r3 = Range(pMatch.range(at: 3), in: fullText) { room = String(fullText[r3]).trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                
                // タイトルに時限が残っている場合の最終クリーンアップ
                if title.contains("】") {
                    title = title.components(separatedBy: "】").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? title
                }
                
                let status = statusType == "kyuko" ? "休講" : (statusType == "hoko" ? "補講" : "")
                
                if !title.isEmpty {
                    print("📖 [Parser] 抽出: \(title) | 曜日:\(weekday) | 時限:\(period) | 教室:\(room) | 状態:\(status)")
                    results.append(Course(id: UUID(), weekday: weekday, period: period, title: title, room: room, status: status, instructor: "", nextClassInfo: "", materials: [], assignments: []))
                }
            }
        }
        return results
    }

    // MARK: - 共通ヘルパー
    
    private static func extractCellContent(from html: String, match: NSTextCheckingResult) -> String {
        guard let range = Range(match.range(at: 1), in: html) else { return "" }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private static func extractTagContent(from html: String, tag: String, className: String? = nil) -> String? {
        let pattern = className != nil ? "<\(tag)[^>]*class=\"[^\"]*\(className!)[^\"]*\"[^>]*>(.*?)</\(tag)>" : "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }
    
    private static func extractPeriodsFromText(_ html: String) -> [Int] {
        var results: Set<Int> = []
        // "1限", "(1)", "(1-2)", "1-2限" などのパターン
        let patterns = ["(\\d)限", "\\((\\d)\\)", "(\\d)-(\\d)", "(\\d)〜(\\d)"]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
                for match in matches {
                    if match.numberOfRanges == 2 { // 単一の数字
                        if let range = Range(match.range(at: 1), in: html), let val = Int(html[range]) {
                            results.insert(val)
                        }
                    } else if match.numberOfRanges == 3 { // 範囲 (1-2)
                        if let r1 = Range(match.range(at: 1), in: html), let v1 = Int(html[r1]),
                           let r2 = Range(match.range(at: 2), in: html), let v2 = Int(html[r2]) {
                            for v in v1...v2 { results.insert(v) }
                        }
                    }
                }
            }
        }
        return Array(results).sorted()
    }

    private static func extractRoomNameFromScheduleItem(_ html: String) -> String {
        let parts = html.components(separatedBy: "<br")
        for part in parts {
            let stripped = stripHtmlTags(from: part)
            if !stripped.isEmpty && !stripped.contains("限") && !stripped.contains("(") && !stripped.contains("詳細") {
                return stripped
            }
        }
        return ""
    }

    private static func extractRoomNameFromCell(_ html: String) -> String {
        if let room = extractTagContent(from: html, tag: "span", className: "room") { return stripHtmlTags(from: room) }
        let pattern = "</a><br[^>]*>(.*?)$"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
           let range = Range(match.range(at: 1), in: html) { return stripHtmlTags(from: String(html[range])) }
        return ""
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
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
    }
}
