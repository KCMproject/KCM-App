import SwiftUI

@main
struct KCM_AppApp: App {
    init() {
        UIScrollView.appearance().contentInsetAdjustmentBehavior = .never
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}
