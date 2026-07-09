import Foundation

enum UserProfileParser {
    static func parseUserName(from rswHtml: String) -> (fullName: String, reading: String)? {
        guard let nameRange = rswHtml.range(of: "氏名") else { return nil }
        let afterName = rswHtml[nameRange.upperBound...]
        guard let tdOpen = afterName.range(of: "<td"),
              let tdClose = afterName.range(of: "</td>", range: tdOpen.upperBound..<afterName.endIndex),
              let gtPos = afterName[tdOpen.upperBound..<tdClose.lowerBound].range(of: ">") else {
            return nil
        }
        let rawName = afterName[gtPos.upperBound..<tdClose.lowerBound]
        let fullName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "　", with: " ")
            .trimmingCharacters(in: .whitespaces)
        var reading = fullName
        if let kanaLabelRange = rswHtml.range(of: "学生氏名(カナ)") ?? rswHtml.range(of: "フリガナ") {
            let afterKana = rswHtml[kanaLabelRange.upperBound...]
            if let kanaTdOpen = afterKana.range(of: "<td"),
               let kanaTdClose = afterKana.range(of: "</td>", range: kanaTdOpen.upperBound..<afterKana.endIndex),
               let kanaGt = afterKana[kanaTdOpen.upperBound..<kanaTdClose.lowerBound].range(of: ">") {
                let rawKana = afterKana[kanaGt.upperBound..<kanaTdClose.lowerBound]
                let kana = rawKana.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "　", with: " ")
                    .trimmingCharacters(in: .whitespaces)
                if !kana.isEmpty { reading = kana }
            }
        }
        return (fullName, reading)
    }
}
