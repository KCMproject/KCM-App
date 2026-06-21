import Foundation

/// 週間時間割に授業が含まれているかを判定する
func weeklyScheduleHasContent(_ schedule: [[ClassCell]]) -> Bool {
    schedule.contains { row in
        row.contains { $0.title != nil }
    }
}
