import Foundation
import Combine

@MainActor
final class TimetableViewModel: ObservableObject {
    static let shared = TimetableViewModel(portalClient: PortalClientFactory.makeLoginService())
    
    @Published var courses: [Course] = []
    @Published var weeklySchedule: [[ClassCell]] = Array(repeating: Array(repeating: .empty, count: 5), count: 6)
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let portalClient: PortalClientProtocol

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func initialFetch() async {
        print("🚀 [Timetable] initialFetch 開始")
        isLoading = true
        errorMessage = nil

        do {
            print("📡 [Timetable] スケジュールデータの取得を開始...")
            let fetchedCourses = try await portalClient.fetchTimetable()
            print("✅ [Timetable] \(fetchedCourses.count) 件の講義を取得しました")
            
            // [Course] リストを [[ClassCell]] グリッドに変換
            var grid = Array(repeating: Array(repeating: ClassCell.empty, count: 5), count: 6)
            let weekdayMap = ["月": 0, "火": 1, "水": 2, "木": 3, "金": 4]
            
            for course in fetchedCourses {
                guard let dayIdx = weekdayMap[course.weekday] else { 
                    print("ℹ️ [Timetable] 曜日外（土日等）のためスキップ: \(course.title) (\(course.weekday))")
                    continue 
                }
                
                // カンマ区切りの時限を分割して処理
                let periods = course.period.split(separator: ",").compactMap { Int($0) }
                
                if !periods.isEmpty {
                    for periodInt in periods {
                        if periodInt >= 1 && periodInt <= 6 {
                            grid[periodInt - 1][dayIdx] = .filled(course.title, course.room)
                            print("📌 [Timetable] 配置成功: \(course.title) -> \(course.weekday)\(periodInt)限")
                        }
                    }
                } else {
                    print("⚠️ [Timetable] 時限が特定できませんでした: \(course.title)")
                }
            }
            
            await MainActor.run {
                self.courses = fetchedCourses
                self.weeklySchedule = grid
                self.isLoading = false
                print("🏁 [Timetable] グリッド反映完了")
            }
        } catch {
            await MainActor.run {
                print("❌ [Timetable] 取得失敗: \(error.localizedDescription)")
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}
