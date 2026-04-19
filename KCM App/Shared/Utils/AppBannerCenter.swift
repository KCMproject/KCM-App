import Combine
import Foundation

@MainActor
final class AppBannerCenter: ObservableObject {
    static let shared = AppBannerCenter()

    @Published var message: String?

    private init() {}

    func show(_ message: String, duration: TimeInterval = 2.4) {
        self.message = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self.message == message {
                self.message = nil
            }
        }
    }
}
