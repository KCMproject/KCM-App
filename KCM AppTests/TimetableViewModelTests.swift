import XCTest
@testable import KCM_App

final class TimetableViewModelTests: XCTestCase {

    @MainActor
    func testHasSaturdayClass() async {
        let mockClient = MockPortalClient()
        let viewModel = TimetableViewModel(portalClient: mockClient)
        
        // 初期状態は false
        XCTAssertFalse(viewModel.hasSaturdayClass)
        
        // 土曜日の授業があるデータをセット
        let saturdayCourse = Course(
            id: UUID(),
            weekday: "土曜日",
            period: "2限",
            title: "土曜の授業",
            room: "教室A",
            status: "",
            instructor: "",
            nextClassInfo: "",
            materials: [],
            assignments: [],
            startTime: "10:40",
            endTime: "12:10",
            dateString: "2026-04-18"
        )
        
        mockClient.weeklyCourses = [saturdayCourse]
        
        // サーバーから更新
        _ = await viewModel.refreshFromServer()
        
        // 土曜日フラグが true になることを確認
        XCTAssertTrue(viewModel.hasSaturdayClass)
        XCTAssertEqual(viewModel.weeklySchedule[1][5].title, "土曜の授業")
    }

    @MainActor
    func testNoSaturdayClass() async {
        let mockClient = MockPortalClient()
        let viewModel = TimetableViewModel(portalClient: mockClient)
        
        // 月曜日だけの授業データをセット
        let mondayCourse = Course(
            id: UUID(),
            weekday: "月曜日",
            period: "1限",
            title: "月曜の授業",
            room: "教室B",
            status: "",
            instructor: "",
            nextClassInfo: "",
            materials: [],
            assignments: [],
            startTime: "09:00",
            endTime: "10:30",
            dateString: "2026-04-13"
        )
        
        mockClient.weeklyCourses = [mondayCourse]
        
        _ = await viewModel.refreshFromServer()
        
        // 土曜日フラグは false のまま
        XCTAssertFalse(viewModel.hasSaturdayClass)
        XCTAssertEqual(viewModel.weeklySchedule[0][0].title, "月曜の授業")
    }

    @MainActor
    func testScheduleMonthOffsetsThroughDateIncludesTargetMonth() {
        let viewModel = TimetableViewModel(portalClient: MockPortalClient())
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29))!
        let target = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!

        XCTAssertEqual(
            viewModel.scheduleMonthOffsets(through: target, referenceDate: reference),
            [0, 1, 2, 3, 4]
        )
    }

    @MainActor
    func testScheduleMonthOffsetsClampToOneYear() {
        let viewModel = TimetableViewModel(portalClient: MockPortalClient())
        let calendar = Calendar(identifier: .gregorian)
        let reference = calendar.date(from: DateComponents(year: 2026, month: 4, day: 29))!
        let target = calendar.date(from: DateComponents(year: 2028, month: 1, day: 1))!

        XCTAssertEqual(
            viewModel.scheduleMonthOffsets(through: target, referenceDate: reference),
            Array(0...12)
        )
    }
}

// MARK: - Mock

class MockPortalClient: PortalClientProtocol {
    var weeklyCourses: [Course] = []
    var isLoggedIn = true
    
    func login(credentials: CampusSquareCredentials, completion: @escaping (CampusSquareLoginResult) -> Void) {}
    func logout() async {
        isLoggedIn = false
    }
    func validateSession() async throws -> Bool {
        return isLoggedIn
    }
    func fetchOshirase() async -> Bool {
        return true
    }
    func fetchAnnouncements() async throws -> [NoticeCard] { return [] }
    func fetchAnnouncements(completion: @escaping (Result<[NoticeCard], Error>) -> Void) {}
    func fetchNoticeAttachments(for notice: NoticeCard) async throws -> [NoticeAttachment] { return [] }
    func resolveNoticeDetailURL(for notice: NoticeCard) async throws -> URL? { return nil }
    func fetchTimetable() async throws -> [Course] { return [] }
    func fetchTimetable(monthOffsets: [Int]) async throws -> [Course] { return [] }
    func fetchTimetable(completion: @escaping (Result<[Course], Error>) -> Void) {}
    func fetchWeeklyTimetable() async throws -> [Course] {
        return weeklyCourses
    }
    func fetchWeeklyTimetable(semester: TimetableSemester) async throws -> [Course] {
        return weeklyCourses
    }
}
