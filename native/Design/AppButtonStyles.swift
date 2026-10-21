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
                    else { Button(configuration).buttonStyle(.bordered).tint(.gray) }
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
        Button(configuration).buttonStyle(.bordered).controlSize(.regular).tint(.gray)
    }
}
