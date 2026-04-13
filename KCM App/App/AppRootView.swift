import SwiftUI

struct AppRootView: View {
    @StateObject private var loginViewModel = LoginViewModel()

    var body: some View {
        Group {
            if loginViewModel.isLoggedIn {
                PortalCloneView(onLogout: loginViewModel.logout)
            } else {
                LoginView(viewModel: loginViewModel)
            }
        }
    }
}

#Preview("Logged Out") {
    AppRootView()
}
