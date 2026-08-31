import SwiftUI

/// ソシャゲのデイリーボーナス風の最前面お知らせモーダル
/// ×ボタンで閉じても次回アプリ起動時にもう一度表示される。
/// 「2度と表示しない」にチェックして閉じると、そのお知らせは二度と表示されない
struct AnnouncementModalView: View {
    let announcements: [AppAnnouncement]
    let onDismiss: (AppAnnouncement, _ neverShowAgain: Bool) -> Void

    @State private var isAppeared = false

    private var current: AppAnnouncement? { announcements.first }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            if let announcement = current {
                AnnouncementCardView(
                    announcement: announcement,
                    pageCount: announcements.count,
                    onDismiss: { neverShowAgain in
                        onDismiss(announcement, neverShowAgain)
                    }
                )
                .id(announcement.id)
                .padding(.horizontal, 36)
                .scaleEffect(isAppeared ? 1 : 0.8)
                .opacity(isAppeared ? 1 : 0)
            }
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) {
                isAppeared = true
            }
        }
        .onChange(of: announcements.first?.id) { _, _ in
            // 次のカードに切り替わったときにバウンドインを再生する
            isAppeared = false
            withAnimation(.spring(response: 0.38, dampingFraction: 0.62).delay(0.05)) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Card

private struct AnnouncementCardView: View {
    let announcement: AppAnnouncement
    let pageCount: Int
    let onDismiss: (_ neverShowAgain: Bool) -> Void

    @State private var neverShowAgain = false

    private var level: AnnouncementLevel { announcement.resolvedLevel }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(levelColor.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: levelIcon)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(levelColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(levelLabel)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(levelColor)
                    if let date = announcement.date, !date.isEmpty {
                        Text(date)
                            .font(.system(size: 11))
                            .foregroundStyle(AppTheme.textSoft)
                    }
                }

                Spacer()
            }

            Text(announcement.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(announcement.body)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                neverShowAgain.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: neverShowAgain ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17))
                        .foregroundStyle(neverShowAgain ? levelColor : AppTheme.textMuted)
                    Text("2度と表示しない")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textSecondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if pageCount > 1 {
                HStack {
                    Spacer()
                    Text("1 / \(pageCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.textMuted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(AppTheme.grayPill)
                        )
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.accent.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        )
        .overlay(alignment: .topTrailing) {
            closeButton
                .padding(10)
        }
    }

    private var closeButton: some View {
        Button {
            onDismiss(neverShowAgain)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppTheme.textMuted)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(AppTheme.grayPill)
                )
        }
    }

    // MARK: - Level helpers

    private var levelColor: Color {
        switch level {
        case .info: return AppTheme.accent
        case .warning: return .orange
        case .critical: return AppTheme.danger
        }
    }

    private var levelIcon: String {
        switch level {
        case .info: return "megaphone.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private var levelLabel: String {
        switch level {
        case .info: return "お知らせ"
        case .warning: return "重要なお知らせ"
        case .critical: return "緊急のお知らせ"
        }
    }
}

#Preview {
    AnnouncementModalView(
        announcements: [
            AppAnnouncement(
                id: "preview-1",
                level: .warning,
                title: "ポータル仕様変更のお知らせ",
                body: "大学側ポータルの仕様変更により、時間割の取得や掲示板の表示が正常に行えない場合があります。\n現在修正中のため、しばらくお待ちください。",
                date: "2026-08-29",
                active: true
            )
        ],
        onDismiss: { _, _ in }
    )
}
