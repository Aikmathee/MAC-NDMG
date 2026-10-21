import SwiftUI
import AppKit

/// Compatibility renderer for local builds using an SDK predating macOS 26.
/// Distribution builds use SwiftUI's typed Liquid Glass API below.
struct GlassSurface: NSViewRepresentable {
    var radius: CGFloat = DesignTokens.panelRadius
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeNSView(context: Context) -> NSView {
        if !reduceTransparency, #available(macOS 26, *),
           let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassClass.init(frame: .zero)
            if glass.responds(to: NSSelectorFromString("setCornerRadius:")) { glass.setValue(radius, forKey: "cornerRadius") }
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .withinWindow
        effect.state = .followsWindowActiveState
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.masksToBounds = true
        return effect
    }
    func updateNSView(_ view: NSView, context: Context) {
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        // System materials respond to accessibility changes; enforce an opaque base as well.
        view.wantsLayer = true
        view.layer?.backgroundColor = reduceTransparency ? NSColor.windowBackgroundColor.cgColor : nil
    }
}

struct ControlSurface: View {
    var radius: CGFloat = DesignTokens.panelRadius
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(nsColor: .controlBackgroundColor))
        } else {
            #if MODERN_GLASS
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: radius))
            } else { GlassSurface(radius: radius) }
            #else
            GlassSurface(radius: radius)
            #endif
        }
    }
}

/// Standard content surfaces, deliberately separate from navigation glass.
struct ContentCard: ViewModifier {
    var radius: CGFloat = DesignTokens.panelRadius
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.45 : hovered ? 0.18 : 0.08), lineWidth: contrast == .increased ? 1.2 : 0.7)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
    }
}

struct SelectionActionBar: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .environment(\.insideActionBar, true)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(ControlSurface())
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.panelRadius, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
}

struct GlassControlGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        #if MODERN_GLASS
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 16) { content }
        } else { content }
        #else
        content
        #endif
    }
}

/// Let the system decide the extent and appearance from actual scroll position.
struct NativeScrollEdges: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if MODERN_GLASS
        if #available(macOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical)
        } else { content }
        #else
        content
        #endif
    }
}

/// Register custom controls as real bars so macOS owns their scroll edge effect.
struct NativeSafeAreaBar<Bar: View>: ViewModifier {
    var edge: VerticalEdge
    @ViewBuilder var bar: Bar
    @ViewBuilder func body(content: Content) -> some View {
        #if MODERN_GLASS
        if #available(macOS 26, *) {
            content.safeAreaBar(edge: edge, spacing: 0) { bar.background(.bar) }
        } else {
            content.safeAreaInset(edge: edge, spacing: 0) { bar.background(.bar) }
        }
        #else
        content.safeAreaInset(edge: edge, spacing: 0) { bar.background(.bar) }
        #endif
    }
}
