//
//  CampusSquareLoginFactory.swift
//  KCM App
//
//  Created by 田中昂平 on 2026/04/18.
//


import Foundation

// MARK: - ファクトリ

/// ログインサービスのファクトリ
@MainActor
enum PortalClientFactory {
    static func makeLoginService() -> PortalClientProtocol {
        return PortalClientImpl()
    }
}
