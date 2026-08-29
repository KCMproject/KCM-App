import Foundation

/// お知らせの重要度（モーダルの色やアイコンを決める）
enum AnnouncementLevel: String, Codable {
    case info
    case warning
    case critical
}

/// GitHub 上の announcements.json から配信されるお知らせ
struct AppAnnouncement: Codable, Identifiable, Equatable {
    let id: String
    var level: AnnouncementLevel?
    let title: String
    let body: String
    var date: String?
    var active: Bool?

    var resolvedLevel: AnnouncementLevel { level ?? .info }
    var isActive: Bool { active ?? true }
}

/// announcements.json のトップレベル構造
struct AnnouncementFeed: Codable {
    var announcements: [AppAnnouncement]?

    /// 表示対象のおしらせ（日付の新しい順）
    var activeAnnouncements: [AppAnnouncement] {
        (announcements ?? [])
            .filter(\.isActive)
            .sorted { ($0.date ?? "") > ($1.date ?? "") }
    }
}
