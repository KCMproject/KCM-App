import Foundation

// MARK: - Persisted Models

struct PersistedGameState: Codable {
    var tapCount: Int
    var collection: [String: Int]
    var walkers: [PersistedWalker]
}

struct PersistedWalker: Codable {
    let charID: String
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var flipped: Bool
    var scale: CGFloat
}

// MARK: - Game State Store

/// ゲームの進行状況を永続化するストア
/// タップ回数、コレクション、歩行中のキャラクターを保存する
final class GameStateStore {
    static let shared = GameStateStore()

    private let filename = "egg_game_state.json"
    private var fileURL: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KCM_App_GameState", isDirectory: true) ?? URL(fileURLWithPath: "")
        return url.appendingPathComponent(filename)
    }

    private init() {
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        guard let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KCM_App_GameState", isDirectory: true) else { return }

        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func load() -> PersistedGameState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PersistedGameState.self, from: data)
    }

    func save(tapCount: Int, collection: [String: Int], walkers: [WalkingChar]) {
        let persistedWalkers = walkers.map { walker in
            PersistedWalker(
                charID: walker.char.id,
                x: walker.x,
                y: walker.y,
                vx: walker.vx,
                vy: walker.vy,
                flipped: walker.flipped,
                scale: walker.scale
            )
        }
        let state = PersistedGameState(
            tapCount: tapCount,
            collection: collection,
            walkers: persistedWalkers
        )

        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
