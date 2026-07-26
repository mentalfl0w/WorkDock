import Foundation
import SwiftUI

/// Credentials a module needs to authenticate.
public protocol Credential: Sendable {
    static var identifierLabel: String { get }
    static var secretLabel: String { get }
    static func make(identifier: String, secret: String) -> Self
    var identifier: String { get }
    var secret: String { get }
}

/// Per-module authentication contract.
public protocol CredentialDescriptor: Credential, Sendable {
    func authenticate() async throws
}

/// Hooks for ``LoginView`` to persist and recall credentials.
public protocol CredentialStore: Sendable {
    func load() async -> (identifier: String, secret: String)?
}

/// Generic, reusable login view.
///
/// - Pre-fills fields from ``CredentialStore`` on appear.
/// - "记住凭据" toggle is passed to `onSubmit` so the module decides whether
///   to persist the password.
/// - Standard `Form` + `.glassProminent` button — system Liquid Glass.
public struct LoginView<C: CredentialDescriptor>: View {
    private let identifierPrompt: String
    private let secretPrompt: String
    private let store: CredentialStore?
    private let onSubmit: @MainActor (C, Bool) async throws -> Void
    private let onCancel: (() -> Void)?

    @State private var identifier: String = ""
    @State private var secret: String = ""
    @State private var remember: Bool = true
    @State private var error: String?
    @State private var submitting: Bool = false
    @Environment(\.moduleBackAction) private var backAction

    public init(
        identifierPrompt: String = C.identifierLabel,
        secretPrompt: String = C.secretLabel,
        store: CredentialStore? = nil,
        onCancel: (() -> Void)? = nil,
        onSubmit: @escaping @MainActor (C, Bool) async throws -> Void
    ) {
        self.identifierPrompt = identifierPrompt
        self.secretPrompt = secretPrompt
        self.store = store
        self.onCancel = onCancel
        self.onSubmit = onSubmit
    }

    public var body: some View {
        Form {
            Section {
                TextField(identifierPrompt, text: $identifier)
                    .textContentType(.username)
                SecureField(secretPrompt, text: $secret)
                    .textContentType(.password)
            }
            .listRowBackground(Color.clear)
            Section {
                Toggle(L.rememberCredential, isOn: $remember)
            }
            .listRowBackground(Color.clear)
            if let error = error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(L.cancel) { onCancel?() ?? backAction?() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(submitting ? L.loggingIn : L.login) {
                    Task { await submit() }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(submitting || identifier.isEmpty || secret.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(in: .rect(cornerRadius: 10))
        }
        .task {
            if let saved = await store?.load() {
                identifier = saved.identifier
                secret = saved.secret
                remember = !saved.secret.isEmpty
            }
        }
    }

    @MainActor
    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let cred = C.make(identifier: identifier, secret: secret)
        do {
            try await cred.authenticate()
            try await onSubmit(cred, remember)
        } catch {
            self.error = String(describing: error)
        }
    }
}
