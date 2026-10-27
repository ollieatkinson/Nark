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
        @State private var cursor: Selection<Value>

        private let row: Control<Row>
        private let data: Data
        private let id: KeyPath<Data.Element, Value>
        private let selection: Value?
        private let selectionEvent: UInt?
        private let height: Int
        private let positions: [Value: Data.Index]?
        private let focusOnArrival: Bool
        private var keyAction: @MainActor (KeyPress, Value?) -> KeyPressResult = { _, _ in .ignored }
        private let content: @MainActor (K<Row>, Data.Element) -> Content

        public init(
            _ data: Data,
            row: Row,
            id: KeyPath<Data.Element, Value>,
            selection: Value?,
            height: Int,
            selectionEvent: UInt? = nil,
            positions: [Value: Data.Index]? = nil,
            focusOnArrival: Bool = false,
            @ViewBuilder content: @escaping @MainActor (K<Row>, Data.Element) -> Content
        ) {
            self.row = Control(row)
            self.data = data
            self.id = id
            self.selection = selection
            self.height = max(1, height)
            self.selectionEvent = selectionEvent
            self.positions = positions
            let cursor = Selection(selection)
            cursor.reveal(in: data, id: id, positions: positions, height: max(1, height))
            _cursor = State(initialValue: cursor)
            self.focusOnArrival = focusOnArrival
            self.content = content
        }

        /// A feature's remaining keys receive the same immediate selection as the list.
        public func onKeyPress(_ action: @escaping @MainActor (KeyPress, Value?) -> KeyPressResult) -> Self {
            var list = self
            list.keyAction = action
            return list
        }

        public var body: some View {
            list

                // Focus the collection as a unit; the cursor owns row navigation.
                .focusable(!data.isEmpty, interactions: .edit)
                .focused($focused)
                .defaultFocus($focused, focusOnArrival)
                .onChange(of: isEnabled && !data.isEmpty) { _, interactive in
                    // Reclaim collection navigation after an editor closes or a
                    // cleared filter restores rows. Never blur the active editor.
                    if interactive && focusOnArrival {
                        focused = true
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: height)
                .accessibilityRole(.list)
                .disabled(!send.isEnabled)
        }

        // Compose only the visible model slice. Cursor movement never asks the
        // renderer to enumerate or validate the full traffic collection.
        private var list: some View {
            let cursor = self.cursor
            let content = self.content
            let concept = row.concept
            let id = self.id
            let selected = cursor.value ?? selection
            let bounds = cursor.range(in: data, id: id, positions: positions, height: height)
            let lower = data.index(data.startIndex, offsetBy: bounds.lowerBound)
            let upper = data.index(data.startIndex, offsetBy: bounds.upperBound)
            let projection = row.projection(.select, using: send, focus: $focused)
            let keyboardProjection = row.projection(.select, using: send)
            return Group {
                if Content.self is any TextRowContent.Type {
                    TextCollection(
                        rows: data[lower ..< upper].compactMap { element in
                            let value = element[keyPath: id]
                            guard let row = content(concept[value], element) as? any TextRowContent else {
                                return nil
                            }
                            return .init(value: value, text: row.textRow, actions: row.rowActions)
                        },
                        cursor: cursor,
                        selected: selected,
                        projection: projection,
                        offset: bounds.lowerBound,
                        count: data.count,
                        height: height
                    )
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(data[lower ..< upper], id: id) { element in
                            let value = element[keyPath: id]
                            SelectionRow(
                                cursor: cursor,
                                value: value,
                                selected: selected == value,
                                projection: projection,
                                content: content(concept[value], element)
                            )
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .onChange(
                of: Selection<Value>.Update(value: selection, event: selectionEvent),
                initial: true
            ) { _, update in
                if cursor.reconcile(update) {
                    revealSelection()
                }
            }
            .onChange(of: data.count) { _, _ in
                cursor.refreshViewport(in: data, id: id, positions: positions, height: height)
            }
            .onChange(of: positions) { _, _ in
                cursor.refreshViewport(in: data, id: id, positions: positions, height: height)
            }
            .onChange(of: height) { _, _ in
                cursor.refreshViewport(in: data, id: id, positions: positions, height: height)
            }
            .onScrollWheel { event in
                guard isEnabled else {
                    return .ignored
                }
                let moved = cursor.scroll(
                    by: event.deltaY,
                    in: data,
                    id: id,
                    positions: positions,
                    height: height
                )
                return moved ? .handled : .ignored
            }
            .onKeyPress { key in
                guard isEnabled, key.modifiers.isEmpty else {
                    return .ignored
                }
                if key.key == .return, let value = cursor.value {
                    send(row.activating(value))
                    return .handled
                }
                let delta: Int
                switch key.key {
                    case .arrowUp:
                        delta = -1
                    case .arrowDown:
                        delta = 1
                    case .pageUp:
                        delta = -height
                    case .pageDown:
                        delta = height
                    case .home:
                        if let first = data.first {
                            cursor[emitting: keyboardProjection] = first[keyPath: id]
                            revealSelection()
                        }
                        return .handled
                    case .end:
                        if let last = data.last {
                            cursor[emitting: keyboardProjection] = last[keyPath: id]
                            revealSelection()
                        }
                        return .handled
                    default:
                        return keyAction(key, cursor.value)
                }
                cursor.move(by: delta, in: data, id: id, positions: positions, projection: keyboardProjection)
                revealSelection()
                return .handled
            }
        }

        private func revealSelection() {
            cursor.reveal(in: data, id: id, positions: positions, height: height)
        }
    }
}
