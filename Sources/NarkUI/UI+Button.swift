import SwiftTUI
import Vocabulary

extension UI {

    /// A button publishes the supplied concept's inherited select event.
    public struct Button<Concept: L & I_nark_ui_type_control, Label: View>: View {

        @Environment(\.eventAction) private var send
        private let control: Control<Concept>
        private let label: Label

        public init(_ concept: Concept, @ViewBuilder label: () -> Label) {
            control = Control(concept)
            self.label = label()
        }

        public var body: some View {
            SwiftTUI.Button {
                send(control.select)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .disabled(!send.isEnabled)
        }
    }
}
