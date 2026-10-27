import Firewall
@testable import NarkUI
import SwiftTUI
import SwiftTUICLI
import SwiftTUIRuntime
import Testing
import Vocabulary

@Suite @MainActor struct TextRowTests {

    @Test func event_key_paths_have_stable_identity_for_the_same_destination() {
        let events = Events()
        let control = UI.Control(nark.ui.type.control)
        let first = control.projection(.change, using: .init(events: events))
        let second = control.projection(.change, using: .init(events: events))
        let other = control.projection(.change, using: .init(events: Events()))
        let firstPath: WritableKeyPath<Int, Int> = \.[emitting: first]
        let secondPath: WritableKeyPath<Int, Int> = \.[emitting: second]
        let otherPath: WritableKeyPath<Int, Int> = \.[emitting: other]
        #expect(firstPath == secondPath)
        #expect(firstPath != otherPath)
    }

    @Test func optional_selection_projection_preserves_transactions_and_ignores_nil() async throws {
        let events = Events()
        let stream = events.stream
        @State var selected: String?
        var transaction = Transaction()
        transaction.disablesAnimations = true
        let projection = UI.Control(nark.ux.monitor.connections.row)
            .projection(.select, using: .init(events: events))
        let binding = $selected.transaction(transaction)[dynamicMember: \.[emitting: projection]]
        #expect(binding.transaction.disablesAnimations)
        binding.wrappedValue = nil
        binding.wrappedValue = "chosen"
        #expect(selected == "chosen")
        binding.wrappedValue = nil
        #expect(selected == nil)
        events.finish()
        var values: [String] = []
        for await event in stream {
            values.append(try event[nark.ux.monitor.connections.row, as: String.self])
        }
        #expect(values == ["chosen"])
    }

    @Test func text_projection_publishes_changes_before_submission() async throws {
        let events = Events()
        let stream = events.stream
        @State var text = ""
        let projection = UI.Control(nark.ux.monitor.search).projection(.change, using: .init(events: events))
        let binding = $text[dynamicMember: \.[emitting: projection]]
        binding.wrappedValue = "service:Main"
        try events.send(Event(nark.ux.monitor.search.event.submit))
        events.finish()
        var received: [Event] = []
        for await event in stream {
            received.append(event)
        }
        #expect(received.count == 2)
        #expect(received.first?.matches(nark.ux.monitor.search.event.change) == true)
        #expect(try received.first?[nark.ux.monitor.search, as: String.self] == "service:Main")
        #expect(received.last?.matches(nark.ux.monitor.search.event.submit) == true)
    }

    @Test func blocked_tree_row_colours_the_site_name_red_and_exposes_policy() throws {
        let row = UI.TreeRow(
            nark.ux.monitor.home.tree.row["site"],
            title: "peer.test",
            depth: 1,
            hasChildren: true,
            expanded: false,
            count: 12,
            blocked: true,
            activity: nil,
            activityMaximum: 0,
            directions: [.outbound],
            width: 40
        )
        let frame = DefaultRenderer().render(
            row.frame(width: 40, height: 1),
            proposal: .init(width: 40, height: 1)
        )
        let cell = try #require(frame.rasterSurface.cells[0].first { $0.character == "p" })
        let reference = DefaultRenderer().render(Text("p").foregroundStyle(.theme.danger))
        #expect(cell.style?.foregroundColor == reference.rasterSurface.cells[0][0].style?.foregroundColor)
        #expect(frame.semanticSnapshot
            .accessibilityNodes
            .contains { $0.label?.contains("current policy blocked") == true })
    }

    @Test func rapid_control_changes_publish_each_new_value_before_model_delivery() async throws {
        let events = Events()
        let stream = events.stream
        @State var value = 0
        let action = UI.EventAction(events: events) { Issue.record($0) }
        let projection = UI.Control(nark.ui.type.control).projection(.change, using: action)
        let binding = $value[dynamicMember: \.[emitting: projection]]
        for _ in 0 ..< 20 {
            binding.wrappedValue += 1
        }
        #expect(binding.wrappedValue == 20)
        events.finish()
        var values: [Int] = []
        for await event in stream {
            values.append(try event[nark.ui.type.control, as: Int.self])
        }
        #expect(values == Array(1 ... 20))
    }

    private func render(_ row: UI.TextRow, width: Int) -> String {
        RenderOnce.render(
            row.frame(width: width, height: 1),
            width: width,
            environment: [
                "NO_COLOR": "1",
                "TERM": "xterm-256color",
                "LANG": "en_US.UTF-8"
            ],
            isStdoutTTY: false
        )
    }

    @Test func columns_align_by_terminal_cells_and_clip_wide_names() {
        let row = UI.TextRow([
            .init("界界hello", width: 5),
            .init("12", width: 4, alignment: .trailing)
        ])
        let output = render(row, width: 10)
        #expect(output.contains("界界…   12"))
        #expect(layoutText(for: output, width: nil).size.width == 10)
    }

    @Test func clipped_styled_runs_remain_a_prefix_and_strip_terminal_controls() {
        let row = UI.TextRow([
            .init(spans: [.init("界", style: .theme.danger), .init("abc", style: .theme.success)], width: 2),
            .init("safe\u{1b}[2J\n", width: 8),
        ])
        let output = render(row, width: 11)
        #expect(output.hasPrefix("…  safe[2J"))
        #expect(!output.contains("\u{1b}"))
    }

    @Test func connection_row_keeps_direction_in_accessible_description() {
        let connection = Firewall.Connection(
            app: "/test",
            host: "peer.test",
            address: "192.0.2.1",
            port: "443",
            transport: "TCP",
            blocked: false,
            direction: .inbound
        )
        let row = UI.ConnectionLayout(width: 80, showsEndpoint: false).row(
            connection,
            policyBlocks: false
        )
        let frame = DefaultRenderer().render(
            row.frame(width: 80, height: 1),
            proposal: .init(width: 80, height: 1)
        )
        #expect(frame.semanticSnapshot
            .accessibilityNodes
            .contains { $0.label?.contains("Incoming") == true })
    }
}
