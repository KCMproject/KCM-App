import LocalAuthentication
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
    @AppStorage(AppSettings.passwordAutofillEnabled) private var passwordAutofillEnabled = false
    @AppStorage(AppSettings.tabBarConfiguration) private var tabBarData: Data = Data()
    @State private var tabOrder: [TabOrderItem] = []
    @StateObject private var loginViewModel = LoginViewModel.shared
    @State private var showingPasswordManager = false
    @State private var authenticationErrorMessage: String?
    let onLogout: () -> Void
    let onTabOrderChanged: ([TabOrderItem]) -> Void

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
            .refreshable {
                await PortalDataCoordinator.shared.refreshAll(showUpdateBanner: true)
            }
        }
        .background(AppTheme.accountBackground)
        .sheet(isPresented: $showingPasswordManager) {
            PasswordManagementView(
                initialCredentials: loginViewModel.loadSavedCredentials(),
                isAutofillEnabled: passwordAutofillEnabled
            ) { studentID, password in
                loginViewModel.saveCredentials(studentID: studentID, password: password)
            }
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
                    .toggle("key.fill", AppTheme.accent, "パスワード自動入力", "起動時に保存済みログイン情報で更新します", bindingForPasswordAutofill),
                    .link("lock.shield", Color.orange, "パスワード管理", "保存済みログイン情報を編集", {
                        Task {
                            await authenticateForPasswordManagement()
                        }
                    }),
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

    private var bindingForPasswordAutofill: Binding<Bool> {
        Binding(
            get: { passwordAutofillEnabled },
            set: { newValue in
                if newValue {
                    Task {
                        await authenticateAndEnablePasswordAutofill()
                    }
                } else {
                    passwordAutofillEnabled = false
                    loginViewModel.setPasswordAutofillEnabled(false)
                }
            }
        )
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

    private func syncTabOrderFromStorage() {
        guard let decoded = try? JSONDecoder().decode([TabOrderItem].self, from: tabBarData),
              !decoded.isEmpty else {
            tabOrder = defaultTabOrder
            return
        }

        let filtered = decoded.filter { $0.id != "account" }
        tabOrder = filtered.isEmpty ? defaultTabOrder : filtered
    }

    private func authenticateAndEnablePasswordAutofill() async {
        do {
            try await DeviceAuthenticationManager.shared.authenticate(
                reason: "パスワード自動入力を有効にします"
            )
            passwordAutofillEnabled = true
            loginViewModel.setPasswordAutofillEnabled(true)
        } catch {
            passwordAutofillEnabled = false
            authenticationErrorMessage = authenticationMessage(for: error)
        }
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

private struct PasswordManagementView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var studentID: String
    @State private var password: String
    let isAutofillEnabled: Bool
    let onSave: (String, String) -> Void

    init(initialCredentials: SavedCredentials?, isAutofillEnabled: Bool, onSave: @escaping (String, String) -> Void) {
        _studentID = State(initialValue: initialCredentials?.studentID ?? "")
        _password = State(initialValue: initialCredentials?.password ?? "")
        self.isAutofillEnabled = isAutofillEnabled
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("保存したログイン情報は端末内に保存されます。自動入力をオンにすると、アプリ起動時にこの情報でログインを試します。")
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.textMuted)

                VStack(spacing: 16) {
                    TextField("学籍番号", text: $studentID)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding()
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    SecureField("パスワード", text: $password)
                        .textFieldStyle(.plain)
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding()
                        .background(AppTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Text(isAutofillEnabled ? "現在は自動入力がオンです" : "現在は自動入力がオフです")
                    .font(.system(size: 13))
                    .foregroundStyle(isAutofillEnabled ? AppTheme.textBlue : AppTheme.textMuted)

                Spacer()
            }
            .padding(24)
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("パスワード管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let trimmedID = studentID.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedID.isEmpty, !trimmedPassword.isEmpty else { return }
                        onSave(trimmedID, trimmedPassword)
                        dismiss()
                    }
                    .disabled(
                        studentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
        }
    }
}

#Preview {
    AccountProfileCloneView(onLogout: {}) { _ in
    }
}
