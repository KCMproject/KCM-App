import SwiftUI

// MARK: - Game Configuration

struct EggGameConfig {
    static let isDebugMode = false
    static let tapsPerTap = 1
    static let tapsPerSpawn = 1_000
    static let debugWeight: Double = 20
}

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

struct EggGameCharacters {
    static let base: [CharDef] = [
        CharDef(id: "normal", name: "ノーマル", rarity: "NORMAL", rarityColor: .gray, imageName: "char_normal", weight: 80, glowColor: .clear),
        CharDef(id: "sunglass", name: "クールくん", rarity: "RARE", rarityColor: .blue, imageName: "char_sunglass", weight: 7, glowColor: .blue.opacity(0.3)),
        CharDef(id: "aloha", name: "アロハくん", rarity: "RARE", rarityColor: .green, imageName: "char_aloha", weight: 6.99, glowColor: .green.opacity(0.3)),
        CharDef(id: "red", name: "赤シャツくん", rarity: "SUPER RARE", rarityColor: .red, imageName: "char_red", weight: 6, glowColor: .red.opacity(0.3)),
        CharDef(id: "gold", name: "ゴールド", rarity: "LEGENDARY", rarityColor: .yellow, imageName: "char_gold", weight: 0.01, glowColor: .yellow.opacity(0.5))
    ]

    static var all: [CharDef] {
        guard EggGameConfig.isDebugMode else { return base }
        return base.map { CharDef(id: $0.id, name: $0.name, rarity: $0.rarity, rarityColor: $0.rarityColor, imageName: $0.imageName, weight: EggGameConfig.debugWeight, glowColor: $0.glowColor) }
    }
}

enum EggGameRandom {
    static func pickChar() -> CharDef {
        let all = EggGameCharacters.all
        let totalWeight = all.reduce(0) { $0 + $1.weight }
        var r = Double.random(in: 0..<totalWeight)
        for char in all {
            r -= char.weight
            if r <= 0 { return char }
        }
        return all[0]
    }
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
}

// MARK: - View

struct EggGameCloneView: View {
    @Binding var isLocked: Bool
    @ObservedObject private var state = EggGameState.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppTheme.pageBackground

                gameArea(geometry: geometry)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onAppear {
                state.gameSize = geometry.size
                state.loadGameState()
                state.startGameLoop()
            }
            .onChange(of: geometry.size) { _, newSize in
                state.gameSize = newSize
            }
        }
        .background(AppTheme.pageBackground.ignoresSafeArea())
        .onDisappear {
            state.stopGameLoop()
            state.saveGameState()
        }
        .onChange(of: state.tapCount) { _, _ in
            state.saveGameState()
        }
        .onChange(of: state.collection) { _, _ in
            state.saveGameState()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            state.saveGameState()
        }
    }

    // MARK: Game Area

    private func gameArea(geometry: GeometryProxy) -> some View {
        ZStack {
            ForEach(state.walkers) { walker in
                characterView(walker)
            }

            if state.showPopAnnouncement, let lastPopped = state.lastPopped {
                popAnnouncement(char: lastPopped)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            VStack(spacing: 16) {
                if state.currentCycle > 0 {
                    Text("\(state.currentCycle) 回割った！")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppTheme.textBlue)
                }

                eggButton
                    .frame(width: 120, height: 140)

                if state.hatchPhase == .none {
                    ProgressView(value: Double(state.tapCount % EggGameConfig.tapsPerSpawn), total: Double(EggGameConfig.tapsPerSpawn))
                        .progressViewStyle(EggProgressStyle())
                        .frame(width: 180)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            collectionList
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 12)
                .padding(.bottom, 12)

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
        .frame(width: geometry.size.width, height: geometry.size.height)
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
                .frame(width: state.charSize, height: state.charSize)
                .scaleEffect(x: walker.flipped ? -1 : 1, y: 1)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        }
        .position(x: walker.x + state.charSize / 2, y: walker.y + state.charSize / 2)
        .scaleEffect(walker.scale)
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
            ForEach(state.tapRipples) { ripple in
                Circle()
                    .stroke(AppTheme.accent.opacity(0.4), lineWidth: 2)
                    .frame(width: 60, height: 60)
                    .scaleEffect(1.0 + CGFloat(Date().timeIntervalSince(ripple.createdAt)) * 4.0)
                    .opacity(1.0 - CGFloat(Date().timeIntervalSince(ripple.createdAt)) * 3.0)
            }

            eggVisual
                .scaleEffect(state.eggScale)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.handleEggTap()
        }
    }

    private var eggVisual: some View {
        ZStack {
            switch state.hatchPhase {
            case .none:
                eggShape(crackLevel: state.crackLevel)

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
            Circle()
                .fill(state.hatchChar?.id == "gold" ? Color.yellow.opacity(0.6) : Color.white.opacity(0.8))
                .frame(width: 160, height: 160)
                .scaleEffect(1.5 - state.shellSplitProgress * 0.5)
                .opacity(1 - state.shellSplitProgress)

            eggHalf(isLeft: true)
                .offset(x: -55 * state.shellSplitProgress, y: -60 * state.shellSplitProgress)
                .rotationEffect(.degrees(-45 * state.shellSplitProgress))
                .opacity(1 - state.shellSplitProgress)

            eggHalf(isLeft: false)
                .offset(x: 55 * state.shellSplitProgress, y: -60 * state.shellSplitProgress)
                .rotationEffect(.degrees(45 * state.shellSplitProgress))
                .opacity(1 - state.shellSplitProgress)

            ForEach(0..<12) { i in
                sparkle(at: i)
            }
        }
    }

    private var revealingEgg: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            (state.hatchChar?.glowColor ?? AppTheme.accent.opacity(0.5)),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(0.5 + state.revealProgress * 2)
                .opacity(1 - state.revealProgress)

            if let hatchChar = state.hatchChar {
                Image(hatchChar.imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    .scaleEffect(0.3 + state.revealProgress * 0.9)
                    .offset(y: 20 - state.revealProgress * 28)
                    .opacity(state.revealProgress)
            }

            ForEach(0..<6) { i in
                starTrail(at: i)
            }
        }
    }

    private func sparkle(at index: Int) -> some View {
        let angle = Double(index) * (2 * .pi / 12)
        let distance: CGFloat = 50 + CGFloat(index % 3) * 15
        let colors: [Color] = state.hatchChar?.id == "gold" ? [.yellow, .orange] : [.blue.opacity(0.7), .yellow.opacity(0.7)]

        return Circle()
            .fill(colors[index % 2])
            .frame(width: 8, height: 8)
            .offset(
                x: cos(angle) * distance * state.shellSplitProgress,
                y: sin(angle) * distance * state.shellSplitProgress
            )
            .opacity(1 - state.shellSplitProgress)
            .scaleEffect(1 - state.shellSplitProgress * 0.5)
    }

    private func starTrail(at index: Int) -> some View {
        let angle = Double(index) * (2 * .pi / 6)
        let distance: CGFloat = 30 + state.revealProgress * 40

        return Text(state.hatchChar?.id == "gold" ? "✨" : "⭐")
            .font(.system(size: 16))
            .offset(
                x: cos(angle) * distance,
                y: sin(angle) * distance
            )
            .opacity(1 - state.revealProgress)
            .scaleEffect(1 - state.revealProgress * 0.7)
    }

    // MARK: Collection List

    private var collectionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(EggGameCharacters.all) { char in
                collectionRow(char: char)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
    }

    private func collectionRow(char: CharDef) -> some View {
        let count = state.collection[char.id, default: 0]
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
}

// MARK: - Egg Rendering Helpers

private func eggShape(crackLevel: Int) -> some View {
    ZStack {
        Ellipse()
            .fill(Color.brown.opacity(0.18))
            .frame(width: 48, height: 8)
            .offset(y: 62)

        EggShape()
            .fill(Color(hex: 0xFEF6E4))
            .overlay(
                EggShape()
                    .stroke(Color(hex: 0xC8A882), lineWidth: 3.5)
            )

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

// MARK: - Preview

#Preview {
    EggGameCloneView(isLocked: .constant(false))
}
