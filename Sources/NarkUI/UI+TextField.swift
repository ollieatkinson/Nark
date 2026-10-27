import SwiftTUI
import Vocabulary

extension UI {

    /// Editing emits change; submission remains an independent feature decision.
    public struct TextField<Concept: L & I_nark_ui_type_textfield>: View {

        @Environment(\.eventAction) private var send
        private let control: Control<Concept>
        private let text: Binding<String>
        public init(_ concept: Concept, text: Binding<String>) {
            control = Control(concept)
            self.text = text
        }

        public var body: some View {
            let projection = control.projection(.change, using: send)
            SwiftTUI.TextField("", text: text[dynamicMember: \.[emitting: projection]])
                .textFieldStyle(.plain)
                .disabled(!send.isEnabled)
        }
    }
}
