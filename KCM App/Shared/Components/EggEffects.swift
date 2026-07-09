import SwiftUI

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
