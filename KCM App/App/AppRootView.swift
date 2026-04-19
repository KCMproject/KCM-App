import SwiftUI

struct AppRootView: View {
    @StateObject private var loginViewModel = LoginViewModel(portalClient: PortalClientFactory.makeLoginService())

    var body: some View {
        Group {
            if loginViewModel.isLoggedIn {
                PortalCloneView(onLogout: loginViewModel.logout)
            } else {
                LoginView(viewModel: loginViewModel)
            }
        }
        .onAppear {
            loginViewModel.checkSession()
        }
    }
}

#Preview("Logged Out") {
    AppRootView()
}
