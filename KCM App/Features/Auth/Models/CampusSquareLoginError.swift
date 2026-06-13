//
//  CampusSquareLoginError.swift
//  KCM App
//
//  Created by 田中昂平 on 2026/04/19.
//

import Foundation


// MARK: - エラー定義

/// ログイン処理で発生するエラー
enum CampusSquareLoginError: Error, LocalizedError {
    /// ネットワークエラー
    case networkError(Error)

    /// 認証エラー
    case authenticationFailed(String)

    /// サーバーエラー
    case serverError(statusCode: Int, message: String)

    /// アカウントロック
    case accountLocked

    /// タイムアウト
    case timeout

    /// セッションエラー
    case sessionExpired

    /// ポータル処理全般のエラー
    case portalError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "ネットワークエラー: \(error.localizedDescription)"
        case .authenticationFailed(let message):
            return "認証に失敗しました: \(message)"
        case .serverError(let statusCode, let message):
            return "サーバーエラー (\(statusCode)): \(message)"
        case .accountLocked:
            return "アカウントがロックされています。管理者に連絡してください。"
        case .timeout:
            return "接続がタイムアウトしました"
        case .sessionExpired:
            return "セッションの有効期限が切れました"
        case .portalError(let message):
            return message
        }
    }
}
