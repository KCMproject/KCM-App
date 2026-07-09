import Foundation

enum ScheduleParser {
    static func parseSchedule(from html: String) -> [Course] {
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
                let fullText = HTMLParserHelpers.stripHtmlTags(from: itemContentHtml)
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
        case 9 * 60..<(10 * 60 + 40): return "1"
        case (10 * 60 + 40)..<(13 * 60): return "2"
        case (13 * 60)..<(14 * 60 + 40): return "3"
        case (14 * 60 + 40)..<(16 * 60 + 20): return "4"
        case (16 * 60 + 20)..<(18 * 60): return "5"
        case (18 * 60)...(22 * 60): return "6"
        default: return ""
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
}
