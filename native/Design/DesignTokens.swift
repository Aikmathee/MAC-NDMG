import SwiftUI

enum DesignTokens {
    static let controlRadius: CGFloat = 12
    static let rowRadius: CGFloat = 18
    static let panelRadius: CGFloat = 24
    static let pageInset: CGFloat = 24
    static let selectionDuration = 0.2
}

private struct ActionBarKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var insideActionBar: Bool {
        get { self[ActionBarKey.self] }
        set { self[ActionBarKey.self] = newValue }
    }
}
