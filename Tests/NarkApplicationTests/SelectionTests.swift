import Foundation
@testable import NarkUI
import SwiftTUI
import Testing
import Vocabulary

@Suite @MainActor struct SelectionTests {

    @Test func an_explicit_same_value_reset_reveals_selection_but_our_own_echo_does_not() throws {
        let projection = UI.Control(nark.ux.monitor.home.tree.row).projection(.select, using: .init())
        let cursor = UI.Selection<String>("a")
        cursor[emitting: projection] = "b"
        let own = try #require(cursor.latestEvent)
        #expect(!cursor.reconcile(.init(value: "b", event: own)))
        let reset = Event(nark.ux.monitor.home.tree.row["b"].event.select).id
        #expect(cursor.reconcile(.init(value: "b", event: reset)))
        #expect(cursor.latestEvent == reset)
        #expect(!cursor.reconcile(.init(value: "a", event: own)))
        #expect(cursor.value == "b")
        #expect(cursor.reconcile(.init(value: "b", event: nil)))
    }

    @Test func scrolling_keeps_its_anchor_when_new_rows_arrive_and_never_reveals_the_old_selection() {
        let data = (0 ..< 300).map(String.init)
        let cursor = UI.Selection<String>("0")
        cursor.reveal(in: data, id: \.self, positions: nil, height: 12)
        cursor.scroll(by: 100, in: data, id: \.self, positions: nil, height: 12)
        #expect(cursor.value == "0")
        #expect(cursor.range(in: data, id: \.self, positions: nil, height: 12) == 100 ..< 112)
        let updated = ["new-a", "new-b"] + data
        let positions = Dictionary(uniqueKeysWithValues: updated.enumerated().map { ($0.element, $0.offset) })
        // The very first frame uses the anchor, before an onChange callback runs.
        #expect(cursor.range(in: updated, id: \.self, positions: positions, height: 12) == 102 ..< 114)
        cursor.refreshViewport(in: updated, id: \.self, positions: positions, height: 12)
        cursor.scroll(by: 1, in: updated, id: \.self, positions: positions, height: 12)
        #expect(cursor.range(in: updated, id: \.self, positions: positions, height: 12) == 103 ..< 115)
        cursor.refreshViewport(in: ["only"], id: \.self, positions: nil, height: 12)
        #expect(cursor.range(in: ["only"], id: \.self, positions: nil, height: 12) == 0 ..< 1)
    }

    @Test func delayed_acknowledgements_cannot_rewind_a_repeated_key_cursor() {
        let projection = UI.Control(nark.ux.monitor.home.tree.row).projection(.select, using: .init())
        let cursor = UI.Selection<String>("a")
        cursor[emitting: projection] = "b"
        let first = cursor.latestEvent
        cursor[emitting: projection] = "a"
        let second = cursor.latestEvent
        cursor[emitting: projection] = "b"
        let last = cursor.latestEvent
        cursor.reconcile(.init(value: "b", event: first))
        cursor.reconcile(.init(value: "a", event: second))
        #expect(cursor.value == "b")
        #expect(cursor.latestEvent == last)
        cursor.reconcile(.init(value: "b", event: last))
        #expect(cursor.value == "b")
        #expect(cursor.latestEvent == last)
    }

    @Test func an_explicit_reset_replaces_pending_selection_and_does_not_emit_an_event() {
        let projection = UI.Control(nark.ux.monitor.home.tree.row).projection(.select, using: .init())
        let cursor = UI.Selection<String>("a")
        cursor[emitting: projection] = "b"
        cursor.reconcile(.init(value: "all", event: nil))
        #expect(cursor.value == "all")
        #expect(cursor.latestEvent == nil)
    }

    @Test func a_key_repeat_burst_advances_every_step_without_waiting_for_a_frame() async throws {
        let events = Events()
        let stream = events.stream
        let data = (0 ..< 128).map(String.init)
        let positions = Dictionary(uniqueKeysWithValues: data.enumerated().map { ($0.element, $0.offset) })
        let projection = UI.Control(nark.ux.monitor.home.tree.row).projection(
            .select,
            using: .init(events: events)
        )
        let cursor = UI.Selection<String>("0")
        for _ in 0 ..< 100 {
            cursor.move(by: 1, in: data, id: \.self, positions: positions, projection: projection)
        }
        #expect(cursor.value == "100")
        for _ in 0 ..< 100 {
            cursor.move(by: -1, in: data, id: \.self, positions: positions, projection: projection)
        }
        #expect(cursor.value == "0")
        cursor.move(by: -1, in: data, id: \.self, positions: positions, projection: projection)
        #expect(cursor.value == "0")
        events.finish()
        var selected: [String] = []
        for await event in stream {
            selected.append(try event[nark.ux.monitor.home.tree.row, as: String.self])
        }
        let forward = (1 ... 100).map { String($0) }
        let backward = (0 ..< 100).reversed().map { String($0) }
        #expect(selected == forward + backward)
    }

    @Test func event_action_identity_preserves_the_failure_handler() {
        let events = Events()
        var firstFailures = 0
        var secondFailures = 0
        let first = UI.EventAction(events: events) { _ in firstFailures += 1 }
        let second = UI.EventAction(events: events) { _ in secondFailures += 1 }
        let copy = first
        #expect(copy == first)
        #expect(first != second)
        events.finish()
        copy(Event(nark.activity.refresh))
        second(Event(nark.activity.refresh))
        #expect(firstFailures == 1)
        #expect(secondFailures == 1)
    }

    @Test func changing_selection_repaints_exactly_one_row_and_clears_the_previous_marker() {
        let cursor = UI.Selection<String>("0")
        let projection = UI.Control(nark.ux.monitor.home.tree.row).projection(.select, using: .init())
        let renderer = DefaultRenderer()
        for value in ["0", "2", "1", "0"] {
            cursor[emitting: projection] = value
            let selected = cursor.value
            let frame = renderer.render(
                VStack(spacing: 0) {
                    ForEach(["0", "1", "2"], id: \.self) { row in
                        UI.SelectionRow(
                            cursor: cursor,
                            value: row,
                            selected: selected == row,
                            projection: projection,
                            content: Text("row \(row)")
                        )
                    }
                }
                .frame(width: 20, height: 3),
                proposal: .init(width: 20, height: 3)
            )
            let markers = frame.rasterSurface.cells.enumerated().compactMap { row, cells in
                cells.contains(where: { $0.character == "▌" }) ? row : nil
            }
            #expect(markers == [Int(value)!])
        }
    }

    @Test func the_viewport_tracks_fast_navigation_and_clamps_after_resize_or_filtering() {
        var viewport = UI.Viewport()
        for index in 0 ..< 2000 {
            viewport.reveal(index, count: 2000, height: 12)
            #expect(viewport.range(count: 2000, height: 12).contains(index))
            #expect(viewport.range(count: 2000, height: 12).count == 12)
        }
        viewport.reveal(2, count: 4, height: 20)
        #expect(viewport.range(count: 4, height: 20) == 0 ..< 4)
        viewport.reveal(nil, count: 0, height: 0)
        #expect(viewport.range(count: 0, height: 0).isEmpty)
        viewport.scroll(by: .max, count: 2000, height: 12)
        #expect(viewport.range(count: 2000, height: 12) == 1988 ..< 2000)
        viewport.scroll(by: .min, count: 2000, height: 12)
        #expect(viewport.range(count: 2000, height: 12) == 0 ..< 12)
    }
}
