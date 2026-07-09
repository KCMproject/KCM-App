import SwiftUI

struct AppRootView: View {
    @StateObject private var loginViewModel = LoginViewModel.shared
    @StateObject private var bannerCenter = AppBannerCenter.shared
    @AppStorage(AppSettings.termsAgreed) private var termsAgreed = false

    var body: some View {
        Group {
            if (loginViewModel.isLoggedIn && loginViewModel.isReady) || loginViewModel.shouldShowCachedPortal {
                PortalCloneView(onLogout: {
                    Task {
                        await loginViewModel.logout()
                    }
                })
            } else {
                LoginView(viewModel: loginViewModel)
            }
        }
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                if let message = bannerCenter.message {
                    Text(message)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(AppTheme.accent.opacity(0.95))
                        )
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if loginViewModel.isLoading && !loginViewModel.isLoggedIn && loginViewModel.shouldShowCachedPortal {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("自動ログイン中…")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(AppTheme.accent.opacity(0.95))
                    )
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            loginViewModel.checkSession()
        }
        .animation(.easeInOut(duration: 0.2), value: bannerCenter.message)
        .animation(.easeInOut(duration: 0.2), value: loginViewModel.isLoading)
        .fullScreenCover(isPresented: .init(
            get: { !termsAgreed },
            set: { if !$0 { } }
        )) {
            TermsAgreementView()
        }
    }
}

private struct TermsAgreementView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.termsAgreed) private var termsAgreed = false
    @State private var hasScrolledToBottom = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("KCM App")
                    .font(.system(size: 24, weight: .bold))
                Text("ご利用にあたって")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textMuted)
            }
            .padding(.top, 40)
            .padding(.bottom, 16)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(agreementContent)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .global).maxY) { _, maxY in
                                        let screenHeight = UIScreen.main.bounds.height
                                        if maxY <= screenHeight - 100 {
                                            hasScrolledToBottom = true
                                        }
                                    }
                            }
                        )
                }
            }

            VStack(spacing: 12) {
                Button {
                    termsAgreed = true
                    dismiss()
                } label: {
                    Text("同意する")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(hasScrolledToBottom ? AppTheme.accent : Color.gray)
                        )
                        .padding(.horizontal, 24)
                }
                .disabled(!hasScrolledToBottom)

                Text("上記の内容をご確認の上、「同意する」をタップしてください。")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.textSoft)
                    .padding(.bottom, 8)
            }
            .padding(.top, 8)
            .background(Color.white.shadow(color: .black.opacity(0.05), radius: 4, y: -2))
        }
        .background(AppTheme.background.ignoresSafeArea())
        .ignoresSafeArea(.keyboard)
    }
}

private let agreementContent = """
本アプリ（KCM App）をご利用いただく前に、以下の内容をご確認ください。

■ 非公式アプリについて
本アプリは国立音楽大学の公式アプリではなく、非公式のサードパーティクライアントです。国立音楽大学とは一切関係がなく、大学による承認、推奨、または支援を受けたものではありません。

■ 認証情報について
本アプリでは、CampusSquareポータルにログインするための学籍番号とパスワードを入力していただきます。これらの情報はiOSのKeychainに暗号化されて端末内にのみ保存され、運営者を含む第三者が取得することはできません。

■ 免責事項
本アプリはCampusSquareポータルのHTMLを解析して動作しており、大学側の仕様変更により正常に動作しなくなる可能性があります。これにより生じたいかなる損害についても、運営者は一切の責任を負いません。

■ オープンソース
本アプリのソースコードはMITライセンスの下でGitHubに公開されています。

詳細な利用規約およびプライバシーポリシーは、アプリ内の「アカウント」タブからご確認いただけます。
"""

#Preview("Logged Out") {
    AppRootView()
}
