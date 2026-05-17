//
//  CampusSquareSession.swift
//  KCM App
//
//  Created by 田中昂平 on 2026/04/19.
//

import Foundation

// MARK: - セッション情報

/// ログイン成功後のセッション情報
struct CampusSquareSession {
    /// ポータルから取得した実際のセッション識別子（JSESSIONID等）
    let sessionId: String
    let loggedInAt: Date
    /// Cookieから算出した有効期限（分）。取得できない場合はフォールバック値
    let expiresInMinutes: Int

    /// セッションが有効かどうか
    var isValid: Bool {
        let expirationTime = Calendar.current.date(byAdding: .minute, value: expiresInMinutes, to: loggedInAt)
        return Date() < (expirationTime ?? Date())
    }
}
