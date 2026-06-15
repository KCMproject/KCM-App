import Foundation

// MARK: - ログイン結果

/// ログイン処理の結果
enum CampusSquareLoginResult {
    case success(session: CampusSquareSession)
    case failure(CampusSquareLoginError)
}

// MARK: - ファサード実装

/// CAMPUSSQUARE 自動ログイン・データ取得クラスのファサード
///
/// 実際の処理は以下の専責クライアントに委譲している:
/// - PortalAuthClient: 認証・セッション管理・自動再ログイン
/// - PortalAnnouncementClient: 掲示板（お知らせ）の取得・詳細解決
/// - PortalTimetableClient: 時間割・週間時間割の取得
/// - PortalPDFClient: 成績通知書PDF・ユーザー名の取得
final class PortalClientImpl: PortalClientProtocol {

    private let networkClient: PortalNetworkClient
    private let authClient: PortalAuthClient
    private let announcementClient: PortalAnnouncementClient
    private let timetableClient: PortalTimetableClient
    private let pdfClient: PortalPDFClient

    init(baseURL: String = "https://cs.kunitachi.ac.jp/campusweb") {
        self.networkClient = PortalNetworkClient(baseURL: baseURL)
        self.authClient = PortalAuthClient(networkClient: networkClient)
        let formClient = PortalFormClient(networkClient: networkClient)
        self.announcementClient = PortalAnnouncementClient(
            networkClient: networkClient,
            authClient: authClient,
            formClient: formClient
        )
        self.timetableClient = PortalTimetableClient(
            networkClient: networkClient,
            authClient: authClient
        )
        self.pdfClient = PortalPDFClient(
            networkClient: networkClient,
            authClient: authClient,
            formClient: formClient,
            timetableClient: timetableClient
        )
    }

    // MARK: - 認証

    func login(credentials: CampusSquareCredentials, completion: @escaping (CampusSquareLoginResult) -> Void) {
        Task {
            do {
                let session = try await authClient.login(credentials: credentials)
                completion(.success(session: session))
            } catch let error as CampusSquareLoginError {
                completion(.failure(error))
            } catch {
                completion(.failure(.networkError(error)))
            }
        }
    }

    func validateSession() async throws -> Bool {
        try await authClient.validateSession()
    }

    func logout() async {
        await authClient.logout()
    }

    // MARK: - お知らせ

    func fetchOshirase() async -> Bool {
        do {
            _ = try await announcementClient.fetchAnnouncements()
            return true
        } catch {
            return false
        }
    }

    func fetchAnnouncements() async throws -> [NoticeCard] {
        try await announcementClient.fetchAnnouncements()
    }

    func fetchAnnouncements(completion: @escaping (Result<[NoticeCard], Error>) -> Void) {
        Task {
            do {
                let notices = try await announcementClient.fetchAnnouncements()
                completion(.success(notices))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchNoticeAttachments(for notice: NoticeCard) async throws -> [NoticeAttachment] {
        try await announcementClient.fetchNoticeAttachments(for: notice)
    }

    func resolveNoticeDetailURL(for notice: NoticeCard) async throws -> URL? {
        try await announcementClient.resolveNoticeDetailURL(for: notice)
    }

    // MARK: - 時間割

    func fetchTimetable() async throws -> [Course] {
        try await timetableClient.fetchTimetable(monthOffsets: [0])
    }

    func fetchTimetable(monthOffsets: [Int]) async throws -> [Course] {
        try await timetableClient.fetchTimetable(monthOffsets: monthOffsets)
    }

    func fetchTimetable(completion: @escaping (Result<[Course], Error>) -> Void) {
        Task {
            do {
                let courses = try await timetableClient.fetchTimetable(monthOffsets: [0])
                completion(.success(courses))
            } catch {
                completion(.failure(error))
            }
        }
    }

    func fetchWeeklyTimetable() async throws -> [Course] {
        try await timetableClient.fetchWeeklyTimetable(semester: .current)
    }

    func fetchWeeklyTimetable(semester: TimetableSemester) async throws -> [Course] {
        try await timetableClient.fetchWeeklyTimetable(semester: semester)
    }

    func fetchWeeklyTimetableHTML(semester: TimetableSemester) async throws -> String {
        try await timetableClient.fetchWeeklyTimetableHTML(semester: semester)
    }

    func fetchWeeklyTimetableWithHTML(semester: TimetableSemester) async throws -> (courses: [Course], html: String) {
        try await timetableClient.fetchWeeklyTimetableWithHTML(semester: semester)
    }

    // MARK: - 成績通知書PDF

    func fetchGradeReportPDF() async throws -> Data {
        try await pdfClient.fetchGradeReportPDF()
    }

    func fetchUserName() async throws -> (fullName: String, reading: String) {
        try await pdfClient.fetchUserName()
    }
}
