import Foundation
import LocalAuthentication

/// Touch ID ya da Mac parolası ile kimlik doğrulama.
enum Authenticator {
    static func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}
