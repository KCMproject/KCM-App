import Combine
import SwiftUI

/// スクロールジオメトリの監視結果
struct ScrollInfo: Equatable {
    var offset: CGFloat
    var maxOffset: CGFloat
}

/// タブバーの折りたたみ状態をコンテンツ側から共有するためのステート
@MainActor
final class TabBarScrollState: ObservableObject {
    static let shared = TabBarScrollState()

    @Published var isScrolledDown = false

    /// ScrollView のスクロール方向を検出して折りたたみ状態を更新する
    /// 下スクロール（コンテンツが上へ移動）で折りたたみ、上スクロールで展開する。
    /// 上下端のバウンス（範囲外のオフセットや端から一定距離内の動き）では状態を切り替えない。
    func handleScroll(oldOffset: CGFloat, newOffset: CGFloat, maxOffset: CGFloat) {
        // バウンス中（スクロール範囲外）は無視
        guard newOffset >= -60, newOffset <= maxOffset + 60 else { return }
        let delta = newOffset - oldOffset
        // 上端から15pt以内・下端から15pt以内の動きはバウンスの可能性があるため無視
        if delta > 3, newOffset > 15 {
            isScrolledDown = true
        } else if delta < -3, newOffset < maxOffset - 15 {
            isScrolledDown = false
        }
    }
}
