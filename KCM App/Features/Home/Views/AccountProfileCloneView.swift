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
                rows: [],
                customContent: AnyView(tabOrderSettingsList)
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
                    switch row.kind {
                    case .toggle(let binding):
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

                            Toggle("", isOn: binding)
                                .labelsHidden()
                                .tint(AppTheme.accent)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                    case .link(let action):
                        Button(action: action) {
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

                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Color.gray.opacity(0.5))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
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

private struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private let termsContent = """
KCM App 利用規約

はじめに
本利用規約（以下「本規約」といいます）は、橋口湧吾（以下「運営者」といいます）が提供するiOSアプリ「KCM App」（以下「本アプリ」といいます）の利用条件を定めるものです。本アプリを利用するすべての方（以下「利用者」といいます）は、本規約に同意したものとみなします。

本アプリは国立音楽大学が提供するCampusSquareポータルの非公式サードパーティクライアントであり、国立音楽大学およびその関連機関とは一切関係がありません。

本アプリのソースコードはMITライセンスの下でGitHubに公開されています。

第1条（定義）
本規約において使用する用語の定義は以下の通りです。
(1) 「本アプリ」とは、運営者が提供する「KCM App」をいいます。
(2) 「本サービス」とは、本アプリを通じて提供される一切の機能をいいます。
(3) 「利用者」とは、本アプリをインストールし、利用するすべての方をいいます。
(4) 「運営者」とは、橋口湧吾をいいます。

第2条（同意）
1. 利用者は、本規約の内容に同意した上で本アプリを利用するものとします。
2. 本規約に同意しない場合、利用者は本アプリを利用することはできません。
3. 利用者が本アプリをインストールした時点で、本規約に同意したものとみなします。

第3条（非公式アプリであることの明記）
1. 本アプリは国立音楽大学の公式アプリではなく、非公式のサードパーティクライアントです。
2. 本アプリは国立音楽大学とは一切関係がなく、大学による承認、推奨、または支援を受けたものではありません。
3. 利用者は、本アプリが非公式であることを理解した上で自己の責任において利用するものとします。

第4条（認証情報の管理）
1. 利用者は、本アプリの利用に際して入力する学籍番号およびパスワード（以下「認証情報」といいます）を自らの責任において管理するものとします。
2. 認証情報の入力は利用者の意思によるものとし、認証情報の漏洩、不正使用等により生じたいかなる損害についても、運営者は一切の責任を負いません。
3. 認証情報は、iOS標準のセキュリティ機能（Keychain）を用いて端末内に安全に保管され、運営者を含む第三者が取得することはできません。

第5条（禁止事項）
利用者は、本アプリの利用に際して、以下の行為を行ってはなりません。
(1) 法令または公序良俗に違反する行為
(2) 運営者または第三者の著作権、商標権、プライバシー権、その他の権利を侵害する行為
(3) 国立音楽大学のCampusSquareポータルに対して過剰なリクエストを送信するなど、システムに過度の負荷を与える行為
(4) 本アプリのリバースエンジニアリング、逆コンパイル、逆アセンブル、その他の解析行為
(5) 本アプリを商業目的で利用する行為
(6) 本アプリの運営を妨害する行為
(7) その他、運営者が不適切と判断する行為

第6条（免責事項）
1. 本アプリはCampusSquareポータルのHTMLを解析（スクレイピング）して動作しており、大学側の仕様変更により本アプリの一部または全部が正常に動作しなくなる可能性があります。これにより生じたいかなる損害についても、運営者は一切の責任を負いません。
2. 本アプリを通じて取得される情報の正確性、完全性、有用性等について、運営者は一切保証しません。
3. 本アプリの利用に起因して利用者または第三者に生じたいかなる損害（直接的、間接的、付随的、特別、または結果的損害を含みますが、これに限りません）についても、運営者は一切の責任を負いません。
4. 本アプリは現状有姿（As Is）で提供され、運営者は商品性、特定目的への適合性、権原の不存在等、明示または黙示を問わず一切の保証を行いません。

第7条（知的財産権）
1. 本アプリのソースコード、デザイン、ロゴ、その他コンテンツに関する著作権およびその他の知的財産権は、別途明示されている場合を除き、運営者に帰属します。
2. 本アプリを通じて表示されるCampusSquareポータルのコンテンツに関する一切の権利は、国立音楽大学または正当な権利者に帰属します。
3. 本条の規定は、第8条に定めるオープンソースライセンスの適用を受ける部分については、当該ライセンスの定めが優先されるものとします。

第8条（オープンソースライセンス）
本アプリのソースコードは、MITライセンスの下で公開されています。詳細は本アプリのGitHubリポジトリおよびLICENSEファイルをご参照ください。

第9条（サービスの変更・停止）
1. 運営者は、利用者に事前に通知することなく、本アプリおよび本サービスの内容を変更、追加、または削除することができるものとします。
2. 運営者は、システムの保守、障害対応、その他運営上必要と判断した場合、本サービスの一部または全部を一時的に停止することができるものとします。
3. 運営者は、本アプリおよび本サービスの提供を終了することができるものとします。

第10条（利用規約の変更）
1. 運営者は、必要と判断した場合、本規約を変更することができるものとします。
2. 変更後の本規約は、本アプリ内または運営者が適切と判断する方法で通知し、通知後利用者が本アプリを継続して利用した時点で同意したものとみなします。
3. 変更後の本規約に同意できない場合、利用者は本アプリの利用を中止するものとします。

第11条（準拠法・管轄裁判所）
1. 本規約の解釈および適用は日本法に準拠するものとします。
2. 本規約に関して紛争が生じた場合、東京地方裁判所を第一審の専属的合意管轄裁判所とします。

附則
本規約は2025年xx月xx日から施行します。
"""

private let privacyContent = """
KCM App プライバシーポリシー

個人情報の収集について
本アプリは、以下の個人情報を収集します。
- 学籍番号（CampusSquareログイン用）
- CampusSquareのパスワード

個人情報の利用目的
収集した個人情報は、CampusSquareポータルへのログインおよび本サービスの提供のみに利用します。

個人情報の保管方法
認証情報はiOSのKeychainに暗号化されて保管され、端末外に送信・保存されることはありません。運営者を含む第三者がこれらの情報にアクセスすることはできません。

第三者提供
本アプリは、収集した個人情報を第三者に提供することはありません。

データの保存と削除
本アプリの利用に関するデータ（授業情報、掲示板データ等）は端末内にローカルで保存されます。アプリをアンインストールすることで、これらのデータはすべて削除されます。

アクセス解析
本アプリは、サードパーティのアクセス解析ツールを使用していません。

お問い合わせ
本プライバシーポリシーに関するお問い合わせは、該当のApp StoreページまたはGitHubリポジトリのIssueからお願いいたします。
"""

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    AccountProfileCloneView(onLogout: {}) { _ in
    }
}
