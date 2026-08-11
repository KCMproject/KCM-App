import Foundation
import Combine

@MainActor
final class TimetableViewModel: ObservableObject {
    static let shared = TimetableViewModel(portalClient: PortalClientFactory.makePortalClient())
    
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
        if !cachedCourses.isEmpty {
            applyCourses(cachedCourses)
        }
        if !cachedWeeklyCourses.isEmpty {
            weeklySchedule = Self.buildGrid(from: cachedWeeklyCourses)
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
        weeklySchedule = Self.buildGrid(from: cachedWeeklyCourses)
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
                let appliedSchedule = await applyScheduleCourses(fetchedCourses, monthKeys: scheduleMonthKeys)
                didUpdate = didUpdate || appliedSchedule
            }

            if scope.includesWeekly {
                let (fetchedWeeklyCourses, weeklyHtml) = try await portalClient.fetchWeeklyTimetableWithHTML(semester: selectedSemester)
                let appliedWeekly = await applyWeeklyContent(courses: fetchedWeeklyCourses, html: weeklyHtml, fallbackCourses: fetchedScheduleCourses)
                didUpdate = didUpdate || appliedWeekly
            }

            isLoading = false
            return didUpdate
        } catch {
            if courses.isEmpty && intensiveCourses.isEmpty && weeklySchedule.allSatisfy({ $0.allSatisfy({ $0.title == nil }) }) {
                self.errorMessage = "時間割を取得できませんでした。時間をおいて再度お試しください。"
            }
            self.isLoading = false
            return false
        }
    }

    private func applyScheduleCourses(_ fetchedCourses: [Course], monthKeys: Set<String>) async -> Bool {
        // キャッシュ全体のデコード・マージ・エンコード・保存はメインスレッドを塞がないようバックグラウンドで行う
        let mergedCourses = await Task.detached(priority: .utility) { [fetchedCourses, monthKeys] in
            PortalCacheStore.shared.mergeAndSaveCourses(fetchedCourses, replacingMonthKeys: monthKeys)
        }.value
        // 内容が変わったときだけ発火して、不要な再レンダリングを避ける
        let didUpdate = mergedCourses != courses
        if didUpdate {
            courses = mergedCourses
        }
        var loadedMonthKeys = cacheStore.loadScheduleMonthKeys()
        loadedMonthKeys.formUnion(monthKeys)
        cacheStore.saveScheduleMonthKeys(loadedMonthKeys)
        return didUpdate
    }

    private func applyWeeklyContent(courses fetchedWeeklyCourses: [Course], html weeklyHtml: String, fallbackCourses: [Course]) async -> Bool {
        let semester = selectedSemester
        let existingIntensive = intensiveCourses
        let currentCourses = courses
        // グリッド構築・集中講義パース・キャッシュ保存はメインスレッドを塞がないようバックグラウンドで行う
        let result = await Task.detached(priority: .utility) { [fetchedWeeklyCourses, weeklyHtml, fallbackCourses, semester, existingIntensive, currentCourses] in
            let store = PortalCacheStore.shared
            var newWeeklySchedule = Self.buildGrid(from: fetchedWeeklyCourses)
            if newWeeklySchedule.allSatisfy({ row in row.allSatisfy({ $0.title == nil }) }) {
                let fallback = fallbackCourses.isEmpty ? currentCourses : fallbackCourses
                newWeeklySchedule = Self.buildGrid(from: fallback)
            }
            store.saveWeeklyCourses(fetchedWeeklyCourses, for: semester)

            let parsedIntensive = CampusSquareParser.parseIntensiveCoursesFromRSW(from: weeklyHtml)
            let mergedIntensive = Self.mergeIntensiveCourses(existing: existingIntensive, parsed: parsedIntensive)
            store.saveIntensiveCourses(mergedIntensive, for: semester)

            if let userName = CampusSquareParser.parseUserName(from: weeklyHtml) {
                store.saveUserName(userName.fullName)
                store.saveUserReading(userName.reading)
            }
            return (weeklySchedule: newWeeklySchedule, intensiveCourses: mergedIntensive)
        }.value

        // 内容が変わったときだけ発火して、不要な再レンダリングを避ける
        let weeklyChanged = result.weeklySchedule != weeklySchedule
        if weeklyChanged {
            weeklySchedule = result.weeklySchedule
        }
        let intensiveChanged = result.intensiveCourses != intensiveCourses
        if intensiveChanged {
            intensiveCourses = result.intensiveCourses
        }
        return weeklyChanged || intensiveChanged
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
        guard monthCount > 0 else { return [0] }
        return Array(0...min(monthCount, 12))
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

    nonisolated private static func buildGrid(from rswCourses: [Course]) -> [[ClassCell]] {
        var grid = Array(repeating: Array(repeating: ClassCell.empty, count: 6), count: 6)
        let weekdayMap = ["月": 0, "火": 1, "水": 2, "木": 3, "金": 4, "土": 5]

        for course in rswCourses {
            guard !course.isScheduleNote else { continue }

            // 曜日インデックスを取得 (prefix(1) を使うことで "月曜日" から "月" を抽出)
            let rawDay = course.weekday.trimmingCharacters(in: .whitespaces)
            let dayKey = String(rawDay.prefix(1))
            guard let dayIdx = weekdayMap[dayKey] else { continue }

            // 時限インデックスを取得 (数字部分のみ抽出。カンマ区切り等に対応)
            // 例: "1,2限" -> ["1", "2"]
            let pStr = course.period.replacingOccurrences(of: "[^0-9,]", with: "", options: .regularExpression)
            let periods = pStr.components(separatedBy: ",").compactMap { Int($0) }

            if periods.isEmpty { continue }

            for p in periods where (1...6).contains(p) {
                grid[p - 1][dayIdx] = .filled(course.title, course.room)
            }
        }

        return grid
    }

    /// 既存の手動日程を保持しつつ、パース結果とマージ
    /// parsedに含まれない既存科目も残す（履修登録から外れた科目等の手動日程を保護）
    nonisolated private static func mergeIntensiveCourses(existing: [IntensiveCourseCard], parsed: [IntensiveCourseCard]) -> [IntensiveCourseCard] {
        let existingByTitle = Dictionary(grouping: existing, by: \.title)
        var mergedByTitle: [String: IntensiveCourseCard] = [:]

        for parsedCourse in parsed {
            guard let existingCourse = existingByTitle[parsedCourse.title]?.first else {
                mergedByTitle[parsedCourse.title] = parsedCourse
                continue
            }
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
            mergedByTitle[existingCourse.title] = existingCourse
        }

        return Array(mergedByTitle.values).sorted { $0.title < $1.title }
    }

    private func applyCourses(_ fetchedCourses: [Course]) {
        self.courses = fetchedCourses
        
        // 注意: ここでは weeklySchedule の更新は行いません。
        // RSWのデータを尊重し、PTWデータとの混同を防ぎます。
    }
}
