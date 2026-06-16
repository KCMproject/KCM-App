import Foundation
import Security

struct SavedCredentials: Equatable {
    let studentID: String
    let password: String
}

final class SavedCredentialsStore {
    static let shared = SavedCredentialsStore()

    private let service = "com.sikureha.KCMApp.savedCredentials"
    private let account = "portal-login"

    private init() {}

    func save(studentID: String, password: String) {
        let payload: [String: String] = [
            "studentID": studentID,
            "password": password
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertQuery = query
            insertQuery[kSecValueData as String] = data
            SecItemAdd(insertQuery as CFDictionary, nil)
        }
    }

    func load() -> SavedCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data else {
            return nil
        }

        // 新形式（JSON）を優先して読み込む
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let studentID = json["studentID"],
           let password = json["password"] {
            return SavedCredentials(studentID: studentID, password: password)
        }

        // 旧形式（平文 "studentID\npassword"）からの移行対応
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        let parts = string.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let credentials = SavedCredentials(studentID: String(parts[0]), password: String(parts[1]))

        // 新形式に移行して保存し直す
        save(studentID: credentials.studentID, password: credentials.password)
        return credentials
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
