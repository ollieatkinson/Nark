import SwiftTUI
import Vocabulary

extension UI {

    /// One text layout for the visible band; row count never grows the view graph.
    struct TextCollection<Value: EventValueConvertible, Concept: L & I_nark_ui_type_control>: View {

        struct Row {

            let value: Value
            let text: TextRow
            let actions: [TextRowAction]
        }

        let rows: [Row]
        let cursor: Selection<Value>
        let selected: Value?
        let projection: EventProjection<Concept>
        let offset: Int
        let count: Int
        let height: Int

        var body: some View {
            let index = rows.firstIndex { $0.value == selected }
            let label = index.flatMap { rows[$0].text.accessibilityLabel }
            return ZStack(alignment: .topLeading) {
                if let index {
                    Rectangle()
                        .fill(.theme.selection)
                        .frame(height: 1)
                        .offset(y: index)
                        .accessibilityHidden(true)
                }
                TextRows(rows: rows.map(\.text), height: height)
                    .padding(.leading, 2)
                if let index {
                    Text("▌")
                        .foregroundStyle(.theme.foreground)
                        .offset(y: index)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityProperties(.init(
                valueDescription: label,
                positionInSet: index.map { offset + $0 + 1 },
                setSize: count,
                rowCount: count
            ))
            .accessibilityCursorAnchor(.init(x: 0, y: index ?? 0))
            .gesture(
                SpatialTapGesture()
                    .onEnded {
                        select(at: $0.location)
                    }
            )
        }

        func select(at point: Point) {
            guard point.x >= 0,
                  point.y >= 0,
                  point.x.isFinite,
                  point.y.isFinite,
                  point.y < Double(rows.count) else {
                return
            }
            let row = rows[Int(point.y)]
            // Ignore coordinates outside representable cells before conversion.
            guard point.x < Double(Int.max) else {
                return
            }
            let x = Int(point.x) - 2
            if let action = row.actions.first(where: { $0.columns.contains(x) }) {
                cursor.send(action.event, selecting: row.value, using: projection)
            } else {
                cursor[emitting: projection] = row.value
            }
        }
    }

    /// Selection never changes these text inputs. Retain formatting and paint
    /// outside the two rows touched by the moving selection decoration.
    private struct TextRows: View, Equatable {

        let rows: [TextRow]
        let height: Int

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.rows == rhs.rows && lhs.height == rhs.height
        }

        var body: some View {
            var content = Text.StringInterpolation(literalCapacity: rows.count * 128, interpolationCount: rows.count)
            for (index, row) in rows.enumerated() {
                if index > 0 {
                    content.appendLiteral("\n")
                }
                content.appendInterpolation(row.text())
            }
            return Text(Text.RichContent(stringInterpolation: content))
                .lineLimit(height)
        }
    }
}
