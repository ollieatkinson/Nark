import SwiftTUI
import Vocabulary

extension UI {

    /// A pointer disclosure target; the enclosing tree retains keyboard focus.
    public struct Disclosure<Concept: L & I_nark_ui_component_disclosure>: View {

        @Environment(\.eventAction) private var send
        private let control: Control<Concept>
        private let expanded: Bool
        public init(_ concept: K<Concept>, expanded: Bool) {
            control = Control(concept)
            self.expanded = expanded
        }

        public var body: some View {
            Text(expanded ? "▾ " : "▸ ")
                .accessibilityRole(.button)
                .accessibilityLabel(expanded ? "Collapse" : "Expand")
                .onTapGesture {
                    send(control.select)
                }
                .disabled(!send.isEnabled)
        }
    }
}
