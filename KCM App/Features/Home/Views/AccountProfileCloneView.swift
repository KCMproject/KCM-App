import LocalAuthentication
import SwiftUI
import UniformTypeIdentifiers

struct AccountProfileCloneView: View {
    struct TabOrderItem: Identifiable, Codable, Hashable {
        let id: String
        let title: String
        let icon: String
    }

    let onLogout: () -> Void
    let onTabOrderChanged: ([TabOrderItem]) -> Void

    @AppStorage(AppSettings.tabBarConfiguration) private var tabBarData: Data = Data()
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

    private let cacheStore = PortalCacheStore.shared

    private let defaultTabOrder: [TabOrderItem] = [
        .init(id: "today", title: "今日", icon: "calendar"),
        .init(id: "timetable", title: "時間割", icon: "calendar.badge.clock"),
        .init(id: "board", title: "掲示板", icon: "tray.full")
    ]

    var body: some View {
        VStack(spacing: 0) {
            AccountHeader(
                userName: cacheStore.loadUserName() ?? "",
                userReading: cacheStore.loadUserReading() ?? ""
            )
            ScrollView {
                settingsView
            }
            .background(AppTheme.accountBackground)
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
            LegalDocumentView(title: "利用規約", content: termsContent)
        }
        .sheet(isPresented: $showingPrivacy) {
            LegalDocumentView(title: "プライバシーポリシー", content: privacyContent)
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
        .onChange(of: tabBarData) { _, _ in
            syncTabOrderFromStorage()
        }
    }

    private var settingsView: some View {
        VStack(spacing: 20) {
            SettingsSection(
                title: "タブ",
                rows: [],
                customContent: AnyView(TabOrderSettingsList(
                    tabOrder: $tabOrder,
                    onOrderChanged: onTabOrderChanged
                ))
            )

            SettingsSection(
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
                    .link("info.circle", AppTheme.textSoft, "アプリについて", "v1.0.0", {}),
                    .link("exclamationmark.bubble", AppTheme.accent, "アプリへのご意見", "フィードバックを送る", {
                        if let url = URL(string: "https://docs.google.com/forms/d/e/1FAIpQLSeRo82PhT8RFdF0JVs5NUu0zNqalONR8n_vwnakIptR8n7YIA/viewform?usp=publish-editor") {
                            UIApplication.shared.open(url)
                        }
                    }),
                    .link("xmark.shield", Color.orange.opacity(0.8), "セッションをクリア", "デバッグ用: Cookieとセッションを削除します", {
                        Task {
                            await loginViewModel.clearSession()
                        }
                    }),
                    .link("rectangle.portrait.and.arrow.right", AppTheme.danger.opacity(0.8), "ログアウト", nil, onLogout)
                ]
            )

            SettingsSection(
                title: "法的事項",
                rows: [
                    .link("doc.text", Color.blue, "利用規約", nil, { showingTerms = true }),
                    .link("hand.raised", Color.blue, "プライバシーポリシー", nil, { showingPrivacy = true })
                ]
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 32)
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
        if let laError = error as? LAError {
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

        return "生体認証に失敗しました。"
    }
}

#Preview {
    AccountProfileCloneView(onLogout: {}) { _ in
    }
}
