import SwiftUI
import Combine

// MARK: - Egg Game State (Singleton)

@MainActor
final class EggGameState: ObservableObject {
    static let shared = EggGameState()

    // MARK: Published (View が監視)

    @Published var tapCount: Int = 0
    @Published var walkers: [WalkingChar] = []
    @Published var collection: [String: Int] = [:]
    @Published var eggScale: CGFloat = 1.0
    @Published var tapRipples: [TapRipple] = []
    @Published var hatchPhase: HatchPhase = .none
    @Published var hatchChar: CharDef?
    @Published var lastPopped: CharDef?
    @Published var showPopAnnouncement = false
    @Published var shellSplitProgress: CGFloat = 0
    @Published var revealProgress: CGFloat = 0

    // MARK: Internal

    var gameSize: CGSize = .zero
    private var gameTimer: Timer?

    let charSize: CGFloat = 52

    // MARK: Types

    struct TapRipple: Identifiable {
        let id = UUID()
        let createdAt = Date()
    }

    enum HatchPhase {
        case none
        case shaking
        case splitting
        case revealing
    }

    // MARK: Computed

    var progress: Double {
        Double(tapCount % EggGameConfig.tapsPerSpawn) / Double(EggGameConfig.tapsPerSpawn)
    }

    var crackLevel: Int {
        [0.25, 0.5, 0.75, 1.0].filter { progress >= $0 }.count
    }

    var currentCycle: Int {
        tapCount / EggGameConfig.tapsPerSpawn
    }

    // MARK: Game Loop

    func startGameLoop() {
        guard gameTimer == nil else { return }
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateWalkers()
            }
        }
    }

    func stopGameLoop() {
        gameTimer?.invalidate()
        gameTimer = nil
    }

    // MARK: Persistence

    func loadGameState() {
        guard let state = GameStateStore.shared.load() else { return }
        tapCount = state.tapCount
        collection = state.collection
        if walkers.isEmpty {
            regenerateWalkersFromCollection()
        }
    }

    func saveGameState() {
        GameStateStore.shared.save(tapCount: tapCount, collection: collection)
    }

    // MARK: Walkers

    func regenerateWalkersFromCollection() {
        var newWalkers: [WalkingChar] = []
        let allChars = EggGameCharacters.all
        for (charID, count) in collection {
            guard let char = allChars.first(where: { $0.id == charID }) else { continue }
            for _ in 0..<count {
                newWalkers.append(makeWalker(char: char))
            }
        }
        walkers = newWalkers
    }

    func updateWalkers() {
        let w = max(gameSize.width, UIScreen.main.bounds.width)
        let h = max(gameSize.height, UIScreen.main.bounds.height)

        walkers = walkers.map { walker in
            var n = walker
            n.x += n.vx
            n.y += n.vy

            if n.x < 0 {
                n.x = 0
                n.vx = abs(n.vx)
                n.flipped = false
            } else if n.x > w - charSize {
                n.x = w - charSize
                n.vx = -abs(n.vx)
                n.flipped = true
            }
            if n.y < 0 {
                n.y = 0
                n.vy = abs(n.vy)
            } else if n.y > h - charSize {
                n.y = h - charSize
                n.vy = -abs(n.vy)
            }

            n.vx += CGFloat.random(in: -0.1...0.1)
            n.vy += CGFloat.random(in: -0.1...0.1)

            let speed = hypot(n.vx, n.vy)
            if speed > 2.0 {
                n.vx = n.vx / speed * 2.0
                n.vy = n.vy / speed * 2.0
            } else if speed < 0.5 && speed > 0 {
                n.vx = n.vx / speed * 0.5
                n.vy = n.vy / speed * 0.5
            }

            return n
        }
    }

    // MARK: Tap Handling

    func handleEggTap() {
        guard hatchPhase == .none else { return }

        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        eggScale = 0.9
        withAnimation(.easeOut(duration: 0.08)) {
            eggScale = 1.0
        }

        let ripple = TapRipple()
        tapRipples.append(ripple)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.tapRipples.removeAll { $0.id == ripple.id }
        }

        let previousCycle = tapCount / EggGameConfig.tapsPerSpawn
        tapCount += EggGameConfig.tapsPerTap
        let newCycle = tapCount / EggGameConfig.tapsPerSpawn

        if newCycle > previousCycle {
            let char = EggGameRandom.pickChar()
            triggerHatch(char)
        }
    }

    func triggerHatch(_ char: CharDef) {
        hatchChar = char

        withAnimation {
            hatchPhase = .shaking
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            withAnimation {
                self.hatchPhase = .splitting
            }
            withAnimation(.easeOut(duration: 0.7)) {
                self.shellSplitProgress = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self else { return }
            withAnimation {
                self.hatchPhase = .revealing
            }
            withAnimation(.easeOut(duration: 0.9)) {
                self.revealProgress = 1.0
            }

            let newWalker = self.makeWalker(char: char)
            self.walkers.append(newWalker)
            self.collection[char.id, default: 0] += 1

            self.lastPopped = char
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                self.showPopAnnouncement = true
            }

            if char.id == "gold" {
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
            } else if char.id == "red" {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.showPopAnnouncement = false
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) { [weak self] in
            guard let self else { return }
            withAnimation {
                self.hatchPhase = .none
            }
            self.hatchChar = nil
            self.shellSplitProgress = 0
            self.revealProgress = 0
        }
    }

    // MARK: Walker Factory

    func makeWalker(char: CharDef) -> WalkingChar {
        let w = max(gameSize.width, UIScreen.main.bounds.width)
        let h = max(gameSize.height, UIScreen.main.bounds.height)
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let speed = CGFloat.random(in: 0.6...1.2)
        return WalkingChar(
            char: char,
            x: CGFloat.random(in: 0...(max(w - charSize, 0))),
            y: CGFloat.random(in: 0...(max(h - charSize, 0))),
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            flipped: Bool.random(),
            scale: char.id == "gold" ? 1.15 : 1.0
        )
    }
}
