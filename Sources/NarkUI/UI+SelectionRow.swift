import SwiftTUI
import Vocabulary

extension UI {

    /// Selection is authored row data, so retained rows cannot carry old list chrome.
    struct SelectionRow<
        Value: EventValueConvertible,
        Concept: L & I_nark_ui_type_control,
        Content: View
    >: View {

        let cursor: Selection<Value>
        let value: Value
        let selected: Bool
        let projection: EventProjection<Concept>
        let content: Content

        var body: some View {
            content
                .modifier(SelectionStyle(selected: selected))
                .onTapGesture {
                    cursor[emitting: projection] = value
                }
        }
    }

    private struct SelectionStyle: ViewModifier, Equatable {

        let selected: Bool

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.selected == rhs.selected
        }

        func body(content: Content) -> some View {
            HStack(spacing: 0) {
                Text(selected ? "▌ " : "  ")
                    .foregroundStyle(.theme.foreground)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? .theme.selection : .theme.background)
            .accessibilityValue(selected ? "selected" : "")
        }
    }
}

// Compare every authored input. Pointer callbacks use the stable cursor and
// projection directly, so unchanged rows can retain their whole subtree.
extension UI.SelectionRow: @MainActor Equatable where Content: Equatable {

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cursor === rhs.cursor
            && lhs.value == rhs.value
            && lhs.selected == rhs.selected
            && lhs.projection == rhs.projection
            && lhs.content == rhs.content
    }
}
