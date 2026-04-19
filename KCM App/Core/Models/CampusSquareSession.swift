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
    let sessionId: String
    let cookies: [HTTPCookie]
    let loggedInAt: Date

    /// セッション有効期限（分）
    var expiresInMinutes: Int = 30

    /// セッションが有効かどうか
    var isValid: Bool {
        let expirationTime = Calendar.current.date(byAdding: .minute, value: expiresInMinutes, to: loggedInAt)
        return Date() < (expirationTime ?? Date())
    }
}

