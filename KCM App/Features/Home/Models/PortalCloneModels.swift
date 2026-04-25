import SwiftUI

struct DayEvent: Identifiable {
    let id: String
    let title: String
    let startTime: String
    let endTime: String
    let location: String
    let status: String

    // 計算済み分数（パフォーマンス最適化）
    let startMinutes: Int
    let endMinutes: Int

    init(title: String, startTime: String, endTime: String, location: String, status: String = "") {
        self.id = "\(title)|\(startTime)|\(endTime)|\(location)|\(status)"
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.location = location
        self.status = status
        self.startMinutes = Self.parseMinutes(startTime)
        self.endMinutes = Self.parseMinutes(endTime)
    }

    func layout(hourHeight: CGFloat, startHour: Int) -> (top: CGFloat, height: CGFloat) {
        let start = startMinutes - startHour * 60
        let end = endMinutes - startHour * 60
        return (
            top: CGFloat(start) * (hourHeight / 60),
            height: CGFloat(end - start) * (hourHeight / 60)
        )
    }

    private static func parseMinutes(_ time: String) -> Int {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return 0 }
        return parts[0] * 60 + parts[1]
    }
}

struct Period {
    let number: Int
    let start: String
    let end: String
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

struct IntensiveCourseCard: Identifiable {
    let id = UUID()
    let title: String
    let period: String
    let location: String
    let instructor: String
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

// MARK: - 曜日ラベル（一元管理）
enum WeekdayLabels {
    static let full = ["日", "月", "火", "水", "木", "金", "土"]
    static let weekdays = ["月", "火", "水", "木", "金", "土"]
}

struct NoticeCard: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let date: String
    let category: String
    let isPinned: Bool
    let content: String
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
        case toggle(Binding<Bool>)
        case link(() -> Void)
    }

    let icon: String
    let color: Color
    let title: String
    let subtitle: String?
    let kind: Kind

    static func toggle(_ icon: String, _ color: Color, _ title: String, _ subtitle: String?, _ binding: Binding<Bool>) -> Self {
        .init(icon: icon, color: color, title: title, subtitle: subtitle, kind: .toggle(binding))
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
