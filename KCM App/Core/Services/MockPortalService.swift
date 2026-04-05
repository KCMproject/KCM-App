import Foundation

struct MockPortalService: PortalSessionManaging {
    func fetchAnnouncements() -> [Announcement] {
        [
            Announcement(
                id: UUID(),
                title: "【重要】履修登録の修正期間",
                postedAt: "4/8 09:00",
                category: "教務",
                summary: "履修登録の修正期間が始まります。対象者は期限内にポータルから手続きを行ってください。",
                isRead: false
            ),
            Announcement(
                id: UUID(),
                title: "情報基礎レポート提出について",
                postedAt: "4/6 14:20",
                category: "授業",
                summary: "第1回レポートの提出先と形式を更新しました。資料欄も合わせて確認してください。",
                isRead: true
            )
        ]
    }

    func fetchCourses() -> [Course] {
        [
            Course(
                id: UUID(),
                weekday: "Mon",
                period: "1限",
                title: "情報基礎",
                room: "A201",
                status: "通常",
                instructor: "田中 教授",
                nextClassInfo: "次回は4/13。教科書第2章を事前に読む。",
                materials: ["第1回スライド", "配布資料 PDF"],
                assignments: ["レポート1: 4/15 23:59 締切"]
            ),
            Course(
                id: UUID(),
                weekday: "Tue",
                period: "3限",
                title: "データ構造",
                room: "B104",
                status: "補講予定",
                instructor: "徳田 准教授",
                nextClassInfo: "補講日はポータル掲示板で告知予定。",
                materials: ["木構造サンプルコード"],
                assignments: ["小テスト対策"]
            )
        ]
    }
}
