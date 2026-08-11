import Foundation

nonisolated enum TimetableParser {
    static func parseWeeklyTimetableFromRSW(from html: String) -> [Course] {
        var results: [Course] = []
        guard let tableHtml = HTMLParserHelpers.findTagWithClass("table", className: "rishu-koma", in: html) else {
            return []
        }
        let tbodyInner = HTMLParserHelpers.extractInnerOfFirstTag(tag: "tbody", from: tableHtml) ?? HTMLParserHelpers.extractInnerOfFirstTag(tag: "table", from: tableHtml) ?? ""
        let trs = HTMLParserHelpers.extractDirectChildTags(tag: "tr", in: tbodyInner)
        guard trs.count >= 1 else { return [] }

        let dayNames = ["月", "火", "水", "木", "金", "土"]
        var seenCodes = Set<String>()

        for rowHtml in trs {
            let tds = HTMLParserHelpers.extractDirectChildTags(tag: "td", in: rowHtml)
            if tds.count < 8 { continue }

            let firstClass = HTMLParserHelpers.attributeValue("class", in: tds[0]) ?? ""
            let secondClass = HTMLParserHelpers.attributeValue("class", in: tds[1]) ?? ""
            let isPeriodRow = firstClass.contains("rishu-koma-head") && secondClass.contains("rishu-koma-head")
            guard isPeriodRow else { continue }

            let period = HTMLParserHelpers.stripHtmlTags(from: tds[0])
            if period.contains("曜") || period.isEmpty { continue }

            for dayIndex in 0..<6 {
                let cellIndex = 2 + dayIndex * 2
                guard cellIndex < tds.count else { break }
                let cellHtml = tds[cellIndex]
                let cellText = HTMLParserHelpers.stripHtmlTags(from: cellHtml)
                if cellText.isEmpty || cellText.contains("未登録") { continue }

                if let parsed = parseRSWCellText(cellText) {
                    let code = parsed.code
                    if seenCodes.contains(code) { continue }
                    seenCodes.insert(code)
                    let weekday = dayNames[dayIndex]
                    results.append(Course(
                        id: UUID(),
                        weekday: weekday,
                        period: period,
                        title: parsed.title,
                        room: parsed.room,
                        status: "",
                        instructor: parsed.instructor,
                        nextClassInfo: "",
                        materials: [],
                        assignments: [],
                        startTime: parsed.startTime,
                        endTime: parsed.endTime,
                        dateString: nil
                    ))
                }
            }
        }
        return results
    }

    private static func parseRSWCellText(_ text: String) -> (code: String, title: String, instructor: String, room: String, startTime: String?, endTime: String?)? {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 4 else { return nil }

        let code = parts[0]
        guard let creditIdx = parts.firstIndex(where: { $0.contains("単位") }) else { return nil }

        let titleInstructorParts = Array(parts[1..<creditIdx])
        guard titleInstructorParts.count >= 1 else { return nil }
        let instructor = titleInstructorParts.count >= 2 ? titleInstructorParts.last! : ""
        let title = titleInstructorParts.count >= 2
            ? titleInstructorParts.dropLast().joined(separator: " ")
            : titleInstructorParts.joined(separator: " ")

        let roomAndTimeParts = creditIdx + 1 < parts.count ? Array(parts[(creditIdx + 1)...]) : []
        var room = roomAndTimeParts.first ?? ""
        var startTime: String? = nil
        var endTime: String? = nil

        if roomAndTimeParts.count >= 2 {
            let combined = roomAndTimeParts.joined(separator: " ")
            let timePattern = "(\\d{1,2}:\\d{2})[〜～-](\\d{1,2}:\\d{2})"
            if let range = combined.range(of: timePattern, options: .regularExpression) {
                let matched = String(combined[range])
                let separators = CharacterSet(charactersIn: "〜～-")
                let timeParts = matched.components(separatedBy: separators).filter { !$0.isEmpty }
                if timeParts.count == 2 {
                    startTime = timeParts[0].trimmingCharacters(in: .whitespaces)
                    endTime = timeParts[1].trimmingCharacters(in: .whitespaces)
                }
                room = combined.replacingOccurrences(of: matched, with: "").trimmingCharacters(in: .whitespaces)
            }
        }

        return (code, title, instructor, room, startTime, endTime)
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
