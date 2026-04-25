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
                let title = stripHtmlTags(from: extractCellContent(from: rowHtml, match: cellMatches[1]))
                let category = stripHtmlTags(from: extractCellContent(from: rowHtml, match: cellMatches[3]))
                let id = "\(title)_\(date)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
                if !title.isEmpty && !date.isEmpty && !title.contains("掲載日時") {
                    results.append(NoticeCard(id: id, title: title, date: date, category: category, isPinned: rowHtml.contains("icon_pin") || rowHtml.contains("重要"), content: ""))
                }
            }
        }
        return results
    }
    
    /// 時間割のパース (RSW0001000 - 履修登録画面)
    /// 指定された10項目の手順を忠実に再現
    static func parseWeeklyTimetableFromRSW(from html: String) -> [Course] {
        print("🕵️ [Parser] parseWeeklyTimetableFromRSW 開始")
        var results: [Course] = []
        
        // 1. 【対象テーブル】: table.rishu-koma を抽出
        guard let tableHtml = findTagWithClass("table", className: "rishu-koma", in: html) else {
            print("❌ [Parser] table.rishu-koma が見つかりません")
            return []
        }
        
        // 2. 【行の取得】: tbody > tr をすべて取得 (直下要素のみ)
        let tbodyInner = extractInnerOfFirstTag(tag: "tbody", from: tableHtml) ?? extractInnerOfFirstTag(tag: "table", from: tableHtml) ?? ""
        let trs = extractDirectChildTags(tag: "tr", in: tbodyInner)
        print("🕵️ [Parser] \(trs.count) 行の tr を検出")
        
        guard trs.count >= 1 else { return [] }
        
        // 3. 【曜日ヘッダー】: 1行目の tr の、2つ目以降の直下 td
        let headerTds = extractDirectChildTags(tag: "td", in: trs[0])
        var dayHeaders: [String] = []
        for i in 1..<headerTds.count {
            dayHeaders.append(stripHtmlTags(from: headerTds[i]))
        }
        print("🕵️ [Parser] 曜日ヘッダー: \(dayHeaders)")

        // 4. 【時限ループ】: 2行目以降の tr を処理
        for rowIndex in 1..<trs.count {
            let rowHtml = trs[rowIndex]
            let tds = extractDirectChildTags(tag: "td", in: rowHtml)
            if tds.isEmpty { continue }
            
            // 5. 【時限名】: 最初の直下 td
            let jigenName = stripHtmlTags(from: tds[0])
            if jigenName.isEmpty || jigenName.contains("曜") { continue } // ヘッダー行や空行のスキップ
            
            // 6. 【コマデータ】: 2つ目以降の td をループ
            for tdIndex in 1..<tds.count {
                let dayIdx = tdIndex - 1
                if dayIdx >= dayHeaders.count { break }
                let weekday = dayHeaders[dayIdx]
                
                let cellHtml = tds[tdIndex]
                
                // 7. 【科目詳細の抽出】: .rishu-koma-inner td を取得
                guard let innerTd = findInnerMostTdOfClass("rishu-koma-inner", in: cellHtml) else {
                    continue
                }
                
                // 8. 【スキップ条件】: 「未登録」が含まれている場合はスキップ
                if innerTd.contains("未登録") { continue }
                
                // 9. 【テキストの分割】: <br> を \n に置換し、split
                let formatted = innerTd
                    .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                
                let lines = formatted.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                // 10. 【マッピング】: [科目コード, 科目名, 教員名, 単位数, 教室]
                if lines.count >= 2 {
                    let code = lines[0]
                    let title = lines[1]
                    let instructor = lines.count > 2 ? lines[2] : ""
                    let room = lines.last ?? ""
                    
                    print("📖 [Parser] RSW確定: \(weekday)曜\(jigenName) -> \(title) (@\(room))")
                    results.append(Course(
                        id: UUID(),
                        weekday: weekday,
                        period: jigenName,
                        title: title,
                        room: room,
                        status: "",
                        instructor: instructor,
                        nextClassInfo: "",
                        materials: [],
                        assignments: []
                    ))
                }
            }
        }
        return results
    }

    /// スケジュール管理（カレンダー形式）のパース (Turn 17 / Turn 23 ベースの正常動作版)
    static func parseSchedule(from html: String) -> [Course] {
        print("🕵️ [Parser] parseSchedule 開始 (HTMLサイズ: \(html.count))")
        var results: [Course] = []
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
                let fullText = stripHtmlTags(from: itemContentHtml)
                if fullText.isEmpty || fullText.contains("休日設定") || fullText.contains("特別期間") { continue }
                
                let parsePattern = "(?:.*?(\\d)限:)?([^@]+)(?:@(.+))?"
                var title = fullText, period = "", room = ""
                if let pRegex = try? NSRegularExpression(pattern: parsePattern, options: []),
                   let pMatch = pRegex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)) {
                    if let r1 = Range(pMatch.range(at: 1), in: fullText) { period = String(fullText[r1]) }
                    if let r2 = Range(pMatch.range(at: 2), in: fullText) { title = String(fullText[r2]).trimmingCharacters(in: .whitespacesAndNewlines) }
                    if let r3 = Range(pMatch.range(at: 3), in: fullText) { room = String(fullText[r3]).trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                if title.contains("】") { title = title.components(separatedBy: "】").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? title }
                let status = statusType == "kyuko" ? "休講" : (statusType == "hoko" ? "補講" : "")
                if !title.isEmpty {
                    results.append(Course(id: UUID(), weekday: weekday, period: period, title: title, room: room, status: status, instructor: "", nextClassInfo: "", materials: [], assignments: []))
                }
            }
        }
        return results
    }

    // MARK: - ヘルパー関数 (DOMシミュレーション)

    private static func findTagWithClass(_ tag: String, className: String, in html: String) -> String? {
        let pattern = "<\(tag)[^>]*class\\s*=\\s*['\"][^'\"]*\(className)[^'\"]*['\"]"
        guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return extractFullTagBalanced(tag: tag, startingAt: range.lowerBound, in: html)
    }

    private static func findInnerMostTdOfClass(_ className: String, in html: String) -> String? {
        let pattern = "<table[^>]*class\\s*=\\s*['\"][^'\"]*\(className)[^'\"]*['\"]"
        guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        guard let tableFull = extractFullTagBalanced(tag: "table", startingAt: range.lowerBound, in: html) else { return nil }
        // そのテーブルの中の最初の td
        let tds = extractDirectChildTags(tag: "td", in: tableFull)
        return tds.first.map { stripOuterTag(tag: "td", from: $0) }
    }

    private static func extractFullTagBalanced(tag: String, startingAt: String.Index, in html: String) -> String? {
        guard let firstOpenBracket = html.range(of: "<", range: startingAt..<html.endIndex)?.lowerBound else { return nil }
        guard let contentStart = html.range(of: ">", range: firstOpenBracket..<html.endIndex)?.upperBound else { return nil }
        var depth = 0
        var scanRange = contentStart..<html.endIndex
        let openM = "<\(tag)", closeM = "</\(tag)>"
        
        while let nextTag = html.range(of: "<", range: scanRange) {
            let snippet = html[nextTag.upperBound...].lowercased()
            if snippet.hasPrefix("/\(tag.lowercased())") {
                if depth == 0 {
                    let tagEnd = html.range(of: ">", range: nextTag.lowerBound..<html.endIndex)!.upperBound
                    return String(html[firstOpenBracket..<tagEnd])
                }
                depth -= 1
            } else if snippet.hasPrefix(tag.lowercased()) {
                depth += 1
            }
            scanRange = html.index(after: nextTag.lowerBound)..<html.endIndex
        }
        return nil
    }

    private static func extractInnerOfFirstTag(tag: String, from html: String) -> String? {
        let openM = "<\(tag)"
        guard let openR = html.range(of: openM, options: .caseInsensitive) else { return nil }
        guard let full = extractFullTagBalanced(tag: tag, startingAt: openR.lowerBound, in: html) else { return nil }
        return stripOuterTag(tag: tag, from: full)
    }

    private static func stripOuterTag(tag: String, from fullTag: String) -> String {
        guard let start = fullTag.range(of: ">")?.upperBound,
              let end = fullTag.range(of: "</\(tag)>", options: [.caseInsensitive, .backwards])?.lowerBound else { return fullTag }
        return String(fullTag[start..<end])
    }

    private static func extractDirectChildTags(tag: String, in html: String) -> [String] {
        var results: [String] = []
        var scanRange = html.startIndex..<html.endIndex
        let openM = "<\(tag)"
        
        while let openR = html.range(of: openM, options: .caseInsensitive, range: scanRange) {
            if let full = extractFullTagBalanced(tag: tag, startingAt: openR.lowerBound, in: html) {
                results.append(full)
                // 次の検索は、現在のタグの終了後から開始
                scanRange = html.index(html.startIndex, offsetBy: html.distance(from: html.startIndex, to: openR.lowerBound) + full.count)..<html.endIndex
            } else {
                scanRange = openR.upperBound..<html.endIndex
            }
        }
        return results
    }

    private static func extractRoomName(from html: String) -> String {
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
        let pattern = className != nil ? "<\(tag)[^>]*class=\"[^\"]*\(className!)[^\"]*\"[^>]*>(.*?)</\(tag)>" : "<\(tag)[^>]*>(.*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[range])
    }

    static func stripHtmlTags(from html: String) -> String {
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    static func extractHref(from html: String, withId id: String) -> String? {
        let pattern = "id\\s*=\\s*['\"]\(id)['\"][^>]*href\\s*=\\s*['\"]([^'\"]+)['\"]"
        let patternAlt = "href\\s*=\\s*['\"]([^'\"]+)['\"][^>]*id\\s*=\\s*['\"]\(id)['\"]"
        for p in [pattern, patternAlt] {
            if let regex = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]),
               let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        return nil
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
