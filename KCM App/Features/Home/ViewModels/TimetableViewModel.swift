import Foundation
import Combine

@MainActor
final class TimetableViewModel: ObservableObject {
    static let shared = TimetableViewModel(portalClient: PortalClientFactory.makeLoginService())
    
    @Published var courses: [Course] = []
    @Published var weeklySchedule: [[ClassCell]] = Array(repeating: Array(repeating: .empty, count: 6), count: 6)
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    /// 土曜日に授業があるかどうか
    var hasSaturdayClass: Bool {
        weeklySchedule.contains { row in
            row.indices.contains(5) && row[5].title != nil
        }
    }

    private let portalClient: PortalClientProtocol
    private let cacheStore = PortalCacheStore.shared

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func loadCachedData() {
        let cachedCourses = cacheStore.loadCourses()
        guard !cachedCourses.isEmpty else { return }
        applyCourses(cachedCourses)
    }

    func initialFetch() async {
        _ = await refreshFromServer()
    }

    func refreshFromServer() async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            // 1. カレンダー用データの取得 (スケジュール管理) - 今日のタイムライン用
            async let fetchedCoursesTask = portalClient.fetchTimetable()
            // 2. 週間時間割グリッド用データの取得 (履修登録) - 週間時間割用
            async let fetchedWeeklyTask = portalClient.fetchWeeklyTimetable()
            
            let (fetchedCourses, fetchedWeeklyCourses) = try await (fetchedCoursesTask, fetchedWeeklyTask)
            
            print("📊 [TimetableViewModel] データ取得完了: 今日の予定 \(fetchedCourses.count)件, 週間 \(fetchedWeeklyCourses.count)件")
            
            // 1. まずは履修登録(RSW)のデータを優先してグリッドを構築
            var newWeeklySchedule = buildGrid(from: fetchedWeeklyCourses)
            
            // 2. 履修登録データが空の場合は、スケジュール管理(PTW)のデータからフォールバック構築
            if newWeeklySchedule.allSatisfy({ row in row.allSatisfy({ $0.title == nil }) }) {
                print("⚠️ [TimetableViewModel] 履修登録データが空のため、スケジュール管理データからグリッドを構築します")
                newWeeklySchedule = buildGrid(from: fetchedCourses)
            }
            
            let didUpdate = fetchedCourses != courses || newWeeklySchedule != weeklySchedule

            self.courses = fetchedCourses
            self.weeklySchedule = newWeeklySchedule
            
            cacheStore.saveCourses(fetchedCourses)
            isLoading = false
            return didUpdate
        } catch {
            print("❌ [TimetableViewModel] 更新エラー: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.isLoading = false
            return false
        }
    }

    private func buildGrid(from rswCourses: [Course]) -> [[ClassCell]] {
        print("🛠 [TimetableViewModel] グリッド構築開始 (\(rswCourses.count)件)")
        var grid = Array(repeating: Array(repeating: ClassCell.empty, count: 6), count: 6)
        let weekdayMap = ["月": 0, "火": 1, "水": 2, "木": 3, "金": 4, "土": 5]

        for course in rswCourses {
            // 曜日インデックスを取得 (prefix(1) を使うことで "月曜日" から "月" を抽出)
            let rawDay = course.weekday.trimmingCharacters(in: .whitespaces)
            let dayKey = String(rawDay.prefix(1))
            guard let dayIdx = weekdayMap[dayKey] else {
                print("⚠️ [TimetableViewModel] 曜日のマッピングに失敗: '\(rawDay)' -> key: '\(dayKey)'")
                continue
            }
            
            // 時限インデックスを取得 (数字部分のみ抽出。カンマ区切り等に対応)
            // 例: "1,2限" -> ["1", "2"]
            let pStr = course.period.replacingOccurrences(of: "[^0-9,]", with: "", options: .regularExpression)
            let periods = pStr.components(separatedBy: ",").compactMap { Int($0) }
            
            if periods.isEmpty {
                print("⚠️ [TimetableViewModel] 時限の抽出に失敗: '\(course.period)' -> pStr: '\(pStr)'")
                continue
            }

            for p in periods where (1...6).contains(p) {
                print("✅ [TimetableViewModel] マッピング成功: \(dayKey)曜\(p)限 -> \(course.title)")
                grid[p - 1][dayIdx] = .filled(course.title, course.room)
            }
        }
        
        // 土曜日のチェック
        let hasSat = grid.contains { $0.indices.contains(5) && $0[5].title != nil }
        print("📊 [TimetableViewModel] グリッド構築完了。土曜日の授業: \(hasSat ? "あり" : "なし")")
        
        return grid
    }

    private func applyCourses(_ fetchedCourses: [Course]) {
        self.courses = fetchedCourses
        
        // 注意: ここでは weeklySchedule の更新は行いません。
        // RSWのデータを尊重し、PTWデータとの混同を防ぎます。
    }
}
