import SwiftUI

/// One label, one bezel, one matching hit region. Do not wrap a second Button
/// inside a primitive style: list rows can otherwise hit-test only its text.
struct PillStyle: ButtonStyle {
    var primary = false
    var large = true
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, large ? 16 : 12)
            .padding(.vertical, large ? 9 : 6)
            .frame(minWidth: 32, minHeight: large ? 36 : 30)
            .foregroundStyle(primary ? Color.white : Color.primary)
            .background { surface }
            .overlay {
                Capsule().strokeBorder(Color.primary.opacity(enabled && hovering ? 0.24 : 0.10), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder private var surface: some View {
        #if MODERN_GLASS
        if #available(macOS 26, *) {
            if primary {
                Capsule().fill(.clear).glassEffect(.regular.tint(.accentColor).interactive(), in: Capsule())
            } else {
                Capsule().fill(.clear).glassEffect(.regular.interactive(), in: Capsule())
            }
        } else { fallback }
        #else
        fallback
        #endif
    }

    @ViewBuilder private var fallback: some View {
        if primary { Capsule().fill(Color.accentColor) }
        else { Capsule().fill(.regularMaterial) }
    }
}

// Content actions use the same full-area control as footer actions.
typealias FramedButtonStyle = PillStyle

/// Give the whole navigation row one hit region, including its empty space.
struct NavigationGlassStyle: ButtonStyle {
    var selected = false
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .background { surface(pressed: configuration.isPressed) }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }

    @ViewBuilder private func surface(pressed: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        if enabled && (hovering || pressed) {
            #if MODERN_GLASS
            if #available(macOS 26, *) {
                shape.fill(.clear).glassEffect(.regular.interactive(), in: shape)
            } else { shape.fill(.regularMaterial) }
            #else
            shape.fill(.regularMaterial)
            #endif
        } else if selected {
            shape.fill(Color.accentColor.opacity(0.16))
        }
    }
}
