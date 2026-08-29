import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct AccountProfileCloneView: View {
    struct TabOrderItem: Identifiable, Codable, Hashable {
        let id: String
        let title: String
        let icon: String
    }

    let onLogout: () -> Void
    let onTabOrderChanged: ([TabOrderItem]) -> Void

    @AppStorage(AppSettings.tabBarConfiguration) private var tabBarData: Data = Data()
    @AppStorage(AppSettings.gameTabEnabled) private var gameTabEnabled = true
    @AppStorage(AppSettings.pushNotificationsEnabled) private var pushNotificationsEnabled = false
    @State private var tabOrder: [TabOrderItem] = []
    @StateObject private var loginViewModel = LoginViewModel.shared
    @State private var showingPasswordManager = false
    @State private var authenticationErrorMessage: String?
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    @State private var isDownloadingGradeReport = false
    @State private var gradeReportFileURL: URL?
    @State private var showGradeReportShare = false
    @State private var gradeReportDownloadError: String?
    @State private var showingAppInfo = false

    private let cacheStore = PortalCacheStore.shared

    private let defaultTabOrder: [TabOrderItem] = [
        .init(id: "today", title: "今日", icon: "calendar"),
        .init(id: "timetable", title: "時間割", icon: "calendar.badge.clock"),
        .init(id: "board", title: "掲示板", icon: "tray.full")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                settingsView
            }
            .background(AppTheme.accountBackground)
            .onScrollGeometryChange(for: ScrollInfo.self) { geometry in
                let maxOffset = max(0, geometry.contentSize.height - geometry.visibleRect.height)
                return ScrollInfo(offset: geometry.contentOffset.y, maxOffset: maxOffset)
            } action: { old, new in
                TabBarScrollState.shared.handleScroll(oldOffset: old.offset, newOffset: new.offset, maxOffset: new.maxOffset)
            }
            .refreshable {
                await PortalDataCoordinator.shared.refreshAll(showUpdateBanner: true)
            }
        }
        .background(AppTheme.accountBackground)
        .sheet(isPresented: $showingPasswordManager) {
            PasswordManagementView(
                initialCredentials: loginViewModel.loadSavedCredentials(),
                isAutofillEnabled: true
            ) { studentID, password in
                loginViewModel.saveCredentials(studentID: studentID, password: password)
            }
        }
        .sheet(isPresented: $showingTerms) {
            LegalDocumentView(title: "利用規約", content: accountTermsContent)
        }
        .sheet(isPresented: $showingPrivacy) {
            LegalDocumentView(title: "プライバシーポリシー", content: accountPrivacyContent)
        }
        .sheet(isPresented: $showGradeReportShare) {
            if let url = gradeReportFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .alert("ダウンロード失敗", isPresented: .init(
            get: { gradeReportDownloadError != nil },
            set: { if !$0 { gradeReportDownloadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(gradeReportDownloadError ?? "不明なエラー")
        }
        .alert("認証できませんでした", isPresented: authenticationAlertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authenticationErrorMessage ?? "時間をおいて再度お試しください。")
        }
        .onAppear(perform: syncTabOrderFromStorage)
        .onChange(of: pushNotificationsEnabled) { _, enabled in
            guard enabled else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        .onChange(of: tabBarData) { _, _ in
            syncTabOrderFromStorage()
        }
        .alert("KCM App", isPresented: $showingAppInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
            Text("バージョン \(version) (build \(build))\n\n非公式CampusSquareクライアント")
        }
    }

    private var header: some View {
        let userName = cacheStore.loadUserName() ?? ""
        let userReading = cacheStore.loadUserReading() ?? ""
        let initial = String(userName.isEmpty ? "?" : userName.prefix(1))

        return VStack(spacing: 0) {
            HStack(spacing: 16) {
                Circle()
                    .fill(Color(red: 0.29, green: 0.36, blue: 0.45))
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text(initial)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(userReading.isEmpty ? userName : userReading)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    if !userName.isEmpty {
                        Text(userName)
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.textMuted)
                    }
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
                rows: [
                    .toggle("gamecontroller", AppTheme.accent, "ゲームタブを表示", nil, "gameTab")
                ],
                customContent: { tabOrderSettingsList }
            )

            settingsSection(
                title: "通知",
                rows: [
                    .toggle("bell", AppTheme.accent, "お知らせ通知", "新着のお知らせを通知で受け取る", "pushNotifications")
                ]
            )

            settingsSection(
                title: "アカウント",
                rows: [
                    .link("lock.shield", Color.orange, "パスワード管理", "保存済みログイン情報を編集", {
                        Task {
                            await authenticateForPasswordManagement()
                        }
                    }),
                    .link("doc.richtext", Color.blue, "成績通知書をダウンロード", isDownloadingGradeReport ? "ダウンロード中..." : nil, {
                        Task {
                            await downloadGradeReport()
                        }
                    }),
                    .link("info.circle", AppTheme.textSoft, "アプリについて", nil, { showingAppInfo = true }),
                    .link("exclamationmark.bubble", AppTheme.accent, "アプリへのご意見", "フィードバックを送る", {
                        if let url = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSeRo82PhT8RFdF0JVs5NUu0zNqalONR8n_vwnakIptR8n7YIA/viewform?usp=publish-editor") {
                            UIApplication.shared.open(url)
                        }
                    }),
                    .link("rectangle.portrait.and.arrow.right", AppTheme.danger.opacity(0.8), "ログアウト", nil, onLogout)
                ]
            )

            settingsSection(
                title: "法的事項",
                rows: [
                    .link("doc.text", Color.blue, "利用規約", nil, { showingTerms = true }),
                    .link("hand.raised", Color.blue, "プライバシーポリシー", nil, { showingPrivacy = true }),
                ]
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 90)
    }

    private var authenticationAlertBinding: Binding<Bool> {
        Binding(
            get: { authenticationErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    authenticationErrorMessage = nil
                }
            }
        )
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

    private func settingsSection(title: String, rows: [SettingRow]) -> some View {
        settingsSection(title: title, rows: rows, customContent: { EmptyView() })
    }

    private func settingsSection<CustomContent: View>(title: String, rows: [SettingRow], @ViewBuilder customContent: () -> CustomContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.textSoft)
                .padding(.horizontal, 4)

            customContent()

            if !rows.isEmpty {
                VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    switch row.kind {
                    case .toggle(let id):
                        toggleRow(row, id: id)

                    case .link(let action):
                        linkRow(row, action: action)
                    }

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

    private func toggleRow(_ row: SettingRow, id: String) -> some View {
        let binding: Binding<Bool> = {
            switch id {
            case "gameTab":
                return $gameTabEnabled
            case "pushNotifications":
                return $pushNotificationsEnabled
            default:
                return .constant(false)
            }
        }()
        return HStack(spacing: 12) {
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

            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(AppTheme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func linkRow(_ row: SettingRow, action: @escaping () -> Void) -> some View {
        let rowView = HStack(spacing: 12) {
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

            Image(systemName: "chevron.right")
                .foregroundStyle(Color.gray.opacity(0.5))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)

        return Button(action: action) {
            rowView.contentShape(Rectangle())
        }
        .buttonStyle(AccountRowButtonStyle())
    }

    private func syncTabOrderFromStorage() {
        guard let decoded = try? JSONDecoder().decode([TabOrderItem].self, from: tabBarData),
              !decoded.isEmpty else {
            tabOrder = defaultTabOrder
            return
        }

        let filtered = decoded.filter { $0.id != "account" }
        tabOrder = filtered.isEmpty ? defaultTabOrder : filtered
    }

    private func downloadGradeReport() async {
        isDownloadingGradeReport = true
        gradeReportDownloadError = nil
        gradeReportFileURL = nil
        do {
            let data = try await loginViewModel.fetchGradeReportPDF()
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("成績通知書.pdf")
            try data.write(to: tempURL)
            gradeReportFileURL = tempURL
            showGradeReportShare = true
        } catch {
            gradeReportDownloadError = error.localizedDescription
        }
        isDownloadingGradeReport = false
    }

    private func authenticateForPasswordManagement() async {
        do {
            try await DeviceAuthenticationManager.shared.authenticate(
                reason: "保存済みログイン情報を表示します"
            )
            showingPasswordManager = true
        } catch {
            authenticationErrorMessage = authenticationMessage(for: error)
        }
    }

    private func authenticationMessage(for error: Error) -> String {
        guard let laError = error as? LAError else { return "生体認証に失敗しました。" }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel:
            return "認証がキャンセルされました。"
        case .biometryNotAvailable:
            return "この端末では生体認証を利用できません。"
        case .biometryNotEnrolled:
            return "Face ID または Touch ID が設定されていません。"
        case .passcodeNotSet:
            return "端末のパスコードが設定されていません。"
        default:
            return "生体認証に失敗しました。"
        }
    }
}

private struct AccountRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.gray.opacity(0.12) : Color.clear)
    }
}

#Preview {
    AccountProfileCloneView(onLogout: {}) { _ in
    }
}
