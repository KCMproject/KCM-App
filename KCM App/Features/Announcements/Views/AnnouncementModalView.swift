import SwiftUI

/// ソシャゲのデイリーボーナス風の最前面お知らせモーダル
/// ×ボタンで閉じるとそのお知らせが既読になり、未読が残っていれば次のカードが表示される
struct AnnouncementModalView: View {
    let announcements: [AppAnnouncement]
    let onDismiss: (AppAnnouncement) -> Void

    @State private var isAppeared = false

    private var current: AppAnnouncement? { announcements.first }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            if let announcement = current {
                card(for: announcement)
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

    // MARK: - Card

    private func card(for announcement: AppAnnouncement) -> some View {
        let level = announcement.resolvedLevel

        return VStack(spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(levelColor(level).opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: levelIcon(level))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(levelColor(level))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(levelLabel(level))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(levelColor(level))
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

            if announcements.count > 1 {
                HStack {
                    Spacer()
                    Text("1 / \(announcements.count)")
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
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [levelColor(level).opacity(0.16), levelColor(level).opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        )
        .overlay(alignment: .topTrailing) {
            closeButton(for: announcement)
                .padding(10)
        }
    }

    private func closeButton(for announcement: AppAnnouncement) -> some View {
        Button {
            onDismiss(announcement)
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

    private func levelColor(_ level: AnnouncementLevel) -> Color {
        switch level {
        case .info: return AppTheme.accent
        case .warning: return .orange
        case .critical: return AppTheme.danger
        }
    }

    private func levelIcon(_ level: AnnouncementLevel) -> String {
        switch level {
        case .info: return "megaphone.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func levelLabel(_ level: AnnouncementLevel) -> String {
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
        onDismiss: { _ in }
    )
}
