import Foundation

/// 授業・予定・時間割・集中講義のキャッシュを管理
@MainActor
final class CourseCacheStore: CacheStore {
    private enum Key {
        static let courses = "portalCache.courses"
        static let scheduleMonthKeys = "portalCache.scheduleMonthKeys"
        static let weeklyCoursesPrefix = "portalCache.weeklyCourses."
        static let intensiveCoursesPrefix = "portalCache.intensiveCourses."
    }

    // MARK: - 月次予定

    func loadCourses() -> [Course] {
        guard let data = data(forKey: Key.courses),
              let courses = decode([Course].self, from: data) else {
            return []
        }
        return courses
    }

    func saveCourses(_ courses: [Course]) {
        guard let data = encode(courses) else { return }
        set(data, forKey: Key.courses)
    }

    func mergeAndSaveCourses(_ serverCourses: [Course]) -> [Course] {
        let merged = mergeCourses(cached: loadCourses(), server: serverCourses)
        saveCourses(merged)
        return merged
    }

    func mergeAndSaveCourses(_ serverCourses: [Course], replacingMonthKeys monthKeys: Set<String>) -> [Course] {
        let merged = mergeCourses(cached: loadCourses(), server: serverCourses, replacingMonthKeys: monthKeys)
        saveCourses(merged)
        return merged
    }

    // MARK: - 予定の月キー

    func loadScheduleMonthKeys() -> Set<String> {
        guard let data = data(forKey: Key.scheduleMonthKeys),
              let keys = decode([String].self, from: data) else {
            return []
        }
        return Set(keys)
    }

    func saveScheduleMonthKeys(_ keys: Set<String>) {
        guard let data = encode(Array(keys).sorted()) else { return }
        set(data, forKey: Key.scheduleMonthKeys)
    }

    // MARK: - 週間時間割

    func loadWeeklyCourses(for semester: TimetableSemester) -> [Course] {
        guard let data = data(forKey: weeklyCoursesKey(for: semester)),
              let courses = decode([Course].self, from: data) else {
            return []
        }
        return courses
    }

    func saveWeeklyCourses(_ courses: [Course], for semester: TimetableSemester) {
        guard let data = encode(courses) else { return }
        set(data, forKey: weeklyCoursesKey(for: semester))
    }

    // MARK: - 集中講義

    func loadIntensiveCourses(for semester: TimetableSemester) -> [IntensiveCourseCard] {
        guard let data = data(forKey: intensiveCoursesKey(for: semester)),
              let courses = decode([IntensiveCourseCard].self, from: data) else {
            return []
        }
        return courses
    }

    func saveIntensiveCourses(_ courses: [IntensiveCourseCard], for semester: TimetableSemester) {
        guard let data = encode(courses) else { return }
        set(data, forKey: intensiveCoursesKey(for: semester))
    }

    // MARK: - Private

    private func weeklyCoursesKey(for semester: TimetableSemester) -> String {
        Key.weeklyCoursesPrefix + semester.rawValue
    }

    private func intensiveCoursesKey(for semester: TimetableSemester) -> String {
        "\(Key.intensiveCoursesPrefix)\(semester.rawValue)"
    }

    private func mergeCourses(cached: [Course], server: [Course]) -> [Course] {
        mergeCourses(cached: cached, server: server, replacingMonthKeys: [])
    }

    private func mergeCourses(cached: [Course], server: [Course], replacingMonthKeys monthKeys: Set<String>) -> [Course] {
        // サーバーが空の場合はキャッシュを消さない（セッション切れ等で空配列が返る可能性があるため）
        if server.isEmpty {
            return cached
        }
        var merged: [String: Course] = [:]
        let serverDates = Set(server.compactMap(\.dateString))
        for course in cached {
            if let dateString = course.dateString,
               monthKeys.contains(String(dateString.prefix(7))) {
                continue
            }
            if let dateString = course.dateString, serverDates.contains(dateString) {
                continue
            }
            merged[courseCacheKey(course)] = course
        }
        for course in server {
            merged[courseCacheKey(course)] = course
        }
        return merged.values.sorted { lhs, rhs in
            let leftDate = lhs.dateString ?? ""
            let rightDate = rhs.dateString ?? ""
            if leftDate != rightDate { return leftDate < rightDate }
            if lhs.weekday != rhs.weekday { return lhs.weekday < rhs.weekday }
            if lhs.period != rhs.period { return lhs.period < rhs.period }
            return lhs.title < rhs.title
        }
    }

    private func courseCacheKey(_ course: Course) -> String {
        [
            course.dateString ?? "",
            course.weekday,
            course.period,
            course.title,
            course.instructor,
            course.scheduleNoteCategory ?? ""
        ].joined(separator: "|")
    }
}
