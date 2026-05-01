import Combine
import Foundation

@MainActor
final class AppBannerCenter: ObservableObject {
    static let shared = AppBannerCenter()

    @Published var message: String?
    private var revision = 0

    private init() {}

    func show(_ message: String, duration: TimeInterval = 2.4) {
        revision += 1
        let currentRevision = revision
        self.message = message

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if self.revision == currentRevision {
                self.message = nil
            }
        }
    }

    func showPersistent(_ message: String) {
        revision += 1
        self.message = message
    }

    func hide(ifShowing message: String? = nil) {
        guard message == nil || self.message == message else { return }
        revision += 1
        self.message = nil
    }
}
