//
//  CampusSquareCredentials.swift
//  KCM App
//
//  Created by 田中昂平 on 2026/04/19.
//


// MARK: - 認証情報

/// ログイン認証情報
struct CampusSquareCredentials {
    let userName: String
    let password: String

    /// バリデーション
    func validate() -> ValidationResult {
        if userName.isEmpty {
            return .failure("ユーザー名を入力してください")
        }
        if userName.count > 30 {
            return .failure("ユーザー名は30文字以内で入力してください")
        }
        if password.isEmpty {
            return .failure("パスワードを入力してください")
        }
        if password.count > 20 {
            return .failure("パスワードは20文字以内で入力してください")
        }
        return .success
    }
}