//
//  CampusSquareLoginProtocol.swift
//  KCM App
//
//  Created by 田中昂平 on 2026/04/18.
//


import Foundation

/// CAMPUSSQUARE ログインインターフェース
protocol PortalClientProtocol: AnyObject {

    /// ログインを実行する
    /// - Parameters:
    ///   - credentials: 認証情報
    ///   - completion: 実行結果のコールバック
    func login(
        credentials: CampusSquareCredentials,
        completion: @escaping (CampusSquareLoginResult) -> Void
    )

    /// 現在のセッションを確認する
    /// - Parameter completion: 確認結果のコールバック
    func validateSession(completion: @escaping (Bool) -> Void)

    /// ログアウトする
    /// - Parameter completion: 実行結果のコールバック
    func logout(completion: @escaping (Bool) -> Void)
    
    /// お知らせを取得する（レガシー）
    func fetchOshirase(completion: @escaping (Bool) -> Void)

    /// お知らせ一覧を取得する
    func fetchAnnouncements(completion: @escaping (Result<[NoticeCard], Error>) -> Void)
    func fetchAnnouncements() async throws -> [NoticeCard]

    /// 時間割を取得する
    func fetchTimetable(completion: @escaping (Result<[Course], Error>) -> Void)
    func fetchTimetable() async throws -> [Course]
}
