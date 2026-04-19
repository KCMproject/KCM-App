import SwiftUI

struct AccountProfileCloneView: View {
    struct TabOrderItem: Identifiable, Codable, Hashable {
        let id: String
        let title: String
        let icon: String
    }

    @AppStorage(AppSettings.pushNotificationsEnabled) private var pushEnabled = true
    @AppStorage(AppSettings.reminderEnabled) private var reminderEnabled = true
    @AppStorage(AppSettings.darkModeEnabled) private var darkEnabled = false
    @State private var tabOrder: [TabOrderItem] = [
        .init(id: "today", title: "今日", icon: "calendar"),
        .init(id: "timetable", title: "時間割", icon: "calendar.badge.clock"),
        .init(id: "board", title: "掲示板", icon: "tray.full")
    ]
    let onLogout: () -> Void
    let onTabOrderChanged: ([TabOrderItem]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                settingsView
            }
            .background(AppTheme.accountBackground)
            .refreshable {
                await PortalDataCoordinator.shared.refreshAll(showUpdateBanner: true)
            }
        }
        .background(AppTheme.accountBackground)
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color(red: 0.29, green: 0.36, blue: 0.45))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text("橋")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("ハシグチ")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("工学部 情報工学科 3年")
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.textMuted)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)
        }
        .background(Color.white)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.border).frame(height: 1)
        }
    }

    private var settingsView: some View {
        VStack(spacing: 20) {
            settingsSection(
                title: "タブ",
                rows: [],
                customContent: AnyView(tabOrderSettingsList)
            )

            settingsSection(
                title: "通知",
                rows: [
                    .toggle("bell", AppTheme.accent, "プッシュ通知", nil, $pushEnabled),
                    .toggle("bell", AppTheme.favorite, "授業前リマインダー", "15分前", $reminderEnabled)
                ]
            )

            settingsSection(
                title: "表示",
                rows: [
                    .toggle("moon.fill", Color.indigo, "ダークモード", nil, $darkEnabled)
                ]
            )

            settingsSection(
                title: "アカウント",
                rows: [
                    .link("shield", Color.green, "プライバシー設定", "学内データのみ扱います", {}),
                    .link("info.circle", AppTheme.textSoft, "アプリについて", "v1.0.0", {}),
                    .link("rectangle.portrait.and.arrow.right", AppTheme.danger.opacity(0.8), "ログアウト", nil, onLogout)
                ]
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 32)
    }

    private var tabOrderSettingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("タブの順序（ドラッグで入れ替え）")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSoft)
                .padding(.horizontal, 4)

            List {
                ForEach(Array(tabOrder.enumerated()), id: \.element.id) { _, item in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.grayPill)
                            .frame(width: 32, height: 32)
                            .overlay {
                                Image(systemName: item.icon)
                                    .foregroundStyle(AppTheme.accent)
                            }

                        Text(item.title)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer()

                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textMuted)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.white)
                }
                .onMove { source, destination in
                    tabOrder.move(fromOffsets: source, toOffset: destination)
                    onTabOrderChanged(tabOrder)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(tabOrder.count) * 60)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.gray.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
        }
    }

    @ViewBuilder
    private func settingsSection(title: String, rows: [SettingRow], customContent: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSoft)
                .padding(.horizontal, 4)

            if let customContent {
                customContent
            }

            if !rows.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.grayPill)
                                .frame(width: 32, height: 32)
                                .overlay {
                                    Image(systemName: row.icon)
                                        .foregroundStyle(row.color)
                                }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                    .font(.system(size: 14))
                                    .foregroundStyle(AppTheme.textPrimary)
                                if let subtitle = row.subtitle {
                                    Text(subtitle)
                                        .font(.system(size: 12))
                                        .foregroundStyle(AppTheme.textMuted)
                                }
                            }

                            Spacer()

                            switch row.kind {
                            case .toggle(let binding):
                                Toggle("", isOn: binding)
                                    .labelsHidden()
                                    .tint(AppTheme.accent)
                            case .link(let action):
                                Button(action: action) {
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(Color.gray.opacity(0.5))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        if index < rows.count - 1 {
                            Rectangle()
                                .fill(Color.gray.opacity(0.12))
                                .frame(height: 1)
                        }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.gray.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 4, y: 1)
            }
        }
        .background(Color.clear)
    }
}

#Preview {
    AccountProfileCloneView(onLogout: {}) { _ in
    }
}
