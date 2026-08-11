import Foundation

nonisolated enum AnnouncementParser {
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
                let cells = cellMatches.map { HTMLParserHelpers.extractCellContent(from: rowHtml, match: $0) }
                let cellTexts = cells.map { HTMLParserHelpers.stripHtmlTags(from: $0) }
                guard let dateIndex = cellTexts.firstIndex(where: { $0.range(of: "\\d{4}/\\d{1,2}/\\d{1,2}", options: .regularExpression) != nil }) else {
                    continue
                }
                let dateFull = cellTexts[dateIndex]
                let date = HTMLParserHelpers.firstMatch(in: dateFull, pattern: "(\\d{4}/\\d{1,2}/\\d{1,2})") ?? String(dateFull.prefix(10))
                guard let titleIndex = cells.indices.first(where: { cells[$0].range(of: "<a\\b", options: [.regularExpression, .caseInsensitive]) != nil }) else {
                    continue
                }
                let titleCellHtml = cells[titleIndex]
                let title = HTMLParserHelpers.stripHtmlTags(from: titleCellHtml)
                var url: String?
                let hrefPattern = "href\\s*=\\s*['\"]([^'\"]+)['\"]"
                if let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive]),
                   let match = hrefRegex.firstMatch(in: titleCellHtml, options: [], range: NSRange(location: 0, length: titleCellHtml.utf16.count)),
                   let range = Range(match.range(at: 1), in: titleCellHtml) {
                    let extractedUrl = String(titleCellHtml[range])
                    url = HTMLParserHelpers.decodeHtmlEntities(extractedUrl)
                }
                let category = parseNoticeCategory(from: cellTexts)
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
        guard let tableBody = HTMLParserHelpers.firstMatch(in: html, pattern: tablePattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
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
            let title = HTMLParserHelpers.stripHtmlTags(from: String(tableBody[titleRange]))
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

    static func extractNoticeGenreLinks(from html: String) -> [CampusSquareParser.NoticeGenreLink] {
        let linkPattern = "<a[^>]*href\\s*=\\s*['\"]([^'\"]*?_eventId=dispKeijiListGenre[^'\"]*)['\"][^>]*>(.*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        var links: [CampusSquareParser.NoticeGenreLink] = []
        var seenKeys: Set<String> = []
        for match in regex.matches(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)) {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let href = HTMLParserHelpers.decodeHtmlEntities(String(html[hrefRange]))
            guard let keijitype = queryValue("keijitype", in: href),
                  let genrecd = queryValue("genrecd", in: href) else {
                continue
            }
            let key = "\(keijitype)/\(genrecd)"
            guard !seenKeys.contains(key) else { continue }
            seenKeys.insert(key)
            links.append(CampusSquareParser.NoticeGenreLink(
                title: HTMLParserHelpers.stripHtmlTags(from: String(html[titleRange])),
                keijitype: keijitype,
                genrecd: genrecd,
                href: href
            ))
        }
        return links
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
              let tableHTML = HTMLParserHelpers.extractFullTagBalanced(tag: "table", startingAt: tableStart, in: html) else {
            return nil
        }
        return tableHTML
    }

    private static func queryValue(_ name: String, in urlString: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "(?:[?&]|&amp;)\(escapedName)=([^&#]+)"
        guard let value = HTMLParserHelpers.firstMatch(in: urlString, pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return HTMLParserHelpers.decodeHtmlEntities(value)
    }
}
