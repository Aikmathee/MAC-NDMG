import SwiftUI
import AppKit

/// Keep native keyboard/mouse selection while drawing its highlight inside the card.
struct CardSelectionAnchor: NSViewRepresentable {
    final class Anchor: NSView {
        func configure() {
            var ancestor: NSView? = self
            while let view = ancestor {
                if let row = view as? NSTableRowView { row.selectionHighlightStyle = .none }
                if let table = view as? NSTableView {
                    table.selectionHighlightStyle = .none
                    table.focusRingType = .none
                }
                ancestor = view.superview
            }
        }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configure() }
    }
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {
        view.configure()
        DispatchQueue.main.async { [weak view] in view?.configure() }
    }
}

struct CardSelection: ViewModifier {
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.colorSchemeContrast) private var contrast
    var selected: Bool
    var radius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(CardSelectionAnchor().allowsHitTesting(false))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.accentColor.opacity(selected ? (contrast == .increased ? 0.24 : 0.12) : 0))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(selected ? (activeState == .inactive ? 0.45 : 0.9) : 0), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
    }
}

