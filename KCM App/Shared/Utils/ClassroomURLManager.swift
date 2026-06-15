import SwiftUI
import Combine

/// 教室URLの読み込み・編集・保存を共通化するマネージャー
@MainActor
final class ClassroomURLManager: ObservableObject {
    @Published var urls: [String: String] = [:]
    @Published var editingKey: String?
    @Published var temporaryURL: String = ""

    /// 編集中かどうか（アラート/シートの表示制御用）
    var isEditing: Bool {
        get { editingKey != nil }
        set {
            if !newValue {
                editingKey = nil
                temporaryURL = ""
            }
        }
    }

    func load() {
        urls = PortalCacheStore.shared.loadClassroomURLs()
    }

    func save() {
        PortalCacheStore.shared.saveClassroomURLs(urls)
    }

    /// 指定キーの編集を開始する
    /// - Parameters:
    ///   - key: 保存用キー
    ///   - currentURL: 既存URLがあれば渡す。nil の場合は内部辞書から検索する
    func startEditing(key: String, currentURL: String? = nil) {
        temporaryURL = currentURL ?? urls[key] ?? ""
        editingKey = key
    }

    /// 編集中のキーに対して temporaryURL を保存する
    func commit() {
        guard let key = editingKey else { return }
        let trimmedURL = temporaryURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedURL.isEmpty {
            urls.removeValue(forKey: key)
        } else {
            urls[key] = trimmedURL
        }
        save()
        editingKey = nil
        temporaryURL = ""
    }

    /// 編集中のキーのURLを削除する
    func clear() {
        guard let key = editingKey else { return }
        urls.removeValue(forKey: key)
        save()
        editingKey = nil
        temporaryURL = ""
    }

    /// 編集をキャンセルする
    func cancel() {
        editingKey = nil
        temporaryURL = ""
    }

    /// 指定キー、またはフォールバックキーのURLを取得する
    func url(for key: String, fallback fallbackKey: String? = nil) -> String? {
        urls[key] ?? fallbackKey.flatMap { urls[$0] }
    }

    /// URL文字列を開く
    func open(_ urlString: String) {
        guard let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}
