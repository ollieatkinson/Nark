import SwiftTUI
import Vocabulary

extension UI {

    /// A viewport-backed collection routes selection and keyboard activation through
    /// the row's inherited control events. A mouse click selects; Enter opens.
    public struct List<
        Row: L & I_nark_ui_type_control,
        Data: RandomAccessCollection,
        Value: EventValueConvertible,
        Content: View
    >: View {

        @Environment(\.eventAction) private var send
        @Environment(\.isEnabled) private var isEnabled
        @FocusState private var focused: Bool
        @State private var currentSelection: Value?
        private let row: Control<Row>
        private let data: Data
        private let id: KeyPath<Data.Element, Value>
        private let selection: Value?
        private let focusOnArrival: Bool
        private let content: @MainActor (K<Row>, Data.Element) -> Content

        public init(
            _ data: Data,
            row: Row,
            id: KeyPath<Data.Element, Value>,
            selection: Value?,
            focusOnArrival: Bool = false,
            @ViewBuilder content: @escaping @MainActor (K<Row>, Data.Element) -> Content
        ) {
            self.row = Control(row)
            self.data = data
            self.id = id
            self.selection = selection
            _currentSelection = State(initialValue: selection)
            self.focusOnArrival = focusOnArrival
            self.content = content
        }

        public var body: some View {
            list

                // Focus the collection on arrival so its bound selection, rather
                // than the first synthesized row, owns keyboard navigation.
                .focusable(focusOnArrival, interactions: .edit)
                .focused($focused)
                .defaultFocus($focused, focusOnArrival)
                .onChange(of: selection) { _, value in
                    // Reconcile model changes without publishing them as user edits.
                    currentSelection = value
                }
                .onChange(of: isEnabled && !data.isEmpty) { _, interactive in
                    // Reclaim collection navigation after an editor closes or a
                    // cleared filter restores rows. Never blur the active editor.
                    if interactive && focusOnArrival {
                        focused = true
                    }
                }
                .listStyle(DenseListStyle())
                // Overflow chrome consumes a new top row as a tree crosses the
                // viewport boundary. Keep row coordinates stable while expanding.
                .scrollIndicators(.hidden, axes: .vertical)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .disabled(!send.isEnabled)
        }

        // Keep the data-source initializer: builder content eagerly realizes every row.
        private var list: some View {
            let projection = row.projection(.select, using: send, focus: focusOnArrival ? $focused : nil)
            let binding = $currentSelection[dynamicMember: \.[emitting: projection]]
            return SwiftTUI.List(data, id: id, selection: binding) { element in
                content(row.concept[element[keyPath: id]], element)
            }
            .onKeyPress(.return) { _ in
                guard let selection = binding.wrappedValue else {
                    return .ignored
                }
                send(row.activating(selection))
                return .handled
            }
        }
    }

    public struct DenseListStyle: ListStyle, Sendable {

        public init() {}
        public var snapshotLabel: String {
            "ListStyle.dense"
        }

        public func resolvePresentation(for configuration: ListStyleConfiguration) -> ListStylePresentation {
            .init(showsRowSeparators: false, showsSectionSeparators: false)
        }
    }
}
