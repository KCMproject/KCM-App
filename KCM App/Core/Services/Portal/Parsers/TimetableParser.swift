import Foundation

enum TimetableParser {
    static func parseWeeklyTimetableFromRSW(from html: String) -> [Course] {
        var results: [Course] = []
        guard let tableHtml = HTMLParserHelpers.findTagWithClass("table", className: "rishu-koma", in: html) else {
            return []
        }
        let tbodyInner = HTMLParserHelpers.extractInnerOfFirstTag(tag: "tbody", from: tableHtml) ?? HTMLParserHelpers.extractInnerOfFirstTag(tag: "table", from: tableHtml) ?? ""
        let trs = HTMLParserHelpers.extractDirectChildTags(tag: "tr", in: tbodyInner)
        guard trs.count >= 1 else { return [] }
        let headerTds = HTMLParserHelpers.extractDirectChildTags(tag: "td", in: trs[0])
        var dayHeaders: [String] = []
        for i in 1..<headerTds.count {
            dayHeaders.append(HTMLParserHelpers.stripHtmlTags(from: headerTds[i]))
        }
        for rowIndex in 1..<trs.count {
            let rowHtml = trs[rowIndex]
            let tds = HTMLParserHelpers.extractDirectChildTags(tag: "td", in: rowHtml)
            if tds.isEmpty { continue }
            let jigenName = HTMLParserHelpers.stripHtmlTags(from: tds[0])
            if jigenName.isEmpty || jigenName.contains("曜") { continue }
            for tdIndex in 1..<tds.count {
                let dayIdx = tdIndex - 1
                if dayIdx >= dayHeaders.count { break }
                let weekday = dayHeaders[dayIdx]
                let cellHtml = tds[tdIndex]
                guard let innerTd = HTMLParserHelpers.findInnerMostTdOfClass("rishu-koma-inner", in: cellHtml) else {
                    continue
                }
                if innerTd.contains("未登録") { continue }
                let formatted = innerTd
                    .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: [.regularExpression])
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                let lines = formatted.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
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

    static func parseIntensiveCoursesFromRSW(from html: String) -> [IntensiveCourseCard] {
        guard let tableHtml = HTMLParserHelpers.findTagWithClass("table", className: "rishu-etc", in: html) else {
            return []
        }
        let tbodyInner = HTMLParserHelpers.extractInnerOfFirstTag(tag: "tbody", from: tableHtml) ?? tableHtml
        let rows = HTMLParserHelpers.extractDirectChildTags(tag: "tr", in: tbodyInner)
        var results: [IntensiveCourseCard] = []
        for rowHtml in rows {
            if rowHtml.contains("<th") || rowHtml.contains("曜日") || rowHtml.contains("開講科目名") {
                continue
            }
            let tds = HTMLParserHelpers.extractDirectChildTags(tag: "td", in: rowHtml)
            guard tds.count >= 5 else { continue }
            let cells = tds.map { HTMLParserHelpers.stripHtmlTags(from: HTMLParserHelpers.stripOuterTag(tag: "td", from: $0)) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let title = cells[safe: 3] ?? ""
            let instructor = cells[safe: 4] ?? ""
            let room = cells[safe: 6] ?? ""
            let day = cells[safe: 0] ?? ""
            let period = cells[safe: 1] ?? ""
            guard !title.isEmpty else { continue }
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
        return results
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
