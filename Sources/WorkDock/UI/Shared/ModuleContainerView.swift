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
///
/// Layout contract, independent of window size:
/// - The header is a fixed-height navigation bar; it never shrinks and is
///   never covered by module content.
/// - The centered title reserves the back control's measured width, so the
///   two cannot overlap when the window narrows; the title truncates instead.
/// - The content area is clipped to its slot, so a module whose content is
///   taller than the window can never draw over the header. Modules own their
///   own scrolling (see `OCRRootView` for a fully scrollable page).
struct ModuleContainerView<Content: View>: View {
    /// Header height: vertical padding (8×2) + control line (~24) = 40pt
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.moduleBackAction) private var onBack

    /// Measured width of the leading back control. The centered title pads by
    /// this amount on both sides, so it stays optically centered while never
    /// running under the button at narrow widths.
    @State private var backControlWidth: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                // Overflow belongs to the module's own scroll view; it must
                // never bleed into the navigation bar above.
                .clipped()
        }
    }

    private var header: some View {
        ZStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, onBack == nil ? 0 : backControlWidth + 12)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
                .help(title)

            if let onBack {
                HStack(spacing: 0) {
                    backButton(onBack)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.3) }
    }

    /// System glass control on the window's own material — one glass layer,
    /// no panel stacked behind the bar.
    private func backButton(_ action: @escaping @Sendable () -> Void) -> some View {
        Button(action: { action() }) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text(L.backToModules)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 2)
            .contentShape(Capsule())
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .help(L.backToModules)
        .accessibilityLabel(Text(L.backToModules))
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            backControlWidth = width
        }
    }
}

enum ModuleContainer {
    static var headerHeight: CGFloat { 40 }
}
