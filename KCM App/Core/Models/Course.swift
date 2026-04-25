import Foundation

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
