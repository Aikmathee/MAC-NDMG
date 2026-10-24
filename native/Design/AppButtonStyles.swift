import SwiftUI

/// Use system interaction, focus, disabled state and accessibility behavior.
struct PillStyle: PrimitiveButtonStyle {
    var primary = false
    @Environment(\.insideActionBar) private var insideActionBar
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if insideActionBar {
                if primary { Button(configuration).buttonStyle(.borderedProminent) }
                else { Button(configuration).buttonStyle(FramedButtonStyle()) }
            } else {
                #if MODERN_GLASS
                if #available(macOS 26, *) {
                    if primary { Button(configuration).buttonStyle(.glassProminent) }
                    else { Button(configuration).buttonStyle(.glass) }
                } else { fallback(configuration) }
                #else
                fallback(configuration)
                #endif
            }
        }.controlSize(.large)
    }
    @ViewBuilder private func fallback(_ configuration: Configuration) -> some View {
        if primary { Button(configuration).buttonStyle(.borderedProminent) }
        else { Button(configuration).buttonStyle(.bordered).tint(.gray) }
    }
}

/// Small content actions have a visible native bezel in every appearance.
struct FramedButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Group {
            #if MODERN_GLASS
            if #available(macOS 26, *) {
                Button(configuration).buttonStyle(.glass)
            } else { Button(configuration).buttonStyle(.bordered).tint(.gray) }
            #else
            Button(configuration).buttonStyle(.bordered).tint(.gray)
            #endif
        }.controlSize(.regular)
    }
}

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
