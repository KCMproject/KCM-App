import SwiftUI

struct AppRootView: View {
    @StateObject private var loginViewModel = LoginViewModel()
    private let portalService: PortalSessionManaging = MockPortalService()

    var body: some View {
        Group {
            if loginViewModel.isLoggedIn {
                MainTabView(portalService: portalService, onLogout: loginViewModel.logout)
            } else {
                LoginView(viewModel: loginViewModel)
            }
        }
    }
}

private struct MainTabView: View {
    let portalService: PortalSessionManaging
    let onLogout: () -> Void

    var body: some View {
        TabView {
            NavigationStack {
                BoardListView(items: portalService.fetchAnnouncements())
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Logout", action: onLogout)
                        }
                    }
            }
            .tabItem {
                Label("掲示板", systemImage: "text.bubble")
            }

            NavigationStack {
                TimetableView(courses: portalService.fetchCourses())
            }
            .tabItem {
                Label("時間割", systemImage: "calendar")
            }
        }
        .tint(AppTheme.accent)
    }
}

#Preview("Logged Out") {
    AppRootView()
}
