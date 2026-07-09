import SwiftUI

struct DayEvent: Identifiable {
    let id: String
    let title: String
    let startTime: String
    let endTime: String
    let location: String
    let classroomKey: String?
    let status: String
    let isIntensive: Bool

    // 計算済み分数（パフォーマンス最適化）
    let startMinutes: Int
    let endMinutes: Int

    init(title: String, startTime: String, endTime: String, location: String, status: String = "", classroomKey: String? = nil, isIntensive: Bool = false) {
        self.id = "\(title)|\(startTime)|\(endTime)|\(location)|\(status)"
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.classroomKey = classroomKey
        self.status = status
        self.isIntensive = isIntensive
        self.startMinutes = DayEvent.minutes(from: startTime)
        self.endMinutes = DayEvent.minutes(from: endTime)
    }

    private static func minutes(from time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }

    func layout(hourHeight: CGFloat, startHour: Int) -> (top: CGFloat, height: CGFloat) {
        let start = startMinutes - startHour * 60
        let end = endMinutes - startHour * 60
        let rawHeight = CGFloat(end - start) * (hourHeight / 60)
        return (
            top: CGFloat(start) * (hourHeight / 60),
            height: max(rawHeight, 1)
        )
    }

}

struct Period {
    let number: Int
    let start: String
    let end: String

    /// 大学の標準的な授業時間（1〜6限）
    static let standardPeriods: [Period] = [
        .init(number: 1, start: "09:00", end: "10:30"),
        .init(number: 2, start: "10:40", end: "12:10"),
        .init(number: 3, start: "13:00", end: "14:30"),
        .init(number: 4, start: "14:40", end: "16:10"),
        .init(number: 5, start: "16:20", end: "17:50"),
        .init(number: 6, start: "18:00", end: "19:30")
    ]
}

struct WeekdayColumn {
    let label: String
}

struct ClassCell: Equatable {
    let title: String?
    let room: String?

    static var empty: Self { .init(title: nil, room: nil) }

    static func filled(_ title: String, _ room: String) -> Self {
        .init(title: title, room: room)
    }
}

struct DateRange: Identifiable, Codable, Equatable {
    let id: UUID
    var startDate: String         // "yyyy-MM-dd"
    var endDate: String           // "yyyy-MM-dd"
    var startTime: String?        // "HH:mm"
    var endTime: String?          // "HH:mm"

    init(startDate: String, endDate: String, startTime: String? = nil, endTime: String? = nil) {
        self.id = UUID()
        self.startDate = startDate
        self.endDate = endDate
        self.startTime = startTime
        self.endTime = endTime
    }

    var dates: [String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: startDate),
              let end = formatter.date(from: endDate) else { return [startDate] }
        var result: [String] = []
        var current = start
        while current <= end {
            result.append(formatter.string(from: current))
            guard let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    /// 開始日〜終了日の表示用文字列
    var formatted: String {
        if startDate == endDate { return startDate }
        return "\(startDate) 〜 \(endDate)"
    }
}

struct IntensiveCourseCard: Identifiable, Codable, Equatable {
    var id: UUID
    let title: String
    let period: String
    var location: String
    let instructor: String
    var dateRanges: [DateRange]
    var startTime: String?
    var endTime: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, period, location, instructor, dateRanges, dates, startTime, endTime
    }

    var allDates: [String] {
        dateRanges.flatMap { $0.dates }
    }

    init(title: String, period: String, location: String, instructor: String, dateRanges: [DateRange] = [], startTime: String? = nil, endTime: String? = nil) {
        self.id = UUID()
        self.title = title
        self.period = period
        self.location = location
        self.instructor = instructor
        self.dateRanges = dateRanges
        self.startTime = startTime
        self.endTime = endTime
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(period, forKey: .period)
        try container.encode(location, forKey: .location)
        try container.encode(instructor, forKey: .instructor)
        try container.encode(dateRanges, forKey: .dateRanges)
        try container.encodeIfPresent(startTime, forKey: .startTime)
        try container.encodeIfPresent(endTime, forKey: .endTime)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.period = try container.decode(String.self, forKey: .period)
        self.location = try container.decode(String.self, forKey: .location)
        self.instructor = try container.decode(String.self, forKey: .instructor)
        self.startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        self.endTime = try container.decodeIfPresent(String.self, forKey: .endTime)

        if let ranges = try container.decodeIfPresent([DateRange].self, forKey: .dateRanges) {
            self.dateRanges = ranges
        } else {
            if let dates = try container.decodeIfPresent([String].self, forKey: .dates), !dates.isEmpty {
                let sorted = dates.sorted()
                guard let first = sorted.first, let last = sorted.last else { self.dateRanges = []; return }
                let start = try container.decodeIfPresent(String.self, forKey: .startTime)
                let end = try container.decodeIfPresent(String.self, forKey: .endTime)
                self.dateRanges = [DateRange(startDate: first, endDate: last, startTime: start, endTime: end)]
            } else {
                self.dateRanges = []
            }
        }
    }
}

struct LessonCard: Identifiable {
    let id = UUID()
    let title: String
    let schedule: String
    let location: String
    let instructor: String
}

struct IrregularScheduleSection: Identifiable {
    let id = UUID()
    let title: String
    let courses: [IntensiveCourseCard]
}

enum NoticeSort {
    case date
    case category
}

// MARK: - アニメーション方向
enum TransitionDirection: Equatable {
    case left, right, none
}

// MARK: - 曜日ラベル（一元管理）
enum WeekdayLabels {
    static let full = ["日", "月", "火", "水", "木", "金", "土"]
    static let weekdays = ["月", "火", "水", "木", "金", "土"]
}

struct NoticeAttachment: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let url: String
}

struct NoticeCard: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let date: String
    let category: String
    let url: String?
    let attachments: [NoticeAttachment]?
    let isPinned: Bool
    let content: String

    var hasAttachments: Bool {
        !(attachments ?? []).isEmpty
    }

    func withAttachments(_ attachments: [NoticeAttachment]?) -> NoticeCard {
        NoticeCard(
            id: id,
            title: title,
            date: date,
            category: category,
            url: url,
            attachments: attachments,
            isPinned: isPinned,
            content: content
        )
    }
}

struct MessageThread: Identifiable, Equatable {
    enum Status {
        case online
        case offline
    }

    let id = UUID()
    let name: String
    let avatar: String
    let sharedCourse: String
    let lastMessage: String
    let lastTime: String
    let unread: Int
    let status: Status
    let messages: [ChatMessage]
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let fromMe: Bool
    let text: String
    let time: String
}

struct SettingRow {
    enum Kind {
        case toggle(String)
        case link(() -> Void)
    }

    let icon: String
    let color: Color
    let title: String
    let subtitle: String?
    let kind: Kind

    static func toggle(_ icon: String, _ color: Color, _ title: String, _ subtitle: String?, _ id: String) -> Self {
        .init(icon: icon, color: color, title: title, subtitle: subtitle, kind: .toggle(id))
    }

    static func link(_ icon: String, _ color: Color, _ title: String, _ subtitle: String?, _ action: @escaping () -> Void) -> Self {
        .init(icon: icon, color: color, title: title, subtitle: subtitle, kind: .link(action))
    }
}

extension Date {
    func startOfWeek(calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: self)
        return calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: self)) ?? self
    }
}
