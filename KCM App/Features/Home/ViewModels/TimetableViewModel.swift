import Foundation
import Combine

@MainActor
final class TimetableViewModel: ObservableObject {
    static let shared = TimetableViewModel(portalClient: PortalClientFactory.makeLoginService())
    
    @Published var courses: [Course] = []
    @Published var weeklySchedule: [[ClassCell]] = Array(repeating: Array(repeating: .empty, count: 6), count: 6)
    @Published var intensiveCourses: [IntensiveCourseCard] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedSemester: TimetableSemester = {
        if let raw = UserDefaults.standard.string(forKey: AppSettings.lastViewedSemester),
           let saved = TimetableSemester(rawValue: raw) {
            return saved
        }
        return .current
    }()
    
    /// 土曜日に授業があるかどうか（RSWの生データを直接見て、フォールバックデータによる誤検出を防ぐ）
    var hasSaturdayClass: Bool {
        let cachedWeeklyCourses = cacheStore.loadWeeklyCourses(for: selectedSemester)
        return cachedWeeklyCourses.contains { course in
            let rawDay = course.weekday.trimmingCharacters(in: .whitespaces)
            return String(rawDay.prefix(1)) == "土"
        }
    }

    private let portalClient: PortalClientProtocol
    private let cacheStore = PortalCacheStore.shared

    init(portalClient: PortalClientProtocol) {
        self.portalClient = portalClient
    }

    func loadCachedData() {
        let cachedCourses = cacheStore.loadCourses()
        let cachedWeeklyCourses = cacheStore.loadWeeklyCourses(for: selectedSemester)
        let cachedIntensive = cacheStore.loadIntensiveCourses(for: selectedSemester)
        print("📊 [TimetableViewModel] loadCachedData: courses=\(cachedCourses.count), weekly=\(cachedWeeklyCourses.count), intensive=\(cachedIntensive.count)")
        if !cachedCourses.isEmpty {
            applyCourses(cachedCourses)
        }
        if !cachedWeeklyCourses.isEmpty {
            weeklySchedule = buildGrid(from: cachedWeeklyCourses)
        }
        if !cachedIntensive.isEmpty {
            intensiveCourses = cachedIntensive
        }
    }

    func earliestCachedDate() -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return courses
            .compactMap { $0.dateString }
            .compactMap { formatter.date(from: $0) }
            .min()
    }

    func selectSemester(_ semester: TimetableSemester) {
        guard selectedSemester != semester else { return }
        selectedSemester = semester
        UserDefaults.standard.set(semester.rawValue, forKey: AppSettings.lastViewedSemester)
        intensiveCourses = cacheStore.loadIntensiveCourses(for: semester)
        let cachedWeeklyCourses = cacheStore.loadWeeklyCourses(for: semester)
        weeklySchedule = buildGrid(from: cachedWeeklyCourses)
        Task {
            _ = await refreshFromServer()
        }
    }

    func initialFetch() async {
        _ = await refreshFromServer()
    }

    func refreshFromServer() async -> Bool {
        await refreshFromServer(scope: .all)
    }

    func refreshScheduleFromServer() async -> Bool {
        await refreshFromServer(scope: .schedule)
    }

    func refreshScheduleFromServer(through targetDate: Date) async -> Bool {
        await refreshFromServer(scope: .scheduleMonths(scheduleMonthOffsets(through: targetDate)))
    }

    func refreshScheduleForOneYearFromServer() async -> Bool {
        await refreshFromServer(scope: .scheduleOneYear)
    }

    func refreshWeeklyFromServer() async -> Bool {
        await refreshFromServer(scope: .weekly)
    }

    private func refreshFromServer(scope: RefreshScope) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            var didUpdate = false
            var fetchedScheduleCourses: [Course] = []

            if scope.includesSchedule {
                let scheduleMonthOffsets = scope.explicitScheduleMonthOffsets ?? scheduleMonthOffsetsToFetch(forOneYear: scope.isOneYear)
                let scheduleMonthKeys = Set(scheduleMonthOffsets.map { scheduleMonthKey(monthOffset: $0) })
                let fetchedCourses = try await portalClient.fetchTimetable(monthOffsets: scheduleMonthOffsets)
                fetchedScheduleCourses = fetchedCourses
                print("📊 [TimetableViewModel] 今日の予定取得完了: \(fetchedCourses.count)件")

                let mergedCourses = cacheStore.mergeAndSaveCourses(fetchedCourses, replacingMonthKeys: scheduleMonthKeys)
                didUpdate = didUpdate || mergedCourses != courses
                courses = mergedCourses

                var loadedMonthKeys = cacheStore.loadScheduleMonthKeys()
                loadedMonthKeys.formUnion(scheduleMonthKeys)
                cacheStore.saveScheduleMonthKeys(loadedMonthKeys)
            }

            if scope.includesWeekly {
                let (fetchedWeeklyCourses, weeklyHtml) = try await portalClient.fetchWeeklyTimetableWithHTML(semester: selectedSemester)
                print("📊 [TimetableViewModel] 週間時間割取得完了: \(fetchedWeeklyCourses.count)件")

                var newWeeklySchedule = buildGrid(from: fetchedWeeklyCourses)
                if newWeeklySchedule.allSatisfy({ row in row.allSatisfy({ $0.title == nil }) }) {
                    let fallbackCourses = fetchedScheduleCourses.isEmpty ? courses : fetchedScheduleCourses
                    print("⚠️ [TimetableViewModel] 履修登録データが空のため、スケジュール管理データからグリッドを構築します")
                    newWeeklySchedule = buildGrid(from: fallbackCourses)
                }

                didUpdate = didUpdate || newWeeklySchedule != weeklySchedule
                weeklySchedule = newWeeklySchedule
                cacheStore.saveWeeklyCourses(fetchedWeeklyCourses, for: selectedSemester)

                // 集中講義も同一HTMLからパース（既存の手動日程は保持してマージ）
                let parsedIntensive = CampusSquareParser.parseIntensiveCoursesFromRSW(from: weeklyHtml)
                let mergedIntensive = mergeIntensiveCourses(existing: intensiveCourses, parsed: parsedIntensive)
                didUpdate = didUpdate || mergedIntensive != intensiveCourses
                intensiveCourses = mergedIntensive
                cacheStore.saveIntensiveCourses(mergedIntensive, for: selectedSemester)
            }

            isLoading = false
            return didUpdate
        } catch {
            print("❌ [TimetableViewModel] 更新エラー: \(error.localizedDescription)")
            if courses.isEmpty && intensiveCourses.isEmpty && weeklySchedule.allSatisfy({ $0.allSatisfy({ $0.title == nil }) }) {
                self.errorMessage = "時間割を取得できませんでした。時間をおいて再度お試しください。"
            }
            self.isLoading = false
            return false
        }
    }

    private func scheduleMonthOffsetsToFetch(forOneYear: Bool = false) -> [Int] {
        let loadedMonthKeys = cacheStore.loadScheduleMonthKeys()
        let maxOffset = forOneYear ? 12 : 2
        let range = (0...maxOffset)
        // 1年分更新の場合は毎回全月を読み直して、変更を見逃さない
        guard !forOneYear else { return Array(range) }
        return range.filter { offset in
            !loadedMonthKeys.contains(scheduleMonthKey(monthOffset: offset))
        }
    }

    func scheduleMonthOffsets(through targetDate: Date, referenceDate: Date = Date()) -> [Int] {
        let calendar = Calendar(identifier: .gregorian)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let maxDate = calendar.date(byAdding: .year, value: 1, to: referenceDay) ?? referenceDay
        let clampedDate = min(max(targetDate, referenceDay), maxDate)
        let currentMonth = startOfMonth(for: referenceDay, calendar: calendar)
        let targetMonth = startOfMonth(for: clampedDate, calendar: calendar)
        let monthCount = calendar.dateComponents([.month], from: currentMonth, to: targetMonth).month ?? 0
        return Array(0...max(0, min(monthCount, 12)))
    }

    private func scheduleMonthKey(monthOffset: Int) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.startOfDay(for: Date())
        let targetDate = calendar.date(byAdding: .month, value: monthOffset, to: baseDate) ?? baseDate
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: targetDate)
    }

    private func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    private enum RefreshScope {
        case schedule
        case scheduleMonths([Int])
        case scheduleOneYear
        case weekly
        case all

        var includesSchedule: Bool {
            switch self {
            case .schedule, .scheduleMonths, .scheduleOneYear, .all:
                return true
            case .weekly:
                return false
            }
        }

        var includesWeekly: Bool {
            switch self {
            case .weekly, .all:
                return true
            case .schedule, .scheduleMonths, .scheduleOneYear:
                return false
            }
        }

        var isOneYear: Bool {
            if case .scheduleOneYear = self {
                return true
            }
            return false
        }

        var explicitScheduleMonthOffsets: [Int]? {
            switch self {
            case .scheduleMonths(let offsets):
                return offsets
            default:
                return nil
            }
        }
    }

    private func buildGrid(from rswCourses: [Course]) -> [[ClassCell]] {
        print("🛠 [TimetableViewModel] グリッド構築開始 (\(rswCourses.count)件)")
        var grid = Array(repeating: Array(repeating: ClassCell.empty, count: 6), count: 6)
        let weekdayMap = ["月": 0, "火": 1, "水": 2, "木": 3, "金": 4, "土": 5]

        for course in rswCourses {
            guard !course.isScheduleNote else { continue }

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

    /// 既存の手動日程を保持しつつ、パース結果とマージ
    /// parsedに含まれない既存科目も残す（履修登録から外れた科目等の手動日程を保護）
    private func mergeIntensiveCourses(existing: [IntensiveCourseCard], parsed: [IntensiveCourseCard]) -> [IntensiveCourseCard] {
        print("🔍 [Merge] existing count: \(existing.count), parsed count: \(parsed.count)")
        for e in existing {
            print("🔍 [Merge] existing: \(e.title), dateRanges: \(e.dateRanges.count), id: \(e.id)")
        }
        for p in parsed {
            print("🔍 [Merge] parsed: \(p.title), dateRanges: \(p.dateRanges.count)")
        }
        
        let existingByTitle = Dictionary(grouping: existing, by: \.title)
        var mergedByTitle: [String: IntensiveCourseCard] = [:]

        for parsedCourse in parsed {
            guard let existingCourse = existingByTitle[parsedCourse.title]?.first else {
                print("⚠️ [Merge] No match for parsed: \(parsedCourse.title), using parsed (empty dateRanges)")
                mergedByTitle[parsedCourse.title] = parsedCourse
                continue
            }
            print("✅ [Merge] Matched: \(parsedCourse.title), existing dateRanges: \(existingCourse.dateRanges.count)")
            var merged = parsedCourse
            merged.id = existingCourse.id
            if !existingCourse.dateRanges.isEmpty {
                merged.dateRanges = existingCourse.dateRanges
            }
            if let start = existingCourse.startTime {
                merged.startTime = start
            }
            if let end = existingCourse.endTime {
                merged.endTime = end
            }
            mergedByTitle[merged.title] = merged
        }

        for existingCourse in existing where mergedByTitle[existingCourse.title] == nil {
            print("🔒 [Merge] Keeping existing not in parsed: \(existingCourse.title)")
            mergedByTitle[existingCourse.title] = existingCourse
        }

        let result = Array(mergedByTitle.values).sorted { $0.title < $1.title }
        print("🔍 [Merge] result count: \(result.count)")
        for r in result {
            print("🔍 [Merge] result: \(r.title), dateRanges: \(r.dateRanges.count)")
        }
        return result
    }

    private func applyCourses(_ fetchedCourses: [Course]) {
        self.courses = fetchedCourses
        
        // 注意: ここでは weeklySchedule の更新は行いません。
        // RSWのデータを尊重し、PTWデータとの混同を防ぎます。
    }
}
