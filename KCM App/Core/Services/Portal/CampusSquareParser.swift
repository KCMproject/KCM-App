import Foundation

/// CampusSquareのHTMLパースに特化したユーティリティ（Facade）
nonisolated enum CampusSquareParser {
    struct NoticeGenreLink: Equatable {
        let title: String
        let keijitype: String
        let genrecd: String
        let href: String
    }

    static func parseAnnouncements(from html: String) -> [NoticeCard] {
        AnnouncementParser.parseAnnouncements(from: html)
    }

    static func parseNoticeAttachments(from html: String, baseURL: String) -> [NoticeAttachment] {
        AnnouncementParser.parseNoticeAttachments(from: html, baseURL: baseURL)
    }

    static func extractNoticeGenreLinks(from html: String) -> [NoticeGenreLink] {
        AnnouncementParser.extractNoticeGenreLinks(from: html)
    }

    static func parseWeeklyTimetableFromRSW(from html: String) -> [Course] {
        TimetableParser.parseWeeklyTimetableFromRSW(from: html)
    }

    static func parseIntensiveCoursesFromRSW(from html: String) -> [IntensiveCourseCard] {
        TimetableParser.parseIntensiveCoursesFromRSW(from: html)
    }

    static func parseSelectedTimetableSemester(from html: String) -> TimetableSemester? {
        TimetableParser.parseSelectedTimetableSemester(from: html)
    }

    static func extractTimetableSemesterHref(from html: String, semester: TimetableSemester) -> String? {
        TimetableParser.extractTimetableSemesterHref(from: html, semester: semester)
    }

    static func parseSchedule(from html: String) -> [Course] {
        ScheduleParser.parseSchedule(from: html)
    }

    static func extractHref(from html: String, withId id: String) -> String? {
        FormFieldParser.extractHref(from: html, withId: id)
    }

    static func extractHrefByFlow(from html: String, flowId: String) -> String? {
        FormFieldParser.extractHrefByFlow(from: html, flowId: flowId)
    }

    static func parseFormFields(from html: String, formID: String) -> [(String, String)] {
        FormFieldParser.parseFormFields(from: html, formID: formID)
    }

    static func parseSelectValues(from html: String, formID: String, selectName: String) -> [String] {
        FormFieldParser.parseSelectValues(from: html, formID: formID, selectName: selectName)
    }

    static func parseUserName(from rswHtml: String) -> (fullName: String, reading: String)? {
        UserProfileParser.parseUserName(from: rswHtml)
    }
}

extension Array {
    nonisolated subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
