import SwiftUI

struct AppRootView: View {
    @StateObject private var loginViewModel = LoginViewModel.shared
    @StateObject private var bannerCenter = AppBannerCenter.shared

    var body: some View {
        Group {
            if loginViewModel.isLoggedIn || loginViewModel.shouldShowCachedPortal {
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
        }
        .overlay(alignment: .top) {
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
        .onAppear {
            loginViewModel.checkSession()
        }
        .animation(.easeInOut(duration: 0.2), value: bannerCenter.message)
        .animation(.easeInOut(duration: 0.2), value: loginViewModel.isLoading)
    }
}

#Preview("Logged Out") {
    AppRootView()
}
