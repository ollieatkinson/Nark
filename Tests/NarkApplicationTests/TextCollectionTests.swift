import Foundation
@testable import NarkUI
import SwiftTUI
import Testing
import Vocabulary

@Suite @MainActor struct TextCollectionTests {

    @Test func a_visible_band_preserves_column_colours_selection_and_reader_metadata() throws {
        let cursor = UI.Selection<String>("second")
        let control = UI.Control(nark.ux.monitor.connections.row)
        let view = UI.TextCollection(
            rows: [
                .init(value: "first", text: .init([.init("界 first", width: 12)]), actions: []),
                .init(
                    value: "second",
                    text: .init(
                        [.init("blocked", width: 12, style: ThemeShapeStyle.theme.danger)],
                        accessibilityLabel: "Blocked peer"
                    ),
                    actions: []
                )
            ],
            cursor: cursor,
            selected: cursor.value,
            projection: control.projection(.select, using: .init()),
            offset: 100,
            count: 2000,
            height: 4
        )
        let renderer = DefaultRenderer()
        let frame = renderer.render(view.frame(width: 14, height: 4), proposal: .init(width: 14, height: 4))
        #expect(frame.rasterSurface.cells[0][0].character == " ")
        #expect(frame.rasterSurface.cells[1][0].character == "▌")
        #expect(frame.rasterSurface.cells[0][2].spanWidth == 2)
        let red = renderer.render(
            Text("b").foregroundStyle(.theme.danger).cellBackground(.theme.selection)
        )
        #expect(
            frame.rasterSurface.cells[1][2].style?.foregroundColor == red.rasterSurface.cells[0][
                0
            ].style?.foregroundColor
        )
        #expect(frame.semanticSnapshot.accessibilityNodes.contains {
            $0.properties?.valueDescription == "Blocked peer" && $0.properties?.positionInSet == 102
                && $0.properties?.rowCount == 2000
        })
        #expect(frame.diagnostics.runtime.issues.isEmpty)
    }

    @Test func row_hit_testing_emits_disclosure_and_selection_through_lexicon() async throws {
        let events = Events()
        let stream = events.stream
        let concept = nark.ux.monitor.home.tree.row["app"]
        let action = UI.TextRowAction(columns: 0 ..< 2, concept: concept.disclosure.event.select)
        let firstID = action.event.id
        let secondID = action.event.id
        #expect(firstID < secondID)
        let cursor = UI.Selection<String>(nil)
        let view = UI.TextCollection(
            rows: [.init(value: "app", text: .init([.init("▸ App", width: 12)]), actions: [action])],
            cursor: cursor,
            selected: nil,
            projection: UI.Control(nark.ux.monitor.home.tree.row).projection(.select, using: .init(events: events)),
            offset: 0,
            count: 1,
            height: 4
        )
        view.select(at: .init(x: 2, y: 0))
        #expect(cursor.value == "app")
        cursor.reconcile(.init(value: nil, event: nil))
        view.select(at: .init(x: 8, y: 0))
        view.select(at: .init(x: 8, y: 3))
        view.select(at: .init(x: -1, y: 0))
        view.select(at: .init(x: .infinity, y: 0))
        events.finish()
        var received: [Event] = []
        for await event in stream {
            received.append(event)
        }
        #expect(received.count == 2)
        #expect(received[0].matches(concept.disclosure.event.select))
        #expect(received[1].matches(concept.event.select))
        #expect(received[0].id < received[1].id)
    }
}
