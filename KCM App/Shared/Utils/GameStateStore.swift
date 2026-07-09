import Foundation

// MARK: - Persisted Models

struct PersistedGameState: Codable {
    var tapCount: Int
    var collection: [String: Int]
}

// MARK: - Game State Store

/// ゲームの進行状況を永続化するストア
/// タップ回数とコレクションを保存する（歩行者はコレクションから再生成）
final class GameStateStore {
    static let shared = GameStateStore()

    private let filename = "egg_game_state.json"
    private var fileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KCM_App_GameState", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("KCM_App_GameState", isDirectory: true)
        return baseURL.appendingPathComponent(filename)
    }

    private init() {
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KCM_App_GameState", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("KCM_App_GameState", isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func load() -> PersistedGameState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedGameState.self, from: data)
    }

    func save(tapCount: Int, collection: [String: Int]) {
        let state = PersistedGameState(tapCount: tapCount, collection: collection)
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
