import Foundation

/// CampusSquareのHTMLパースに特化したユーティリティ
enum CampusSquareParser {
    struct NoticeGenreLink: Equatable {
        let title: String
        let keijitype: String
        let genrecd: String
        let href: String
    }
    
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
            if cellMatches.count >= 2 {
                let cells = cellMatches.map { extractCellContent(from: rowHtml, match: $0) }
                let cellTexts = cells.map { stripHtmlTags(from: $0) }
                guard let dateIndex = cellTexts.firstIndex(where: { $0.range(of: "\\d{4}/\\d{1,2}/\\d{1,2}", options: .regularExpression) != nil }) else {
                    continue
                }

                let dateFull = cellTexts[dateIndex]
                let date = firstMatch(in: dateFull, pattern: "(\\d{4}/\\d{1,2}/\\d{1,2})") ?? String(dateFull.prefix(10))

                guard let titleIndex = cells.indices.first(where: { cells[$0].range(of: "<a\\b", options: [.regularExpression, .caseInsensitive]) != nil }) else {
                    continue
                }

                let titleCellHtml = cells[titleIndex]
                let title = stripHtmlTags(from: titleCellHtml)

                var url: String?
                let hrefPattern = "href\\s*=\\s*['\"]([^'\"]+)['\"]"
                if let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive]),
                   let match = hrefRegex.firstMatch(in: titleCellHtml, options: [], range: NSRange(location: 0, length: titleCellHtml.utf16.count)),
                   let range = Range(match.range(at: 1), in: titleCellHtml) {
                    let extractedUrl = String(titleCellHtml[range])
                    url = decodeHtmlEntities(extractedUrl)
                }

                let category = parseNoticeCategory(from: Array(cellTexts.dropFirst(titleIndex + 1)))
                let id = "\(title)_\(date)".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
                if !title.isEmpty && !date.isEmpty && !title.contains("掲載日時") {
                    results.append(NoticeCard(id: id, title: title, date: date, category: category, url: url, attachments: nil, isPinned: rowHtml.contains("icon_pin") || rowHtml.contains("重要"), content: ""))
                }
            }
        }
        return results
    }

    static func parseNoticeAttachments(from html: String, baseURL: String) -> [NoticeAttachment] {
        let tablePattern = "<table[^>]*>\\s*<tbody>\\s*<tr[^>]*>\\s*<th[^>]*>\\s*添付ファイル\\s*</th>\\s*</tr>(.*?)</tbody>\\s*</table>"
        guard let tableBody = firstMatch(in: html, pattern: tablePattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            ?? attachmentTableBodyFallback(from: html) else {
            return []
        }

        let linkPattern = "<a[^>]*href\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>(.*?)</a>"
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        return linkRegex.matches(in: tableBody, options: [], range: NSRange(location: 0, length: tableBody.utf16.count)).compactMap { match in
            guard let hrefRange = Range(match.range(at: 1), in: tableBody),
                  let titleRange = Range(match.range(at: 2), in: tableBody) else {
                return nil
            }

            let href = String(tableBody[hrefRange]).replacingOccurrences(of: "&amp;", with: "&")
            let title = stripHtmlTags(from: String(tableBody[titleRange]))
            guard !title.isEmpty else { return nil }

            let urlString: String
            if href.hasPrefix("http") {
                urlString = href
            } else if href.hasPrefix("/") {
                urlString = URL(string: href, relativeTo: URL(string: baseURL))?.absoluteString ?? href
            } else {
                urlString = "\(baseURL)/\(href)"
            }

            return NoticeAttachment(id: urlString, title: title, url: urlString)
        }
    }

    private static func parseNoticeCategory(from candidates: [String]) -> String {
        if let category = candidates.first(where: { $0.contains("掲示板") }) {
            return category
        }

        return candidates.first { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "-" else { return false }
            guard trimmed.range(of: "\\d{4}/\\d{1,2}/\\d{1,2}", options: .regularExpression) == nil else {
                return false
            }
            guard !trimmed.contains("から"), !trimmed.contains("まで") else { return false }
            return true
        } ?? ""
    }

    private static func attachmentTableBodyFallback(from html: String) -> String? {
        guard let markerRange = html.range(of: "添付ファイル") else { return nil }
        var searchRange = html.startIndex..<markerRange.lowerBound
        var tableStart: String.Index?
        while let candidate = html.range(of: "<table", options: [.caseInsensitive], range: searchRange) {
            tableStart = candidate.lowerBound
            searchRange = candidate.upperBound..<markerRange.lowerBound
        }
        guard let tableStart,
              let tableHTML = extractFullTagBalanced(tag: "table", startingAt: tableStart, in: html) else {
            return nil
        }
        return tableHTML
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
            if jigenName.isEmpty || jigenName.contains("曜") { continue }
            
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
                    .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: [.regularExpression])
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                
                let lines = formatted.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                
                // 10. 【マッピング】: [科目コード, 科目名, 教員名, 単位数, 教室]
                if lines.count >= 2 {
                    let title = lines[1]
                    let instructor = lines.count > 2 ? lines[2] : ""
                    var room = lines.count > 4 ? lines[4] : (lines.count > 3 ? lines[3] : "")
                    
                    var startTime: String? = nil
                    var endTime: String? = nil
                    
                    for line in lines {
                        let timePattern = "(\\d{1,2}:\\d{2})[～〜-](\\d{1,2}:\\d{2})"
                        if let range = line.range(of: timePattern, options: .regularExpression) {
                            let parts = line[range].components(separatedBy: CharacterSet(charactersIn: "～〜-"))
                            if parts.count == 2 {
                                startTime = parts[0].trimmingCharacters(in: .whitespaces)
                                endTime = parts[1].trimmingCharacters(in: .whitespaces)
                                break
                            }
                        }
                    }
                    
                    if room.contains(":") || room.contains("～") {
                        if let r = lines.first(where: { $0.range(of: "[A-Z0-9]+-[A-Z0-9]+", options: .regularExpression) != nil }) {
                            room = r
                        } else {
                            room = ""
                        }
                    }
                    
                    print("📖 [Parser] RSW確定: \(weekday)曜\(jigenName) (Row:\(rowIndex-1), Col:\(dayIdx)) -> \(title) (@\(room))")
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
                        assignments: [],
                        startTime: startTime,
                        endTime: endTime,
                        dateString: nil
                    ))
                }
            }
        }
        return results
    }

    /// 集中講義テーブルのパース (rishu-etc)
    static func parseIntensiveCoursesFromRSW(from html: String) -> [IntensiveCourseCard] {
        print("🕵️ [Parser] parseIntensiveCoursesFromRSW 開始")
        guard let tableHtml = findTagWithClass("table", className: "rishu-etc", in: html) else {
            print("❌ [Parser] table.rishu-etc が見つかりません")
            return []
        }

        let tbodyInner = extractInnerOfFirstTag(tag: "tbody", from: tableHtml) ?? tableHtml
        let rows = extractDirectChildTags(tag: "tr", in: tbodyInner)
        var results: [IntensiveCourseCard] = []

        for rowHtml in rows {
            // ヘッダー行（thを含む、または「曜日」「開講科目名」などのヘッダテキストを含む）をスキップ
            if rowHtml.contains("<th") || rowHtml.contains("曜日") || rowHtml.contains("開講科目名") {
                continue
            }

            let tds = extractDirectChildTags(tag: "td", in: rowHtml)
            guard tds.count >= 5 else { continue }

            let cells = tds.map { stripHtmlTags(from: stripOuterTag(tag: "td", from: $0)) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            // cells: [曜日, 時限, コード, 科目名, 教員名, 単位, 教室]
            let title = cells[safe: 3] ?? ""
            let instructor = cells[safe: 4] ?? ""
            let room = cells[safe: 6] ?? ""
            let day = cells[safe: 0] ?? ""
            let period = cells[safe: 1] ?? ""

            guard !title.isEmpty else { continue }

            // 曜日と時限が両方「その他」の場合は空文字（表示しない）、そうでなければ「曜日 時限」
            let displayPeriod: String
            if day == "その他" && period == "その他" {
                displayPeriod = ""
            } else if !day.isEmpty && !period.isEmpty {
                displayPeriod = "\(day) \(period)"
            } else {
                displayPeriod = ""
            }

            results.append(IntensiveCourseCard(
                title: title,
                period: displayPeriod,
                location: room,
                instructor: instructor,
                dateRanges: [],
                startTime: nil,
                endTime: nil
            ))
        }

        print("🕵️ [Parser] 集中講義 \(results.count) 件を抽出")
        return results
    }

    /// スケジュール管理（カレンダー形式）のパース
    static func parseSchedule(from html: String) -> [Course] {
        print("🕵️ [Parser] parseSchedule 開始")
        var results: [Course] = []
        let cellPattern = "<td[^>]*class\\s*=\\s*['\"][^'\"]*(?:today|day|sat|sun|kyujitsu|tokubetsukikan)[^'\"]*['\"][^>]*>(.*?)</td>"
        guard let cellRegex = try? NSRegularExpression(pattern: cellPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { return [] }
        let matches = cellRegex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count))
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        
        for match in matches {
            guard let cellRange = Range(match.range(at: 1), in: html) else { continue }
            let cellHtml = String(html[cellRange])
            
            let datePattern = "addSchedule\\((\\d{4})(\\d{2})(\\d{2})\\)"
            guard let dateRegex = try? NSRegularExpression(pattern: datePattern, options: []),
                  let dateMatch = dateRegex.firstMatch(in: cellHtml, options: [], range: NSRange(location: 0, length: cellHtml.utf16.count)),
                  let yRange = Range(dateMatch.range(at: 1), in: cellHtml),
                  let mRange = Range(dateMatch.range(at: 2), in: cellHtml),
                  let dRange = Range(dateMatch.range(at: 3), in: cellHtml) else {
                continue
            }
            
            let year = Int(cellHtml[yRange]) ?? 0
            let month = Int(cellHtml[mRange]) ?? 0
            let day = Int(cellHtml[dRange]) ?? 0
            let dateString = String(format: "%04d-%02d-%02d", year, month, day)
            
            var components = DateComponents()
            components.year = year; components.month = month; components.day = day
            let calendar = Calendar(identifier: .gregorian)
            guard let date = calendar.date(from: components) else { continue }
            let weekday = weekdays[calendar.component(.weekday, from: date) - 1]
            
            let itemPattern = "<span[^>]*class\\s*=\\s*['\"]([^'\"]*(?:kaiko|kyuko|hoko)[^'\"]*)['\"][^>]*>(.*?)</span>"
            guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else { continue }
            let itemMatches = itemRegex.matches(in: cellHtml, options: [], range: NSRange(location: 0, length: cellHtml.utf16.count))
            
            for itemMatch in itemMatches {
                guard let classRange = Range(itemMatch.range(at: 1), in: cellHtml),
                      let itemContentRange = Range(itemMatch.range(at: 2), in: cellHtml) else { continue }
                
                let statusClass = String(cellHtml[classRange]).lowercased()
                let itemContentHtml = String(cellHtml[itemContentRange])
                let fullText = stripHtmlTags(from: itemContentHtml)
                if fullText.isEmpty { continue }

                if let note = parseScheduleNote(from: fullText) {
                    results.append(Course(
                        id: UUID(), weekday: weekday, period: "", title: note.body, room: "",
                        status: "", instructor: "", nextClassInfo: "", materials: [], assignments: [],
                        startTime: nil, endTime: nil, dateString: dateString,
                        scheduleNoteCategory: note.category
                    ))
                    continue
                }

                if fullText.contains("休日設定") || fullText.contains("特別期間") { continue }
                
                var title = fullText, period = "", room = ""
                var startTime: String? = nil, endTime: String? = nil

                let leadingTimePattern = "^\\s*(\\d{1,2}:\\d{2})[～〜-](\\d{1,2}:\\d{2})\\s*:?\\s*([^@]+)(?:@(.+))?\\s*$"
                if let timeRegex = try? NSRegularExpression(pattern: leadingTimePattern, options: []),
                   let timeMatch = timeRegex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)) {
                    if let r1 = Range(timeMatch.range(at: 1), in: fullText) { startTime = String(fullText[r1]) }
                    if let r2 = Range(timeMatch.range(at: 2), in: fullText) { endTime = String(fullText[r2]) }
                    if let r3 = Range(timeMatch.range(at: 3), in: fullText) {
                        title = String(fullText[r3]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if let r4 = Range(timeMatch.range(at: 4), in: fullText) {
                        room = String(fullText[r4]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if let startTime {
                        period = periodNumber(forStartTime: startTime)
                    }
                } else if let pRegex = try? NSRegularExpression(pattern: "(?:.*?(\\d)限)?(?:\\((\\d{1,2}:\\d{2})[～〜-](\\d{1,2}:\\d{2})\\))?:?([^@]+)(?:@(.+))?", options: []),
                   let pMatch = pRegex.firstMatch(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count)) {
                    if let r1 = Range(pMatch.range(at: 1), in: fullText) { period = String(fullText[r1]) }
                    if let r2 = Range(pMatch.range(at: 2), in: fullText) { startTime = String(fullText[r2]) }
                    if let r3 = Range(pMatch.range(at: 3), in: fullText) { endTime = String(fullText[r3]) }
                    if let r4 = Range(pMatch.range(at: 4), in: fullText) {
                        title = String(fullText[r4]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if title.hasPrefix(":") { title = String(title.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    if let r5 = Range(pMatch.range(at: 5), in: fullText) { room = String(fullText[r5]).trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                
                if title.contains("】") { title = title.components(separatedBy: "】").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? title }
                let status = statusClass.contains("kyuko") ? "休講" : (statusClass.contains("hoko") ? "補講" : "")
                
                if !title.isEmpty {
                    results.append(Course(
                        id: UUID(), weekday: weekday, period: period, title: title, room: room,
                        status: status, instructor: "", nextClassInfo: "", materials: [], assignments: [],
                        startTime: startTime, endTime: endTime, dateString: dateString
                    ))
                }
            }
        }
        return results
    }

    private static func periodNumber(forStartTime time: String) -> String {
        let minutes = minutes(from: time)
        switch minutes {
        case 9 * 60..<(10 * 60 + 40):
            return "1"
        case (10 * 60 + 40)..<(13 * 60):
            return "2"
        case (13 * 60)..<(14 * 60 + 40):
            return "3"
        case (14 * 60 + 40)..<(16 * 60 + 20):
            return "4"
        case (16 * 60 + 20)..<(18 * 60):
            return "5"
        case (18 * 60)...(22 * 60):
            return "6"
        default:
            return ""
        }
    }

    private static func minutes(from time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return -1 }
        return parts[0] * 60 + parts[1]
    }

    private static func parseScheduleNote(from text: String) -> (category: String, body: String)? {
        let pattern = "^[\\[［]([^\\]］]+)[\\]］]\\s*(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
              let categoryRange = Range(match.range(at: 1), in: text),
              let bodyRange = Range(match.range(at: 2), in: text) else {
            return nil
        }

        let category = String(text[categoryRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(text[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isEmpty else { return nil }
        return (category, body.isEmpty ? category : body)
    }

    // MARK: - ヘルパー関数 (DOMシミュレーション)

    private static func findTagWithClass(_ tag: String, className: String, in html: String) -> String? {
        let pattern = "<\(tag)[^>]*class\\s*=\\s*['\"][^'\"]*\(className)[^'\"]*['\"][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range, in: html) else {
            return nil
        }
        return extractFullTagBalanced(tag: tag, startingAt: range.lowerBound, in: html)
    }

    private static func findInnerMostTdOfClass(_ className: String, in html: String) -> String? {
        let pattern = "<table[^>]*class\\s*=\\s*['\"][^'\"]*\(className)[^'\"]*['\"]"
        guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        guard let tableFull = extractFullTagBalanced(tag: "table", startingAt: range.lowerBound, in: html) else { return nil }
        let tds = extractDirectChildTags(tag: "td", in: tableFull)
        return tds.first.map { stripOuterTag(tag: "td", from: $0) }
    }

    private static func extractFullTagBalanced(tag: String, startingAt: String.Index, in html: String) -> String? {
        guard let firstOpenBracket = html.range(of: "<", range: startingAt..<html.endIndex)?.lowerBound else { return nil }
        guard let contentStart = html.range(of: ">", range: firstOpenBracket..<html.endIndex)?.upperBound else { return nil }
        var depth = 0
        var scanRange = contentStart..<html.endIndex
        
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
                if let nextStart = html.index(openR.lowerBound, offsetBy: full.count, limitedBy: html.endIndex) {
                    scanRange = nextStart..<html.endIndex
                } else { break }
            } else {
                scanRange = openR.upperBound..<html.endIndex
            }
        }
        return results
    }

    private static func extractCellContent(from html: String, match: NSTextCheckingResult) -> String {
        guard let range = Range(match.range(at: 1), in: html) else { return "" }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in html: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    private static func attributeValue(_ name: String, in tagHTML: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\(escapedName)\\s*=\\s*['\"]([^'\"]*)['\"]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tagHTML, options: [], range: NSRange(location: 0, length: tagHTML.utf16.count)),
              let range = Range(match.range(at: 1), in: tagHTML) else {
            return nil
        }
        return decodeHtmlEntities(String(tagHTML[range]))
    }

    private static func selectedOptionValue(in selectBody: String) -> String? {
        let optionPattern = "<option[^>]*value\\s*=\\s*['\"]([^'\"]*)['\"][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: optionPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let matches = regex.matches(in: selectBody, options: [], range: NSRange(location: 0, length: selectBody.utf16.count))
        guard !matches.isEmpty else { return nil }

        let selectedMatch = matches.first { match in
            guard let optionRange = Range(match.range(at: 0), in: selectBody) else { return false }
            return selectBody[optionRange].localizedCaseInsensitiveContains("selected")
        } ?? matches[0]

        guard let valueRange = Range(selectedMatch.range(at: 1), in: selectBody) else {
            return nil
        }
        return decodeHtmlEntities(String(selectBody[valueRange]))
    }

    private static func decodeHtmlEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
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

    static func parseFormFields(from html: String, formID: String) -> [(String, String)] {
        let escapedID = NSRegularExpression.escapedPattern(for: formID)
        let formPattern = "<form[^>]*id\\s*=\\s*['\"]\(escapedID)['\"][^>]*>(.*?)</form>"
        guard let formBody = firstMatch(in: html, pattern: formPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        var fields: [(String, String)] = []
        let inputPattern = "<input[^>]*name\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>"
        if let inputRegex = try? NSRegularExpression(pattern: inputPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            for match in inputRegex.matches(in: formBody, options: [], range: NSRange(location: 0, length: formBody.utf16.count)) {
                guard let inputRange = Range(match.range(at: 0), in: formBody),
                      let nameRange = Range(match.range(at: 1), in: formBody) else {
                    continue
                }
                let inputHTML = String(formBody[inputRange])
                let type = attributeValue("type", in: inputHTML)?.lowercased() ?? "text"
                guard type != "submit", type != "reset", type != "button" else { continue }
                fields.append((String(formBody[nameRange]), attributeValue("value", in: inputHTML) ?? ""))
            }
        }

        let selectPattern = "<select[^>]*name\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>(.*?)</select>"
        if let selectRegex = try? NSRegularExpression(pattern: selectPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            for match in selectRegex.matches(in: formBody, options: [], range: NSRange(location: 0, length: formBody.utf16.count)) {
                guard let nameRange = Range(match.range(at: 1), in: formBody),
                      let bodyRange = Range(match.range(at: 2), in: formBody) else {
                    continue
                }
                fields.append((String(formBody[nameRange]), selectedOptionValue(in: String(formBody[bodyRange])) ?? ""))
            }
        }

        return fields
    }

    static func extractNoticeGenreLinks(from html: String) -> [NoticeGenreLink] {
        let linkPattern = "<a[^>]*href\\s*=\\s*['\"]([^'\"]*?_eventId=dispKeijiListGenre[^'\"]*)['\"][^>]*>(.*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        var links: [NoticeGenreLink] = []
        var seenKeys: Set<String> = []
        for match in regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let href = decodeHtmlEntities(String(html[hrefRange]))
            guard let keijitype = queryValue("keijitype", in: href),
                  let genrecd = queryValue("genrecd", in: href) else {
                continue
            }

            let key = "\(keijitype)/\(genrecd)"
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            links.append(NoticeGenreLink(
                title: stripHtmlTags(from: String(html[titleRange])),
                keijitype: keijitype,
                genrecd: genrecd,
                href: href
            ))
        }
        return links
    }

    static func parseSelectValues(from html: String, formID: String, selectName: String) -> [String] {
        let escapedID = NSRegularExpression.escapedPattern(for: formID)
        let escapedName = NSRegularExpression.escapedPattern(for: selectName)
        let formPattern = "<form[^>]*id\\s*=\\s*['\"]\(escapedID)['\"][^>]*>(.*?)</form>"
        guard let formBody = firstMatch(in: html, pattern: formPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let selectPattern = "<select[^>]*name\\s*=\\s*['\"]\(escapedName)['\"][^>]*>(.*?)</select>"
        guard let selectBody = firstMatch(in: formBody, pattern: selectPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let optionPattern = "<option[^>]*value\\s*=\\s*['\"]([^'\"]*)['\"][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: optionPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        return regex.matches(in: selectBody, options: [], range: NSRange(location: 0, length: selectBody.utf16.count)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: selectBody) else { return nil }
            return decodeHtmlEntities(String(selectBody[range]))
        }
    }

    private static func queryValue(_ name: String, in urlString: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?:[?&]|&amp;)\(escapedName)=([^&#]+)"
        guard let value = firstMatch(in: urlString, pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return decodeHtmlEntities(value)
    }

    static func parseSelectedTimetableSemester(from html: String) -> TimetableSemester? {
        let pattern = "title\\s*=\\s*['\"]([^'\"]*表示しています)['\"][^>]*>\\s*(?:<[^>]+>\\s*)*([^<]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              let titleRange = Range(match.range(at: 1), in: html),
              let textRange = Range(match.range(at: 2), in: html) else {
            return nil
        }
        let text = "\(html[titleRange]) \(html[textRange])"
        if text.contains("前期") { return .first }
        if text.contains("後期") { return .second }
        return nil
    }

    static func extractTimetableSemesterHref(from html: String, semester: TimetableSemester) -> String? {
        let escapedCode = NSRegularExpression.escapedPattern(for: semester.portalCode)
        let pattern = "href\\s*=\\s*['\"]([^'\"]*gakkiKbnCode=\(escapedCode)[^'\"]*)['\"][^>]*>\\s*\(semester.displayName)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
