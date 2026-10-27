import SwiftTUI

extension UI {

    /// Reuse the detected terminal background, including its transparency.
    /// Unknown palettes and accessibility overrides retain an opaque backdrop.
    public struct TerminalBackground: ViewModifier {

        @Environment(\.terminalAppearance) private var appearance
        @Environment(\.accessibilityPreferences) private var preferences

        public init() {}

        public func body(content: Content) -> some View {
            content.background {
                if appearance.backgroundColor == nil || preferences.contrast == .increased
                    || preferences.reduceTransparency == true || (preferences.colorProfile ?? .standard) != .standard {
                    Rectangle().fill(.theme.background)
                }
            }
        }
    }
}
