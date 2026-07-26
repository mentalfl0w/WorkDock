import SwiftUI

/// Environment key for the "back to gallery" action, injected by ModuleHostView.
struct ModuleBackActionKey: EnvironmentKey {
    static let defaultValue: (@Sendable () -> Void)? = nil
}
extension EnvironmentValues {
    /// Called to navigate back to the module gallery.
    var moduleBackAction: (@Sendable () -> Void)? {
        get { self[ModuleBackActionKey.self] }
        set { self[ModuleBackActionKey.self] = newValue }
    }
}

/// Standard container for module content — provides back button + title header.
///
/// Usage in module's `mainView()`:
/// ```swift
/// ModuleContainerView(title: "My Module") {
///     // module-specific content (tabBar, list, etc.)
/// }
/// ```
///
/// The back button reads `moduleBackAction` from environment, which is
/// injected by `ModuleHostView`.
struct ModuleContainerView<Content: View>: View {
    /// Header height: vertical padding (10×2) + text line (~20) = 40pt
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.moduleBackAction) private var onBack

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Title truly centered
                Text(title)
                    .font(.headline)
                // Back button overlaid at leading edge
                HStack {
                    if let onBack {
                        Button(action: onBack) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(L.backToModules)
                                    .font(.system(size: 12))
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Divider().opacity(0.3) }

            content()
        }
    }
}

enum ModuleContainer {
    static var headerHeight: CGFloat { 40 }
}
