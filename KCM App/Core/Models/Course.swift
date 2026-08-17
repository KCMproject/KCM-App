import Foundation

nonisolated enum TimetableSemester: String, CaseIterable, Codable {
    case first
    case second

    var displayName: String {
        switch self {
        case .first: return "前期"
        case .second: return "後期"
        }
    }

    var portalCode: String {
        switch self {
        case .first: return "1"
        case .second: return "2"
        }
    }

    static var current: Self {
        let month = Calendar.current.component(.month, from: Date())
        return (4...9).contains(month) ? .first : .second
    }
}

nonisolated struct Course: Identifiable, Hashable, Codable {
    let id: UUID
    let weekday: String
    let period: String
    let title: String
    let room: String
    let status: String
    let instructor: String
    let nextClassInfo: String
    let materials: [String]
    let assignments: [String]
    let startTime: String?
    let endTime: String?
    let dateString: String? // YYYY-MM-DD形式
    let scheduleNoteCategory: String?

    var isScheduleNote: Bool {
        scheduleNoteCategory != nil
    }

    init(
        id: UUID,
        weekday: String,
        period: String,
        title: String,
        room: String,
        status: String,
        instructor: String,
        nextClassInfo: String,
        materials: [String],
        assignments: [String],
        startTime: String?,
        endTime: String?,
        dateString: String?,
        scheduleNoteCategory: String? = nil
    ) {
        self.id = id
        self.weekday = weekday
        self.period = period
        self.title = title
        self.room = room
        self.status = status
        self.instructor = instructor
        self.nextClassInfo = nextClassInfo
        self.materials = materials
        self.assignments = assignments
        self.startTime = startTime
        self.endTime = endTime
        self.dateString = dateString
        self.scheduleNoteCategory = scheduleNoteCategory
    }
}
