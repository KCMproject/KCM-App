import SwiftUI

enum AppTheme {
    // MARK: - ライトモードカラー
    static let accent = Color(red: 0.13, green: 0.41, blue: 0.86)
    static let background = Color(red: 0.96, green: 0.97, blue: 0.99)
    static let surface = Color.white
    static let pageBackground = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let accountBackground = Color(red: 0.97, green: 0.98, blue: 0.99)
    static let textPrimary = Color(red: 0.19, green: 0.24, blue: 0.30)
    static let textSecondary = Color(red: 0.37, green: 0.42, blue: 0.48)
    static let textMuted = Color(red: 0.58, green: 0.62, blue: 0.69)
    static let textSoft = Color(red: 0.73, green: 0.76, blue: 0.82)
    static let textBlue = Color(red: 0.31, green: 0.62, blue: 0.97)
    static let inactive = Color(red: 0.69, green: 0.72, blue: 0.77)
    static let border = Color.black.opacity(0.08)
    static let grayBorder = Color(red: 0.83, green: 0.85, blue: 0.89)
    static let lightBlueBorder = Color(red: 0.79, green: 0.88, blue: 0.98)
    static let blueCardBorder = Color(red: 0.57, green: 0.76, blue: 0.96)
    static let grayPill = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let favorite = Color(red: 0.96, green: 0.73, blue: 0.22)
    static let danger = Color(red: 0.91, green: 0.24, blue: 0.24)

    // MARK: - ダークモード対応カラー（必要に応じて拡張）
    // 現在はシステムカラーを使用しているため、特別な定義は不要
    // カード背景などは `Color(.systemBackground)` ではなく `AppTheme.surface` を使用すべき
}
