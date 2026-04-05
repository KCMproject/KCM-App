import Foundation

struct Announcement: Identifiable, Hashable {
    let id: UUID
    let title: String
    let postedAt: String
    let category: String
    let summary: String
    let isRead: Bool
}
