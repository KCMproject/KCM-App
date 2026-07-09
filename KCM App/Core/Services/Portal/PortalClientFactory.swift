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
    private static var sharedService: PortalClientProtocol = PortalClientImpl()

    static func makePortalClient() -> PortalClientProtocol {
        return sharedService
    }

    static func setSharedService(_ service: PortalClientProtocol) {
        sharedService = service
    }
}
