import Foundation
import SwiftTUI
import Vocabulary

extension UI {

    /// A compact choice control. The component renders options and emits the
    /// inherited select event with a value; the experience owns its meaning.
    public struct Select<Concept: L & I_nark_ui_type_select>: View {

        public struct Option: Sendable {

            public let value: String
            public let title: String
            public init(_ value: String, title: String) {
                self.value = value
                self.title = title
            }
        }

        @Environment(\.eventAction) private var send
        private let control: Control<Concept>
        private let options: [Option]
        private let selection: String
        private let isEnabled: Bool

        public init(
            _ concept: Concept,
            options: [Option],
            selection: String,
            isEnabled: Bool = true
        ) {
            control = Control(concept)
            self.options = options
            self.selection = selection
            self.isEnabled = isEnabled
        }

        public var body: some View {
            HStack(spacing: 1) {
                ForEach(options, id: \.value) { option in
                    Text(option.value == selection
                        ? "[\(option.title.formatted(.terminalText))]"
                        : option.title.formatted(.terminalText))
                        .foregroundStyle(option.value == selection ? .theme.tint : .theme.muted)
                        .lineLimit(1)
                        .accessibilityRole(.button)
                        .accessibilityLabel(option.title + (option.value == selection ? ", selected" : ""))
                        .onTapGesture {
                            send(control.selecting(option.value))
                        }
                        .disabled(option.value == selection || !isEnabled)
                }
            }
            .disabled(!send.isEnabled || !isEnabled)
        }
    }
}
