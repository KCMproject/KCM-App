import Foundation

enum FormFieldParser {
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

    static func extractHrefByFlow(from html: String, flowId: String) -> String? {
        let escapedFlowId = NSRegularExpression.escapedPattern(for: flowId)
        let pattern = "href\\s*=\\s*['\"]([^'\"]*_flowId=\(escapedFlowId)[^'\"]*)['\"]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: html.utf16.count)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
    }

    static func parseFormFields(from html: String, formID: String) -> [(String, String)] {
        let escapedID = NSRegularExpression.escapedPattern(for: formID)
        let formPattern = "<form[^>]*id\\s*=\\s*['\"]\(escapedID)['\"][^>]*>(.*?)</form>"
        guard let formBody = HTMLParserHelpers.firstMatch(in: html, pattern: formPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
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
                let type = HTMLParserHelpers.attributeValue("type", in: inputHTML)?.lowercased() ?? "text"
                guard type != "submit", type != "reset", type != "button" else { continue }
                fields.append((String(formBody[nameRange]), HTMLParserHelpers.attributeValue("value", in: inputHTML) ?? ""))
            }
        }
        let selectPattern = "<select[^>]*name\\s*=\\s*['\"]([^'\"]+)['\"][^>]*>(.*?)</select>"
        if let selectRegex = try? NSRegularExpression(pattern: selectPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            for match in selectRegex.matches(in: formBody, options: [], range: NSRange(location: 0, length: formBody.utf16.count)) {
                guard let nameRange = Range(match.range(at: 1), in: formBody),
                      let bodyRange = Range(match.range(at: 2), in: formBody) else {
                    continue
                }
                fields.append((String(formBody[nameRange]), HTMLParserHelpers.selectedOptionValue(in: String(formBody[bodyRange])) ?? ""))
            }
        }
        return fields
    }

    static func parseSelectValues(from html: String, formID: String, selectName: String) -> [String] {
        let escapedID = NSRegularExpression.escapedPattern(for: formID)
        let escapedName = NSRegularExpression.escapedPattern(for: selectName)
        let formPattern = "<form[^>]*id\\s*=\\s*['\"]\(escapedID)['\"][^>]*>(.*?)</form>"
        guard let formBody = HTMLParserHelpers.firstMatch(in: html, pattern: formPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let selectPattern = "<select[^>]*name\\s*=\\s*['\"]\(escapedName)['\"][^>]*>(.*?)</select>"
        guard let selectBody = HTMLParserHelpers.firstMatch(in: formBody, pattern: selectPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let optionPattern = "<option[^>]*value\\s*=\\s*['\"]([^'\"]*)['\"][^>]*>"
        guard let regex = try? NSRegularExpression(pattern: optionPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        return regex.matches(in: selectBody, options: [], range: NSRange(location: 0, length: selectBody.utf16.count)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: selectBody) else { return nil }
            return HTMLParserHelpers.decodeHtmlEntities(String(selectBody[range]))
        }
    }
}
