//
//  CampusSquareLoginProtocol.swift
//  KCM App
//
//  Created by 田中昂平 on 2026/04/18.
//


import Foundation

/// CAMPUSSQUARE ログインインターフェース
protocol PortalClientProtocol {

    /// ログインを実行する
    /// - Parameters:
    ///   - credentials: 認証情報
    ///   - completion: 実行結果のコールバック
    func login(
        credentials: CampusSquareCredentials,
        completion: @escaping (CampusSquareLoginResult) -> Void
    )

    /// 現在のセッションを確認する
    func validateSession() async throws -> Bool

    /// ログアウトする
    func logout() async

    /// お知らせを取得する（レガシー）
    func fetchOshirase() async -> Bool

    /// お知らせ一覧を取得する
    func fetchAnnouncements(completion: @escaping (Result<[NoticeCard], Error>) -> Void)
    func fetchAnnouncements() async throws -> [NoticeCard]
    func fetchNoticeAttachments(for notice: NoticeCard) async throws -> [NoticeAttachment]
    
    /// 掲示板詳細の最新URLを解決する（セッション切れ後に古いURLを更新する）
    func resolveNoticeDetailURL(for notice: NoticeCard) async throws -> URL?

    /// 時間割を取得する
    func fetchTimetable(completion: @escaping (Result<[Course], Error>) -> Void)
    func fetchTimetable() async throws -> [Course]
    func fetchTimetable(monthOffsets: [Int]) async throws -> [Course]

    /// 週間時間割（グリッド形式）を取得する
    func fetchWeeklyTimetable() async throws -> [Course]
    func fetchWeeklyTimetable(semester: TimetableSemester) async throws -> [Course]

    /// 週間時間割ページの生HTMLを取得する（集中講義パース用）
    func fetchWeeklyTimetableHTML(semester: TimetableSemester) async throws -> String

    /// 週間時間割と集中講義HTMLを1回のフェッチで両方取得する
    func fetchWeeklyTimetableWithHTML(semester: TimetableSemester) async throws -> (courses: [Course], html: String)

    /// 成績通知書のPDFをダウンロードする
    func fetchGradeReportPDF() async throws -> Data

    /// ユーザー名（氏名・フリガナ）を取得する
    func fetchUserName() async throws -> (fullName: String, reading: String)
}
