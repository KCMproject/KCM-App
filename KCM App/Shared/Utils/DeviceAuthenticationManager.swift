import LocalAuthentication

@MainActor
final class DeviceAuthenticationManager {
    static let shared = DeviceAuthenticationManager()

    private init() {}

    func authenticate(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "キャンセル"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw authError ?? LAError(.biometryNotAvailable)
        }

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? LAError(.authenticationFailed))
                }
            }
        }
    }
}
