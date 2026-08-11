import Foundation

/// 時間割（スケジュール管理・週間時間割）の取得を担当するクライアント
final class PortalTimetableClient {

    private let networkClient: PortalNetworkClient
    private let authClient: PortalAuthClient
    private let baseURL: String
    private let portalURL = "/portal.do"
    private let mainURL: String

    init(networkClient: PortalNetworkClient, authClient: PortalAuthClient) {
        self.networkClient = networkClient
        self.authClient = authClient
        self.baseURL = networkClient.baseURL
        self.mainURL = "\(baseURL)\(portalURL)?page=main"
    }

    // MARK: - 公開API

    func fetchTimetable(monthOffsets: [Int]) async throws -> [Course] {
        try await authClient.executeWithAutoRelogin {
            try await self._fetchTimetable(monthOffsets: monthOffsets)
        }
    }

    func fetchWeeklyTimetable(semester: TimetableSemester) async throws -> [Course] {
        try await authClient.executeWithAutoRelogin {
            let html = try await self._fetchWeeklyTimetableHTML(semester: semester)
            return await Task.detached(priority: .utility) {
                CampusSquareParser.parseWeeklyTimetableFromRSW(from: html)
            }.value
        }
    }

    func fetchWeeklyTimetableHTML(semester: TimetableSemester) async throws -> String {
        try await authClient.executeWithAutoRelogin {
            try await self._fetchWeeklyTimetableHTML(semester: semester)
        }
    }

    func fetchWeeklyTimetableWithHTML(semester: TimetableSemester) async throws -> (courses: [Course], html: String) {
        try await authClient.executeWithAutoRelogin {
            let html = try await self._fetchWeeklyTimetableHTML(semester: semester)
            let courses = await Task.detached(priority: .utility) {
                CampusSquareParser.parseWeeklyTimetableFromRSW(from: html)
            }.value
            return (courses, html)
        }
    }

    // MARK: - 内部実装

    private func _fetchTimetable(monthOffsets: [Int]) async throws -> [Course] {
        let mainHtml = try await networkClient.fetchHTML(from: mainURL)

        if mainHtml.contains("ログイン") && (mainHtml.contains("password") || mainHtml.contains("userName")) {
            throw CampusSquareLoginError.sessionExpired
        }

        let uniqueOffsets = Array(Set(monthOffsets)).sorted()
        let maxConcurrent = 5

        return await withTaskGroup(of: [Course].self) { group in
            var pending = 0
            var courseArrays: [[Course]] = []

            for offset in uniqueOffsets {
                group.addTask {
                    do {
                        let html = try await self.fetchScheduleHTML(monthOffset: offset, referer: self.mainURL)
                        // HTMLパースはメインスレッドを塞がないようバックグラウンドで行う
                        return await Task.detached(priority: .utility) {
                            CampusSquareParser.parseSchedule(from: html)
                        }.value
                    } catch {
                        return []
                    }
                }
                pending += 1
                if pending >= maxConcurrent {
                    if let courses = await group.next() {
                        courseArrays.append(courses)
                    }
                    pending -= 1
                }
            }
            for await courses in group {
                courseArrays.append(courses)
            }

            return courseArrays.flatMap { $0 }
        }
    }

    private func _fetchWeeklyTimetableHTML(semester: TimetableSemester) async throws -> String {
        let mainHtml = try await networkClient.fetchHTML(from: mainURL)
        try PortalClientHelper.validatePortalPage(mainHtml)

        guard let rswPath = CampusSquareParser.extractHrefByFlow(from: mainHtml, flowId: "RSW0001000-flow")
                ?? CampusSquareParser.extractHref(from: mainHtml, withId: "menu-link-mf-164915") else {
            throw CampusSquareLoginError.portalError("履修登録リンクが見つかりません")
        }

        let rswURL = PortalClientHelper.absolutePortalURLString(from: rswPath, baseURL: baseURL)
        let initialHtml = try await networkClient.fetchHTML(from: rswURL, referer: mainURL)
        let selectedSemester = CampusSquareParser.parseSelectedTimetableSemester(from: initialHtml)

        let html: String
        if selectedSemester == semester {
            html = initialHtml
        } else if let semesterPath = CampusSquareParser.extractTimetableSemesterHref(from: initialHtml, semester: semester) {
            let semesterURL = PortalClientHelper.absolutePortalURLString(from: semesterPath, baseURL: baseURL)
            html = try await networkClient.fetchHTML(from: semesterURL, referer: rswURL)
        } else {
            html = initialHtml
        }

        return html
    }

    private func fetchScheduleHTML(monthOffset: Int, referer: String) async throws -> String {
        let calendar = Calendar(identifier: .gregorian)
        let baseDate = calendar.startOfDay(for: Date())
        guard let targetDate = calendar.date(byAdding: .month, value: monthOffset, to: baseDate) else {
            throw CampusSquareLoginError.portalError("スケジュール月の計算に失敗しました")
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let initDate = formatter.string(from: targetDate)
        let path = "campussquare.do?_flowId=PTW0001200-flow&initDate=\(initDate)"
        let url = PortalClientHelper.absolutePortalURLString(from: path, baseURL: baseURL)
        return try await networkClient.fetchHTML(from: url, referer: referer)
    }
}
