import SwiftUI

// MARK: - Debug Constants

/// 本番に戻す際はここを false にしてください
private let isDebugMode = false
/// 1タップで加算されるタップ数（デバッグ用）
private let tapsPerTap = 1
/// デバッグ時は全キャラ出現率を均等にする
private let debugWeight: Double = 20

// MARK: - Character Definitions

struct CharDef: Identifiable, Hashable {
    let id: String
    let name: String
    let rarity: String
    let rarityColor: Color
    let imageName: String
    let weight: Double
    let glowColor: Color
}

private let chars: [CharDef] = {
    let baseChars: [CharDef] = [
        CharDef(id: "normal", name: "ノーマル", rarity: "NORMAL", rarityColor: .gray, imageName: "char_normal", weight: 80, glowColor: .clear),
        CharDef(id: "sunglass", name: "クールくん", rarity: "RARE", rarityColor: .blue, imageName: "char_sunglass", weight: 7, glowColor: .blue.opacity(0.3)),
        CharDef(id: "aloha", name: "アロハくん", rarity: "RARE", rarityColor: .green, imageName: "char_aloha", weight: 6.99, glowColor: .green.opacity(0.3)),
        CharDef(id: "red", name: "赤シャツくん", rarity: "SUPER RARE", rarityColor: .red, imageName: "char_red", weight: 6, glowColor: .red.opacity(0.3)),
        CharDef(id: "gold", name: "ゴールド", rarity: "LEGENDARY", rarityColor: .yellow, imageName: "char_gold", weight: 0.01, glowColor: .yellow.opacity(0.5))
    ]

    guard isDebugMode else { return baseChars }
    return baseChars.map { CharDef(id: $0.id, name: $0.name, rarity: $0.rarity, rarityColor: $0.rarityColor, imageName: $0.imageName, weight: debugWeight, glowColor: $0.glowColor) }
}()

private let totalWeight = chars.reduce(0) { $0 + $1.weight }
private let tapsPerSpawn = 1_000

private func pickChar() -> CharDef {
    var r = Double.random(in: 0..<totalWeight)
    for char in chars {
        r -= char.weight
        if r <= 0 { return char }
    }
    return chars[0]
}

// MARK: - Walking Character Model

struct WalkingChar: Identifiable {
    let id = UUID()
    let char: CharDef
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var flipped: Bool
    var scale: CGFloat
    var bounce: CGFloat = 1.0
}

// MARK: - View

struct EggGameCloneView: View {
    @Binding var isLocked: Bool
    @State private var tapCount = 0
    @State private var walkers: [WalkingChar] = []
    @State private var collection: [String: Int] = [:]
    @State private var eggScale: CGFloat = 1.0
    @State private var tapRipples: [TapRipple] = []
    @State private var hatchPhase: HatchPhase = .none
    @State private var hatchChar: CharDef?
    @State private var lastPopped: CharDef?
    @State private var showPopAnnouncement = false
    @State private var gameTimer: Timer?
    @State private var gameSize: CGSize = .zero
    @State private var shellSplitProgress: CGFloat = 0
    @State private var revealProgress: CGFloat = 0

    private let charSize: CGFloat = 52

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

    private var progress: Double {
        Double(tapCount % tapsPerSpawn) / Double(tapsPerSpawn)
    }

    private var crackLevel: Int {
        [0.25, 0.5, 0.75, 1.0].filter { progress >= $0 }.count
    }

    private var currentCycle: Int {
        tapCount / tapsPerSpawn
    }

    var body: some View {
        ZStack {
            AppTheme.pageBackground.ignoresSafeArea()

            GeometryReader { geometry in
                gameArea(geometry: geometry)
                    .onAppear {
                        gameSize = geometry.size
                        loadGameState()
                    }
                    .onChange(of: geometry.size) { _, newSize in
                        gameSize = newSize
                    }
            }
        }
        .onAppear(perform: startGameLoop)
        .onDisappear {
            stopGameLoop()
            saveGameState()
        }
        .onChange(of: tapCount) { _, _ in
            saveGameState()
        }
        .onChange(of: collection) { _, _ in
            saveGameState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            saveGameState()
        }
    }

    // MARK: Game Area

    private func gameArea(geometry: GeometryProxy) -> some View {
        ZStack {
            // Walking characters
            ForEach(walkers) { walker in
                characterView(walker)
            }

            // Pop announcement
            if showPopAnnouncement, let lastPopped {
                popAnnouncement(char: lastPopped)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Center egg + UI
            VStack(spacing: 16) {
                if currentCycle > 0 {
                    Text("\(currentCycle) 回割った！")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.textBlue)
                }

                eggButton
                    .frame(width: 120, height: 140)

                if hatchPhase == .none {
                    ProgressView(value: Double(tapCount % tapsPerSpawn), total: Double(tapsPerSpawn))
                        .progressViewStyle(EggProgressStyle())
                        .frame(width: 180)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Collection list
            collectionList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 12)
                .padding(.bottom, 12)

            // Lock toggle
            Button {
                isLocked.toggle()
            } label: {
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isLocked ? AppTheme.accent : AppTheme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.9)))
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
    }

    // MARK: Character View

    private func characterView(_ walker: WalkingChar) -> some View {
        ZStack {
            if walker.char.id == "gold" {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.yellow.opacity(0.4), .clear],
                            center: .center,
                            startRadius: 5,
                            endRadius: 35
                        )
                    )
                    .frame(width: 70, height: 70)
                    .opacity(0.8)
            }

            Image(walker.char.imageName)
                .resizable()
                .scaledToFit()
                .frame(width: charSize, height: charSize)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .position(x: walker.x + charSize / 2, y: walker.y + charSize / 2)
        .scaleEffect(
            x: walker.scale * walker.bounce * (walker.flipped ? -1 : 1),
            y: walker.scale * (2.0 - walker.bounce)
        )
        .zIndex(walker.char.id == "gold" ? 10 : 5)
    }

    // MARK: Pop Announcement

    private func popAnnouncement(char: CharDef) -> some View {
        HStack(spacing: 6) {
            if char.id == "gold" {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .bold))
            }

            Text("\(char.name) GET!")
                .font(.system(size: 14, weight: .bold))

            Text(char.rarity)
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.3))
                .clipShape(Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(announcementGradient(for: char))
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 16)
    }

    private func announcementGradient(for char: CharDef) -> some ShapeStyle {
        switch char.id {
        case "gold":
            return LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
        case "red":
            return LinearGradient(colors: [.red, .pink], startPoint: .leading, endPoint: .trailing)
        default:
            return LinearGradient(colors: [AppTheme.accent, AppTheme.accent.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        }
    }

    // MARK: Egg Button

    private var eggButton: some View {
        ZStack {
            // Tap ripples
            ForEach(tapRipples) { ripple in
                Circle()
                    .stroke(AppTheme.accent.opacity(0.4), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.0 + CGFloat(Date().timeIntervalSince(ripple.createdAt)) * 4.0)
                    .opacity(1.0 - CGFloat(Date().timeIntervalSince(ripple.createdAt)) * 3.0)
            }

            eggVisual
                .scaleEffect(eggScale)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleEggTap()
        }
    }

    private var eggVisual: some View {
        ZStack {
            switch hatchPhase {
            case .none:
                eggShape(crackLevel: crackLevel)

            case .shaking:
                eggShape(crackLevel: 4)
                    .modifier(ShakeEffect(shake: true))

            case .splitting:
                splittingEgg

            case .revealing:
                revealingEgg
            }
        }
    }

    // MARK: Splitting Egg Animation

    private var splittingEgg: some View {
        ZStack {
            // Flash
            Circle()
                .fill(hatchChar?.id == "gold" ? Color.yellow.opacity(0.6) : Color.white.opacity(0.8))
                .frame(width: 160, height: 160)
                .scaleEffect(1.5 - shellSplitProgress * 0.5)
                .opacity(1 - shellSplitProgress)

            // Left shell half
            eggHalf(isLeft: true)
                .offset(x: -55 * shellSplitProgress, y: -60 * shellSplitProgress)
                .rotationEffect(.degrees(-45 * shellSplitProgress))
                .opacity(1 - shellSplitProgress)

            // Right shell half
            eggHalf(isLeft: false)
                .offset(x: 55 * shellSplitProgress, y: -60 * shellSplitProgress)
                .rotationEffect(.degrees(45 * shellSplitProgress))
                .opacity(1 - shellSplitProgress)

            // Sparkles
            ForEach(0..<12) { i in
                sparkle(at: i)
            }
        }
    }

    private var revealingEgg: some View {
        ZStack {
            // Glow ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (hatchChar?.glowColor ?? AppTheme.accent.opacity(0.5)),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(0.5 + revealProgress * 2)
                .opacity(1 - revealProgress)

            // Character
            if let hatchChar {
                Image(hatchChar.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .scaleEffect(0.3 + revealProgress * 0.9)
                    .offset(y: 20 - revealProgress * 28)
                    .opacity(revealProgress)
            }

            // Trailing stars
            ForEach(0..<6) { i in
                starTrail(at: i)
            }
        }
    }

    private func sparkle(at index: Int) -> some View {
        let angle = Double(index) * (2 * .pi / 12)
        let distance: CGFloat = 50 + CGFloat(index % 3) * 15
        let colors: [Color] = hatchChar?.id == "gold" ? [.yellow, .orange] : [.blue.opacity(0.7), .yellow.opacity(0.7)]

        return Circle()
            .fill(colors[index % 2])
            .frame(width: 8, height: 8)
            .offset(
                x: cos(angle) * distance * shellSplitProgress,
                y: sin(angle) * distance * shellSplitProgress
            )
            .opacity(1 - shellSplitProgress)
            .scaleEffect(1 - shellSplitProgress * 0.5)
    }

    private func starTrail(at index: Int) -> some View {
        let angle = Double(index) * (2 * .pi / 6)
        let distance: CGFloat = 30 + revealProgress * 40

        return Text(hatchChar?.id == "gold" ? "✨" : "⭐")
            .font(.system(size: 16))
            .offset(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
            .opacity(1 - revealProgress)
            .scaleEffect(1 - revealProgress * 0.7)
    }

    // MARK: Collection List

    private var collectionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(chars) { char in
                collectionRow(char: char)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    private func collectionRow(char: CharDef) -> some View {
        let count = collection[char.id, default: 0]
        let obtained = count > 0

        return HStack(spacing: 6) {
            if obtained {
                Image(char.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 26)
            } else {
                Text("❓")
                    .font(.system(size: 14))
                    .frame(width: 26, height: 26)
                    .background(AppTheme.grayPill)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text("× \(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(obtained ? Color.white.opacity(0.6) : Color.white.opacity(0.3))
        )
        .opacity(obtained ? 1.0 : 0.5)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(char.id == "gold" && obtained ? Color.yellow.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: Game Loop

    private func startGameLoop() {
        guard gameTimer == nil else { return }
        gameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            updateWalkers()
        }
    }

    private func stopGameLoop() {
        gameTimer?.invalidate()
        gameTimer = nil
    }

    // MARK: - Persistence

    private func loadGameState() {
        guard let state = GameStateStore.shared.load() else { return }
        tapCount = state.tapCount
        collection = state.collection
        regenerateWalkersFromCollection()
    }

    private func saveGameState() {
        GameStateStore.shared.save(tapCount: tapCount, collection: collection)
    }

    private func regenerateWalkersFromCollection() {
        let areaWidth = gameSize.width
        var newWalkers: [WalkingChar] = []
        for (charID, count) in collection {
            guard let char = chars.first(where: { $0.id == charID }) else { continue }
            for _ in 0..<count {
                newWalkers.append(makeWalker(char: char, areaWidth: areaWidth))
            }
        }
        walkers = newWalkers
    }

    private func updateWalkers() {
        let width = gameSize.width
        let height = gameSize.height

        walkers = walkers.map { walker in
            var newWalker = walker
            newWalker.x += newWalker.vx
            newWalker.y += newWalker.vy

            // Boundary checks
            var hitWall = false
            if newWalker.x < 0 {
                newWalker.x = 0
                newWalker.vx = abs(newWalker.vx)
                newWalker.flipped = false
                hitWall = true
            }
            if newWalker.x > width - charSize {
                newWalker.x = width - charSize
                newWalker.vx = -abs(newWalker.vx)
                newWalker.flipped = true
                hitWall = true
            }
            if newWalker.y < 0 {
                newWalker.y = 0
                newWalker.vy = abs(newWalker.vy)
            }
            if newWalker.y > height - charSize {
                newWalker.y = height - charSize
                newWalker.vy = -abs(newWalker.vy)
            }

            // Wall bounce animation
            if hitWall {
                newWalker.bounce = 0.75
            }
            newWalker.bounce += (1.0 - newWalker.bounce) * 0.12

            // Random direction changes
            newWalker.vx += CGFloat.random(in: -0.04...0.04)
            newWalker.vy += CGFloat.random(in: -0.04...0.04)

            // Speed limits
            let speed = hypot(newWalker.vx, newWalker.vy)
            if speed > 1.2 {
                newWalker.vx = newWalker.vx / speed * 1.2
                newWalker.vy = newWalker.vy / speed * 1.2
            }
            if speed < 0.2 && speed > 0 {
                newWalker.vx = newWalker.vx / speed * 0.2
                newWalker.vy = newWalker.vy / speed * 0.2
            }

            return newWalker
        }
    }

    // MARK: Tap Handling

    private func handleEggTap() {
        guard hatchPhase == .none else { return }

        // Haptic feedback
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()

        // Visual feedback: quick scale down + up
        eggScale = 0.9
        withAnimation(.easeOut(duration: 0.08)) {
            eggScale = 1.0
        }

        // Tap ripple effect
        let ripple = TapRipple()
        tapRipples.append(ripple)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            tapRipples.removeAll { $0.id == ripple.id }
        }

        let previousCycle = tapCount / tapsPerSpawn
        tapCount += tapsPerTap
        let newCycle = tapCount / tapsPerSpawn

        if newCycle > previousCycle {
            let char = pickChar()
            triggerHatch(char)
        }
    }

    private func triggerHatch(_ char: CharDef) {
        hatchChar = char

        // Phase 1: Shaking (0.5s)
        withAnimation {
            hatchPhase = .shaking
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Phase 2: Splitting (0.7s)
            withAnimation {
                hatchPhase = .splitting
            }
            withAnimation(.easeOut(duration: 0.7)) {
                shellSplitProgress = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            // Phase 3: Revealing (0.9s)
            withAnimation {
                hatchPhase = .revealing
            }
            withAnimation(.easeOut(duration: 0.9)) {
                revealProgress = 1.0
            }

            // Add to walkers and collection
            let areaWidth = gameSize.width
            let newWalker = makeWalker(char: char, areaWidth: areaWidth)
            walkers.append(newWalker)
            collection[char.id, default: 0] += 1

            lastPopped = char
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                showPopAnnouncement = true
            }

            // Stronger haptic for rare characters
            if char.id == "gold" {
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
            } else if char.id == "red" {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showPopAnnouncement = false
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            // Reset
            withAnimation {
                hatchPhase = .none
            }
            hatchChar = nil
            shellSplitProgress = 0
            revealProgress = 0
        }
    }

    private func makeWalker(char: CharDef, areaWidth: CGFloat) -> WalkingChar {
        let height = gameSize.height
        let angle = CGFloat.random(in: 0...(2 * .pi))
        let speed = CGFloat.random(in: 0.4...0.9)
        return WalkingChar(
            char: char,
            x: CGFloat.random(in: 0...(max(areaWidth - charSize, 0))),
            y: CGFloat.random(in: 0...(max(height - charSize, 0))),
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            flipped: Bool.random(),
            scale: char.id == "gold" ? 1.15 : 1.0
        )
    }
}

// MARK: - Egg Shapes

struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 110
        let scaleY = rect.height / 130
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)
            .translatedBy(x: rect.minX / scaleX, y: rect.minY / scaleY)

        path.move(to: CGPoint(x: 55, y: 6))
        path.addCurve(to: CGPoint(x: 14, y: 68), control1: CGPoint(x: 28, y: 6), control2: CGPoint(x: 14, y: 36))
        path.addCurve(to: CGPoint(x: 55, y: 122), control1: CGPoint(x: 14, y: 100), control2: CGPoint(x: 32, y: 122))
        path.addCurve(to: CGPoint(x: 96, y: 68), control1: CGPoint(x: 78, y: 122), control2: CGPoint(x: 96, y: 100))
        path.addCurve(to: CGPoint(x: 55, y: 6), control1: CGPoint(x: 96, y: 36), control2: CGPoint(x: 82, y: 6))
        path.closeSubpath()

        return path.applying(transform)
    }
}

struct EggHalf: Shape {
    let isLeft: Bool

    func path(in rect: CGRect) -> Path {
        let eggPath = EggShape().path(in: rect)
        var path = Path()
        let width = rect.width
        let height = rect.height

        if isLeft {
            path.addRect(CGRect(x: 0, y: 0, width: width / 2, height: height))
        } else {
            path.addRect(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        }

        return eggPath.intersection(path)
    }
}

struct EggCracks: Shape {
    let level: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 110
        let scaleY = rect.height / 130
        let transform = CGAffineTransform(scaleX: scaleX, y: scaleY)

        let cracks: [(Int, String)] = [
            (1, "M52 48 L58 58 L53 65"),
            (2, "M58 58 L66 54 L70 62 M52 48 L46 44 L42 52"),
            (3, "M55 65 L59 76 L54 83 M42 52 L36 57 L40 64 M70 62 L76 66 L72 74"),
            (4, "M47 38 L42 32 L48 28 M64 40 L70 34 M46 95 L40 103 M66 92 L72 100 L68 108")
        ]

        for (minLevel, d) in cracks where level >= minLevel {
            path.addPath(parseSVGPath(d).applying(transform))
        }

        return path
    }

    private func parseSVGPath(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        var index = d.startIndex

        func parseNumber() -> CGFloat? {
            // Skip whitespace and commas
            while index < d.endIndex && (d[index] == " " || d[index] == ",") {
                d.formIndex(after: &index)
            }
            guard index < d.endIndex else { return nil }

            let start = index
            if d[index] == "-" {
                d.formIndex(after: &index)
            }
            var hasDigit = false
            var hasDot = false
            while index < d.endIndex {
                let c = d[index]
                if c.isNumber {
                    hasDigit = true
                    d.formIndex(after: &index)
                } else if c == "." && !hasDot {
                    hasDot = true
                    d.formIndex(after: &index)
                } else {
                    break
                }
            }
            guard hasDigit else { return nil }
            let numStr = String(d[start..<index])
            return CGFloat(Double(numStr) ?? 0)
        }

        var currentCommand: Character = " "

        while index < d.endIndex {
            // Skip whitespace
            while index < d.endIndex && d[index] == " " {
                d.formIndex(after: &index)
            }
            guard index < d.endIndex else { break }

            // Check for command letter
            if d[index].isLetter {
                currentCommand = d[index]
                d.formIndex(after: &index)
            }

            guard let x = parseNumber(), let y = parseNumber() else { break }

            switch currentCommand {
            case "M":
                current = CGPoint(x: x, y: y)
                path.move(to: current)
                currentCommand = "L" // Subsequent coords are treated as line-to
            case "L", "l":
                current = CGPoint(x: x, y: y)
                path.addLine(to: current)
            default:
                break
            }
        }

        return path
    }
}

private func eggShape(crackLevel: Int) -> some View {
    ZStack {
        // Shadow
        Ellipse()
            .fill(Color.brown.opacity(0.18))
            .frame(width: 48, height: 8)
            .offset(y: 62)

        // Egg body
        EggShape()
            .fill(Color(hex: 0xFEF6E4))
            .overlay(
                EggShape()
                    .stroke(Color(hex: 0xC8A882), lineWidth: 3.5)
            )

        // Cracks
        EggCracks(level: crackLevel)
            .stroke(Color(hex: 0xC8A882), lineWidth: 2)
    }
}

private func eggHalf(isLeft: Bool) -> some View {
    EggHalf(isLeft: isLeft)
        .fill(Color(hex: 0xFEF6E4))
        .overlay(
            EggHalf(isLeft: isLeft)
                .stroke(Color(hex: 0xC8A882), lineWidth: 3.5)
        )
}

// MARK: - Effects

struct ShakeEffect: ViewModifier {
    let shake: Bool

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(shake ? -6 : 0))
            .offset(x: shake ? -3 : 0)
            .animation(
                shake
                    ? .easeInOut(duration: 0.08).repeatForever(autoreverses: true)
                    : .spring(response: 0.18, dampingFraction: 0.5),
                value: shake
            )
    }
}

struct EggProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 5)
                .fill(AppTheme.accent.opacity(0.15))
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(AppTheme.accent)
                        .frame(width: CGFloat(configuration.fractionCompleted ?? 0) * geometry.size.width)
                        .animation(.linear(duration: 0.1), value: configuration.fractionCompleted)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .frame(height: 10)
    }
}

// MARK: - Color Helper

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

// MARK: - Preview

#Preview {
    EggGameCloneView(isLocked: .constant(false))
}
