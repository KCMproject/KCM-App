import Foundation

/// HTML 文字列に対する低レベルなタグ操作ヘルパー
enum HTMLParserHelpers {

    /// 指定タグ・クラス名を持つ要素全体を抽出する
    static func findTagWithClass(_ tag: String, className: String, in html: String) -> String? {
        let pattern = "<\(tag)[^>]*class\\s*=\\s*['\"][^'\"]*\(className)[^'\"]*['\"][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range, in: html) else {
            return nil
        }
        return extractFullTagBalanced(tag: tag, startingAt: range.lowerBound, in: html)
    }

    /// 指定クラスの table の最も内側の td コンテンツを取得する
    static func findInnerMostTdOfClass(_ className: String, in html: String) -> String? {
        let pattern = "<table[^>]*class\\s*=\\s*['\"][^'\"]*\(className)[^'\"]*['\"]"
        guard let range = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        guard let tableFull = extractFullTagBalanced(tag: "table", startingAt: range.lowerBound, in: html) else { return nil }
        let tds = extractDirectChildTags(tag: "td", in: tableFull)
        return tds.first.map { stripOuterTag(tag: "td", from: $0) }
    }

    /// 開始位置にあるタグに対応する終了タグまでの範囲を返す（入れ子に対応）
    static func extractFullTagBalanced(tag: String, startingAt: String.Index, in html: String) -> String? {
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

    /// 最初に見つかった指定タグの内部を取得する
    static func extractInnerOfFirstTag(tag: String, from html: String) -> String? {
        let openM = "<\(tag)"
        guard let openR = html.range(of: openM, options: .caseInsensitive) else { return nil }
        guard let full = extractFullTagBalanced(tag: tag, startingAt: openR.lowerBound, in: html) else { return nil }
        return stripOuterTag(tag: tag, from: full)
    }

    /// タグの外側（<tag...> と </tag>）を取り除く
    static func stripOuterTag(tag: String, from fullTag: String) -> String {
        guard let start = fullTag.range(of: ">")?.upperBound,
              let end = fullTag.range(of: "</\(tag)>", options: [.caseInsensitive, .backwards])?.lowerBound else {
            return fullTag
        }
        return String(fullTag[start..<end])
    }

    /// 指定タグの直下子要素をすべて抽出する
    static func extractDirectChildTags(tag: String, in html: String) -> [String] {
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

    /// NSTextCheckingResult のキャプチャグループ 1 の内容を取得する
    static func extractCellContent(from html: String, match: NSTextCheckingResult) -> String {
        guard let range = Range(match.range(at: 1), in: html) else { return "" }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 正規表現で最初にマッチしたキャプチャグループ 1 を返す
    static func firstMatch(in html: String, pattern: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range])
    }

    /// タグ属性の値を抽出する
    static func attributeValue(_ name: String, in tagHTML: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        let pattern = "\(escapedName)\\s*=\\s*['\"]([^'\"]*)['\"]"
        guard let value = firstMatch(in: tagHTML, pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return decodeHtmlEntities(value)
    }

    /// <select> 内の選択中オプション値を取得する
    static func selectedOptionValue(in selectBody: String) -> String? {
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

    /// 主な HTML エンティティをデコードする
    static func decodeHtmlEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    /// HTML タグを除去し、主要エンティティをデコードする
    static func stripHtmlTags(from html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: [.regularExpression])
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
