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
            
            // 取得した [Course] からグリッドを生成
            let newWeeklySchedule = buildGrid(from: fetchedWeeklyCourses)
            
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
        var grid = Array(repeating: Array(repeating: ClassCell.empty, count: 6), count: 6)
        let weekdayMap = ["月": 0, "火": 1, "水": 2, "木": 3, "金": 4, "土": 5]

        for course in rswCourses {
            // 曜日インデックスを取得
            // weekday は "月曜日" や "月" などの形式を想定
            let dayKey = String(course.weekday.prefix(1))
            guard let dayIdx = weekdayMap[dayKey] else { continue }
            
            // 時限インデックスを取得
            // period は "1限" や "1" などの形式を想定
            let pStr = course.period.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            if let p = Int(pStr), (1...6).contains(p) {
                grid[p - 1][dayIdx] = .filled(course.title, course.room)
            }
        }
        return grid
    }

    private func applyCourses(_ fetchedCourses: [Course]) {
        self.courses = fetchedCourses
        
        // 注意: ここでは weeklySchedule の更新は行いません。
        // RSWのデータを尊重し、PTWデータとの混同を防ぎます。
    }
}
