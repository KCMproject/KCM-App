import Foundation

enum TimetableSemester: String, CaseIterable, Codable {
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

struct Course: Identifiable, Hashable, Codable {
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
}
