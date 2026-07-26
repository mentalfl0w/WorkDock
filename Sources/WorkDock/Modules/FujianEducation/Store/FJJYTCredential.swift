import Foundation

/// Fujian Education module's credential shape — specializes the generic
/// ``LoginView`` with this platform's labels and login call.
public struct FJJYTCredential: CredentialDescriptor {
    public let identifier: String
    public let secret: String

    public static let identifierLabel = L.username
    public static let secretLabel = L.password

    public static func make(identifier: String, secret: String) -> FJJYTCredential {
        FJJYTCredential(identifier: identifier, secret: secret)
    }

    /// Probe authentication. We can't run the real spider here without
    /// referencing the module, so this is a no-op probe; the actual login
    /// happens in the `onSubmit` callback the module passes to `LoginView`.
    public func authenticate() async throws {
        // Real authentication is delegated to FujianEducationModule.signIn;
        // this exists to satisfy CredentialDescriptor. Throw if fields empty.
        guard !identifier.isEmpty, !secret.isEmpty else {
            throw NSError(domain: "FJJYTCredential", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L.credentialEmpty])
        }
    }
}
