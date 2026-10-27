import Foundation
import SwiftTUI
import Vocabulary

extension UI {

    /// Page navigation uses explicit shortcuts; Tab remains pane traversal.
    public struct Tab<Concept: L & I_nark_ui_component_tab>: View {

        @Environment(\.eventAction) private var send
        private let control: Control<Concept>
        private let title: String
        private let selected: Bool
        public init(_ concept: Concept, title: String, selected: Bool) {
            control = Control(concept)
            self.title = title
            self.selected = selected
        }

        public var body: some View {
            Text(selected ? "[\(title.formatted(.terminalText))]" : title.formatted(.terminalText))
                .foregroundStyle(selected ? .theme.tint : .theme.foreground)
                .accessibilityRole(.tab)
                .onTapGesture {
                    if !selected {
                        send(control.select)
                    }
                }
                .disabled(!send.isEnabled)
        }
    }
}
