import SwiftUI

struct AppRootView: View {
    @StateObject private var loginViewModel = LoginViewModel.shared
    @StateObject private var bannerCenter = AppBannerCenter.shared

    var body: some View {
        Group {
            if loginViewModel.isLoggedIn || loginViewModel.shouldShowCachedPortal {
                PortalCloneView(onLogout: loginViewModel.logout)
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
        .onAppear {
            PortalDataCoordinator.shared.loadCachedData()
            loginViewModel.checkSession()
        }
        .animation(.easeInOut(duration: 0.2), value: bannerCenter.message)
    }
}

#Preview("Logged Out") {
    AppRootView()
}
